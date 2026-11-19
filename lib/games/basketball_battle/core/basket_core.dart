import 'dart:math' as math;

import 'basket_view.dart';

export 'basket_view.dart';

/// ANIX Basketball Battle — a 60-second shoot-out. Every player shoots on their own hoop at the same time; scores
/// are broadcast live (peer pattern) and the best score wins. Pure Dart, deterministic for a seed and independent
/// of the frame rate (fixed 240 Hz physics step behind an accumulator).
///
/// World: metres, regulation sizes. x = lateral (right +), y = height above the floor, z = depth away from the
/// shooter (the free-throw line is z = 0). The camera stands behind the shooter ([BasketCamera]).
///
/// Rules (match the rules text in the registry):
///  * swipe up to shoot; the ball is a real 3D projectile (gravity + air drag) that bounces off the rim (a torus),
///    the backboard (a plate, edges included) and the floor;
///  * a basket counts when the ball's centre falls through the rim plane inside the ring, coming from above;
///    a clean swish (no rim, no backboard) scores 3, anything else 2;
///  * three makes in a row set the shooter ON FIRE: every shot released while on fire scores double, until a miss;
///  * from 12 points the whole hoop starts sliding left/right, faster as the score grows;
///  * 60 s clock after a 3 s countdown; a shot released before the horn still counts (buzzer beater);
///  * ranking: points, then accuracy (made / shots); still level at the top = draw.

// ----------------------------------------------------------------------------------------------- real dimensions
const double kRimHeight = 3.05; // top of the ring above the floor
const double kRimInnerR = 0.2286; // 45.72 cm inside diameter
const double kRimTubeR = 0.008; // 16 mm rod
const double kRimRingR = kRimInnerR + kRimTubeR; // centre line of the rod
const double kBallR = 0.1194; // size 7 ball, 75 cm circumference
const double kBoardW = 1.83, kBoardH = 1.07, kBoardBottom = 2.90;
const double kBoardToRim = 0.1524; // board face to the inside edge of the ring (6 in)
const double kSquareW = 0.59, kSquareH = 0.45; // shooter's square, bottom edge level with the ring
const double kNetLen = 0.45;
const double kRimZ = 4.225; // free-throw line to the centre of the ring (horizontal)
const double kBoardZ = kRimZ + kRimInnerR + kBoardToRim; // ≈ 4.606: the line is 15 ft from the board
const double kBaselineZ = kBoardZ + 1.22;
const double kLaneW = 4.9; // FIBA key width
const double kReleaseY = 1.25; // ball in the shooter's hands
const double kReleaseZ = 0;
const double kRestHalfRange = 0.45; // lateral spread of the shooting spots
const double kSlideAmp = 0.6; // sliding hoop amplitude (m)

// ----------------------------------------------------------------------------------------------- physics tuning
const double kGravity = 9.81;

/// Quadratic air drag per unit mass: ½·ρ·Cd·A / m (ρ 1.204, Cd 0.47, A = π r², m = 0.62 kg).
const double kDrag = 0.5 * 1.204 * 0.47 * math.pi * kBallR * kBallR / 0.62;
const double kStep = 1 / 240;
const double kMaxSpeed = 14; // 14 m/s * kStep < ball radius: nothing can tunnel through rim, board or floor
const double kLaunchAngle = 58 * math.pi / 180;
const double kRimE = 0.58, kRimKeep = 0.86; // ball on steel ring: restitution, tangential speed kept
const double kBoardE = 0.72, kBoardKeep = 0.9;
const double kFloorE = 0.8, kFloorKeep = 0.88;
const double kRespawn = 0.55; // ball keeps bouncing this long after a shot is decided
const double kMaxShotTime = 5;

// ----------------------------------------------------------------------------------------------- swipe mapping
/// Swipes are measured in canvas units ([kCanvasW] x [kCanvasH]). Up must be at least [kMinSwipeUp].
const double kMinSwipeUp = 20;
const double kSwipeMin = 40, kSwipeMax = 560;

/// Launch speed gained per canvas unit of swipe length (m/s). 0.004 makes the "make" window ≈ 25 units wide.
const double kSpeedPerUnit = 0.004;

/// A perfect straight-on shot from the middle spot needs a swipe this long.
const double kIdealSwipe = 260;

class BEvent {
  const BEvent(this.kind, this.x, this.y, this.z, [this.value = 0]);

  /// rim | board | floor | swish | score | miss | fire | fireout | go | horn
  final String kind;
  final double x, y, z;
  final int value;
}

enum BallPhase { ready, flying, dead, idle }

/// Something that shoots on a court (the bot). Called once per fixed physics step.
abstract class BasketShooter {
  void think(BasketCourt court, double h);
}

/// Launch speed for a swipe of [length] canvas units.
double swipeSpeed(double length) =>
    _speedAt40 + (length.clamp(kSwipeMin, kSwipeMax) - kSwipeMin) * kSpeedPerUnit;

/// Swipe length that gives launch speed [v] (inverse of [swipeSpeed], unclamped).
double swipeLengthFor(double v) => kSwipeMin + (v - _speedAt40) / kSpeedPerUnit;

final double _speedAt40 = idealSpeed(0, 0) - (kIdealSwipe - kSwipeMin) * kSpeedPerUnit;

/// Free flight (no collisions) from a spot at lateral [bx] towards [tx] at rim depth, launched at [speed]:
/// horizontal distance travelled when the ball comes back down through the rim plane, or -1 if it never gets there.
double flightReach(double bx, double tx, double speed) => _flight(bx, tx, speed).$1;

/// Seconds until the ball falls through the rim plane (free flight), or -1.
double flightTime(double bx, double tx, double speed) => _flight(bx, tx, speed).$2;

(double, double) _flight(double bx, double tx, double speed) {
  final (double vx0, double vy0, double vz0) = launchVelocity(bx, tx, speed);
  double x = bx, y = kReleaseY, z = kReleaseZ, vx = vx0, vy = vy0, vz = vz0, t = 0;
  for (int i = 0; i < 2400; i++) {
    final double sp = math.sqrt(vx * vx + vy * vy + vz * vz);
    vx -= kDrag * sp * vx * kStep;
    vy -= (kGravity + kDrag * sp * vy) * kStep;
    vz -= kDrag * sp * vz * kStep;
    final double py = y;
    x += vx * kStep;
    y += vy * kStep;
    z += vz * kStep;
    t += kStep;
    if (vy < 0 && py >= kRimHeight && y < kRimHeight) {
      final double f = (py - kRimHeight) / (py - y);
      final double cx = x - vx * kStep * (1 - f), cz = z - vz * kStep * (1 - f);
      return (math.sqrt((cx - bx) * (cx - bx) + (cz - kReleaseZ) * (cz - kReleaseZ)), t - kStep * (1 - f));
    }
    if (vy < 0 && y < kRimHeight - 1) break;
  }
  return (-1, -1);
}

/// Velocity for a shot from lateral [bx] aimed at lateral [tx] at rim depth, at [speed] and [kLaunchAngle].
(double, double, double) launchVelocity(double bx, double tx, double speed) {
  final double dx = tx - bx, dz = kRimZ - kReleaseZ;
  final double d = math.sqrt(dx * dx + dz * dz);
  final double vh = speed * math.cos(kLaunchAngle);
  return (vh * dx / d, speed * math.sin(kLaunchAngle), vh * dz / d);
}

/// Launch speed that drops the ball through the centre of a hoop at lateral [tx] (bisection on [flightReach]).
double idealSpeed(double bx, double tx) {
  final double target = math.sqrt((tx - bx) * (tx - bx) + (kRimZ - kReleaseZ) * (kRimZ - kReleaseZ));
  double lo = 4, hi = 14;
  for (int i = 0; i < 50; i++) {
    final double mid = (lo + hi) / 2;
    final double r = flightReach(bx, tx, mid);
    if (r < 0 || r < target) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return (lo + hi) / 2;
}

class BasketCourt {
  BasketCourt({int seed = 1, this.duration = 60, this.countdown = 3, this.shooter}) : _rng = math.Random(seed) {
    _spawn();
  }

  final math.Random _rng;
  final double duration;
  BasketShooter? shooter;

  /// Seconds before the clock starts.
  double countdown;

  /// Game clock (seconds since GO), advanced in fixed steps.
  double time = 0;
  double _acc = 0;

  // ball (metres, m/s)
  double x = 0, y = kReleaseY, z = kReleaseZ, vx = 0, vy = 0, vz = 0;
  double restX = 0;

  /// Screen-plane rotation (rad) and its rate, for drawing the seams.
  double angle = 0, spin = 0;

  /// Backspin roll (rad) for drawing the seams moving over the top.
  double roll = 0, rollRate = 0;
  BallPhase phase = BallPhase.ready;
  double _phaseT = 0;
  bool _touchedRim = false, _touchedBoard = false, _scored = false, _upThrough = false, _inNet = false;
  bool _shotOnFire = false;

  // hoop
  double hoopX = 0, hoopVx = 0;
  double _slidePhase = 0, _slideOmega = 0;

  int score = 0;
  int streak = 0;
  int made = 0;
  int shots = 0;
  int swishes = 0;
  bool _hornSent = false;
  final List<BEvent> events = <BEvent>[];

  bool get flying => phase == BallPhase.flying;
  bool get ready => phase == BallPhase.ready;
  bool get onFire => streak >= 3;
  bool get clockRunning => countdown <= 0 && time < duration;
  bool get timeUp => time >= duration;

  /// The match is over for this shooter: the horn has gone and the last shot has been decided.
  bool get over => timeUp && phase != BallPhase.flying;
  double get left => math.max(0, duration - time);
  double get accuracy => shots == 0 ? 0 : made / shots;

  /// Whether the shot in the air is worth double (released while on fire).
  bool get shotOnFire => _shotOnFire;
  bool get inNet => _inNet;

  /// Target lateral sliding speed of the hoop (m/s): still below 12 points.
  double get hoopSpeed => score < 12 ? 0 : math.min(1.2, 0.35 + (score - 12) * 0.03);

  void _spawn() {
    restX = (_rng.nextDouble() * 2 - 1) * kRestHalfRange;
    x = restX;
    y = kReleaseY;
    z = kReleaseZ;
    vx = vy = vz = 0;
    spin = rollRate = 0;
    _touchedRim = _touchedBoard = _scored = _upThrough = _inNet = false;
    phase = BallPhase.ready;
    _phaseT = 0;
  }

  /// Throws the resting ball. [sx],[sy] = swipe vector in canvas units (up is negative y). The swipe length sets the
  /// launch speed; its direction, extended from the ball to the rim's height on screen, sets where it is aimed.
  bool throwBall(double sx, double sy) {
    if (phase != BallPhase.ready || !clockRunning) return false;
    if (sy > -kMinSwipeUp) return false;
    final double len = math.sqrt(sx * sx + sy * sy);
    final double tx = aimFromSwipe(restX, sx, sy);
    final (double ax, double ay, double az) = launchVelocity(restX, tx, swipeSpeed(len));
    vx = ax;
    vy = ay;
    vz = az;
    spin = vx / kBallR * 0.35;
    rollRate = -14; // natural backspin off the fingertips
    phase = BallPhase.flying;
    _phaseT = 0;
    _shotOnFire = onFire;
    shots++;
    return true;
  }

  /// World lateral position at rim depth that a swipe from the ball at [bx] points at on screen.
  static double aimFromSwipe(double bx, double sx, double sy) {
    final CanvasPoint b = BasketCamera.project(bx, kReleaseY, kReleaseZ);
    final double rimY = BasketCamera.project(0, kRimHeight, kRimZ).y;
    final double t = (rimY - b.y) / sy;
    return BasketCamera.unprojectX(b.x + sx * t, kRimZ);
  }

  /// Swipe (canvas units) that throws from the current spot at [tx] with launch [speed] — the inverse of [throwBall].
  (double, double) swipeFor(double tx, double speed) {
    final CanvasPoint b = BasketCamera.project(restX, kReleaseY, kReleaseZ);
    final CanvasPoint t = BasketCamera.project(tx, kRimHeight, kRimZ);
    final double dx = t.x - b.x, dy = t.y - b.y;
    final double d = math.sqrt(dx * dx + dy * dy);
    final double len = swipeLengthFor(speed);
    return (dx / d * len, dy / d * len);
  }

  /// Hoop lateral position [ahead] seconds from now if its speed does not change.
  double predictHoopX(double ahead) => _slideOmega == 0 ? hoopX : kSlideAmp * math.sin(_slidePhase + _slideOmega * ahead);

  /// Advances the court by a frame of [dt] seconds (fixed internal step; [dt] is clamped to 0.1 s).
  void step(double dt) {
    _acc += dt.clamp(0.0, 0.1);
    while (_acc >= kStep) {
      _acc -= kStep;
      _fixed(kStep);
    }
  }

  void _fixed(double h) {
    if (countdown > 0) {
      countdown -= h;
      if (countdown <= 0) {
        countdown = 0;
        events.add(const BEvent('go', 0, 0, 0));
      }
      return;
    }
    if (time < duration) {
      time = math.min(duration, time + h);
      if (time >= duration && !_hornSent) {
        _hornSent = true;
        events.add(const BEvent('horn', 0, 0, 0));
      }
    }
    shooter?.think(this, h);
    _slide(h);
    switch (phase) {
      case BallPhase.ready:
      case BallPhase.idle:
        if (phase == BallPhase.ready && timeUp) phase = BallPhase.idle;
        return;
      case BallPhase.flying:
      case BallPhase.dead:
        _phaseT += h;
        _integrate(h);
        if (phase == BallPhase.flying && (_phaseT > kMaxShotTime || _outOfPlay())) _decide();
        if (phase == BallPhase.dead && _phaseT > kRespawn) {
          if (timeUp) {
            phase = BallPhase.idle;
          } else {
            _spawn();
          }
        }
    }
  }

  void _slide(double h) {
    final double target = hoopSpeed / kSlideAmp;
    if (_slideOmega != target) {
      final double d = target - _slideOmega;
      final double m = 1.5 * h; // smooth speed changes, no jerks
      _slideOmega += d.clamp(-m, m);
    }
    if (_slideOmega == 0) {
      hoopVx = 0;
      return;
    }
    _slidePhase += _slideOmega * h;
    if (_slidePhase > math.pi * 2) _slidePhase -= math.pi * 2;
    hoopX = kSlideAmp * math.sin(_slidePhase);
    hoopVx = kSlideAmp * _slideOmega * math.cos(_slidePhase);
  }

  bool _outOfPlay() => z > kBaselineZ + 2 || z < BasketCamera.camZ + 0.6 || x.abs() > 5;

  void _integrate(double h) {
    final double sp = math.sqrt(vx * vx + vy * vy + vz * vz);
    vx -= kDrag * sp * vx * h;
    vy -= (kGravity + kDrag * sp * vy) * h;
    vz -= kDrag * sp * vz * h;
    final double s2 = math.sqrt(vx * vx + vy * vy + vz * vz);
    if (s2 > kMaxSpeed) {
      vx *= kMaxSpeed / s2;
      vy *= kMaxSpeed / s2;
      vz *= kMaxSpeed / s2;
    }
    final double px = x, py = y, pz = z;
    x += vx * h;
    y += vy * h;
    z += vz * h;
    angle += spin * h;
    roll += rollRate * h;
    spin *= math.exp(-0.4 * h);

    _collideRim();
    _collideBoard();
    _net(h);
    _scoreCheck(px, py, pz);
    _floor(h);
  }

  void _collideRim() {
    final double dx = x - hoopX, dz = z - kRimZ;
    final double hd = math.sqrt(dx * dx + dz * dz);
    double ux = 1, uz = 0;
    if (hd > 1e-9) {
      ux = dx / hd;
      uz = dz / hd;
    }
    // closest point on the ring's centre line
    final double qx = hoopX + ux * kRimRingR, qy = kRimHeight - kRimTubeR, qz = kRimZ + uz * kRimRingR;
    final double ex = x - qx, ey = y - qy, ez = z - qz;
    final double d = math.sqrt(ex * ex + ey * ey + ez * ez);
    const double min = kBallR + kRimTubeR;
    if (d >= min || d < 1e-9) return;
    final double nx = ex / d, ny = ey / d, nz = ez / d;
    x = qx + nx * min;
    y = qy + ny * min;
    z = qz + nz * min;
    if (_bounce(nx, ny, nz, hoopVx, kRimE, kRimKeep)) {
      spin = -spin * 0.5 + nx * 6;
      rollRate *= -0.4;
      if (phase == BallPhase.flying) {
        events.add(BEvent('rim', qx, qy, qz));
        _touchedRim = true;
      }
    }
  }

  void _collideBoard() {
    final double l = hoopX - kBoardW / 2, r = hoopX + kBoardW / 2;
    final double qx = x.clamp(l, r), qy = y.clamp(kBoardBottom, kBoardBottom + kBoardH);
    const double qz = kBoardZ;
    final double ex = x - qx, ey = y - qy, ez = z - qz;
    final double d = math.sqrt(ex * ex + ey * ey + ez * ez);
    if (d >= kBallR) return;
    double nx = 0, ny = 0, nz = -1;
    if (d > 1e-9) {
      nx = ex / d;
      ny = ey / d;
      nz = ez / d;
    }
    x = qx + nx * kBallR;
    y = qy + ny * kBallR;
    z = qz + nz * kBallR;
    if (_bounce(nx, ny, nz, hoopVx, kBoardE, kBoardKeep)) {
      spin *= 0.7;
      if (phase == BallPhase.flying) {
        events.add(BEvent('board', x, y, kBoardZ));
        _touchedBoard = true;
      }
    }
  }

  /// Reflects the velocity relative to a surface moving at [svx] along x. Returns whether it was approaching.
  bool _bounce(double nx, double ny, double nz, double svx, double e, double keep) {
    final double rx = vx - svx, ry = vy, rz = vz;
    final double vn = rx * nx + ry * ny + rz * nz;
    if (vn >= 0) return false;
    final double tx = rx - vn * nx, ty = ry - vn * ny, tz = rz - vn * nz;
    vx = svx + tx * keep - e * vn * nx;
    vy = ty * keep - e * vn * ny;
    vz = tz * keep - e * vn * nz;
    return vn < -0.15;
  }

  /// A made ball drops through the net: the mesh holds it inside a narrowing cone (soft, so nothing snaps),
  /// soaks up its sideways speed and brakes the fall until it drops out of the bottom.
  void _net(double h) {
    if (!_inNet) return;
    final double depth = kRimHeight - y;
    if (depth > kNetLen) {
      _inNet = false; // out of the bottom of the net, which drags its sideways speed away
      vx = hoopVx + (vx - hoopVx) * 0.4;
      vz *= 0.4;
      return;
    }
    if (depth < 0) return;
    final double t = depth / kNetLen;
    final double maxOff = math.max(0.02, kRimInnerR * (1 - 0.4 * t) - kBallR * 0.85);
    final double dx = x - hoopX, dz = z - kRimZ;
    final double hd = math.sqrt(dx * dx + dz * dz);
    if (hd > maxOff && hd > 1e-9) {
      final double ux = dx / hd, uz = dz / hd;
      final double pull = (hd - maxOff) * 400 * h; // the mesh stretches, then pulls back
      vx -= ux * pull;
      vz -= uz * pull;
      final double out = (vx - hoopVx) * ux + vz * uz;
      if (out > 0) {
        final double cut = out * (1 - math.exp(-60 * h));
        vx -= ux * cut;
        vz -= uz * cut;
      }
    }
    final double k = math.exp(-12 * h);
    vx = hoopVx + (vx - hoopVx) * k;
    vz *= k;
    if (vy < -1.0) vy = -1.0 + (vy + 1.0) * math.exp(-14 * h);
    spin *= k;
  }

  void _scoreCheck(double px, double py, double pz) {
    if (phase != BallPhase.flying || _scored) return;
    final bool down = py >= kRimHeight && y < kRimHeight;
    final bool up = py < kRimHeight && y >= kRimHeight;
    if (!down && !up) return;
    final double f = (py - kRimHeight) / (py - y);
    final double cx = px + (x - px) * f, cz = pz + (z - pz) * f;
    final double dx = cx - hoopX, dz = cz - kRimZ;
    if (dx * dx + dz * dz >= kRimInnerR * kRimInnerR) return;
    if (up) {
      _upThrough = true; // came up through the net: never a basket
      return;
    }
    if (_upThrough) return;
    _scored = true;
    _inNet = true;
    final bool clean = !_touchedRim && !_touchedBoard;
    final int base = clean ? 3 : 2;
    final int pts = _shotOnFire ? base * 2 : base;
    score += pts;
    made++;
    if (clean) swishes++;
    streak++;
    events.add(BEvent(clean ? 'swish' : 'score', hoopX, kRimHeight, kRimZ, pts));
    if (streak == 3) events.add(BEvent('fire', hoopX, kRimHeight, kRimZ));
  }

  void _floor(double h) {
    if (y - kBallR > 0) return;
    y = kBallR;
    if (vy < 0) {
      if (vy < -0.8) events.add(BEvent('floor', x, 0, z, (-vy * 10).round()));
      vy = -vy * kFloorE;
      vx *= kFloorKeep;
      vz *= kFloorKeep;
      rollRate = vz / kBallR;
      if (vy < 0.25) vy = 0;
    }
    if (vy == 0) {
      final double k = math.exp(-1.5 * h); // rolling resistance
      vx *= k;
      vz *= k;
    }
    if (phase == BallPhase.flying) _decide();
  }

  /// The shot is over (floor, out of play or too long): a miss unless it went in.
  void _decide() {
    if (!_scored) {
      final bool wasOnFire = onFire;
      streak = 0;
      events.add(BEvent('miss', x, y, z));
      if (wasOnFire) events.add(BEvent('fireout', x, y, z));
    }
    phase = BallPhase.dead;
    _phaseT = 0;
  }
}

/// Offline opponent. It really plays: it owns a [BasketCourt] with the same physics and swipes like a person —
/// reaction pause after each new ball, aim at the rim (leading a sliding hoop) and a swipe length, both with
/// skill-scaled human error. Its score comes only from balls that actually go in.
class BasketBot implements BasketShooter {
  BasketBot({required int seed, required this.skill, double duration = 60, double countdown = 0})
      : _rng = math.Random(seed * 7919 + 13) {
    court = BasketCourt(seed: seed, duration: duration, countdown: countdown, shooter: this);
  }

  final math.Random _rng;
  final double skill;
  late final BasketCourt court;
  double? _wait;

  int get score => court.score;
  int get streak => court.streak;
  int get made => court.made;
  int get shots => court.shots;
  bool get over => court.over;

  /// Advances the bot's court; returns the points it scored during this frame (0 most frames).
  int step(double dt, [double? duration]) {
    final int before = court.score;
    court.step(dt);
    court.events.clear();
    return court.score - before;
  }

  double _gauss() {
    final double u = math.max(1e-12, _rng.nextDouble()), v = _rng.nextDouble();
    return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v);
  }

  @override
  void think(BasketCourt c, double h) {
    if (!c.ready || !c.clockRunning) {
      _wait = null;
      return;
    }
    _wait ??= 0.3 + (1 - skill) * 0.7 + _rng.nextDouble() * 0.45;
    _wait = _wait! - h;
    if (_wait! > 0) return;
    _wait = null;
    // lead a sliding hoop: a skilled bot predicts where the rim will be when the ball drops
    final double v0 = idealSpeed(c.restX, c.hoopX);
    final double t = flightTime(c.restX, c.hoopX, v0);
    final double lead = c.predictHoopX(t < 0 ? 1 : t);
    final double aimErr = 0.05 + (1 - skill) * 0.12;
    final double tx = c.hoopX + (lead - c.hoopX) * (0.35 + 0.65 * skill) + _gauss() * aimErr;
    final double v = idealSpeed(c.restX, tx);
    final double lenErr = 12 + (1 - skill) * 26;
    final double len = swipeLengthFor(v) + _gauss() * lenErr;
    final (double sx, double sy) = c.swipeFor(tx, swipeSpeed(len));
    c.throwBall(sx, sy);
  }
}

/// One player's final line: used to rank seats the same way on every phone.
class BasketLine {
  const BasketLine(this.score, this.made, this.shots);
  final int score, made, shots;
  double get accuracy => shots == 0 ? 0 : made / shots;

  /// > 0 when this line beats [o].
  int compare(BasketLine o) {
    if (score != o.score) return score.compareTo(o.score);
    final int a = made * o.shots, b = o.made * shots; // exact accuracy comparison, no float error
    if (shots == 0 || o.shots == 0) return 0;
    return a.compareTo(b);
  }
}

/// Seats best → worst ([forfeited] last) and the seats sharing first place (more than one = a draw at the top).
({List<int> order, List<int> top}) rankBasket(Map<int, BasketLine> lines, {Set<int> forfeited = const <int>{}}) {
  final List<int> seats = lines.keys.toList()..sort();
  final List<int> live = seats.where((int s) => !forfeited.contains(s)).toList();
  final List<int> out = seats.where(forfeited.contains).toList();
  live.sort((int a, int b) {
    final int c = lines[b]!.compare(lines[a]!);
    return c != 0 ? c : a.compareTo(b);
  });
  final List<int> top = live.isEmpty
      ? <int>[]
      : <int>[for (final int s in live) if (lines[s]!.compare(lines[live.first]!) == 0) s];
  return (order: <int>[...live, ...out], top: top);
}

/// Offline match: the local shooter plus bots, all stepped in lock-step with the same clock.
class BasketMatch {
  BasketMatch({required int seed, required List<double> botSkills, this.duration = 60, double countdown = 3})
      : me = BasketCourt(seed: seed, duration: duration, countdown: countdown) {
    for (int i = 0; i < botSkills.length; i++) {
      bots.add(BasketBot(seed: seed + (i + 1) * 7, skill: botSkills[i], duration: duration, countdown: countdown));
    }
  }

  final double duration;
  final BasketCourt me;
  final List<BasketBot> bots = <BasketBot>[];

  /// Points scored by each bot during the last [step] (for HUD pops).
  late List<int> botPoints = List<int>.filled(bots.length, 0);

  void step(double dt) {
    me.step(dt);
    for (int i = 0; i < bots.length; i++) {
      botPoints[i] = bots[i].step(dt);
    }
  }

  bool get over => me.over && bots.every((BasketBot b) => b.over);

  Map<int, BasketLine> get lines => <int, BasketLine>{
        0: BasketLine(me.score, me.made, me.shots),
        for (int i = 0; i < bots.length; i++) i + 1: BasketLine(bots[i].score, bots[i].made, bots[i].shots),
      };
}
