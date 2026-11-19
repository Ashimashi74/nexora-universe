import 'dart:math' as math;

/// Pure-Dart kart racing simulation (CTR style): closed walled track from a seed, drift + mini-turbo, boost pads,
/// item boxes (turbo, homing missile, shield, oil slick), checkpoint-validated laps, positions and bot drivers.
/// No Flutter imports: unit-tested and identical on every phone.
///
/// Units: world units (a kart is [KartDims.length] x [KartDims.width]); time in seconds. The simulation always
/// advances in fixed [kFixedDt] steps (frame time is accumulated and clamped to [kMaxFrameDt]), so the result of a
/// race depends only on the seed and the inputs, never on the phone's frame rate.

const double kFixedDt = 1 / 120;
const double kMaxFrameDt = 0.1;

class V2 {
  const V2(this.x, this.y);
  final double x, y;
  static const V2 zero = V2(0, 0);
  V2 operator +(V2 o) => V2(x + o.x, y + o.y);
  V2 operator -(V2 o) => V2(x - o.x, y - o.y);
  V2 operator *(double k) => V2(x * k, y * k);
  V2 operator -() => V2(-x, -y);
  double dot(V2 o) => x * o.x + y * o.y;
  double cross(V2 o) => x * o.y - y * o.x;
  double get len => math.sqrt(x * x + y * y);
  double get len2 => x * x + y * y;
  double dist(V2 o) => (this - o).len;
  V2 get unit {
    final double l = len;
    return l == 0 ? const V2(1, 0) : V2(x / l, y / l);
  }

  /// Right-hand normal in screen space (y down): rotates the vector +90°.
  V2 get perp => V2(-y, x);
  static V2 polar(double a, [double r = 1]) => V2(math.cos(a) * r, math.sin(a) * r);
}

/// Wraps an angle to (-pi, pi].
double wrapAngle(double a) {
  a = a % (math.pi * 2);
  if (a > math.pi) a -= math.pi * 2;
  if (a <= -math.pi) a += math.pi * 2;
  return a;
}

/// Kart footprint. The drawn kart (sprite rect and vector fallback) fills exactly this box (nose pointing +x);
/// the collision shape is the capsule made of two circles of radius [r] at ±[circleOffset] along the heading,
/// i.e. a rounded box of the same length and width.
class KartDims {
  static const double length = 52;
  static const double width = 36;
  static const double r = width / 2;
  static const double circleOffset = length / 2 - r;

  /// Radius of the circle enclosing the kart (for culling / screen-space checks).
  static double get halfDiagonal => math.sqrt(length * length + width * width) / 2;
}

/// Prop sizes, shared by the simulation (hit tests) and the renderer (drawn size).
class KartProps {
  static const double boxSize = 30; // item box, square
  static const double oilW = 50, oilH = 38; // oil slick oval
  static const double oilR = 19; // hit radius (inscribed in the oval)
  static const double missileR = 8;
  static const double padLength = 64; // boost pad along the track
  static double padWidth(double trackWidth) => trackWidth * 0.4;
}

/// Closest-point query result on the track centre line.
class TrackHit {
  const TrackHit(this.seg, this.t, this.point, this.lateral, this.dist);
  final int seg;
  final double t;
  final V2 point;

  /// Signed offset from the centre line (+ = right of the direction of travel).
  final double lateral;
  final double dist;

  /// Continuous track coordinate in samples.
  double get s => seg + t;
}

class KartTrack {
  KartTrack(this.points, {this.width = 180, this.runoff = 56}) {
    _build();
  }

  /// Generates a smooth star-shaped (never self-intersecting) closed track, resampled to uniform spacing.
  /// The amplitude is reduced until every corner is drivable (min radius) and no two parts of the track
  /// come closer than two wall offsets (walls never overlap another part of the track).
  factory KartTrack.generate(int seed) {
    final math.Random r = math.Random(seed);
    final int k1 = 2 + r.nextInt(2), k2 = 3 + r.nextInt(3);
    final double p1 = r.nextDouble() * math.pi * 2, p2 = r.nextDouble() * math.pi * 2;
    final double a1 = 0.14 + r.nextDouble() * 0.12, a2 = 0.06 + r.nextDouble() * 0.08;
    double amp = 1;
    List<V2> pts = const <V2>[];
    for (int attempt = 0; attempt < 16; attempt++) {
      const int dense = 900;
      final List<V2> raw = <V2>[];
      for (int i = 0; i < dense; i++) {
        final double t = i / dense * math.pi * 2;
        final double rad = 1 + a1 * amp * math.sin(k1 * t + p1) + a2 * amp * math.sin(k2 * t + p2);
        raw.add(V2(math.cos(t) * 1380 * rad, math.sin(t) * 910 * rad));
      }
      pts = resample(raw, 24);
      if (minRadius(raw) >= minCornerRadius && _clear(pts, 180 / 2 + 56)) break;
      amp *= 0.85;
    }
    return KartTrack(pts);
  }

  static const double minCornerRadius = 175;

  /// Asphalt edge to the start of the grass (red/white curb): no slowdown on the curb.
  static const double curb = 14;
  static const int gateCount = 16;

  final List<V2> points;

  /// Asphalt width.
  final double width;

  /// Grass between the curb edge... and the tyre wall, measured from the asphalt edge.
  final double runoff;

  /// Distance from the centre line to the face of the walls (both sides). Drawn and collided identically.
  double get wallOffset => width / 2 + runoff;

  late final List<V2> _dirs;
  late final List<double> _lineOff;
  late final List<double> _lineRadius;
  late final double length;
  late final double spacing;

  int get n => points.length;
  V2 at(int i) => points[((i % n) + n) % n];

  /// Unit direction of travel at sample [i].
  V2 dir(int i) => _dirs[((i % n) + n) % n];

  /// Right-hand normal at sample [i].
  V2 nrm(int i) => dir(i).perp;

  /// Centre-line point at continuous coordinate [s].
  V2 centerAt(double s) {
    final int i = s.floor();
    final double f = s - i;
    return at(i) * (1 - f) + at(i + 1) * f;
  }

  V2 dirAt(double s) {
    final int i = s.floor();
    final double f = s - i;
    return (dir(i) * (1 - f) + dir(i + 1) * f).unit;
  }

  /// Racing-line lateral offset at sample [i] (+ = right).
  double lineOffset(int i) => _lineOff[((i % n) + n) % n];
  double lineOffsetAt(double s) {
    final int i = s.floor();
    final double f = s - i;
    return lineOffset(i) * (1 - f) + lineOffset(i + 1) * f;
  }

  V2 lineAt(double s) => centerAt(s) + dirAt(s).perp * lineOffsetAt(s);

  /// Racing-line radius of curvature at sample [i] (large on straights).
  double lineRadius(int i) => _lineRadius[((i % n) + n) % n];

  /// Signed difference b - a in samples, wrapped to (-n/2, n/2].
  double wrapDelta(double d) {
    d = d % n;
    if (d > n / 2) d -= n;
    return d;
  }

  void _build() {
    final int count = points.length;
    _dirs = <V2>[for (int i = 0; i < count; i++) (at(i + 1) - at(i - 1)).unit];
    double s = 0;
    for (int i = 0; i < count; i++) {
      s += at(i).dist(at(i + 1));
    }
    length = s;
    spacing = s / count;
    // Minimum-curvature racing line: relax each point towards its neighbours' midpoint, constrained laterally
    // so the whole kart stays on the asphalt with a margin.
    final double maxOff = width / 2 - KartDims.width / 2 - 10;
    final List<double> off = List<double>.filled(count, 0);
    V2 p(int j) {
      final int k = ((j % count) + count) % count;
      return points[k] + _dirs[k].perp * off[k];
    }

    for (int it = 0; it < 500; it++) {
      for (int i = 0; i < count; i++) {
        final V2 mid = (p(i - 1) + p(i + 1)) * 0.5;
        off[i] = (mid - points[i]).dot(_dirs[i].perp).clamp(-maxOff, maxOff);
      }
    }
    _lineOff = off;
    _lineRadius = <double>[
      for (int i = 0; i < count; i++) circumRadius(p(i - 2), p(i), p(i + 2)),
    ];
  }

  double get totalLength => length;

  /// Closest point of the centre polyline to [p]. Searches around [hint] (a segment index) and falls back to the
  /// whole track when the hint is missing or clearly wrong.
  TrackHit project(V2 p, [int hint = -1]) {
    if (hint >= 0) {
      TrackHit? best;
      int bestK = 0;
      for (int k = -10; k <= 10; k++) {
        final TrackHit h = _seg(hint + k, p);
        if (best == null || h.dist < best.dist) {
          best = h;
          bestK = k;
        }
      }
      // a minimum on the edge of the window means the point is outside it (teleport, stale hint)
      if (best!.dist <= wallOffset + 60 && bestK.abs() < 10) return best;
    }
    TrackHit? best;
    for (int i = 0; i < n; i++) {
      final TrackHit h = _seg(i, p);
      if (best == null || h.dist < best.dist) best = h;
    }
    return best!;
  }

  TrackHit _seg(int i0, V2 p) {
    final int i = ((i0 % n) + n) % n;
    final V2 a = points[i], b = at(i + 1);
    final V2 ab = b - a;
    final double l2 = ab.len2;
    final double t = l2 == 0 ? 0 : ((p - a).dot(ab) / l2).clamp(0.0, 1.0);
    final V2 c = a + ab * t;
    final V2 d = p - c;
    final double lat = d.dot(ab.unit.perp);
    return TrackHit(i, t, c, lat, d.len);
  }

  /// Nearest sample to [p], searching around [hint] (or the whole track when hint < 0).
  int nearest(V2 p, [int hint = -1]) {
    final TrackHit h = project(p, hint);
    return (h.t < 0.5 ? h.seg : h.seg + 1) % n;
  }

  /// Distance beyond the asphalt edge (0 on the asphalt).
  double offTrack(V2 p, int idx) => math.max(0, project(p, idx).dist - width / 2);

  static double circumRadius(V2 a, V2 b, V2 c) {
    final double cr = (b - a).cross(c - a).abs();
    if (cr < 1e-9) return 1e9;
    return a.dist(b) * b.dist(c) * c.dist(a) / (2 * cr);
  }

  static double minRadius(List<V2> pts) {
    double best = double.infinity;
    final int m = pts.length;
    for (int i = 0; i < m; i++) {
      best = math.min(best, circumRadius(pts[(i - 1 + m) % m], pts[i], pts[(i + 1) % m]));
    }
    return best;
  }

  static bool _clear(List<V2> pts, double wall) {
    final int m = pts.length;
    double len = 0;
    for (int i = 0; i < m; i++) {
      len += pts[i].dist(pts[(i + 1) % m]);
    }
    final double sp = len / m;
    final int skip = (wall * 4 / sp).ceil();
    for (int i = 0; i < m; i++) {
      for (int j = i + skip; j < m; j++) {
        if (m - (j - i) < skip) continue;
        if (pts[i].dist(pts[j]) < wall * 2 + 80) return false;
      }
    }
    return true;
  }

  /// Uniform arc-length resampling of a closed polyline.
  static List<V2> resample(List<V2> raw, double step) {
    final int m = raw.length;
    double len = 0;
    for (int i = 0; i < m; i++) {
      len += raw[i].dist(raw[(i + 1) % m]);
    }
    final int count = math.max(8, (len / step).round());
    final double sp = len / count;
    final List<V2> out = <V2>[raw[0]];
    double carried = 0;
    int i = 0;
    double target = sp;
    while (out.length < count && i < m) {
      final V2 a = raw[i], b = raw[(i + 1) % m];
      final double sl = a.dist(b);
      while (carried + sl >= target && out.length < count) {
        final double f = (target - carried) / sl;
        out.add(a + (b - a) * f);
        target += sp;
      }
      carried += sl;
      i++;
    }
    return out;
  }
}

enum KartItem { none, turbo, missile, shield, oil }

class Kart {
  Kart(this.seat, this.pos, this.heading);
  final int seat;
  V2 pos;
  double heading;
  V2 vel = V2.zero;

  /// Forward speed (velocity along the heading), updated every step.
  double speed = 0;

  /// Steering input -1..1 and the smoothed value actually applied.
  double steer = 0;
  double steerApplied = 0;
  bool brake = false;
  bool drifting = false;
  int driftDir = 0;
  double driftCharge = 0;
  double boost = 0;
  double spin = 0;
  double shield = 0;
  double itemHeld = 0;
  KartItem item = KartItem.none;

  /// Engine multiplier (1 for humans; bots get skill + rubber banding).
  double engine = 1;

  /// Nearest centre-line segment and continuous track coordinate (samples).
  int idx = 0;
  double s = 0;

  /// Gates passed in order since the start (gate 0 = start/finish line).
  int passed = 0;

  /// Completed laps.
  int lap = 0;
  bool finished = false;
  double finishTime = 0;
  int finishPlace = 0;

  /// Continuous race distance in samples (0 at the first crossing of the line, laps*n at the finish).
  double raceProgress = 0;

  /// Visual slip angle (velocity direction relative to the heading).
  double slip = 0;

  /// Seconds spent driving the wrong way.
  double wrongWay = 0;
  bool get isWrongWay => wrongWay > 1.0;
}

class Missile {
  Missile(this.owner, this.target, this.pos, this.idx) : s = idx.toDouble();
  final int owner;
  final int target;

  /// True when fired with nobody ahead: it flies down the track and hits the first kart it meets.
  bool get free => target < 0;
  V2 pos;
  int idx;
  double s;
  double life = 6;
}

class OilSlick {
  OilSlick(this.pos, {this.owner = -1});
  final V2 pos;
  final int owner;
  double life = 18;
  double age = 0;
}

class ItemBox {
  ItemBox(this.pos);
  final V2 pos;
  double respawn = 0;
  bool get active => respawn <= 0;
}

class KartEvent {
  const KartEvent(this.kind, this.seat, [this.x = 0, this.y = 0, this.other = -1]);
  final String kind; // pickup, boost, pad, hit, missile_hit, shield, shield_break, lap, finish, bump, wall
  final int seat;
  final double x, y;
  final int other;
}

class KartRace {
  KartRace({required this.seed, required this.racers, this.laps = 3, this.botSkill = const <double>[]}) {
    track = KartTrack.generate(seed);
    _r = math.Random(seed ^ 0x5bd1e995);
    final int n = track.n;
    for (int g = 0; g < KartTrack.gateCount; g++) {
      gates.add(g * n / KartTrack.gateCount);
    }
    final V2 d = track.dir(0);
    final double rowGap = (KartDims.length * 1.6 / track.spacing).ceilToDouble();
    for (int i = 0; i < racers; i++) {
      final int row = i ~/ 2;
      final double side = (i.isEven ? -1 : 1) * track.width / 4;
      final double s0 = -2.5 - row * rowGap;
      final V2 p = track.centerAt(s0 + n) + track.dirAt(s0 + n).perp * side;
      final Kart k = Kart(i, p, math.atan2(d.y, d.x));
      final TrackHit h = track.project(p);
      k
        ..idx = h.seg
        ..s = h.s;
      k.raceProgress = track.wrapDelta(k.s);
      karts.add(k);
    }
    for (int s = 0; s < 4; s++) {
      final int i = (n * (s + 0.5) / 4).round();
      final V2 c = track.at(i), nn = track.nrm(i);
      for (int k = -1; k <= 1; k++) {
        boxes.add(ItemBox(c + nn * (k * track.width * 0.27)));
      }
    }
    for (int s = 0; s < 3; s++) {
      pads.add((n * (s + 0.25) / 3).round());
    }
  }

  final int seed;
  final int racers;
  final int laps;

  /// Per-seat bot skill 0..1 (seats without an entry, or with 0, are human).
  final List<double> botSkill;
  late final KartTrack track;
  late final math.Random _r;
  final List<Kart> karts = <Kart>[];
  final List<Missile> missiles = <Missile>[];
  final List<OilSlick> oils = <OilSlick>[];
  final List<ItemBox> boxes = <ItemBox>[];
  final List<int> pads = <int>[];
  final List<double> gates = <double>[];
  final List<KartEvent> events = <KartEvent>[];

  /// Simulated time including the countdown.
  double time = 0;
  double countdown = 3;
  double _acc = 0;
  final List<int> finishOrder = <int>[];

  /// Fixed steps simulated so far.
  int ticks = 0;

  // ---- tuning (world units / s) ----
  static const double maxSpeed = 380;
  static const double accel = 560;
  static const double brakeDecel = 900;
  static const double turnMax = 3.0;
  static const double gripNormal = 14, gripDrift = 4.5, gripGrass = 9;
  static const double boostTop = 1.35;
  static const double spinTime = 0.8;
  static const double wallRestitution = 0.3;
  static const double kartRestitution = 0.45;

  /// Kept for compatibility: radius of each of the two collision circles.
  static const double kartR = KartDims.r;

  bool get started => countdown <= 0;
  bool get allFinished => karts.every((Kart k) => k.finished);

  /// Race clock (0 at GO).
  double get raceTime => math.max(0, time - 3);
  int get finishPasses => laps * KartTrack.gateCount + 1;
  double get gateGap => track.n / KartTrack.gateCount;

  bool isBot(int seat) => seat < botSkill.length && botSkill[seat] > 0;

  /// Race standings (index 0 = leader): finishers by finishing order, then by race distance.
  List<Kart> standings() {
    final List<Kart> l = List<Kart>.of(karts);
    l.sort((Kart a, Kart b) {
      if (a.finished && b.finished) {
        final int c = a.finishPlace.compareTo(b.finishPlace);
        return c != 0 ? c : a.finishTime.compareTo(b.finishTime);
      }
      if (a.finished) return -1;
      if (b.finished) return 1;
      final int c = b.raceProgress.compareTo(a.raceProgress);
      return c != 0 ? c : a.seat.compareTo(b.seat);
    });
    return l;
  }

  int placeOf(int seat) => standings().indexWhere((Kart k) => k.seat == seat) + 1;

  /// Human input for [seat]: steer -1..1, drift held, use item pressed (edge), brake held.
  void input(int seat, double steer, bool drift, bool useItem, {bool brake = false}) {
    final Kart k = karts[seat];
    if (k.finished) return; // autopilot after the line
    k.steer = steer.clamp(-1.0, 1.0);
    k.brake = brake;
    _driftInput(k, drift);
    if (useItem && started) this.useItem(seat);
  }

  void _driftInput(Kart k, bool drift) {
    if (drift && !k.drifting && k.spin <= 0 && k.speed > 160 && k.steer.abs() > 0.2) {
      k.drifting = true;
      k.driftDir = k.steer.sign.toInt();
      k.driftCharge = 0;
    } else if (!drift && k.drifting) {
      _endDrift(k);
    }
  }

  /// Mini-turbo thresholds (blue → orange → purple sparks).
  static const double driftLv1 = 0.8, driftLv2 = 1.6;

  void _endDrift(Kart k, {bool award = true}) {
    k.drifting = false;
    if (award && k.driftCharge > driftLv2) {
      k.boost = math.max(k.boost, 1.1);
      events.add(KartEvent('boost', k.seat, k.pos.x, k.pos.y, 2));
    } else if (award && k.driftCharge > driftLv1) {
      k.boost = math.max(k.boost, 0.6);
      events.add(KartEvent('boost', k.seat, k.pos.x, k.pos.y, 1));
    }
    k.driftCharge = 0;
  }

  void useItem(int seat) {
    final Kart k = karts[seat];
    switch (k.item) {
      case KartItem.none:
        return;
      case KartItem.turbo:
        k.boost = math.max(k.boost, 1.6);
        events.add(KartEvent('boost', seat, k.pos.x, k.pos.y, 3));
      case KartItem.shield:
        k.shield = 8;
        events.add(KartEvent('shield', seat, k.pos.x, k.pos.y));
      case KartItem.oil:
        final V2 back = V2.polar(k.heading, -(KartDims.length / 2 + KartProps.oilR + 8));
        oils.add(OilSlick(k.pos + back, owner: seat));
      case KartItem.missile:
        // homes onto the racer directly ahead; the leader's missile flies free down the track
        final List<Kart> st = standings();
        final int me = st.indexWhere((Kart x) => x.seat == seat);
        launchMissile(seat, me > 0 ? st[me - 1].seat : -1);
    }
    k.item = KartItem.none;
    k.itemHeld = 0;
  }

  /// Fires a homing missile from [owner] at [target] (also used for missiles fired on another phone).
  Missile launchMissile(int owner, int target) {
    final Kart k = karts[owner];
    final Missile m = Missile(owner, target < 0 || target >= karts.length ? -1 : target,
        k.pos + V2.polar(k.heading, KartDims.length / 2), k.idx);
    missiles.add(m);
    return m;
  }

  /// Applies a hit to [seat] (missile / oil / remote event). Shield absorbs it.
  void hit(int seat, {int by = -1}) {
    final Kart k = karts[seat];
    if (k.shield > 0) {
      k.shield = 0;
      events.add(KartEvent('shield_break', seat, k.pos.x, k.pos.y));
      return;
    }
    k.spin = spinTime;
    k.vel = k.vel * 0.4;
    k.speed *= 0.4;
    _endDrift(k, award: false);
    k.boost = 0;
    events.add(KartEvent('hit', seat, k.pos.x, k.pos.y, by));
  }

  KartItem _roll(int place) {
    final double behind = racers <= 1 ? 0 : (place - 1) / (racers - 1);
    final double x = _r.nextDouble();
    if (place == 1) {
      // nobody ahead to hit: the leader gets defensive items
      if (x < 0.3) return KartItem.turbo;
      if (x < 0.65) return KartItem.shield;
      return KartItem.oil;
    }
    if (x < 0.25 + behind * 0.25) return KartItem.turbo;
    if (x < 0.5 + behind * 0.2) return KartItem.missile;
    if (x < 0.78) return KartItem.shield;
    return KartItem.oil;
  }

  /// Advances the race by a frame of [dt] seconds (clamped), in fixed [kFixedDt] steps.
  /// [simulate] = seats this phone simulates (all offline; own seat online).
  void step(double dt, {Set<int>? simulate}) {
    if (!(dt > 0)) return;
    _acc += math.min(dt, kMaxFrameDt);
    while (_acc >= kFixedDt - 1e-9) {
      _acc -= kFixedDt;
      _fixed(kFixedDt, simulate);
    }
  }

  /// Runs the race headlessly until every kart has finished (or [maxSeconds] of race time passed).
  /// Unfinished human karts are driven by the autopilot. Used offline to produce the real finishing order.
  void simulateToEnd({double maxSeconds = 300}) {
    final double end = time + maxSeconds;
    while (!allFinished && time < end) {
      _fixed(kFixedDt, null, autopilotAll: true);
    }
  }

  bool _sim(Set<int>? simulate, int seat) => simulate == null || simulate.contains(seat);

  void _fixed(double h, Set<int>? simulate, {bool autopilotAll = false}) {
    ticks++;
    time += h;
    if (countdown > 0) {
      countdown -= h;
      return;
    }
    final int? bestHuman = _bestHumanSeat();
    for (final Kart k in karts) {
      if (!_sim(simulate, k.seat)) continue;
      if (k.finished || autopilotAll || isBot(k.seat)) {
        final double skill = isBot(k.seat) ? botSkill[k.seat] : 0.6;
        _bot(k, h, skill, bestHuman);
      }
      _physics(k, h);
    }
    for (final Kart k in karts) {
      if (_sim(simulate, k.seat)) _walls(k);
    }
    for (int pass = 0; pass < 2; pass++) {
      for (int i = 0; i < karts.length; i++) {
        for (int j = i + 1; j < karts.length; j++) {
          _collideKarts(karts[i], karts[j], simulate, pass == 0);
        }
      }
    }
    for (final Kart k in karts) {
      if (_sim(simulate, k.seat)) _progress(k, h);
    }
    _items(h, simulate);
  }

  int? _bestHumanSeat() {
    Kart? best;
    for (final Kart k in karts) {
      if (isBot(k.seat)) continue;
      if (best == null || k.raceProgress > best.raceProgress) best = k;
    }
    return best?.seat;
  }

  void _physics(Kart k, double h) {
    // ---- steering (speed-sensitive) ----
    final double rate = 8 * h;
    k.steerApplied += (k.steer - k.steerApplied).clamp(-rate, rate);
    final TrackHit th = track.project(k.pos, k.idx);
    final bool grass = th.dist > track.width / 2 + KartTrack.curb;
    double fwdSpeed = k.vel.dot(V2.polar(k.heading));
    if (k.spin > 0) {
      k.spin -= h;
      k.heading += h * (math.pi * 4 / spinTime);
    } else {
      final double f = (fwdSpeed.abs() / 90).clamp(0.0, 1.0) * (1 - 0.45 * (fwdSpeed / maxSpeed).clamp(0.0, 1.0));
      double yaw;
      if (k.drifting) {
        yaw = (k.driftDir * 0.8 + k.steerApplied * 0.55) * turnMax * f;
        k.driftCharge += h * (0.55 + 0.75 * (k.steerApplied * k.driftDir).clamp(0.0, 1.0));
        if (fwdSpeed < 120 || grass) _endDrift(k, award: !grass);
      } else {
        yaw = k.steerApplied * turnMax * f;
      }
      k.heading += yaw * h;
    }
    k.heading = wrapAngle(k.heading);
    final V2 fwd = V2.polar(k.heading);
    // ---- grip: the velocity direction follows the heading at a rate set by the tyre grip ----
    final double grip = k.spin > 0 ? 1.5 : (k.drifting ? gripDrift : (grass ? gripGrass : gripNormal));
    double mag = k.vel.len;
    if (mag > 1e-6) {
      final double va = math.atan2(k.vel.y, k.vel.x);
      final double slip = wrapAngle(va - k.heading);
      if (slip.abs() <= math.pi / 2) {
        final double ns = slip * math.exp(-grip * h);
        final double scrub = k.drifting ? 0.15 : (grass ? 1.0 : 0.5);
        mag *= math.max(0, 1 - scrub * slip.abs() * h);
        k.vel = V2.polar(k.heading + ns, mag);
      } else {
        // moving backwards relative to the nose (after a bounce or spin): damp both components
        final V2 right = fwd.perp;
        double vf = k.vel.dot(fwd), vl = k.vel.dot(right);
        vl *= math.exp(-grip * h);
        vf = math.min(0, vf + brakeDecel * 0.7 * h);
        k.vel = fwd * vf + right * vl;
      }
    }
    // ---- longitudinal: auto throttle with a falling acceleration curve, brake, off-track drag ----
    fwdSpeed = k.vel.dot(fwd);
    double top = maxSpeed * k.engine * (k.finished ? 0.6 : 1);
    if (grass) top *= 0.5;
    if (k.boost > 0) {
      k.boost -= h;
      top = math.max(top * boostTop, maxSpeed * k.engine * (grass ? 0.9 : boostTop));
    }
    double a = 0;
    if (k.spin > 0) {
      a = -fwdSpeed * 2.2;
    } else if (k.brake) {
      a = fwdSpeed > 0 ? -math.min(brakeDecel, fwdSpeed / h) : 0;
    } else if (fwdSpeed < top) {
      a = accel * (1 - math.max(0, fwdSpeed) / top) + (k.boost > 0 ? 500 : 0);
      a = math.min(a, (top - fwdSpeed) / h);
    } else {
      a = -math.min(grass ? 700.0 : 260.0, (fwdSpeed - top) / h);
    }
    k.vel = k.vel + fwd * (a * h);
    k.pos = k.pos + k.vel * h;
    k.speed = k.vel.dot(fwd);
    k.slip = k.vel.len < 20 ? 0 : wrapAngle(math.atan2(k.vel.y, k.vel.x) - k.heading);
    if (k.shield > 0) k.shield -= h;
  }

  /// Keeps both collision circles inside the walls: push out along the wall normal, reflect only the normal
  /// velocity (with restitution) and keep the tangential part so the kart slides along instead of sticking.
  void _walls(Kart k) {
    final V2 fwd = V2.polar(k.heading);
    for (final double o in const <double>[KartDims.circleOffset, -KartDims.circleOffset]) {
      final V2 c = k.pos + fwd * o;
      final TrackHit h = track.project(c, k.idx);
      final double pen = h.dist + KartDims.r - track.wallOffset;
      if (pen <= 0 || h.dist < 1e-6) continue;
      final V2 nOut = (c - h.point) * (1 / h.dist);
      k.pos = k.pos - nOut * pen;
      final double vn = k.vel.dot(nOut);
      if (vn > 0) {
        final V2 vt = k.vel - nOut * vn;
        final double friction = 1 - 0.25 * (vn / 300).clamp(0.0, 1.0);
        k.vel = vt * friction - nOut * (vn * wallRestitution);
        if (vn > 110) events.add(KartEvent('wall', k.seat, c.x, c.y));
        if (k.drifting && vn > 150) _endDrift(k, award: false);
      }
    }
  }

  void _collideKarts(Kart a, Kart b, Set<int>? simulate, bool impulse) {
    final bool sa = _sim(simulate, a.seat), sb = _sim(simulate, b.seat);
    if (!sa && !sb) return;
    if (a.pos.dist(b.pos) > KartDims.length + 4) return;
    final V2 fa = V2.polar(a.heading), fb = V2.polar(b.heading);
    double bestPen = 0;
    V2 nrm = V2.zero;
    for (final double oa in const <double>[KartDims.circleOffset, -KartDims.circleOffset]) {
      for (final double ob in const <double>[KartDims.circleOffset, -KartDims.circleOffset]) {
        final V2 d = (b.pos + fb * ob) - (a.pos + fa * oa);
        final double l = d.len;
        final double pen = KartDims.r * 2 - l;
        if (pen > bestPen) {
          bestPen = pen;
          nrm = l > 1e-6 ? d * (1 / l) : (b.pos - a.pos).unit;
        }
      }
    }
    if (bestPen <= 0) return;
    final double wa = sa && sb ? 0.5 : (sa ? 1 : 0), wb = 1 - wa;
    a.pos = a.pos - nrm * (bestPen * wa);
    b.pos = b.pos + nrm * (bestPen * wb);
    if (!impulse) return;
    final double vRel = (b.vel - a.vel).dot(nrm);
    if (vRel >= 0) return; // already separating
    final double j = -(1 + kartRestitution) * vRel;
    if (sa && sb) {
      a.vel = a.vel - nrm * (j / 2);
      b.vel = b.vel + nrm * (j / 2);
    } else if (sa) {
      a.vel = a.vel - nrm * j;
    } else {
      b.vel = b.vel + nrm * j;
    }
    if (-vRel > 60) {
      final V2 m = (a.pos + b.pos) * 0.5;
      events.add(KartEvent('bump', a.seat, m.x, m.y, b.seat));
    }
  }

  /// Track coordinate, gate validation, laps, finish and wrong-way detection.
  void _progress(Kart k, double h) {
    final TrackHit th = track.project(k.pos, k.idx);
    final double sNew = th.s;
    final double delta = track.wrapDelta(sNew - k.s);
    // A kart moves well under one sample per fixed step; a bigger jump is a discontinuity (teleport / glitch)
    // and never counts as crossing a gate.
    if (delta.abs() < 4 && !k.finished) {
      final int c = KartTrack.gateCount;
      final double next = gates[k.passed % c];
      final double dn = track.wrapDelta(next - k.s);
      if (delta > 0 && dn > 0 && dn <= delta) {
        k.passed++;
        if (k.passed > 1 && (k.passed - 1) % c == 0) {
          k.lap = (k.passed - 1) ~/ c;
          events.add(KartEvent('lap', k.seat, k.pos.x, k.pos.y, k.lap));
        }
        if (k.passed >= finishPasses) finish(k.seat, raceTime);
      } else if (delta < 0 && k.passed > 0) {
        final double last = gates[(k.passed - 1) % c];
        final double dl = track.wrapDelta(last - k.s);
        if (dl <= 0 && dl > delta) {
          k.passed--; // reversed back over the last gate
          k.lap = k.passed <= 1 ? 0 : (k.passed - 1) ~/ c;
        }
      }
    }
    k.idx = th.seg;
    k.s = sNew;
    k.raceProgress = _raceProgress(k);
    // wrong way: nose against the track direction while moving
    final double along = V2.polar(k.heading).dot(track.dirAt(k.s));
    if (along < -0.3 && k.vel.len > 40 && k.spin <= 0) {
      k.wrongWay += h;
    } else {
      k.wrongWay = math.max(0, k.wrongWay - h * 3);
    }
  }

  double _raceProgress(Kart k) {
    if (k.passed == 0) return math.min(0, track.wrapDelta(k.s - gates[0]));
    final int c = KartTrack.gateCount;
    final double last = gates[(k.passed - 1) % c];
    final double d = track.wrapDelta(k.s - last).clamp(-gateGap, gateGap);
    return (k.passed - 1) * gateGap + d;
  }

  void _items(double h, Set<int>? simulate) {
    for (final Kart k in karts) {
      if (k.item != KartItem.none) k.itemHeld += h;
    }
    // boost pads (kart centre inside the drawn pad rectangle)
    for (final Kart k in karts) {
      if (!_sim(simulate, k.seat)) continue;
      for (final int p in pads) {
        final double along = track.wrapDelta(k.s - p) * track.spacing;
        if (along.abs() > KartProps.padLength / 2) continue;
        final double lat = (k.pos - track.at(p)).dot(track.nrm(p));
        if (lat.abs() <= KartProps.padWidth(track.width) / 2 && k.boost < 0.5) {
          k.boost = 0.9;
          events.add(KartEvent('pad', k.seat, k.pos.x, k.pos.y));
        }
      }
    }
    for (final ItemBox b in boxes) {
      if (!b.active) {
        b.respawn -= h;
        continue;
      }
      for (final Kart k in karts) {
        if (!_sim(simulate, k.seat)) continue;
        if (_touches(k, b.pos, KartProps.boxSize / 2)) {
          b.respawn = 1.5;
          if (k.item == KartItem.none) {
            k.item = _roll(placeOf(k.seat));
            k.itemHeld = 0;
            events.add(KartEvent('pickup', k.seat, b.pos.x, b.pos.y));
          }
          break;
        }
      }
    }
    for (int i = missiles.length - 1; i >= 0; i--) {
      final Missile m = missiles[i];
      m.life -= h;
      Kart? t = m.free ? null : karts[m.target];
      final V2 aim = t != null && m.pos.dist(t.pos) < 260 ? t.pos : track.centerAt(m.s + 3);
      final V2 d = aim - m.pos;
      final double l = d.len;
      if (l > 0) m.pos = m.pos + d * (math.min(l, 640 * h) / l);
      final TrackHit th = track.project(m.pos, m.idx);
      m.idx = th.seg;
      m.s = th.s;
      if (m.free) {
        for (final Kart o in karts) {
          if (o.seat != m.owner && _touches(o, m.pos, KartProps.missileR)) t = o;
        }
      }
      if (t != null && _touches(t, m.pos, KartProps.missileR)) {
        missiles.removeAt(i);
        events.add(KartEvent('missile_hit', t.seat, t.pos.x, t.pos.y, m.owner));
        if (_sim(simulate, t.seat)) hit(t.seat, by: m.owner);
        continue;
      }
      if (m.life <= 0) missiles.removeAt(i);
    }
    for (int i = oils.length - 1; i >= 0; i--) {
      final OilSlick o = oils[i];
      o.life -= h;
      o.age += h;
      bool used = false;
      for (final Kart k in karts) {
        if (!_sim(simulate, k.seat)) continue;
        if (k.seat == o.owner && o.age < 1.0) continue; // the dropper drives away from its own slick
        if (k.spin <= 0 && _touches(k, o.pos, KartProps.oilR)) {
          hit(k.seat, by: o.owner);
          used = true;
          break;
        }
      }
      if (used || o.life <= 0) oils.removeAt(i);
    }
  }

  /// True when a circle of radius [r] at [p] overlaps the kart's capsule.
  bool _touches(Kart k, V2 p, double r) {
    final V2 f = V2.polar(k.heading);
    final V2 a = k.pos + f * KartDims.circleOffset, b = k.pos - f * KartDims.circleOffset;
    final V2 ab = b - a;
    final double t = ((p - a).dot(ab) / ab.len2).clamp(0.0, 1.0);
    return p.dist(a + ab * t) < KartDims.r + r;
  }

  bool touches(Kart k, V2 p, double r) => _touches(k, p, r);

  void finish(int seat, double at) {
    final Kart k = karts[seat];
    if (k.finished) return;
    k.finished = true;
    k.finishTime = at;
    k.lap = math.max(k.lap, laps);
    finishOrder.add(seat);
    k.finishPlace = finishOrder.length;
    _endDrift(k, award: false);
    k.brake = false;
    events.add(KartEvent('finish', seat, k.pos.x, k.pos.y, finishOrder.length));
  }

  /// Speed at which a kart can hold a corner of radius [r] with plain steering.
  static double cornerSpeed(double r) => turnMax * r / (1 + 0.45 * turnMax * r / maxSpeed);

  void _bot(Kart k, double h, double skill, int? bestHuman) {
    final int n = track.n;
    final double spd = k.vel.len;
    final V2 fwd = V2.polar(k.heading), right = fwd.perp;
    // ---- engine: skill + gentle rubber banding against the best human (not for finished karts) ----
    double engine = 0.86 + 0.14 * skill;
    if (bestHuman != null && !k.finished && bestHuman != k.seat) {
      final double gap = k.raceProgress - karts[bestHuman].raceProgress;
      final double band = (-gap / (n * 0.3)).clamp(-1.0, 1.0);
      engine += band > 0 ? 0.05 * band : 0.07 * band;
    }
    k.engine = engine;
    // ---- racing line target with avoidance ----
    final double look = 2.2 + spd / 85;
    final double ts = k.s + look;
    double lat = track.lineOffsetAt(ts) + math.sin(time * 0.6 + k.seat * 1.7) * (1 - skill) * 34;
    for (final Kart o in karts) {
      if (o.seat == k.seat) continue;
      final V2 rel = o.pos - k.pos;
      final double ahead = rel.dot(fwd), side = rel.dot(right);
      if (ahead > 0 && ahead < 120 && side.abs() < KartDims.width * 1.3 && o.vel.len < spd + 20) {
        lat += (side > 0 ? -1 : 1) * (KartDims.width * 1.3 - side.abs());
      }
    }
    for (final OilSlick o in oils) {
      final V2 rel = o.pos - k.pos;
      final double ahead = rel.dot(fwd), side = rel.dot(right);
      if (ahead > 0 && ahead < 200 && side.abs() < KartDims.r + KartProps.oilR + 14) {
        lat += (side > 0 ? -1 : 1) * (KartDims.r + KartProps.oilR + 14 - side.abs());
      }
    }
    final double maxLat = track.width / 2 - KartDims.width / 2 - 6;
    lat = lat.clamp(-maxLat, maxLat);
    final V2 target = track.centerAt(ts) + track.dirAt(ts).perp * lat;
    final double want = math.atan2(target.y - k.pos.y, target.x - k.pos.x);
    final double diff = wrapAngle(want - k.heading);
    // ---- speed plan: corner speed of the racing line ahead with braking distance ----
    double allowed = double.infinity;
    double minR = double.infinity;
    final int i0 = k.s.floor();
    for (int j = 0; j <= 16; j++) {
      final double r = track.lineRadius(i0 + j);
      if (j <= 6) minR = math.min(minR, r);
      final double vc = cornerSpeed(r) * (0.86 + 0.12 * skill) * (k.drifting ? 1.1 : 1);
      final double dist = math.max(0, (j - (k.s - i0)) * track.spacing);
      allowed = math.min(allowed, math.sqrt(vc * vc + 2 * brakeDecel * 0.7 * dist));
    }
    final bool wrongWay = diff.abs() > math.pi * 0.6;
    if (wrongWay) {
      k.steer = diff.sign;
      k.brake = false;
    } else {
      k.steer = (diff * 2.6).clamp(-1.0, 1.0);
      k.brake = k.speed > allowed + 10;
    }
    // ---- drifting on long corners (better drivers only) ----
    final double curveSign = track.dir(i0 + 2).cross(track.dir(i0 + 8)).sign; // + = right-hand corner ahead
    if (skill >= 0.5 && !k.finished && k.spin <= 0) {
      if (!k.drifting && minR < 300 && k.speed > 220 && diff.abs() > 0.1 && diff.sign == curveSign) {
        k.steer = diff.sign;
        _driftInput(k, true);
      } else if (k.drifting) {
        final double goal = skill > 0.85 ? driftLv2 + 0.05 : driftLv1 + 0.05;
        final bool straight = minR > 520;
        if ((straight && k.driftCharge > driftLv1) || k.driftCharge > goal + 0.4 || (k.driftCharge > goal && minR > 380) ||
            diff.sign != k.driftDir && diff.abs() > 0.25) {
          _endDrift(k);
        }
      }
    }
    if (k.finished || k.item == KartItem.none || !started) return;
    // ---- items ----
    final int place = placeOf(k.seat);
    bool use = false;
    switch (k.item) {
      case KartItem.turbo:
        use = minR > 420 && !k.drifting;
      case KartItem.missile:
        use = place > 1; // only worth firing with a racer ahead
      case KartItem.shield:
        // good drivers keep the shield in hand until something is actually coming
        use = missiles.any((Missile m) => m.target == k.seat && m.pos.dist(k.pos) < 450) ||
            (skill < 0.7 && k.itemHeld > 5);
      case KartItem.oil:
        use = karts.any((Kart o) {
          if (o.seat == k.seat) return false;
          final V2 rel = o.pos - k.pos;
          return rel.dot(fwd) < -20 && rel.dot(fwd) > -260 && rel.dot(right).abs() < 60;
        });
      case KartItem.none:
        break;
    }
    if (k.itemHeld > 9 && (k.item != KartItem.shield || skill < 0.7)) use = true;
    if (use && _r.nextDouble() < h * (0.6 + 2.4 * skill)) useItem(k.seat);
  }
}

double rtApproach(double cur, double target, double k) => cur + (target - cur) * k.clamp(0.0, 1.0);
