import 'dart:math' as math;

/// Pure-Dart obstacle-course race (Fall-Guys style, top-down, y = forward).
///
/// Rules
/// * 3 s countdown, then everybody auto-runs forward (with acceleration) and steers left/right; JUMP hops.
/// * The course is a fixed list of seeded sections. Each section starts with a clear runway holding a
///   checkpoint. Falling into a pit (or off the bridge) drops you, and after a short fall you respawn at your
///   last checkpoint with a brief ghost period. Nobody is ever stuck: every section is passable by design
///   (see the generator rules) and verified by the bot tests.
/// * Crossing the finish line records your finish time. Once the first runner finishes, the others have
///   [qualifyWindow] seconds; whoever has not finished then is eliminated (DNF). The race also ends at
///   [maxRaceTime]. Ranking: finishers by time, then DNF runners by distance, then forfeits.
///
/// Physics run on a fixed [fixedDt] timestep from an accumulator, so the outcome does not depend on the
/// frame rate; the frame dt is clamped to [maxFrameDt] so a hitch never tunnels anything. Obstacles animate
/// from race time only, so every phone sees the same course.

enum ObKind { sweeper, pit, gate, drop, bumper }

enum ObSectionKind { sweepers, pits, gates, drops, bumpers, bridge }

/// One obstacle. Geometry (world units):
/// * sweeper: pivot (x, y), arm length w, arm half-thickness [ObstacleRace.armHalf], hub [ObstacleRace.hubR].
/// * pit: rectangle (x, y, w, h); you fall when your centre is more than [ObstacleRace.pitMargin] inside it.
/// * gate: wall across the course at y..y+h with a moving gap of width w.
/// * drop: w×h block centred on (x, y) that lands on a cycle and is solid while down.
/// * bumper: solid bouncy disc at (x, y) with radius w.
class Obstacle {
  Obstacle(this.kind, this.x, this.y, {this.w = 0, this.h = 0, this.speed = 0, this.phase = 0});
  final ObKind kind;
  final double x, y, w, h, speed, phase;

  /// Sweeper arm angle at [t].
  double angle(double t) => phase + speed * t;

  /// Gate gap centre at [t]; the gap never leaves the course and a wall stub always remains on both sides.
  double gateGap(double t, double width) => width / 2 + math.sin(phase + speed * t) * gateAmp(width);
  double gateAmp(double width) => math.max(0, width / 2 - w / 2 - 20);

  /// Drop block cycle 0..1: 0.35..0.75 warning, lands at 0.75, solid until 0.95, then lifts.
  double dropCycle(double t) {
    final double c = (t * (speed == 0 ? 0.42 : speed) + phase) % 1.0;
    return c < 0 ? c + 1 : c;
  }

  bool dropSolid(double t) {
    final double c = dropCycle(t);
    return c >= 0.75 && c < 0.95;
  }

  /// Y range the obstacle can touch (for culling and bot look-ahead).
  double get yMin => switch (kind) {
        ObKind.sweeper => y - w - ObstacleRace.armHalf,
        ObKind.pit || ObKind.gate => y,
        ObKind.drop => y - h / 2,
        ObKind.bumper => y - w,
      };
  double get yMax => switch (kind) {
        ObKind.sweeper => y + w + ObstacleRace.armHalf,
        ObKind.pit || ObKind.gate => y + h,
        ObKind.drop => y + h / 2,
        ObKind.bumper => y + w,
      };
}

class ObSection {
  ObSection(this.kind, this.index, this.y0);
  final ObSectionKind kind;
  final int index;

  /// Section start; [y0]..[y0]+[ObstacleRace.runway] is clear floor holding the checkpoint.
  final double y0;
  double y1 = 0;
  double get checkpointY => y0 + 20;
  double get spawnY => y0 + 48;
}

enum RunPhase { racing, falling, finished, dnf, out }

class Runner {
  Runner(this.seat, this.x, this.y) : bestY = y;
  final int seat;
  double x, y;
  double vx = 0, vy = 0;
  double z = 0, vz = 0;
  RunPhase phase = RunPhase.racing;

  /// Seconds of reduced control after a hit.
  double stun = 0;

  /// Seconds of ghosting after a respawn (no hits, no shoves).
  double ghost = 0;

  /// Kept for compatibility: > 0 while being knocked back.
  double knock = 0;

  /// Coyote grace left after walking off solid floor (s).
  double coyote = 0;

  /// Buffered jump press left (s).
  double jumpBuffer = 0;
  double fallT = 0;
  int checkpoint = -1;
  int respawns = 0;
  double finishTime = -1;
  double outAt = 0;
  double bestY;
  double steer = 0;

  /// Forward throttle 0.4..1 (bots ease off to fall in line instead of shoving).
  double throttle = 1;
  double _stuck = 0;
  bool _overPit = false;

  /// On the course and in control (not falling, not done).
  bool get alive => phase == RunPhase.racing;
  bool get racing => phase == RunPhase.racing || phase == RunPhase.falling;
  bool get finished => phase == RunPhase.finished;
  bool get done => phase == RunPhase.finished || phase == RunPhase.dnf || phase == RunPhase.out;
  bool get grounded => z <= 0 && vz <= 0;

  /// Kept for compatibility with the old API.
  bool get wantJump => jumpBuffer > 0;
  set wantJump(bool v) => jumpBuffer = v ? ObstacleRace.jumpBufferTime : 0;
}

class ObEvent {
  const ObEvent(this.kind, this.seat, this.x, this.y);

  /// jump, land, knock, bump, squash, fall, respawn, checkpoint, finish, dnf, out.
  final String kind;
  final int seat;
  final double x, y;
}

/// Smooth, frame-rate independent follow camera. [y] is the world y at the bottom of the view.
class ObCamera {
  double y = -ObstacleRace.followOffset + 80;
  double viewH = ObstacleRace.viewH;

  void snap(double targetY) => y = targetY - ObstacleRace.followOffset;

  void follow(double targetY, double dt, {double maxY = double.infinity}) {
    final double want = math.min(targetY - ObstacleRace.followOffset, maxY);
    if ((want - y).abs() > viewH) {
      y = want; // respawn far away: cut instead of a long whip
      return;
    }
    y += (want - y) * (1 - math.exp(-ObstacleRace.camStiffness * dt));
  }
}

/// Maps the course onto a screen: uniform scale, same horizontal framing on every phone, kept inside the
/// safe area (notch, status bar, gesture bar, side cut-outs). All values in logical pixels.
class ObViewport {
  ObViewport._(this.scale, this.left, this.top, this.bottom, this.safeLeft, this.safeRight);

  factory ObViewport.fit(double width, double height,
      {double padTop = 0, double padBottom = 0, double padLeft = 0, double padRight = 0}) {
    final double availW = math.max(1, width - padLeft - padRight);
    final double availH = math.max(1, height - padTop - padBottom);
    double scale = availW / ObstacleRace.visibleW;
    if (availH / scale < ObstacleRace.minViewH) scale = availH / ObstacleRace.minViewH;
    final double left = padLeft + (availW - ObstacleRace.width * scale) / 2;
    return ObViewport._(scale, left, padTop, height - padBottom, padLeft, width - padRight);
  }

  final double scale;

  /// Screen x of world x = 0.
  final double left;

  /// Safe top / bottom screen y of the play view; world camera y sits at [bottom].
  final double top, bottom;
  final double safeLeft, safeRight;

  double get worldH => (bottom - top) / scale;
  double sx(double wx) => left + wx * scale;
  double sy(double wy, double cam) => bottom - (wy - cam) * scale;
  double toWorldX(double px) => (px - left) / scale;
}

class ObstacleRace {
  ObstacleRace({required this.seed, required this.count, this.botSkill = const <double>[], this.sectionCount = 10}) {
    _gen();
    for (int i = 0; i < count; i++) {
      final Runner r = Runner(i, startSlotX(i), startY);
      runners.add(r);
      _rng.add(math.Random(seed * 131 + i * 7919 + 17));
      _bots.add(_BotBrain());
    }
    camera.snap(startY);
  }

  // ---------------------------------------------------------------- tuning (world units, seconds)
  static const double width = 420;
  static const double margin = 12; // floor rail shown beside the course
  static const double visibleW = width + margin * 2;
  static const double minViewH = 560;
  static const double viewH = 760;
  static const double runnerR = 15;
  static const double startY = 90;
  static const double startRunway = 260;
  static const double runway = 90;
  static const double finishRunway = 260;

  static const double fixedDt = 1 / 120;
  static const double maxFrameDt = 0.1;

  static const double runMax = 250;
  static const double runAccel = 650;
  static const double airAccelK = 0.35;
  static const double sideMax = 300;
  static const double sideAccel = 2600;
  static const double gravity = 2200;
  static const double jumpV = 620;
  static const double coyoteTime = 0.10;
  static const double jumpBufferTime = 0.12;

  static const double armHalf = 8;
  static const double armHeight = 20; // a runner higher than this clears a sweeper arm
  static const double hubR = 14;
  static const double pitMargin = 5;
  static const double knockSpeed = 420;
  static const double stunTime = 0.45;
  static const double fallTime = 0.7;
  static const double ghostTime = 1.2;
  static const double bumperBounce = 320;

  static const double qualifyWindow = 20;
  static const double maxRaceTime = 180;
  static const double followOffset = 230;
  static const double camStiffness = 6;

  /// Air time and forward reach of a jump at full speed.
  static double get jumpAir => 2 * jumpV / gravity;
  static double get jumpReach => runMax * jumpAir;
  static double get maxPitLen => 100;

  final int seed;
  final int count;
  final int sectionCount;
  final List<double> botSkill;
  final List<Runner> runners = <Runner>[];
  final List<Obstacle> obstacles = <Obstacle>[];
  final List<ObSection> sections = <ObSection>[];
  final List<ObEvent> events = <ObEvent>[];

  /// Forfeits in the order they happened.
  final List<int> outOrder = <int>[];
  final List<math.Random> _rng = <math.Random>[];
  final List<_BotBrain> _bots = <_BotBrain>[];
  final ObCamera camera = ObCamera();
  double finishY = 0;
  double time = 0;
  double countdown = 3;
  double _acc = 0;
  double firstFinish = -1;

  /// Seat the camera follows.
  int focus = 0;

  double get cam => camera.y;
  set cam(double v) => camera.y = v;

  bool isBot(int s) => s < botSkill.length && botSkill[s] > 0;
  double get runSpeed => runMax;
  int get aliveCount => runners.where((Runner r) => r.racing).length;
  int get finishedCount => runners.where((Runner r) => r.finished).length;
  bool get over => runners.every((Runner r) => r.done);
  double get cutoff => firstFinish < 0 ? maxRaceTime : math.min(maxRaceTime, firstFinish + qualifyWindow);
  double get timeLeft => math.max(0, cutoff - time);
  double startSlotX(int i) => width * (i + 1) / (count + 1);

  // ---------------------------------------------------------------- course generation
  void _gen() {
    final math.Random r = math.Random(seed);
    final List<ObSectionKind> kinds = List<ObSectionKind>.of(ObSectionKind.values)..shuffle(r);
    while (kinds.length < sectionCount) {
      ObSectionKind k;
      do {
        k = ObSectionKind.values[r.nextInt(ObSectionKind.values.length)];
      } while (k == kinds.last);
      kinds.add(k);
    }
    // Ease in: the opening section is never the bridge.
    if (kinds.first == ObSectionKind.bridge) {
      final int j = kinds.indexWhere((ObSectionKind k) => k != ObSectionKind.bridge);
      kinds[0] = kinds[j];
      kinds[j] = ObSectionKind.bridge;
    }
    double y = startY + startRunway;
    final int n = math.min(sectionCount, kinds.length);
    for (int i = 0; i < n; i++) {
      final double d = n <= 1 ? 0 : i / (n - 1);
      final ObSection s = ObSection(kinds[i], i, y);
      sections.add(s);
      y = _genSection(r, s, y + runway, d) + 40;
      s.y1 = y;
    }
    finishY = y + 60;
    obstacles.sort((Obstacle a, Obstacle b) => a.yMin.compareTo(b.yMin));
    for (final Obstacle o in obstacles) {
      _maxExtent = math.max(_maxExtent, o.yMax - o.yMin);
    }
  }

  double _genSection(math.Random r, ObSection s, double y, double d) {
    const double rr = runnerR;
    switch (s.kind) {
      case ObSectionKind.sweepers:
        final int n = d > 0.45 ? 2 : 1;
        for (int k = 0; k < n; k++) {
          final double w = 120 + r.nextDouble() * 35 + d * 20;
          final double px = 80 + r.nextDouble() * (width - 160);
          final double py = y + w + armHalf + 6;
          obstacles.add(Obstacle(ObKind.sweeper, px, py,
              w: w, speed: (r.nextBool() ? 1 : -1) * (1.3 + d * 1.0 + r.nextDouble() * 0.3), phase: r.nextDouble() * 6.283));
          y = py + w + armHalf + 30;
        }
        return y;
      case ObSectionKind.pits:
        final int rows = d > 0.5 ? 3 : 2;
        double lane = 90 + r.nextDouble() * (width - 180);
        for (int k = 0; k < rows; k++) {
          final double h = math.min(maxPitLen, 60 + r.nextDouble() * 25 + d * 15);
          final double lw = 84 - d * 16; // walkable lane width (always ≥ 2.2 runner widths)
          if (k > 0) lane = (lane + (r.nextBool() ? 1 : -1) * (70 + r.nextDouble() * 90)).clamp(lw / 2 + 2 * rr, width - lw / 2 - 2 * rr);
          final double a = lane - lw / 2, b = lane + lw / 2;
          if (a > 2 * rr) obstacles.add(Obstacle(ObKind.pit, 0, y, w: a, h: h));
          if (width - b > 2 * rr) obstacles.add(Obstacle(ObKind.pit, b, y, w: width - b, h: h));
          y += h + 95 + r.nextDouble() * 30;
        }
        return y - 40;
      case ObSectionKind.gates:
        final int n = d > 0.6 ? 3 : 2;
        for (int k = 0; k < n; k++) {
          obstacles.add(Obstacle(ObKind.gate, 0, y,
              w: math.max(130, 162 - d * 30 + r.nextDouble() * 14), h: 26, speed: 0.5 + d * 0.55 + r.nextDouble() * 0.2, phase: r.nextDouble() * 6.283));
          y += 26 + 150;
        }
        return y - 100;
      case ObSectionKind.drops:
        final int n = 3 + (d * 2).round();
        const double bw = 64;
        final List<Obstacle> placed = <Obstacle>[];
        final double h = 110.0 * n;
        int guard = 0;
        while (placed.length < n && guard++ < 400) {
          final double bx = bw / 2 + 2 * rr + 20 + r.nextDouble() * (width - bw - 4 * rr - 40);
          final double by = y + bw / 2 + r.nextDouble() * (h - bw);
          final bool clear = placed.every((Obstacle o) {
            final double gx = (bx - o.x).abs() - bw, gy = (by - o.y).abs() - bw;
            return gx >= 2 * rr + 24 || gy >= 2 * rr + 24;
          });
          if (clear) {
            placed.add(Obstacle(ObKind.drop, bx, by, w: bw, h: bw, speed: 0.4 + d * 0.12, phase: r.nextDouble()));
          }
        }
        obstacles.addAll(placed);
        return y + h;
      case ObSectionKind.bumpers:
        final int n = 3 + (d * 2).round();
        final List<Obstacle> placed = <Obstacle>[];
        final double h = 110.0 * n;
        int guard = 0;
        while (placed.length < n && guard++ < 600) {
          final double br = 22 + r.nextDouble() * 6;
          final double bx = br + 2 * rr + 20 + r.nextDouble() * (width - 2 * br - 4 * rr - 40);
          final double by = y + br + r.nextDouble() * (h - 2 * br);
          final bool clear = placed.every((Obstacle o) {
            final double dist = math.sqrt((bx - o.x) * (bx - o.x) + (by - o.y) * (by - o.y));
            return dist >= br + o.w + 2 * rr + 30; // a lane ≥ 2 runner widths between any two
          });
          if (clear) placed.add(Obstacle(ObKind.bumper, bx, by, w: br));
        }
        obstacles.addAll(placed);
        return y + h;
      case ObSectionKind.bridge:
        final double bw = 104 - d * 20; // ≥ 84: 2.8 runner widths
        double c = bw / 2 + 50 + r.nextDouble() * (width - bw - 100);
        const int segs = 3;
        for (int k = 0; k < segs; k++) {
          final double len = 110 + r.nextDouble() * 30;
          if (k > 0) c = (c + (r.nextBool() ? 1 : -1) * (24 + r.nextDouble() * 16)).clamp(bw / 2 + 2 * rr, width - bw / 2 - 2 * rr);
          final double a = c - bw / 2, b = c + bw / 2;
          if (a > 0) obstacles.add(Obstacle(ObKind.pit, 0, y, w: a, h: len));
          if (b < width) obstacles.add(Obstacle(ObKind.pit, b, y, w: width - b, h: len));
          y += len;
        }
        return y;
    }
  }

  double _maxExtent = 0;

  Iterable<Obstacle> near(double y0, double y1) sync* {
    // obstacles are sorted by yMin; skip straight to the first that can reach y0.
    int lo = 0, hi = obstacles.length;
    final double from = y0 - _maxExtent;
    while (lo < hi) {
      final int mid = (lo + hi) >> 1;
      if (obstacles[mid].yMin < from) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    for (int i = lo; i < obstacles.length; i++) {
      final Obstacle o = obstacles[i];
      if (o.yMin > y1) break;
      if (o.yMax < y0) continue;
      yield o;
    }
  }

  ObSection? sectionAt(double y) {
    for (final ObSection s in sections.reversed) {
      if (y >= s.y0) return s;
    }
    return null;
  }

  // ---------------------------------------------------------------- input & net
  void input(int seat, double steer, bool jump) {
    final Runner r = runners[seat];
    r.steer = steer.isNaN ? 0 : steer.clamp(-1.0, 1.0);
    if (jump && countdown <= 0) r.jumpBuffer = jumpBufferTime;
  }

  /// Forfeit / disconnect.
  void eliminate(int seat, double at) {
    final Runner r = runners[seat];
    if (r.done) return;
    r.phase = RunPhase.out;
    r.outAt = at;
    outOrder.add(seat);
    events.add(ObEvent('out', seat, r.x, r.y));
  }

  /// A finish reported by another phone (time in race seconds).
  void markFinished(int seat, double at) {
    final Runner r = runners[seat];
    if (r.finished || r.phase == RunPhase.out) return;
    r.phase = RunPhase.finished;
    r.finishTime = at;
    r.bestY = math.max(r.bestY, finishY);
    if (firstFinish < 0 || at < firstFinish) firstFinish = at;
    events.add(ObEvent('finish', seat, r.x, r.y));
  }

  /// Ranking best → worst.
  List<int> ranking() {
    final List<Runner> fin = runners.where((Runner r) => r.finished).toList()
      ..sort((Runner a, Runner b) => a.finishTime != b.finishTime ? a.finishTime.compareTo(b.finishTime) : a.seat.compareTo(b.seat));
    final List<Runner> rest = runners.where((Runner r) => !r.finished && r.phase != RunPhase.out).toList()
      ..sort((Runner a, Runner b) => a.bestY != b.bestY ? b.bestY.compareTo(a.bestY) : a.seat.compareTo(b.seat));
    return <int>[...fin.map((Runner r) => r.seat), ...rest.map((Runner r) => r.seat), ...outOrder.reversed];
  }

  /// Live place of [seat] (1-based).
  int placeOf(int seat) => ranking().indexOf(seat) + 1;

  /// 0..1 progress along the course.
  double progress(int seat) => ((runners[seat].y - startY) / (finishY - startY)).clamp(0.0, 1.0);

  // ---------------------------------------------------------------- simulation
  /// Advance by a frame of [dt] seconds (clamped), in fixed sub-steps.
  void step(double dt, {Set<int>? simulate}) {
    if (dt.isNaN || dt <= 0) return;
    _acc += math.min(dt, maxFrameDt);
    while (_acc >= fixedDt - 1e-9) {
      _acc -= fixedDt;
      _tick(fixedDt, simulate);
    }
  }

  void _tick(double h, Set<int>? simulate) {
    if (countdown > 0) {
      countdown -= h;
      if (countdown < 1e-9) countdown = 0;
      for (final Runner r in runners) {
        r.jumpBuffer = 0;
      }
      camera.follow(runners[focus].y, h);
      return;
    }
    time += h;
    for (final Runner r in runners) {
      if (simulate != null && !simulate.contains(r.seat)) continue;
      if (r.done) {
        if (r.finished) _coast(r, h);
        continue;
      }
      if (r.phase == RunPhase.falling) {
        _falling(r, h);
        continue;
      }
      if (isBot(r.seat)) _bot(r, h);
      _move(r, h);
    }
    _shoves(simulate);
    if (time >= cutoff - 1e-9) {
      for (final Runner r in runners) {
        if (!r.done) {
          r.phase = RunPhase.dnf;
          r.outAt = time;
          events.add(ObEvent('dnf', r.seat, r.x, r.y));
        }
      }
    }
    final Runner f = runners[focus];
    camera.follow(f.y, h, maxY: finishY + finishRunway - camera.viewH);
  }

  void _coast(Runner r, double h) {
    r.vy = math.max(0, r.vy - runAccel * 1.5 * h);
    r.vx *= math.exp(-6 * h);
    r.y = math.min(r.y + r.vy * h, finishY + finishRunway - 40);
    r.x = r.x.clamp(runnerR, width - runnerR);
    if (r.z > 0 || r.vz > 0) {
      r.vz -= gravity * h;
      r.z = math.max(0, r.z + r.vz * h);
      if (r.z <= 0) r.vz = 0;
    }
  }

  void _falling(Runner r, double h) {
    r.fallT += h;
    r.z -= 260 * h * (1 + r.fallT * 3);
    r.vx *= math.exp(-8 * h);
    r.vy *= math.exp(-8 * h);
    r.x += r.vx * h;
    r.y += r.vy * h;
    if (r.fallT >= fallTime) respawn(r.seat);
  }

  /// Put [seat] back at its last checkpoint.
  void respawn(int seat) {
    final Runner r = runners[seat];
    final double sy = r.checkpoint < 0 ? startY : sections[r.checkpoint].spawnY;
    const List<double> slots = <double>[0.5, 0.32, 0.68, 0.18, 0.82, 0.41, 0.59];
    double bx = width / 2;
    double best = -1;
    for (final double f in slots) {
      final double x = width * f;
      if (_inPit(x, sy) || _solidAt(x, sy)) continue;
      double near = 1e9;
      for (final Runner o in runners) {
        if (o.seat == seat || !o.racing) continue;
        near = math.min(near, math.sqrt((o.x - x) * (o.x - x) + (o.y - sy) * (o.y - sy)));
      }
      if (near > 3 * runnerR) {
        bx = x;
        break;
      }
      if (near > best) {
        best = near;
        bx = x;
      }
    }
    r
      ..x = bx
      ..y = sy
      ..vx = 0
      ..vy = 0
      ..z = 0
      ..vz = 0
      ..stun = 0
      ..knock = 0
      ..coyote = 0
      ..jumpBuffer = 0
      ..fallT = 0
      ..ghost = ghostTime
      .._overPit = false
      .._stuck = 0
      ..phase = RunPhase.racing;
    r.respawns++;
    _bots[seat].reset();
    events.add(ObEvent('respawn', seat, r.x, r.y));
  }

  void _move(Runner r, double h) {
    final double skillF = isBot(r.seat) ? 0.95 + 0.05 * botSkill[r.seat].clamp(0.0, 1.0) : 1.0;
    if (r.stun > 0) r.stun = math.max(0, r.stun - h);
    if (r.knock > 0) r.knock = math.max(0, r.knock - h);
    if (r.ghost > 0) r.ghost = math.max(0, r.ghost - h);
    if (r.jumpBuffer > 0) r.jumpBuffer = math.max(0, r.jumpBuffer - h);

    // Jump (buffered press + coyote grace).
    if (r.jumpBuffer > 0 && r.stun <= 0 && (r.grounded || r.coyote > 0)) {
      r.vz = jumpV;
      r.z = 0.001;
      r.coyote = 0;
      r.jumpBuffer = 0;
      r._overPit = false;
      events.add(ObEvent('jump', r.seat, r.x, r.y));
    }

    // Horizontal control: accelerate towards the wanted velocity; reduced in the air and while stunned.
    final bool air = !r.grounded;
    final double ctrl = (air ? airAccelK : 1.0) * (r.stun > 0 ? 0.25 : 1.0);
    r.vx = _approach(r.vx, r.steer * sideMax, sideAccel * ctrl * h);
    final double wantVy = runMax * skillF * r.throttle.clamp(0.4, 1.0) * (r.stun > 0 ? 0.3 : 1.0);
    r.vy = _approach(r.vy, wantVy, runAccel * (air ? airAccelK : 1.0) * (r.stun > 0 ? 2.0 : 1.0) * h);

    // Vertical.
    if (air) {
      r.vz -= gravity * h;
      r.z += r.vz * h;
      if (r.z <= 0) {
        r.z = 0;
        r.vz = 0;
        events.add(ObEvent('land', r.seat, r.x, r.y));
      }
    }

    final double px = r.x, py = r.y;
    r.x += r.vx * h;
    r.y += r.vy * h;

    // Moving hazards first (a landing block must find you under it), then push out of solids.
    for (final Obstacle o in near(r.y - runnerR - 40, r.y + runnerR + 40)) {
      switch (o.kind) {
        case ObKind.sweeper:
          _sweeper(r, o);
        case ObKind.drop:
          final double c = o.dropCycle(time);
          if (c >= 0.75 && c < 0.75 + 0.03 && _circleRect(r.x, r.y, runnerR * 0.7, o.x - o.w / 2, o.y - o.h / 2, o.w, o.h) && r.ghost <= 0) {
            final double dx = r.x - o.x, dy = r.y - o.y;
            final bool side = dx.abs() / o.w > dy.abs() / o.h;
            r.vx = side ? dx.sign * knockSpeed * 0.7 : 0;
            r.vy = side ? 0 : (dy >= 0 ? 1 : -1) * knockSpeed * 0.7;
            r.stun = stunTime + 0.2;
            r.knock = 0.25;
            events.add(ObEvent('squash', r.seat, r.x, r.y));
          }
        default:
          break;
      }
    }
    _resolve(r);

    // Pits: coyote grace starts only when you walk from solid floor onto a pit.
    final bool overPit = _inPit(r.x, r.y);
    if (r.grounded) {
      if (overPit) {
        final bool wasOver = r._overPit || _inPit(px, py);
        if (!wasOver) r.coyote = coyoteTime;
        if (r.coyote <= 0) {
          _startFall(r);
          return;
        }
        r.coyote = math.max(0, r.coyote - h);
        if (r.coyote <= 0) {
          _startFall(r);
          return;
        }
      } else {
        r.coyote = 0;
      }
    }
    r._overPit = overPit && r.grounded;

    // Never behind the start, never through a wall: detect being wedged and unstick.
    if (r.y < startY - 60) r.y = startY - 60;
    if (_solidAt(r.x, r.y, inset: 4)) {
      r._stuck += h;
      if (r._stuck > 0.5) {
        respawn(r.seat);
        return;
      }
    } else {
      r._stuck = 0;
    }

    // Checkpoints & finish.
    for (int i = r.checkpoint + 1; i < sections.length; i++) {
      if (r.y >= sections[i].checkpointY) {
        r.checkpoint = i;
        events.add(ObEvent('checkpoint', r.seat, r.x, sections[i].checkpointY));
      } else {
        break;
      }
    }
    r.bestY = math.max(r.bestY, r.y);
    if (r.y >= finishY) {
      // Interpolate the crossing inside the sub-step so the finish time is not quantised to the frame.
      final double frac = r.y == py ? 1 : ((finishY - py) / (r.y - py)).clamp(0.0, 1.0);
      final double at = time - h + h * frac;
      r.phase = RunPhase.finished;
      r.finishTime = at;
      if (firstFinish < 0 || at < firstFinish) firstFinish = at;
      events.add(ObEvent('finish', r.seat, r.x, r.y));
    }
  }

  void _startFall(Runner r) {
    r.phase = RunPhase.falling;
    r.fallT = 0;
    r.coyote = 0;
    r._overPit = false;
    events.add(ObEvent('fall', r.seat, r.x, r.y));
  }

  void _sweeper(Runner r, Obstacle o) {
    final double a = o.angle(time);
    final double ex = o.x + math.cos(a) * o.w, ey = o.y + math.sin(a) * o.w;
    final _Seg s = _segClosest(r.x, r.y, o.x, o.y, ex, ey);
    final double reach = runnerR + armHalf;
    if (s.d >= reach || r.z > armHeight) return;
    // Push out of the arm so it can never pass through a runner.
    double nx = r.x - s.cx, ny = r.y - s.cy;
    final double nl = math.sqrt(nx * nx + ny * ny);
    if (nl < 1e-6) {
      nx = -math.sin(a);
      ny = math.cos(a);
    } else {
      nx /= nl;
      ny /= nl;
    }
    // Arm's velocity at the contact point decides which side the runner is shoved to.
    final double rx = s.cx - o.x, ry = s.cy - o.y;
    final double tvx = -o.speed * ry, tvy = o.speed * rx;
    r.x = s.cx + nx * reach;
    r.y = s.cy + ny * reach;
    if (r.ghost > 0 || r.knock > 0) return;
    final double tv = math.sqrt(tvx * tvx + tvy * tvy);
    final double sgn = (nx * tvx + ny * tvy) >= 0 ? 1 : -1;
    final double kx = tv > 1e-6 ? sgn * tvx / tv : nx, ky = tv > 1e-6 ? sgn * tvy / tv : ny;
    final double mag = knockSpeed + 0.35 * tv;
    r.vx = (kx * 0.75 + nx * 0.25) * mag;
    r.vy = (ky * 0.75 + ny * 0.25) * mag;
    r.vz = 260;
    r.z = math.max(r.z, 0.001);
    r.stun = stunTime;
    r.knock = 0.35;
    r.jumpBuffer = 0;
    events.add(ObEvent('knock', r.seat, r.x, r.y));
  }

  /// Push the runner out of every solid shape and keep it on the course.
  void _resolve(Runner r) {
    for (int it = 0; it < 3; it++) {
      bool moved = false;
      for (final Obstacle o in near(r.y - runnerR - 2, r.y + runnerR + 2)) {
        switch (o.kind) {
          case ObKind.gate:
            final double g = o.gateGap(time, width);
            moved |= _pushRect(r, -40, o.y, g - o.w / 2 + 40, o.h);
            moved |= _pushRect(r, g + o.w / 2, o.y, width + 40 - (g + o.w / 2), o.h);
          case ObKind.drop:
            if (o.dropSolid(time)) moved |= _pushRect(r, o.x - o.w / 2, o.y - o.h / 2, o.w, o.h);
          case ObKind.bumper:
            final double dx = r.x - o.x, dy = r.y - o.y;
            final double d = math.sqrt(dx * dx + dy * dy);
            final double min = runnerR + o.w;
            if (d < min && r.z < 30) {
              final double nx = d > 1e-6 ? dx / d : 0, ny = d > 1e-6 ? dy / d : -1;
              r.x = o.x + nx * min;
              r.y = o.y + ny * min;
              final double vn = r.vx * nx + r.vy * ny;
              if (vn < bumperBounce) {
                r.vx += (bumperBounce - vn) * nx;
                r.vy += (bumperBounce - vn) * ny;
                r.stun = math.max(r.stun, 0.15);
                events.add(ObEvent('bump', r.seat, o.x + nx * o.w, o.y + ny * o.w));
              }
              moved = true;
            }
          case ObKind.sweeper:
            final double dx = r.x - o.x, dy = r.y - o.y;
            final double d = math.sqrt(dx * dx + dy * dy);
            final double min = runnerR + hubR;
            if (d < min) {
              final double nx = d > 1e-6 ? dx / d : 0, ny = d > 1e-6 ? dy / d : -1;
              r.x = o.x + nx * min;
              r.y = o.y + ny * min;
              moved = true;
            }
          case ObKind.pit:
            break;
        }
      }
      if (r.x < runnerR) {
        r.x = runnerR;
        if (r.vx < 0) r.vx = 0;
      } else if (r.x > width - runnerR) {
        r.x = width - runnerR;
        if (r.vx > 0) r.vx = 0;
      }
      if (!moved) break;
    }
  }

  bool _pushRect(Runner r, double x, double y, double w, double h) {
    if (w <= 0 || h <= 0) return false;
    final double cx = r.x.clamp(x, x + w), cy = r.y.clamp(y, y + h);
    final double dx = r.x - cx, dy = r.y - cy;
    final double d2 = dx * dx + dy * dy;
    if (d2 >= runnerR * runnerR) return false;
    if (d2 > 1e-9) {
      final double d = math.sqrt(d2);
      r.x = cx + dx / d * runnerR;
      r.y = cy + dy / d * runnerR;
      final double nx = dx / d, ny = dy / d;
      final double vn = r.vx * nx + r.vy * ny;
      if (vn < 0) {
        r.vx -= vn * nx;
        r.vy -= vn * ny;
      }
      return true;
    }
    // Centre inside the rectangle: leave by the shortest side.
    final double l = r.x - x, rt = x + w - r.x, b = r.y - y, t = y + h - r.y;
    final double m = math.min(math.min(l, rt), math.min(b, t));
    if (m == b) {
      r.y = y - runnerR;
      if (r.vy > 0) r.vy = 0;
    } else if (m == t) {
      r.y = y + h + runnerR;
      if (r.vy < 0) r.vy = 0;
    } else if (m == l) {
      r.x = x - runnerR;
      if (r.vx > 0) r.vx = 0;
    } else {
      r.x = x + w + runnerR;
      if (r.vx < 0) r.vx = 0;
    }
    return true;
  }

  void _shoves(Set<int>? simulate) {
    for (int i = 0; i < runners.length; i++) {
      for (int j = i + 1; j < runners.length; j++) {
        final Runner a = runners[i], b = runners[j];
        if (!a.alive || !b.alive || a.ghost > 0 || b.ghost > 0 || (a.z - b.z).abs() > 24) continue;
        final double dx = b.x - a.x, dy = b.y - a.y;
        final double d = math.sqrt(dx * dx + dy * dy);
        if (d >= runnerR * 2) continue;
        final double nx = d > 1e-6 ? dx / d : (a.seat < b.seat ? 1 : -1), ny = d > 1e-6 ? dy / d : 0;
        final double k = (runnerR * 2 - d) * 0.5;
        if (simulate == null || simulate.contains(a.seat)) {
          a.x -= nx * k;
          a.y -= ny * k;
          _resolve(a);
        }
        if (simulate == null || simulate.contains(b.seat)) {
          b.x += nx * k;
          b.y += ny * k;
          _resolve(b);
        }
      }
    }
  }

  // ---------------------------------------------------------------- queries
  bool _inPit(double x, double y) {
    for (final Obstacle o in near(y - 1, y + 1)) {
      if (o.kind != ObKind.pit) continue;
      if (x > o.x + pitMargin && x < o.x + o.w - pitMargin && y > o.y + pitMargin && y < o.y + o.h - pitMargin) {
        return true;
      }
    }
    return false;
  }

  bool inPit(double x, double y) => _inPit(x, y);

  /// Is the point [inset] or more inside a solid shape (runner centre wedged)?
  bool _solidAt(double x, double y, {double inset = 0}) {
    for (final Obstacle o in near(y - 2, y + 2)) {
      switch (o.kind) {
        case ObKind.gate:
          final double g = o.gateGap(time, width);
          if (y > o.y + inset && y < o.y + o.h - inset && (x < g - o.w / 2 - inset || x > g + o.w / 2 + inset)) return true;
        case ObKind.drop:
          if (o.dropSolid(time) && (x - o.x).abs() < o.w / 2 - inset && (y - o.y).abs() < o.h / 2 - inset) return true;
        case ObKind.bumper:
          if ((x - o.x) * (x - o.x) + (y - o.y) * (y - o.y) < (o.w - inset) * (o.w - inset)) return true;
        case ObKind.sweeper:
          if ((x - o.x) * (x - o.x) + (y - o.y) * (y - o.y) < (hubR - inset) * (hubR - inset)) return true;
        case ObKind.pit:
          break;
      }
    }
    return false;
  }

  bool solidAt(double x, double y) => _solidAt(x, y);

  static double _approach(double v, double target, double dv) =>
      v < target ? math.min(target, v + dv) : math.max(target, v - dv);

  static bool _circleRect(double px, double py, double r, double x, double y, double w, double h) {
    final double cx = px.clamp(x, x + w), cy = py.clamp(y, y + h);
    return (px - cx) * (px - cx) + (py - cy) * (py - cy) < r * r;
  }

  static _Seg _segClosest(double px, double py, double ax, double ay, double bx, double by) {
    final double vx = bx - ax, vy = by - ay;
    final double l2 = vx * vx + vy * vy;
    double t = l2 == 0 ? 0 : ((px - ax) * vx + (py - ay) * vy) / l2;
    t = t.clamp(0.0, 1.0);
    final double cx = ax + vx * t, cy = ay + vy * t;
    return _Seg(cx, cy, math.sqrt((cx - px) * (cx - px) + (cy - py) * (cy - py)));
  }

  static double segDist(double px, double py, double ax, double ay, double bx, double by) =>
      _segClosest(px, py, ax, ay, bx, by).d;

  // ---------------------------------------------------------------- bots
  void _bot(Runner r, double h) {
    final double skill = botSkill[r.seat].clamp(0.0, 1.0);
    final _BotBrain b = _bots[r.seat];
    final math.Random rng = _rng[r.seat];
    b.think -= h;
    if (b.think <= 0) {
      b.think = 0.05 + (1 - skill) * 0.2;
      b.target = (_planLane(r, b.target) + (rng.nextDouble() * 2 - 1) * (1 - skill) * 14).clamp(runnerR, width - runnerR);
    }
    r.steer = ((b.target - r.x) / 28 - r.vx / sideMax * 0.25).clamp(-1.0, 1.0);
    // Shoulder to shoulder with someone slightly ahead: ease off and fall in line (skilled bots do this more).
    r.throttle = 1;
    for (final Runner o in runners) {
      if (o.seat == r.seat || !o.alive || o.ghost > 0 || r.ghost > 0) continue;
      final double dy = o.y - r.y, dx = (o.x - r.x).abs();
      if (dx < 2 * runnerR + 6 && dy > -4 && dy < 30 && (dy > 0.5 || o.seat < r.seat) && rng.nextDouble() < 0.4 + 0.6 * skill) {
        r.throttle = 0.55;
        break;
      }
    }
    if (r.stun > 0) return;
    final bool canJump = r.grounded || r.coyote > 0;
    if (!canJump) return;
    // Walked onto a pit edge: use the coyote grace.
    if (r.coyote > 0) {
      if (!b.miss(-1 - r.checkpoint * 100 - (r.y ~/ 10), skill, rng)) r.jumpBuffer = jumpBufferTime;
      return;
    }
    final double vy = math.max(60, r.vy);
    for (int i = 0; i < obstacles.length; i++) {
      final Obstacle o = obstacles[i];
      if (o.yMin > r.y + 160) break;
      if (o.yMax < r.y - 40) continue;
      switch (o.kind) {
        case ObKind.pit:
          final double dist = o.y + pitMargin - r.y;
          if (dist <= 0 || o.h > jumpReach * 0.8) break;
          final double tt = dist / vy;
          final double xa = r.x + r.vx * math.min(tt, 0.25);
          final bool inLane = (o.x <= 0 || xa > o.x + pitMargin - 2) && (o.x + o.w >= width || xa < o.x + o.w - pitMargin + 2);
          final double lead = 6 + vy * 0.03 + (1 - skill) * 10;
          if (inLane && dist <= lead && !b.miss(i, skill, rng)) r.jumpBuffer = jumpBufferTime;
        case ObKind.sweeper:
          if (r.ghost > 0.2) break;
          bool hits(double t, double pad) {
            final double a = o.angle(time + t);
            final double px = r.x + r.vx * math.min(t, 0.2), py = r.y + vy * t;
            return segDist(px, py, o.x, o.y, o.x + math.cos(a) * o.w, o.y + math.sin(a) * o.w) < runnerR + armHalf + pad;
          }
          for (double t = 0.04; t <= 0.16 + 1e-9; t += 0.04) {
            if (!hits(t, 4)) continue;
            // Only jump if the arm will not be under us when we come down; otherwise ease off and let it pass.
            bool landClear = true;
            for (double tl = jumpAir - 0.06; tl <= jumpAir + 0.08; tl += 0.02) {
              if (hits(tl, 6)) {
                landClear = false;
                break;
              }
            }
            if (landClear || skill < 0.5) {
              if (!b.miss(i * 1000 + (time / 2).floor(), skill, rng)) r.jumpBuffer = jumpBufferTime;
            } else {
              r.throttle = 0.4;
            }
            break;
          }
        default:
          break;
      }
    }
  }

  double _planLane(Runner r, double last) {
    const double look = 300;
    final double vy = math.max(120, r.vy);
    final List<Obstacle> ahead = near(r.y - runnerR, r.y + look).toList();
    double bestX = r.x, bestC = double.infinity;
    for (double x = runnerR + 3; x <= width - runnerR - 3 + 1e-9; x += 6) {
      double c = 0.3 * (x - r.x).abs() + 0.1 * (x - last).abs();
      for (final Obstacle o in ahead) {
        final bool round = o.kind == ObKind.bumper || o.kind == ObKind.drop || o.kind == ObKind.sweeper;
        final double d = (round ? o.y : o.yMin) - r.y;
        final double w8 = d <= 0 ? 1 : math.max(0.25, 1 - d / look);
        final double tLat = (x - r.x).abs() / sideMax;
        final double tArr = math.max(0, d) / vy;
        final double shift = sideMax * 0.85 * math.max(0, tArr - 0.06) + 10;
        final double xr = x.clamp(r.x - shift, r.x + shift);
        switch (o.kind) {
          case ObKind.pit:
            final bool inPitLane = (o.x <= 0 || xr > o.x + pitMargin - runnerR * 0.6) && (o.x + o.w >= width || xr < o.x + o.w - pitMargin + runnerR * 0.6);
            if (inPitLane) c += (o.h <= jumpReach * 0.8 ? 90 : 1200) * w8;
          case ObKind.gate:
            final double t = math.max(tArr, tLat);
            final double g = o.gateGap(time + t, width);
            final double half = o.w / 2 - runnerR - 6;
            final double off = (x - g).abs();
            c += (off > half ? 600 + off : 0.3 * off) * w8;
          case ObKind.bumper:
            if ((xr - o.x).abs() < o.w + runnerR + 6) c += 220 * w8;
          case ObKind.drop:
            final double cyc = o.dropCycle(time + math.max(tArr, tLat));
            final bool danger = cyc > 0.55 && cyc < 0.97;
            if ((xr - o.x).abs() < o.w / 2 + runnerR + 6) c += (danger ? 420 : 30) * w8;
          case ObKind.sweeper:
            if ((xr - o.x).abs() < runnerR + hubR + 6 && d > -runnerR) c += 120 * w8;
        }
      }
      for (final Runner o in runners) {
        if (o.seat == r.seat || !o.alive || o.ghost > 0) continue;
        final double dy = o.y - r.y;
        // Don't run shoulder to shoulder (shoves push you sideways); falling in line behind is fine.
        final double dx = (x - o.x).abs();
        if (dy > -35 && dy < 60 && dx > 6 && dx < 2 * runnerR + 8) c += 120;
      }
      if (c < bestC) {
        bestC = c;
        bestX = x;
      }
    }
    return bestX;
  }
}

class _Seg {
  const _Seg(this.cx, this.cy, this.d);
  final double cx, cy, d;
}

class _BotBrain {
  double think = 0;
  double target = ObstacleRace.width / 2;
  final Map<int, bool> _rolled = <int, bool>{};

  /// Roll once per hazard whether this bot fumbles it (skill 1 never does).
  bool miss(int key, double skill, math.Random rng) =>
      _rolled.putIfAbsent(key, () => rng.nextDouble() < (1 - skill) * 0.3);

  void reset() {
    think = 0;
    _rolled.clear();
  }
}
