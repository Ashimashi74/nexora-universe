/// ===================== SOLO ARCADE RULES — PART 3 =====================
/// The three games that scroll a corridor/road (Geo Dash, Traffic Racer) and the falling
/// wall (Tetris Rush) plus the 4x4 slide puzzle (2048), which reuse [GridBoard].
/// Pure Dart, deterministic, no Flutter imports.
/// ==================================================================
library;

import 'dart:math' as math;

import 'solo_rules.dart';

// ---------------------------------------------------------------- tetris rush
/// A 10x18 well. Pieces fall, lines clear, gravity accelerates every 10 lines.
class TetrisWorld {
  TetrisWorld({required this.seed}) : rng = math.Random(seed) {
    well = List<List<int>>.generate(rows, (_) => List<int>.filled(cols, 0));
    _next = _pick();
    _spawn();
  }

  static const int cols = 10;
  static const int rows = 18;
  static const int hiddenRows = 2;

  final int seed;
  final math.Random rng;
  late List<List<int>> well;
  Tetromino? current;
  SoloPiece _next = SoloPiece.i;
  int lines = 0;
  int score = 0;
  double gravity = 0.75; // seconds per cell
  double _fall = 0;
  bool over = false;

  /// 0 = empty, otherwise 1 + piece index (used for colour).
  List<List<int>> get board => well;

  void reset() {
    well = List<List<int>>.generate(rows, (_) => List<int>.filled(cols, 0));
    lines = 0;
    score = 0;
    gravity = 0.75;
    over = false;
    _next = _pick();
    _spawn();
  }

  SoloPiece _pick() => SoloPiece.values[rng.nextInt(SoloPiece.values.length)];

  void _spawn() {
    final SoloPiece kind = _next;
    _next = _pick();
    final Tetromino piece = Tetromino(kind, 3, 0, 0);
    if (_collides(piece)) {
      over = true; // game over: the well is full at the spawn point
      current = null;
      return;
    }
    current = piece;
    _fall = 0;
  }

  bool _collides(Tetromino p) {
    for (final (int, int) c in p.cells) {
      if (c.$1 < 0 || c.$1 >= cols || c.$2 >= rows) return true;
      if (c.$2 >= 0 && well[c.$2][c.$1] != 0) return true;
    }
    return false;
  }

  bool moveLeft() {
    final Tetromino? p = current;
    if (p == null) return false;
    final Tetromino t = p.moved(-1, 0);
    if (_collides(t)) return false;
    current = t;
    return true;
  }

  bool moveRight() {
    final Tetromino? p = current;
    if (p == null) return false;
    final Tetromino t = p.moved(1, 0);
    if (_collides(t)) return false;
    current = t;
    return true;
  }

  bool rotate() {
    final Tetromino? p = current;
    if (p == null) return false;
    final Tetromino t = p.rotated();
    if (!_collides(t)) {
      current = t;
      return true;
    }
    // simple wall kick
    final Tetromino k = t.moved(1, 0);
    if (!_collides(k)) {
      current = k;
      return true;
    }
    return false;
  }

  /// Soft drop one cell; returns true when the piece locked.
  bool down() {
    final Tetromino? p = current;
    if (p == null) return false;
    final Tetromino t = p.moved(0, 1);
    if (_collides(t)) {
      _lock();
      return true;
    }
    current = t;
    return false;
  }

  void hardDrop() {
    while (!down()) {}
  }

  void _lock() {
    final Tetromino? p = current;
    if (p == null) return;
    for (final (int, int) c in p.cells) {
      if (c.$2 >= 0 && c.$2 < rows && c.$1 >= 0 && c.$1 < cols) {
        well[c.$2][c.$1] = 1 + p.kind.index;
      }
    }
    _clearLines();
    _spawn();
  }

  void _clearLines() {
    int cleared = 0;
    for (int r = rows - 1; r >= 0; r--) {
      if (well[r].every((int v) => v != 0)) {
        well.removeAt(r);
        well.insert(0, List<int>.filled(cols, 0));
        cleared++;
        r++;
      }
    }
    if (cleared == 0) return;
    lines += cleared;
    // 0 single, 1 double, 2 triple, 3 quad
    const List<int> points = <int>[100, 300, 500, 800];
    score += points[(cleared - 1).clamp(0, 3)];
    gravity = math.max(0.12, 0.75 - lines * 0.03);
  }

  /// Called by the UI ticker; drops the piece automatically.
  void tick(double dt) {
    if (over || current == null) return;
    _fall += dt;
    if (_fall >= gravity) {
      _fall = 0;
      if (down()) score += 10;
    }
  }
}

// ---------------------------------------------------------------- 2048
class World2048Game {
  World2048Game({required this.seed}) : board = GridBoard(4, math.Random(seed)) {
    board.spawn();
    board.spawn();
  }

  final int seed;
  final GridBoard board;
  int score = 0;
  bool over = false;
  bool won = false;

  /// Sliding in [dir] (0 left, 1 up, 2 right, 3 down). Returns score gained this move.
  int move(int dir) {
    if (over) return 0;
    final int? gained = board.slide(dir);
    if (gained == null) {
      // A blocked swipe still has to end the run once no direction is legal; otherwise the
      // player is left staring at a dead board with no overlay.
      if (!board.canMove) over = true;
      return 0;
    }
    score += gained;
    board.spawn();
    if (board.maxTile >= 2048) won = true;
    if (!board.canMove) over = true;
    return gained;
  }

  void restart() {
    board.reset();
    board.spawn();
    board.spawn();
    score = 0;
    over = false;
    won = false;
  }
}

// ---------------------------------------------------------------- geo dash
/// A one-button endless side-scroller: tap to jump over spikes, hold to fly higher.
class DashWorld {
  DashWorld({required this.seed}) : rng = math.Random(seed);

  final int seed;
  final math.Random rng;
  double y = 0; // 0 = ground, 1 = ceiling
  double vy = 0;
  double speed = 0.55;
  double distance = 0;
  bool onGround = true;
  bool dead = false;
  double spawnCooldown = 0.8;
  final List<DashHazard> hazards = <DashHazard>[];

  int get metres => (distance * 10).floor();

  void update(double dt, {bool holding = false}) {
    if (dead) return;
    speed = math.min(1.5, 0.55 + distance * 0.02);
    distance += speed * dt * 6;
    vy -= 5.2 * dt; // gravity
    if (holding && vy < 4.6) vy += 9.5 * dt; // lift while held
    y += vy * dt;
    if (y <= 0) {
      y = 0;
      vy = 0;
      onGround = true;
    } else {
      onGround = false;
    }
    if (y > 1) {
      y = 1;
      vy = math.min(vy, 0);
    }
    spawnCooldown -= dt;
    if (spawnCooldown <= 0) {
      spawnCooldown = (0.95 - distance * 0.006).clamp(0.42, 0.95);
      final double h = rng.nextDouble() < 0.45 ? 0.16 : 0.3;
      final bool flying = rng.nextDouble() < 0.25;
      hazards.add(DashHazard(height: h, flying: flying));
    }
    for (final DashHazard z in hazards) {
      z.x -= speed * dt * 2.2;
    }
    hazards.removeWhere((DashHazard z) => z.x < -0.2);
    for (final DashHazard z in hazards) {
      final bool nearPlayer = z.x > 0.12 && z.x < 0.34;
      if (!nearPlayer) continue;
      if (z.flying) {
        if ((y - z.height).abs() < 0.14) dead = true;
      } else if (y < z.height) {
        dead = true;
      }
    }
  }

  void leap() {
    if (onGround && !dead) vy = 4.4;
  }
}

class DashHazard {
  DashHazard({required this.height, required this.flying});
  double x = 1.15;

  /// Ground spikes: height of the block. Flying hazards: the y band they patrol.
  final double height;
  final bool flying;
}

// ---------------------------------------------------------------- traffic racer
/// Three lanes, oncoming traffic, overtaking overtakes score. Speed climbs with time.
class TrafficWorld {
  TrafficWorld({required this.seed}) : rng = math.Random(seed);

  final int seed;
  final math.Random rng;
  int lane = 1;
  double speed = 0.5;
  double travelled = 0;
  double spawnCooldown = 0.7;
  bool crashed = false;
  final List<TrafficCar> cars = <TrafficCar>[];

  int get metres => travelled.floor();

  void update(double dt) {
    if (crashed) return;
    speed = math.min(2.4, 0.5 + travelled * 0.0009);
    travelled += speed * dt * 26;
    spawnCooldown -= dt;
    if (spawnCooldown <= 0) {
      spawnCooldown = (0.8 - speed * 0.16).clamp(0.26, 0.8);
      final int l = rng.nextInt(3);
      cars.add(TrafficCar(lane: l, y: 1.2));
    }
    for (final TrafficCar c in cars) {
      c.y -= (speed * 1.5) * dt;
    }
    for (final TrafficCar c in cars) {
      if (c.y > 0.02 && c.y < 0.24 && c.lane == lane && !c.passed) crashed = true;
      if (c.y <= 0.02 && !c.passed) {
        c.passed = true;
      }
    }
    cars.removeWhere((TrafficCar c) => c.y < -0.3);
  }

  void steer(int dir) => lane = (lane + dir).clamp(0, 2);
}

class TrafficCar {
  TrafficCar({required this.lane, required this.y});
  final int lane;
  double y;
  bool passed = false;
}
