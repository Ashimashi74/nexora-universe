import 'dart:math' as math;
import 'dart:typed_data';

/// ANIX Mini Golf — pure Dart rules + physics, deterministic.
///
/// * Course units: a 300 x 520 portrait frame. 1 unit = 3.56 mm, so the ball (r 6) and the cup (r 15) keep the
///   real 42.7 mm : 108 mm proportion, and gravity / capture speed use real-world values in these units.
/// * Physics runs in fixed 1/240 s sub-steps (two per 1/120 s tick). [GolfMatch.advance] eats real frame time
///   through an accumulator (frame dt clamped), so 30, 60 or 120 Hz screens replay a shot identically.
/// * Every ball on the green is simulated during a shot: balls knock each other, windmill blades push resting
///   balls, a knocked ball that drops counts as holed, a knocked ball that falls in water goes back to where it lay
///   (no penalty). The shooter's water / out-of-bounds costs one penalty stroke and replays from the previous lie.
/// * Rules: 9 holes, 2-4 players. Tee order on hole 1 is seat order, then honour (best score on the previous hole
///   tees first). After everyone has teed off the player furthest from the cup (walking distance around the walls,
///   not straight-line) plays next. A player who reaches [kMaxStrokes] without holing picks up and writes
///   [kMaxStrokes] + 1. Lowest total wins.
/// * The windmill turns on a match clock ([GolfMatch.millClock]); online moves carry the clock value of the shot so
///   every phone replays the same blade timing.

class GVec {
  const GVec(this.x, this.y);
  final double x;
  final double y;
}

/// A rail (wall). Collides as a capsule of radius [kRailHalf] around the segment — exactly what is drawn.
class GWall {
  const GWall(this.x1, this.y1, this.x2, this.y2);
  final double x1, y1, x2, y2;
}

class GRect {
  const GRect(this.l, this.t, this.r, this.b);
  final double l, t, r, b;
  bool has(double x, double y) => x >= l && x <= r && y >= t && y <= b;
}

class GBumper {
  const GBumper(this.x, this.y, this.r);
  final double x, y, r;
}

/// Spinning cross of two blades of half-length [len] through (x, y); [speed] in rad/s (sign = direction).
class GWindmill {
  const GWindmill(this.x, this.y, this.len, this.speed);
  final double x, y, len, speed;
}

/// A tilted area: a constant acceleration (units/s²) on the ball while its centre is inside [area].
class GSlope {
  const GSlope(this.area, this.ax, this.ay);
  final GRect area;
  final double ax, ay;
}

class GHole {
  GHole({
    required this.par,
    required this.start,
    required this.cup,
    required this.walls,
    this.sand = const <GRect>[],
    this.water = const <GRect>[],
    this.bumpers = const <GBumper>[],
    this.mills = const <GWindmill>[],
    this.slopes = const <GSlope>[],
  });
  final int par;
  final GVec start;
  final GVec cup;
  final List<GWall> walls;
  final List<GRect> sand;
  final List<GRect> water;
  final List<GBumper> bumpers;
  final List<GWindmill> mills;
  final List<GSlope> slopes;

  GRect? _bounds;

  /// Playable area: the walls' bounding box (inner edge of the outer rails is inside it).
  GRect get bounds => _bounds ??= () {
        double l = double.infinity, t = double.infinity, r = -double.infinity, b = -double.infinity;
        for (final GWall w in walls) {
          l = math.min(l, math.min(w.x1, w.x2));
          r = math.max(r, math.max(w.x1, w.x2));
          t = math.min(t, math.min(w.y1, w.y2));
          b = math.max(b, math.max(w.y1, w.y2));
        }
        return GRect(l, t, r, b);
      }();
}

// ------------------------------------------------------------------------------------------------ dimensions
const double kGolfW = 300, kGolfH = 520;

/// The part of the 300 x 520 frame any hole draws into (rails, flag, shadows). The renderer fits this rect.
const GRect kGolfView = GRect(18, 14, 282, 512);

/// 1 course unit in metres (ball radius 6 = 21.35 mm).
const double kUnitM = 0.02135 / 6;
const double kBallR = 6;

/// Regulation cup 108 mm vs ball 42.7 mm.
const double kCupR = 15;

/// Half thickness of a rail as drawn and as collided.
const double kRailHalf = 4.5;

/// Half thickness of a windmill blade, and the hub radius.
const double kBladeHalf = 4;
const double kHubR = 7;

/// Fastest putt (units/s ≈ 2.5 m/s).
const double kMaxShot = 700;
const int kMaxStrokes = 7;

/// Rolling resistance on carpet (units/s² ≈ 0.68 m/s²), in sand, and a small air/velocity drag (1/s).
const double kRollDecel = 190;
const double kSandDecel = 900;
const double kDrag = 0.25;

/// Below this speed with no slope able to move it, a ball is at rest.
const double kStopSpeed = 3;

/// Gravity in units/s².
const double kGravity = 9.81 / kUnitM;

/// Time the ball centre must spend over the cup to drop one radius (≈ 66 ms) — gives a centre-hit capture speed of
/// about 1.6 m/s (455 units/s), lower for an off-centre roll whose chord over the cup is shorter.
final double kDropTime = math.sqrt(2 * kBallR / kGravity);

/// Fastest a ball can drop at a dead-centre hit (chord = cup diameter).
double get kCaptureSpeed => 2 * kCupR / kDropTime;

const double kRestWall = 0.78, kRestBlade = 0.85, kRestBumper = 1.15, kRestBall = 0.92;

/// Fixed simulation step and one "tick" (two sub-steps).
const double kSimDt = 1 / 240;
const double kTickDt = 1 / 120;

/// A shot ends at the latest after this much simulated time.
const double kMaxShotTime = 20;

List<GWall> _box(double l, double t, double r, double b) =>
    <GWall>[GWall(l, t, r, t), GWall(r, t, r, b), GWall(r, b, l, b), GWall(l, b, l, t)];

/// The 9 holes. An odd [seed] mirrors the course so daily courses differ.
List<GHole> golfCourse(int seed) {
  final List<GHole> h = <GHole>[
    // 1: straight, gentle
    GHole(par: 2, start: const GVec(150, 450), cup: const GVec(150, 90), walls: _box(70, 40, 230, 490)),
    // 2: bumpers slalom
    GHole(par: 3, start: const GVec(150, 460), cup: const GVec(150, 80), walls: _box(40, 40, 260, 490), bumpers: const <GBumper>[
      GBumper(132, 340, 16), GBumper(168, 255, 16), GBumper(132, 170, 16),
    ]),
    // 3: L-shape
    GHole(par: 3, start: const GVec(80, 460), cup: const GVec(225, 95), walls: <GWall>[
      ..._box(30, 40, 270, 490),
      const GWall(130, 160, 130, 490),
      const GWall(130, 160, 270, 160),
    ]),
    // 4: sand trap in front of the cup
    GHole(par: 3, start: const GVec(150, 460), cup: const GVec(150, 100), walls: _box(50, 40, 250, 490), sand: const <GRect>[
      GRect(80, 140, 220, 200),
    ], bumpers: const <GBumper>[GBumper(150, 300, 22)]),
    // 5: windmill guarding the gate
    GHole(par: 3, start: const GVec(150, 460), cup: const GVec(150, 90), walls: <GWall>[
      ..._box(60, 40, 240, 490),
      const GWall(60, 260, 105, 260),
      const GWall(195, 260, 240, 260),
    ], mills: const <GWindmill>[GWindmill(150, 260, 50, 1.6)]),
    // 6: water hazard with a bridge
    GHole(par: 3, start: const GVec(150, 465), cup: const GVec(150, 80), walls: _box(40, 40, 260, 490), water: const <GRect>[
      GRect(40, 230, 125, 300), GRect(175, 230, 260, 300),
    ]),
    // 7: zig-zag
    GHole(par: 4, start: const GVec(70, 465), cup: const GVec(230, 85), walls: <GWall>[
      ..._box(30, 40, 270, 490),
      const GWall(30, 370, 200, 370),
      const GWall(100, 250, 270, 250),
      const GWall(30, 140, 200, 140),
    ]),
    // 8: uphill ramp, then a diamond to bank around
    GHole(par: 3, start: const GVec(150, 465), cup: const GVec(150, 80), walls: <GWall>[
      ..._box(30, 40, 270, 490),
      const GWall(150, 200, 210, 270),
      const GWall(210, 270, 150, 340),
      const GWall(150, 340, 90, 270),
      const GWall(90, 270, 150, 200),
    ], sand: const <GRect>[GRect(30, 40, 90, 100), GRect(210, 40, 270, 100)], slopes: const <GSlope>[
      GSlope(GRect(30, 370, 270, 425), 0, 230),
    ]),
    // 9: finale — water + bumper bridge, then the windmill gate
    GHole(par: 4, start: const GVec(150, 470), cup: const GVec(150, 75), walls: <GWall>[
      ..._box(30, 30, 270, 500),
      const GWall(30, 200, 110, 200),
      const GWall(190, 200, 270, 200),
    ], water: const <GRect>[GRect(30, 330, 110, 380), GRect(190, 330, 270, 380)], bumpers: const <GBumper>[
      GBumper(150, 355, 14), GBumper(80, 120, 12), GBumper(220, 120, 12),
    ], mills: const <GWindmill>[GWindmill(150, 200, 46, -2.1)]),
  ];
  if (seed.isOdd) return <GHole>[for (final GHole x in h) _mirror(x)];
  return h;
}

GHole _mirror(GHole h) {
  double m(double x) => kGolfW - x;
  GRect mr(GRect r) => GRect(m(r.r), r.t, m(r.l), r.b);
  return GHole(
    par: h.par,
    start: GVec(m(h.start.x), h.start.y),
    cup: GVec(m(h.cup.x), h.cup.y),
    walls: <GWall>[for (final GWall w in h.walls) GWall(m(w.x1), w.y1, m(w.x2), w.y2)],
    sand: <GRect>[for (final GRect r in h.sand) mr(r)],
    water: <GRect>[for (final GRect r in h.water) mr(r)],
    bumpers: <GBumper>[for (final GBumper b in h.bumpers) GBumper(m(b.x), b.y, b.r)],
    mills: <GWindmill>[for (final GWindmill w in h.mills) GWindmill(m(w.x), w.y, w.len, -w.speed)],
    slopes: <GSlope>[for (final GSlope s in h.slopes) GSlope(mr(s.area), -s.ax, s.ay)],
  );
}

/// Score name for [strokes] on a hole of [par] (English key; the UI translates).
String golfScoreName(int strokes, int par) {
  if (strokes > kMaxStrokes) return 'pickup';
  if (strokes == 1) return 'ace';
  switch (strokes - par) {
    case <= -3:
      return 'albatross';
    case -2:
      return 'eagle';
    case -1:
      return 'birdie';
    case 0:
      return 'par';
    case 1:
      return 'bogey';
    case 2:
      return 'double';
    default:
      return 'over';
  }
}

/// A ball centre may rest at (x, y) on [h]: inside the course, off rails, bumpers, windmill hubs and water.
bool golfLegalSpot(GHole h, double x, double y) {
  final GRect bb = h.bounds;
  if (x < bb.l + kRailHalf + kBallR || x > bb.r - kRailHalf - kBallR) return false;
  if (y < bb.t + kRailHalf + kBallR || y > bb.b - kRailHalf - kBallR) return false;
  for (final GWall w in h.walls) {
    if (GolfMatch.segDist(x, y, w.x1, w.y1, w.x2, w.y2) < kRailHalf + kBallR) return false;
  }
  for (final GBumper p in h.bumpers) {
    if (GolfMatch._dist(x, y, p.x, p.y) < p.r + kBallR) return false;
  }
  for (final GWindmill m in h.mills) {
    if (GolfMatch._dist(x, y, m.x, m.y) < kHubR + kBallR) return false;
  }
  for (final GRect r in h.water) {
    if (r.has(x, y)) return false;
  }
  return true;
}

class GBall {
  GBall(this.x, this.y)
      : lastX = x,
        lastY = y;
  double x, y;
  double vx = 0, vy = 0;
  bool holed = false;

  /// Reached [kMaxStrokes] without holing: picked up, scores [kMaxStrokes] + 1.
  bool pickedUp = false;

  /// False until the ball has been teed up on this hole.
  bool onCourse = true;
  int strokes = 0;

  /// Lie before the current shot (water / out-of-bounds replay spot).
  double lastX, lastY;

  /// Time the centre has spent over the cup in the current pass.
  double overCup = 0;

  bool get moving => vx != 0 || vy != 0;
  bool get finished => holed || pickedUp;
  double get speed => math.sqrt(vx * vx + vy * vy);
}

/// Events for the renderer (sound/FX); never affect results.
class GEvent {
  const GEvent(this.kind, this.x, this.y, [this.strength = 0, this.seat = -1, this.strokes = 0]);

  /// wall | bumper | ball | mill | sand | water | oob | lip | cup | pickup
  final String kind;
  final double x, y, strength;
  final int seat;

  /// For 'cup' / 'pickup': the seat's strokes on the hole.
  final int strokes;
}

class GolfMatch {
  GolfMatch({required this.players, int seed = 1}) : course = golfCourse(seed) {
    cards = List<List<int>>.generate(players, (_) => <int>[]);
    _teeOrder = List<int>.generate(players, (int i) => i);
    _startHole();
  }

  final int players;
  final List<GHole> course;
  late List<List<int>> cards;
  int hole = 0;
  late List<GBall> balls;
  int current = 0;
  bool simulating = false;

  /// Simulated time of the current shot.
  double simTime = 0;

  /// Windmill clock (s). Advances during shots and while players aim ([idle]).
  double millClock = 0;
  int shotsTaken = 0;
  final List<GEvent> events = <GEvent>[];
  final Set<int> out = <int>{}; // forfeited seats
  late List<int> _teeOrder;
  double _acc = 0;

  GHole get h => course[hole];
  bool get over => hole >= course.length;

  /// Seats still playing the current hole.
  bool _active(int i) => i < balls.length && !out.contains(i) && !balls[i].finished;

  void _startHole() {
    while (!over) {
      balls = <GBall>[for (int i = 0; i < players; i++) GBall(h.start.x, h.start.y)..onCourse = false];
      _acc = 0;
      final int? n = _nextShooter();
      if (n != null) {
        current = n;
        _teeUp(n);
        return;
      }
      // everybody left: write the remaining holes
      for (int i = 0; i < players; i++) {
        cards[i].add(kMaxStrokes + 1);
      }
      hole++;
    }
  }

  /// Next player: anyone still on the tee (honour order), else the furthest from the cup by walking distance.
  int? _nextShooter() {
    for (final int i in _teeOrder) {
      if (i < balls.length && _active(i) && !balls[i].onCourse) return i;
    }
    int? best;
    double bd = -1;
    for (int i = 0; i < balls.length; i++) {
      if (!_active(i)) continue;
      final double d = distanceToCup(balls[i].x, balls[i].y);
      if (d > bd + 1e-9) {
        bd = d;
        best = i;
      }
    }
    return best;
  }

  /// Puts [seat]'s ball on the tee (next free spot when another ball sits there).
  void _teeUp(int seat) {
    final GBall b = balls[seat];
    if (b.onCourse) return;
    final (double x, double y) = _freeSpot(h.start.x, h.start.y, seat);
    b
      ..x = x
      ..y = y
      ..lastX = x
      ..lastY = y
      ..onCourse = true;
  }

  /// Nearest legal resting spot to (x, y) not touching another ball (deterministic search).
  (double, double) _freeSpot(double x, double y, int seat) {
    bool ok(double px, double py) {
      if (!_legal(px, py)) return false;
      for (int i = 0; i < balls.length; i++) {
        if (i == seat || !_active(i) || !balls[i].onCourse) continue;
        if (_dist(px, py, balls[i].x, balls[i].y) < 2 * kBallR + 1) return false;
      }
      return true;
    }

    if (ok(x, y)) return (x, y);
    for (int ring = 1; ring <= 12; ring++) {
      final double r = ring * (2 * kBallR + 2) / 2;
      for (int k = 0; k < 12; k++) {
        // start sideways (along the tee line) and alternate sides
        final double a = (k.isEven ? 0 : math.pi) + (k ~/ 2) * math.pi / 6 * (k.isEven ? 1 : -1);
        final double px = x + math.cos(a) * r, py = y + math.sin(a) * r;
        if (ok(px, py)) return (px, py);
      }
    }
    return (x, y);
  }

  bool _legal(double x, double y) => golfLegalSpot(h, x, y);

  static double _dist(double ax, double ay, double bx, double by) => math.sqrt((ax - bx) * (ax - bx) + (ay - by) * (ay - by));

  static double segDist(double x, double y, double x1, double y1, double x2, double y2) {
    final double ex = x2 - x1, ey = y2 - y1;
    final double l2 = ex * ex + ey * ey;
    double t = l2 == 0 ? 0 : ((x - x1) * ex + (y - y1) * ey) / l2;
    t = t < 0 ? 0 : (t > 1 ? 1 : t);
    return _dist(x, y, x1 + ex * t, y1 + ey * t);
  }

  /// Walking distance from (x, y) to the cup around walls and water (course units).
  double distanceToCup(double x, double y) => GolfGeo.of(h).at(x, y);

  /// Total strokes per player (finished holes).
  int total(int seat) => cards[seat].fold(0, (int a, int b) => a + b);
  int parSoFar() => <int>[for (int i = 0; i < cards[0].length && i < course.length; i++) course[i].par].fold(0, (int a, int b) => a + b);
  int parTotal() => course.fold(0, (int a, GHole x) => a + x.par);

  /// Strokes relative to par over the holes [seat] has finished.
  int toPar(int seat) => total(seat) - parSoFar();

  /// Shoots for the current player: [angle] radians, [power] 0..1. [clock] pins the windmill clock (online/bot).
  bool shoot(double angle, double power, {double? clock}) {
    if (simulating || over) return false;
    if (!angle.isFinite || !power.isFinite) return false;
    if (!_active(current)) return false;
    _teeUp(current);
    if (clock != null && clock.isFinite) millClock = clock;
    final GBall b = balls[current];
    final double p = power.clamp(0.02, 1.0);
    for (final GBall o in balls) {
      o
        ..lastX = o.x
        ..lastY = o.y
        ..overCup = 0;
    }
    b
      ..vx = math.cos(angle) * kMaxShot * p
      ..vy = math.sin(angle) * kMaxShot * p
      ..strokes += 1;
    simulating = true;
    simTime = 0;
    _acc = 0;
    shotsTaken++;
    return true;
  }

  /// Windmill blade angle at the current clock (or at clock [t]).
  double millAngle(GWindmill w, [double? t]) => hole * 0.7 + w.x * 0.01 + w.speed * (t ?? millClock);

  /// Lets the windmill turn while players aim. A blade that would push into a resting ball waits for the next shot
  /// (it is pushed physically during the shot).
  void idle(double dt) {
    if (simulating || over || h.mills.isEmpty || !(dt > 0)) return;
    final double nt = millClock + math.min(dt, 0.05);
    for (final GWindmill m in h.mills) {
      final double a = millAngle(m, nt);
      for (int i = 0; i < balls.length; i++) {
        if (!_active(i) || !balls[i].onCourse) continue;
        final GBall b = balls[i];
        for (int k = 0; k < 2; k++) {
          final double aa = a + k * math.pi / 2;
          final double cx = math.cos(aa) * m.len, cy = math.sin(aa) * m.len;
          if (segDist(b.x, b.y, m.x - cx, m.y - cy, m.x + cx, m.y + cy) < kBladeHalf + kBallR - 0.05) return;
        }
      }
    }
    millClock = nt;
  }

  /// Frame-rate independent driver: feeds real frame time through a fixed-step accumulator. Returns true when the
  /// shot is resolved (or nothing is simulating).
  bool advance(double dt) {
    if (!simulating) return true;
    if (!(dt > 0)) return false;
    _acc += math.min(dt, 0.1);
    while (_acc >= kTickDt) {
      _acc -= kTickDt;
      if (_tick()) {
        _acc = 0;
        _resolve();
        return true;
      }
    }
    return false;
  }

  /// Advances the simulation by [n] fixed 1/120 s ticks; returns true when the shot is resolved.
  bool step([int n = 2]) {
    if (!simulating) return true;
    for (int i = 0; i < n; i++) {
      if (_tick()) {
        _resolve();
        return true;
      }
    }
    return false;
  }

  void runToEnd() {
    while (!step(240)) {}
  }

  /// One 1/120 s tick = two fixed sub-steps. Returns true once every ball is at rest.
  bool _tick() {
    _sub();
    _sub();
    bool rest = true;
    for (int i = 0; i < balls.length; i++) {
      if (!_active(i) || !balls[i].onCourse) continue;
      if (balls[i].moving || balls[i].overCup > 0 || !_holds(balls[i])) rest = false;
    }
    if (simTime >= kMaxShotTime) {
      for (final GBall b in balls) {
        b
          ..vx = 0
          ..vy = 0;
      }
      return true;
    }
    return rest;
  }

  void _sub() {
    const double dt = kSimDt;
    simTime += dt;
    millClock += dt;
    final GHole hh = h;
    for (int i = 0; i < balls.length; i++) {
      if (!_active(i) || !balls[i].onCourse) continue;
      final GBall b = balls[i];
      _forces(b, hh, dt);
      final double sp = b.speed;
      // continuous collision: never move more than 40% of a radius between collision passes
      final int n = math.max(1, (sp * dt / (kBallR * 0.4)).ceil());
      for (int k = 0; k < n; k++) {
        b.x += b.vx * dt / n;
        b.y += b.vy * dt / n;
        _collideStatic(b, hh, i);
      }
    }
    _collideBalls();
    for (int i = 0; i < balls.length; i++) {
      if (!_active(i) || !balls[i].onCourse) continue;
      _hazards(i, hh, dt);
    }
  }

  /// Static friction can hold [b] where it lies (no slope steeper than the rolling resistance).
  bool _holds(GBall b) {
    double ax = 0, ay = 0;
    for (final GSlope s in h.slopes) {
      if (s.area.has(b.x, b.y)) {
        ax += s.ax;
        ay += s.ay;
      }
    }
    if (ax == 0 && ay == 0) return true;
    final double f = h.sand.any((GRect r) => r.has(b.x, b.y)) ? kSandDecel : kRollDecel;
    return math.sqrt(ax * ax + ay * ay) <= f;
  }

  void _forces(GBall b, GHole hh, double dt) {
    double ax = 0, ay = 0;
    for (final GSlope s in hh.slopes) {
      if (s.area.has(b.x, b.y)) {
        ax += s.ax;
        ay += s.ay;
      }
    }
    final bool sand = hh.sand.any((GRect r) => r.has(b.x, b.y));
    final double f = sand ? kSandDecel : kRollDecel;
    final double slope = math.sqrt(ax * ax + ay * ay);
    double sp = b.speed;
    if (sp == 0) {
      if (slope <= f) return; // static friction holds it
      b.vx = (ax - ax / slope * f) * dt;
      b.vy = (ay - ay / slope * f) * dt;
      return;
    }
    b.vx += ax * dt;
    b.vy += ay * dt;
    sp = b.speed;
    if (sp == 0) return;
    final double ns = math.max(0.0, sp - f * dt) * (1 - kDrag * dt);
    if (ns < kStopSpeed && slope <= f) {
      b.vx = 0;
      b.vy = 0;
    } else {
      b.vx = b.vx / sp * ns;
      b.vy = b.vy / sp * ns;
    }
  }

  void _collideStatic(GBall b, GHole hh, int seat) {
    for (final GWall w in hh.walls) {
      _capsule(b, w.x1, w.y1, w.x2, w.y2, kRailHalf + kBallR, kRestWall, 'wall', seat);
    }
    for (final GWindmill m in hh.mills) {
      final double a = millAngle(m);
      for (int k = 0; k < 2; k++) {
        final double aa = a + k * math.pi / 2;
        final double cx = math.cos(aa) * m.len, cy = math.sin(aa) * m.len;
        _capsule(b, m.x - cx, m.y - cy, m.x + cx, m.y + cy, kBladeHalf + kBallR, kRestBlade, 'mill', seat, mill: m);
      }
      _circle(b, m.x, m.y, kHubR + kBallR, kRestBlade, 'mill', seat);
    }
    for (final GBumper p in hh.bumpers) {
      _circle(b, p.x, p.y, p.r + kBallR, kRestBumper, 'bumper', seat);
    }
  }

  void _circle(GBall b, double cx, double cy, double min, double e, String kind, int seat) {
    final double dx = b.x - cx, dy = b.y - cy;
    final double d = math.sqrt(dx * dx + dy * dy);
    if (d >= min) return;
    final double nx = d > 1e-9 ? dx / d : 0, ny = d > 1e-9 ? dy / d : 1;
    b
      ..x = cx + nx * min
      ..y = cy + ny * min;
    final double vn = b.vx * nx + b.vy * ny;
    if (vn < 0) {
      b
        ..vx -= (1 + e) * vn * nx
        ..vy -= (1 + e) * vn * ny;
      _capSpeed(b);
      if (-vn > 30) events.add(GEvent(kind, b.x, b.y, -vn, seat));
    }
  }

  void _capsule(GBall b, double x1, double y1, double x2, double y2, double rad, double e, String kind, int seat, {GWindmill? mill}) {
    final double ex = x2 - x1, ey = y2 - y1;
    final double l2 = ex * ex + ey * ey;
    if (l2 == 0) return;
    double t = ((b.x - x1) * ex + (b.y - y1) * ey) / l2;
    t = t < 0 ? 0 : (t > 1 ? 1 : t);
    final double px = x1 + ex * t, py = y1 + ey * t;
    final double dx = b.x - px, dy = b.y - py;
    final double d2 = dx * dx + dy * dy;
    if (d2 >= rad * rad) return;
    final double d = math.sqrt(d2);
    double nx, ny;
    if (d > 1e-9) {
      nx = dx / d;
      ny = dy / d;
    } else {
      nx = -ey / math.sqrt(l2);
      ny = ex / math.sqrt(l2);
    }
    b
      ..x = px + nx * rad
      ..y = py + ny * rad;
    // surface velocity of a spinning blade at the contact point
    double sx = 0, sy = 0;
    if (mill != null) {
      sx = -mill.speed * (py - mill.y);
      sy = mill.speed * (px - mill.x);
    }
    final double rvx = b.vx - sx, rvy = b.vy - sy;
    final double vn = rvx * nx + rvy * ny;
    if (vn < 0) {
      // normal restitution + a little rail friction on the tangential part
      final double tx = -ny, ty = nx;
      final double vt = rvx * tx + rvy * ty;
      final double nvn = -e * vn, nvt = vt * 0.96;
      b
        ..vx = sx + nx * nvn + tx * nvt
        ..vy = sy + ny * nvn + ty * nvt;
      _capSpeed(b);
      if (-vn > 30) events.add(GEvent(kind, b.x, b.y, -vn, seat));
    }
  }

  void _capSpeed(GBall b) {
    final double sp = b.speed;
    const double cap = kMaxShot * 1.15;
    if (sp > cap) {
      b
        ..vx = b.vx / sp * cap
        ..vy = b.vy / sp * cap;
    }
  }

  void _collideBalls() {
    for (int i = 0; i < balls.length; i++) {
      if (!_active(i) || !balls[i].onCourse) continue;
      for (int j = i + 1; j < balls.length; j++) {
        if (!_active(j) || !balls[j].onCourse) continue;
        final GBall a = balls[i], c = balls[j];
        final double dx = c.x - a.x, dy = c.y - a.y;
        final double d = math.sqrt(dx * dx + dy * dy);
        const double min = 2 * kBallR;
        if (d >= min) continue;
        final double nx = d > 1e-9 ? dx / d : 1, ny = d > 1e-9 ? dy / d : 0;
        final double push = (min - d) / 2;
        a
          ..x -= nx * push
          ..y -= ny * push;
        c
          ..x += nx * push
          ..y += ny * push;
        final double vn = (c.vx - a.vx) * nx + (c.vy - a.vy) * ny;
        if (vn < 0) {
          final double jn = -(1 + kRestBall) * vn / 2;
          a
            ..vx -= jn * nx
            ..vy -= jn * ny;
          c
            ..vx += jn * nx
            ..vy += jn * ny;
          if (-vn > 20) events.add(GEvent('ball', (a.x + c.x) / 2, (a.y + c.y) / 2, -vn, i));
        }
      }
    }
  }

  void _hazards(int seat, GHole hh, double dt) {
    final GBall b = balls[seat];
    // cup: the ball drops once its centre has been over the hole long enough to fall one radius
    final double dc = _dist(b.x, b.y, hh.cup.x, hh.cup.y);
    if (dc < kCupR) {
      b.overCup += dt;
      if (b.overCup >= kDropTime || !b.moving) {
        if (b.overCup >= kDropTime) {
          b
            ..holed = true
            ..x = hh.cup.x
            ..y = hh.cup.y
            ..vx = 0
            ..vy = 0
            ..overCup = 0;
          events.add(GEvent('cup', b.x, b.y, 0, seat, b.strokes));
        }
        return;
      }
    } else if (b.overCup > 0) {
      // lip-out: the far rim deflects the ball and takes some of its pace
      final double frac = (b.overCup / kDropTime).clamp(0.0, 1.0);
      final double cx = b.x - hh.cup.x, cy = b.y - hh.cup.y;
      final double side = b.vx * cy - b.vy * cx; // which side of the cup the path passed
      final double rot = (side >= 0 ? 1 : -1) * 0.6 * frac;
      final double c = math.cos(rot), s = math.sin(rot);
      final double k = 1 - 0.35 * frac;
      final double nvx = (b.vx * c - b.vy * s) * k, nvy = (b.vx * s + b.vy * c) * k;
      b
        ..vx = nvx
        ..vy = nvy
        ..overCup = 0;
      events.add(GEvent('lip', b.x, b.y, frac, seat));
    }
    for (final GRect r in hh.water) {
      if (r.has(b.x, b.y)) {
        events.add(GEvent('water', b.x, b.y, 0, seat));
        _replace(seat, penalty: seat == current);
        return;
      }
    }
    final GRect bb = hh.bounds;
    if (!b.x.isFinite || !b.y.isFinite || b.x < bb.l || b.x > bb.r || b.y < bb.t || b.y > bb.b) {
      events.add(GEvent('oob', b.x.isFinite ? b.x : hh.start.x, b.y.isFinite ? b.y : hh.start.y, 0, seat));
      _replace(seat, penalty: seat == current);
    }
  }

  /// Back to the previous lie (the shooter adds a penalty stroke).
  void _replace(int seat, {required bool penalty}) {
    final GBall b = balls[seat];
    final bool lieOk = b.lastX.isFinite && b.lastY.isFinite && _legal(b.lastX, b.lastY);
    final (double x, double y) = lieOk ? _freeSpot(b.lastX, b.lastY, seat) : _freeSpot(h.start.x, h.start.y, seat);
    b
      ..lastX = x
      ..lastY = y
      ..x = x
      ..y = y
      ..vx = 0
      ..vy = 0
      ..overCup = 0;
    if (penalty) b.strokes += 1;
  }

  /// After every ball stops: pick-up rule, next shooter, next hole.
  void _resolve() {
    simulating = false;
    for (final GBall o in balls) {
      o
        ..vx = 0
        ..vy = 0;
    }
    final GBall b = balls[current];
    if (!b.finished && b.strokes >= kMaxStrokes) {
      b
        ..pickedUp = true
        ..strokes = kMaxStrokes + 1;
      events.add(GEvent('pickup', b.x, b.y, 0, current, b.strokes));
    }
    _advance();
  }

  void _advance() {
    final int? n = _nextShooter();
    if (n != null) {
      current = n;
      _teeUp(n);
      return;
    }
    final List<int> scores = <int>[
      for (int i = 0; i < players; i++) out.contains(i) || i >= balls.length ? kMaxStrokes + 1 : balls[i].strokes
    ];
    for (int i = 0; i < players; i++) {
      cards[i].add(scores[i]);
    }
    // honour: best score on this hole tees first next; ties keep the previous order
    final List<int> prev = List<int>.of(_teeOrder);
    _teeOrder.sort((int a, int c) => scores[a] != scores[c] ? scores[a].compareTo(scores[c]) : prev.indexOf(a).compareTo(prev.indexOf(c)));
    hole++;
    _startHole();
  }

  /// A player left: they are written down for the max on every remaining hole.
  void forfeit(int seat) {
    if (seat < 0 || seat >= players) return;
    out.add(seat);
    if (!simulating && current == seat && !over) _advance();
  }

  /// Ranking best → worst (fewest strokes, then lower seat).
  List<int> ranking() {
    final List<int> s = List<int>.generate(players, (int i) => i);
    int tot(int i) => total(i) + (out.contains(i) ? 1000 : 0);
    s.sort((int a, int b) => tot(a) != tot(b) ? tot(a).compareTo(tot(b)) : a.compareTo(b));
    return s;
  }

  String stateKey() => '$hole|$current|${millClock.toStringAsFixed(4)}|${balls.map((GBall b) => '${b.x.toStringAsFixed(2)},'
      '${b.y.toStringAsFixed(2)},${b.strokes},${b.holed ? 1 : 0}${b.pickedUp ? 1 : 0}${b.onCourse ? 1 : 0}').join(';')}|'
      '${cards.map((List<int> c) => c.join(',')).join('/')}';

  /// Deterministic look-ahead copy (bot planning).
  GolfMatch probe() => GolfMatch._copy(this);

  GolfMatch._copy(GolfMatch o)
      : players = o.players,
        course = o.course {
    cards = <List<int>>[for (final List<int> c in o.cards) List<int>.of(c)];
    _teeOrder = List<int>.of(o._teeOrder);
    hole = o.hole;
    current = o.current;
    shotsTaken = o.shotsTaken;
    millClock = o.millClock;
    out.addAll(o.out);
    balls = <GBall>[
      for (final GBall b in o.balls)
        GBall(b.x, b.y)
          ..strokes = b.strokes
          ..holed = b.holed
          ..pickedUp = b.pickedUp
          ..onCourse = b.onCourse
          ..lastX = b.lastX
          ..lastY = b.lastY
    ];
  }

  /// Simulates one shot on a copy and returns the copy after every ball stopped (no turn advance).
  GolfMatch simulateShot(double angle, double power, {double? clock}) {
    final GolfMatch g = probe();
    g.shoot(angle, power, clock: clock);
    while (g.simulating) {
      if (g._tick()) g.simulating = false;
    }
    return g;
  }

  /// Distance a ball launched at [v] rolls on flat carpet before stopping (constant rolling resistance plus the
  /// linear drag, integrated exactly).
  static double rollDistance(double v) {
    if (v <= 0) return 0;
    const double a = kRollDecel, k = kDrag;
    return (v - a / k * math.log(1 + k * v / a)) / k;
  }

  /// Power (0..1) that rolls a ball [d] units on flat carpet and arrives with [arrive] units/s left.
  static double powerFor(double d, [double arrive = 0]) {
    final double need = math.max(0.0, d) + rollDistance(arrive);
    double lo = 0, hi = kMaxShot * 1.2;
    for (int i = 0; i < 50; i++) {
      final double mid = (lo + hi) / 2;
      if (rollDistance(mid) < need) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return (hi / kMaxShot).clamp(0.02, 1.0);
  }

  /// A sensible default putt for the current player along the walking route (absent-player timeout).
  (double, double) autoPutt() {
    final GBall b = balls[current];
    final (double tx, double ty, bool isCup) = GolfGeo.of(h).aimPoint(b.x, b.y);
    final double d = _dist(b.x, b.y, tx, ty);
    return (math.atan2(ty - b.y, tx - b.x), powerFor(isCup ? d + 12 : d + 30, isCup ? 120 : 0));
  }

  /// Bot: plans a shot and returns (angle, power). [skill] 0..1 sets the execution error.
  (double, double) botShot(math.Random rng, double skill, {int samples = 48, double? clock}) {
    final GolfBotPlanner p = GolfBotPlanner(this, rng, skill, samples: samples, clock: clock);
    while (!p.work(64)) {}
    return p.shot;
  }
}

/// Bot planner that can run a few simulations per frame ([work]) so the UI never hitches.
class GolfBotPlanner {
  GolfBotPlanner(this.g, this.rng, this.skill, {int samples = 48, double? clock}) : clock = clock ?? g.millClock {
    final GBall b = g.balls[g.current];
    final GolfGeo geo = GolfGeo.of(g.h);
    final (double tx, double ty, bool isCup) = geo.aimPoint(b.x, b.y);
    final double d = GolfMatch._dist(b.x, b.y, tx, ty);
    final double a0 = math.atan2(ty - b.y, tx - b.x);
    // through a corner: carry about half the remaining route past the waypoint so the ball banks onward
    final double p0 = isCup ? GolfMatch.powerFor(d + 10, 110) : GolfMatch.powerFor(d + 0.5 * geo.at(tx, ty));
    for (final double da in const <double>[0, -0.02, 0.02, -0.05, 0.05, -0.1, 0.1]) {
      for (final double pf in const <double>[1, 0.88, 1.12, 0.76, 1.3]) {
        _queue.add((a0 + da, (p0 * pf).clamp(0.02, 1.0)));
      }
    }
    final double direct = math.atan2(g.h.cup.y - b.y, g.h.cup.x - b.x);
    for (int i = 0; i < samples; i++) {
      final bool near = i.isEven;
      final double a = near ? direct + (rng.nextDouble() - 0.5) * 0.6 : rng.nextDouble() * math.pi * 2;
      _queue.add((a, 0.1 + rng.nextDouble() * 0.9));
    }
  }

  final GolfMatch g;
  final math.Random rng;
  final double skill;
  final double clock;
  final List<(double, double)> _queue = <(double, double)>[];
  int _i = 0;
  bool _refined = false;
  double _bestA = 0, _bestP = 0.5, _bestScore = double.infinity;
  (double, double)? _shot;

  bool get done => _shot != null;

  /// The chosen shot (with execution error applied). Valid once [work] returned true.
  (double, double) get shot => _shot ?? (_bestA, _bestP);

  double _score(GolfMatch r, double p) {
    final GBall me = r.balls[g.current];
    final GBall before = g.balls[g.current];
    if (me.holed) return -1000 + p * 10; // prefer the gentler make (more likely to stay in)
    final int penalty = me.strokes - before.strokes - 1;
    double s = GolfGeo.of(r.h).at(me.x, me.y) + penalty * 260;
    if (r.h.sand.any((GRect q) => q.has(me.x, me.y))) s += 25;
    return s;
  }

  /// Runs up to [n] simulations; returns true when the plan is final.
  bool work(int n) {
    if (_shot != null) return true;
    for (int k = 0; k < n; k++) {
      if (_i >= _queue.length) {
        if (!_refined && _bestScore > -900) {
          _refined = true;
          for (int j = 0; j < 14; j++) {
            _queue.add((_bestA + (rng.nextDouble() - 0.5) * 0.06, (_bestP * (0.93 + rng.nextDouble() * 0.14)).clamp(0.02, 1.0)));
          }
          continue;
        }
        _finish();
        return true;
      }
      final (double a, double p) = _queue[_i++];
      final double sc = _score(g.simulateShot(a, p, clock: clock), p);
      if (sc < _bestScore) {
        _bestScore = sc;
        _bestA = a;
        _bestP = p;
      }
    }
    return false;
  }

  void _finish() {
    final double e = (1 - skill.clamp(0.0, 1.0));
    final double a = _bestA + (rng.nextDouble() - 0.5) * 2 * e * 0.18;
    final double p = (_bestP * (1 + (rng.nextDouble() - 0.5) * 2 * e * 0.24)).clamp(0.02, 1.0);
    _shot = (a, p);
  }
}

/// Walking-distance field to the cup for one hole: Dijkstra on a 4-unit grid of legal ball-centre cells (rails,
/// bumpers, hubs and water blocked; sand costs triple). Also used to prove every hole is solvable.
class GolfGeo {
  GolfGeo._(this.hole) {
    nx = (kGolfW / cell).ceil() + 1;
    ny = (kGolfH / cell).ceil() + 1;
    blocked = Uint8List(nx * ny);
    dist = Float64List(nx * ny)..fillRange(0, nx * ny, double.infinity);
    for (int j = 0; j < ny; j++) {
      for (int i = 0; i < nx; i++) {
        if (!golfLegalSpot(hole, i * cell, j * cell)) blocked[j * nx + i] = 1;
      }
    }
    _dijkstra();
  }

  static final Expando<GolfGeo> _cache = Expando<GolfGeo>();
  static GolfGeo of(GHole h) => _cache[h] ??= GolfGeo._(h);

  static const double cell = 4;
  final GHole hole;
  late final int nx, ny;
  late final Uint8List blocked;
  late final Float64List dist;

  bool _sand(int i, int j) => hole.sand.any((GRect r) => r.has(i * cell, j * cell));

  void _dijkstra() {
    final int ci = (hole.cup.x / cell).round(), cj = (hole.cup.y / cell).round();
    final List<int> heap = <int>[];
    final List<double> key = <double>[];
    void push(int n, double d) {
      heap.add(n);
      key.add(d);
      int c = heap.length - 1;
      while (c > 0) {
        final int p = (c - 1) >> 1;
        if (key[p] <= key[c]) break;
        final int tn = heap[p];
        heap[p] = heap[c];
        heap[c] = tn;
        final double tk = key[p];
        key[p] = key[c];
        key[c] = tk;
        c = p;
      }
    }

    (int, double) pop() {
      final int n = heap.first;
      final double d = key.first;
      final int ln = heap.removeLast();
      final double lk = key.removeLast();
      if (heap.isNotEmpty) {
        heap[0] = ln;
        key[0] = lk;
        int c = 0;
        while (true) {
          final int l = 2 * c + 1, r = l + 1;
          int m = c;
          if (l < heap.length && key[l] < key[m]) m = l;
          if (r < heap.length && key[r] < key[m]) m = r;
          if (m == c) break;
          final int tn = heap[m];
          heap[m] = heap[c];
          heap[c] = tn;
          final double tk = key[m];
          key[m] = key[c];
          key[c] = tk;
          c = m;
        }
      }
      return (n, d);
    }

    final int start = cj * nx + ci;
    dist[start] = 0;
    push(start, 0);
    const List<(int, int, double)> nb = <(int, int, double)>[
      (1, 0, 1), (-1, 0, 1), (0, 1, 1), (0, -1, 1), (1, 1, 1.41421356), (1, -1, 1.41421356), (-1, 1, 1.41421356), (-1, -1, 1.41421356),
    ];
    while (heap.isNotEmpty) {
      final (int n, double d) = pop();
      if (d > dist[n]) continue;
      final int i = n % nx, j = n ~/ nx;
      for (final (int di, int dj, double w) in nb) {
        final int a = i + di, b = j + dj;
        if (a < 0 || b < 0 || a >= nx || b >= ny) continue;
        final int m = b * nx + a;
        if (blocked[m] == 1) continue;
        // no corner cutting through a blocked cell
        if (di != 0 && dj != 0 && (blocked[j * nx + a] == 1 || blocked[b * nx + i] == 1)) continue;
        final double nd = d + w * cell * (_sand(a, b) ? 3 : 1);
        if (nd < dist[m]) {
          dist[m] = nd;
          push(m, nd);
        }
      }
    }
  }

  /// Walking distance from (x, y) to the cup (large when unreachable).
  double at(double x, double y) {
    final int i = (x / cell).round().clamp(0, nx - 1), j = (y / cell).round().clamp(0, ny - 1);
    final double here = dist[j * nx + i];
    if (here.isFinite) return here + _offset(x, y, i, j);
    // a resting spot right against a rail can round into a blocked cell: use the best neighbour
    double best = double.infinity;
    for (int dj = -3; dj <= 3; dj++) {
      for (int di = -3; di <= 3; di++) {
        final int a = i + di, b = j + dj;
        if (a < 0 || b < 0 || a >= nx || b >= ny) continue;
        final double v = dist[b * nx + a];
        if (v.isFinite) best = math.min(best, v + _offset(x, y, a, b));
      }
    }
    return best.isFinite ? best : 1e5;
  }

  double _offset(double x, double y, int i, int j) => GolfMatch._dist(x, y, i * cell, j * cell);

  bool reachable(double x, double y) => at(x, y) < 1e4;

  /// Furthest point along the walking route that the ball can roll to in a straight line (or the cup itself).
  (double, double, bool) aimPoint(double x, double y) {
    if (_clear(x, y, hole.cup.x, hole.cup.y)) return (hole.cup.x, hole.cup.y, true);
    int i = (x / cell).round().clamp(0, nx - 1), j = (y / cell).round().clamp(0, ny - 1);
    if (!dist[j * nx + i].isFinite) {
      // step onto the nearest reachable cell
      double best = double.infinity;
      int bi = i, bj = j;
      for (int dj = -3; dj <= 3; dj++) {
        for (int di = -3; di <= 3; di++) {
          final int a = i + di, b = j + dj;
          if (a < 0 || b < 0 || a >= nx || b >= ny) continue;
          if (dist[b * nx + a] < best) {
            best = dist[b * nx + a];
            bi = a;
            bj = b;
          }
        }
      }
      i = bi;
      j = bj;
    }
    double tx = i * cell, ty = j * cell;
    for (int guard = 0; guard < 400; guard++) {
      int bi = i, bj = j;
      double bd = dist[j * nx + i];
      for (int dj = -1; dj <= 1; dj++) {
        for (int di = -1; di <= 1; di++) {
          final int a = i + di, b = j + dj;
          if (a < 0 || b < 0 || a >= nx || b >= ny) continue;
          if (dist[b * nx + a] < bd) {
            bd = dist[b * nx + a];
            bi = a;
            bj = b;
          }
        }
      }
      if (bi == i && bj == j) break;
      i = bi;
      j = bj;
      if (_clear(x, y, i * cell, j * cell)) {
        tx = i * cell;
        ty = j * cell;
      }
    }
    return (tx, ty, false);
  }

  /// A ball can roll straight from a to b without touching anything blocked.
  bool _clear(double ax, double ay, double bx, double by) {
    final double d = GolfMatch._dist(ax, ay, bx, by);
    final int n = math.max(1, (d / 2).ceil());
    for (int k = 1; k <= n; k++) {
      final double x = ax + (bx - ax) * k / n, y = ay + (by - ay) * k / n;
      final int i = (x / cell).round().clamp(0, nx - 1), j = (y / cell).round().clamp(0, ny - 1);
      if (blocked[j * nx + i] == 1 && GolfMatch._dist(x, y, ax, ay) > cell * 1.5) return false;
    }
    return true;
  }
}
