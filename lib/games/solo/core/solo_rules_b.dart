/// ===================== SOLO ARCADE RULES — PART 2 =====================
/// The runner family (Endless Runner, Geo Dash, Traffic Racer), the reflex family
/// (Fruit Ninja, Knife Hit), Helix Jump, Bubble Shooter and Stack Tower. Same contract as
/// `solo_rules.dart`: pure Dart, deterministic, no Flutter imports.
/// ==================================================================
library;

import 'dart:math' as math;

/// Shared helper: a seeded random source so a run can be replayed exactly.
math.Random seeded(int seed) => math.Random(seed);

// ---------------------------------------------------------------- endless runner
/// Lanes are 0..2 (left, centre, right). Obstacles spawn ahead and close in at
/// [speed] cells/second; the player may only sidestep between lanes.
class RunnerWorld {
  RunnerWorld({required this.seed, this.speed = 1.6, this.laneCount = 3})
      : rng = math.Random(seed),
        _distance = 0;

  final int seed;
  final math.Random rng;
  double speed;
  final int laneCount;
  int lane = 1;
  double _distance = 0;
  final List<RunnerObstacle> obstacles = <RunnerObstacle>[];
  double spawnCooldown = 0.4;
  bool crashed = false;

  /// Metres travelled (what the score board shows).
  int get metres => _distance.floor();

  /// Seconds survived.
  double time = 0;

  void update(double dt) {
    if (crashed) return;
    time += dt;
    speed = 1.6 + time * 0.075; // acceleration, capped so it stays playable on a phone
    if (speed > 5.2) speed = 5.2;
    _distance += speed * 8 * dt;

    for (final RunnerObstacle o in obstacles) {
      o.distance -= speed * dt;
    }
    obstacles.removeWhere((RunnerObstacle o) => o.distance < -0.2);

    spawnCooldown -= dt;
    if (spawnCooldown <= 0) {
      spawnCooldown = (0.85 - time * 0.012).clamp(0.34, 0.85);
      final int blockedLane = rng.nextInt(laneCount);
      // Leave at least one lane open: two blockers only ever appear on 3 lanes.
      obstacles.add(RunnerObstacle(lane: blockedLane, distance: 6, height: rng.nextDouble() < 0.35 ? 1.6 : 1));
      if (time > 12 && rng.nextDouble() < 0.35) {
        final int other = (blockedLane + 1 + rng.nextInt(laneCount - 1)) % laneCount;
        obstacles.add(RunnerObstacle(lane: other, distance: 6, height: 1));
      }
    }

    // Collision: an obstacle overlapping the player's cell.
    for (final RunnerObstacle o in obstacles) {
      if (o.distance <= 0.45 && o.distance >= -0.15 && o.lane == lane && o.height > 0.5) {
        crashed = true;
        break;
      }
    }
  }

  void moveTo(int nextLane) {
    lane = nextLane.clamp(0, laneCount - 1);
  }

  void sidestep(int dir) => moveTo(lane + dir);
}

class RunnerObstacle {
  RunnerObstacle({required this.lane, required this.distance, this.height = 1});
  final int lane;

  /// Distance ahead of the player in abstract cells (0 = at the player).
  double distance;
  final double height;
}

// ---------------------------------------------------------------- fruit ninja
class FruitSlice {
  FruitSlice({required this.x, required this.y, required this.vx, required this.vy, required this.radius, this.bomb = false});
  double x, y, vx, vy;
  final double radius;
  final bool bomb;
  double rotation = 0;
  bool sliced = false;
  bool missed = false;
}

/// Fruit is launched from the bottom of a normalised 0..1 play area and arcs under
/// gravity; slicing a fruit scores, letting it fall scores nothing, slicing a bomb ends
/// the run.
class FruitWorld {
  FruitWorld({required this.seed}) : rng = math.Random(seed);

  final int seed;
  final math.Random rng;
  final List<FruitSlice> items = <FruitSlice>[];
  int sliced = 0;
  int missed = 0;
  int combo = 0;
  bool exploded = false;
  double gravity = 1.55;
  double spawnCooldown = 0.5;
  double time = 0;

  void update(double dt) {
    if (exploded) return;
    time += dt;
    spawnCooldown -= dt;
    if (spawnCooldown <= 0) {
      spawnCooldown = (1.05 - time * 0.01).clamp(0.45, 1.05);
      final int n = 1 + rng.nextInt(2);
      for (int i = 0; i < n; i++) {
        _launch(bomb: rng.nextDouble() < 0.12);
      }
    }
    for (final FruitSlice f in items) {
      f.vy += gravity * dt;
      f.x += f.vx * dt;
      f.y += f.vy * dt;
      f.rotation += dt * 2.2 * (f.vx >= 0 ? 1 : -1);
      if (f.y > 1.25 && !f.sliced && !f.missed) {
        f.missed = true;
        if (!f.bomb) {
          missed++;
          combo = 0;
        }
      }
    }
    items.removeWhere((FruitSlice f) => f.y > 1.5 || f.sliced);
  }

  void _launch({bool bomb = false}) {
    final double x = 0.12 + rng.nextDouble() * 0.76;
    // Aim so the apex is around 65–85% of the height.
    final double vy = -(1.55 + rng.nextDouble() * 0.5);
    items.add(FruitSlice(
      x: x,
      y: 1.05,
      vx: (0.5 - x) * 0.9 + (rng.nextDouble() - 0.5) * 0.35,
      vy: vy,
      radius: bomb ? 0.05 : 0.055 + rng.nextDouble() * 0.02,
      bomb: bomb,
    ));
  }

  /// Slices at a normalised point. Returns the number of fruits cut (bombs count as 0
  /// and set [exploded]).
  int sliceAt(double px, double py) {
    int cut = 0;
    for (final FruitSlice f in items) {
      if (f.sliced) continue;
      final double dx = (f.x - px) * 1.6; // aspect correction (portrait screen)
      final double dy = f.y - py;
      if (dx * dx + dy * dy > (f.radius * 1.9) * (f.radius * 1.9)) continue;
      if (f.bomb) {
        exploded = true;
        return 0;
      }
      f.sliced = true;
      sliced++;
      combo++;
      cut++;
    }
    return cut;
  }
}

// ---------------------------------------------------------------- knife hit
/// Knives are thrown into a rotating log. Each throw must stick between the knives
/// already there; hitting one ends the run. Every 5th knife, a boss stage speeds the log up.
class KnifeWorld {
  KnifeWorld({required this.seed}) : rng = math.Random(seed);

  final int seed;
  final math.Random rng;
  final List<double> stuckAngles = <double>[];
  double rotation = 0;
  double spin = 0.9;
  int thrown = 0;
  int stage = 0;
  bool hit = false;
  double knifeRadius = 0.20;

  /// Minimum angular gap between two knives on the log.
  double get gap => 0.30;

  void update(double dt) {
    if (hit) return;
    rotation = (rotation + spin * dt) % (math.pi * 2);
  }

  /// Throws a knife at the bottom of the log ([angle] is the world angle of the throw,
  /// normally pi/2). Returns true when it sticks.
  bool throwAt([double angle = math.pi / 2]) {
    if (hit) return false;
    // The local angle of the impact point on the log.
    final double local = (angle - rotation) % (math.pi * 2);
    final double normalised = local < 0 ? local + math.pi * 2 : local;
    for (final double a in stuckAngles) {
      double d = (a - normalised).abs();
      if (d > math.pi) d = math.pi * 2 - d;
      if (d < gap) {
        hit = true;
        return false;
      }
    }
    stuckAngles.add(normalised);
    thrown++;
    if (thrown % 5 == 0) {
      stage++;
      spin = 0.9 + stage * 0.45;
      knifeRadius = math.max(0.12, knifeRadius - 0.012);
    }
    return true;
  }
}

// ---------------------------------------------------------------- helix jump
/// A ring is either open (only a thin frame — the ball always passes) or deadly red (the ball
/// must be over the gap when it crosses the level).
enum HelixRing { open, red }

/// A tower of rings; the ball drops through the gap of each ring. Red sections kill.
class HelixWorld {
  HelixWorld({required this.seed, this.ringCount = 220}) : rng = math.Random(seed) {
    rings = List<HelixRing>.generate(ringCount, (int i) => HelixRing.open);
    int i = 6;
    while (i < ringCount - 6) {
      final int len = 3 + rng.nextInt(3);
      for (int k = 0; k < len && i + k < ringCount - 4; k++) {
        rings[i + k] = HelixRing.red;
      }
      i += len + 7 + rng.nextInt(4);
    }
  }

  final int seed;
  final int ringCount;
  final math.Random rng;
  late final List<HelixRing> rings;

  /// Height measured in rings; grows as the ball falls.
  double depth = 0;
  double gapAngle = 0;
  double spin = 0;
  double fallSpeed = 0;
  int jumps = 0;
  bool dead = false;

  /// Ring index the ball occupies.
  int get ring => depth.floor();

  void update(double dt, {required double tilt}) {
    if (dead) return;
    spin += tilt * 2.4 * dt;
    fallSpeed = math.min(7.5, fallSpeed + 9 * dt);
    depth += fallSpeed * dt;
    if (depth < 0) depth = 0; // the ball never leaves the top of the tower
    if (depth >= ringCount - 1) {
      depth = ringCount - 1;
      return; // climbed the whole tower: the UI ends the run as a win
    }
    gapAngle = spin % (math.pi * 2);
    // Crossing a red ring level: the gap is a fixed arc per ring, so the player has to spin
    // the tower to line the ball up, exactly like the real game.
    final double level = depth - ring;
    if (level > 0.02 && level < 0.30 && rings[ring] == HelixRing.red) {
      final double gapCentre = (ring * 1.7) % (math.pi * 2);
      double d = (gapCentre - gapAngle).abs();
      if (d > math.pi) d = math.pi * 2 - d;
      if (d > 0.42) {
        dead = true; // crossed a red ring away from its gap
      }
    }
  }

  void jump() {
    if (dead) return;
    jumps++;
    fallSpeed = math.max(-4.5, -5.2);
    depth -= 0.6;
    if (depth < 0) depth = 0;
  }

  bool get finished => depth >= ringCount - 1;
}

// ---------------------------------------------------------------- bubble shooter
/// Hex-packed bubble grid. Rows alternate offset. A shot that joins 3+ same-coloured
/// bubbles pops them (and detached clusters), otherwise it sticks.
class BubbleWorld {
  BubbleWorld({required this.seed, this.cols = 9, this.rows = 12, this.colours = 5})
      : rng = math.Random(seed) {
    grid = List<List<int>>.generate(rows, (_) => List<int>.filled(cols, -1));
    for (int r = 0; r < 5; r++) {
      for (int c = 0; c < cols; c++) {
        grid[r][c] = rng.nextInt(colours);
      }
    }
  }

  final int seed;
  final int cols;
  final int rows;
  final int colours;
  final math.Random rng;
  late List<List<int>> grid;

  int nextColour = 0;
  int shots = 0;
  int popped = 0;

  /// Aim angle in radians (0 = straight up, positive = right).
  double aim = 0;

  /// Number of coloured bubbles still on the board (the win condition).
  int get remaining => grid.expand((List<int> r) => r).where((int v) => v >= 0).length;

  bool get cleared => remaining == 0;

  List<int> get coloursInPlay {
    final Set<int> s = <int>{for (final List<int> r in grid) for (final int v in r) if (v >= 0) v};
    return s.toList()..sort();
  }

  int pickColour() {
    final List<int> live = coloursInPlay;
    nextColour = live.isEmpty ? rng.nextInt(colours) : live[rng.nextInt(live.length)];
    return nextColour;
  }

  /// Fires the current bubble along [aim]. Returns the number popped.
  ///
  /// The bubble rises from the bottom of the aimed column and sticks under the lowest bubble
  /// already in it, exactly like the real game; a column whose bottom cell is taken cannot be
  /// used, so the shot tries progressively closer columns instead of teleporting to the top.
  int fire() {
    shots++;
    final int aimed = (cols / 2 + math.sin(aim) * cols * 0.75).round().clamp(0, cols - 1);
    for (final int target in _landingOrder(aimed)) {
      final int? row = _landingRow(target);
      if (row == null) continue;
      grid[row][target] = nextColour;
      return _resolve(row, target);
    }
    return 0; // every reachable column is full: the shot is wasted
  }

  /// Aimed column first, then its neighbours, then the rest — so a blocked shot does something
  /// sensible instead of vanishing.
  Iterable<int> _landingOrder(int aimed) sync* {
    yield aimed;
    for (int d = 1; d < cols; d++) {
      if (aimed - d >= 0) yield aimed - d;
      if (aimed + d < cols) yield aimed + d;
    }
  }

  /// Where a shot aimed at [col] would stick: the cell the bubble would occupy, or null.
  /// Exposed so the board can draw a landing marker and tests can target a real cell.
  (int row, int col)? landingCell(int col) {
    final int? row = _landingRow(col);
    return row == null ? null : (row, col);
  }

  /// Row the shot sticks at in [col], or null when the column is full.
  int? _landingRow(int col) {
    for (int r = rows - 1; r >= 0; r--) {
      if (grid[r][col] >= 0) {
        final int land = r + 1;
        if (land >= rows || grid[land][col] >= 0) return null;
        return land;
      }
    }
    return rows - 1; // empty column: the bubble rests on the floor
  }

  int _resolve(int row, int col) {
    final int colour = grid[row][col];
    final List<(int, int)> cluster = _cluster(row, col, colour);
    if (cluster.length < 3) return 0;
    for (final (int, int) c in cluster) {
      grid[c.$1][c.$2] = -1;
    }
    int total = cluster.length;
    // Drop every bubble no longer connected to the top row.
    final Set<(int, int)> reachable = _reachableFromTop();
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        if (grid[r][c] >= 0 && !reachable.contains((r, c))) {
          grid[r][c] = -1;
          total++;
        }
      }
    }
    popped += total;
    return total;
  }

  List<(int, int)> _neighbours(int row, int col) {
    final bool offset = row.isOdd;
    final List<(int, int)> d = offset
        ? <(int, int)>[(0, -1), (0, 1), (-1, 0), (-1, 1), (1, 0), (1, 1)]
        : <(int, int)>[(0, -1), (0, 1), (-1, -1), (-1, 0), (1, -1), (1, 0)];
    return <(int, int)>[
      for (final (int, int) x in d)
        if (row + x.$1 >= 0 && row + x.$1 < rows && col + x.$2 >= 0 && col + x.$2 < cols) (row + x.$1, col + x.$2),
    ];
  }

  List<(int, int)> _cluster(int row, int col, int colour) {
    final List<(int, int)> out = <(int, int)>[];
    final Set<(int, int)> seen = <(int, int)>{};
    final List<(int, int)> stack = <(int, int)>[(row, col)];
    while (stack.isNotEmpty) {
      final (int, int) cur = stack.removeLast();
      if (!seen.add(cur)) continue;
      if (grid[cur.$1][cur.$2] != colour) continue;
      out.add(cur);
      stack.addAll(_neighbours(cur.$1, cur.$2));
    }
    return out;
  }

  Set<(int, int)> _reachableFromTop() {
    final Set<(int, int)> seen = <(int, int)>{};
    final List<(int, int)> stack = <(int, int)>[
      for (int c = 0; c < cols; c++)
        if (grid[0][c] >= 0) (0, c),
    ];
    while (stack.isNotEmpty) {
      final (int, int) cur = stack.removeLast();
      if (!seen.add(cur)) continue;
      if (grid[cur.$1][cur.$2] < 0) continue;
      stack.addAll(_neighbours(cur.$1, cur.$2));
    }
    return seen;
  }
}

// ---------------------------------------------------------------- stack tower
/// Blocks slide left/right; dropping one on the stack trims whatever hangs over the
/// edge. A perfect drop is rewarded with a combo. Missing the tower entirely ends the run.
class StackWorld {
  StackWorld({required this.seed}) : rng = math.Random(seed) {
    blocks.add(StackBlock(0.18, 0.64)); // bottom block: left, width
  }

  final int seed;
  final math.Random rng;
  final List<StackBlock> blocks = <StackBlock>[];
  double movingLeft = 0.18;
  double movingWidth = 0.64;
  double speed = 0.42;
  int direction = 1;
  int floors = 0;
  int perfect = 0;
  bool over = false;

  StackBlock get top => blocks.last;

  void update(double dt) {
    if (over) return;
    movingLeft += direction * speed * dt;
    if (movingLeft < 0) {
      movingLeft = 0;
      direction = 1;
    }
    if (movingLeft + movingWidth > 1) {
      movingLeft = 1 - movingWidth;
      direction = -1;
    }
  }

  /// Drops the block. Returns 'perfect', 'ok' or 'miss'.
  String drop() {
    if (over) return 'miss';
    final double l = math.max(top.left, movingLeft);
    final double r = math.min(top.left + top.width, movingLeft + movingWidth);
    final double overlap = r - l;
    if (overlap <= 0.012) {
      over = true;
      return 'miss';
    }
    final bool isPerfect = (movingLeft - top.left).abs() < 0.012;
    if (isPerfect) {
      perfect++;
      movingWidth = top.width;
      movingLeft = top.left;
    } else {
      movingWidth = overlap;
      movingLeft = l;
    }
    blocks.add(StackBlock(movingLeft, movingWidth));
    floors++;
    speed = math.min(1.5, 0.42 + floors * 0.012);
    // The next block starts from the opposite edge of the tower.
    movingWidth = math.min(movingWidth, 0.9);
    movingLeft = direction > 0 ? 0 : 1 - movingWidth;
    return isPerfect ? 'perfect' : 'ok';
  }
}

class StackBlock {
  const StackBlock(this.left, this.width);
  final double left;
  final double width;
}
