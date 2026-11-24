/// ===================== SOLO ARCADE RULES =====================
/// Pure-Dart rules for the ten single-player arcade games. No Flutter, no timers, no IO:
/// the UI layer (`lib/games/solo/ui/`) drives these classes from a ticker and paints them,
/// and `test/games/solo/*` exercises them head-lessly. Keeping the rules here means every
/// game is deterministic (a seed produces the same run) and the same code can be replayed
/// or validated later without touching rendering.
///
/// Two tiny generic engines cover most of the family:
///  * [GridBoard] — the 4x4 slide puzzle (2048) and the falling-block wall (Tetris Rush)
///    share column/row semantics, so sliding and clearing live in one place.
///  * [Ledger] — score, combo chain and best-of bookkeeping used by every game.
/// ===========================================================
library;

import 'dart:math' as math;

/// Score / combo bookkeeping shared by all solo games.
class Ledger {
  Ledger();

  int score = 0;
  int combo = 0;
  int bestCombo = 0;

  /// Adds [base] multiplied by the current combo multiplier (1x, 1.25x, 1.5x … capped at 4x).
  int add(int base) {
    final int gained = (base * multiplier).round();
    score += gained;
    return gained;
  }

  /// Grows the chain; returns the new multiplier.
  double chain() {
    combo++;
    if (combo > bestCombo) bestCombo = combo;
    return multiplier;
  }

  /// Breaks the chain (a miss, a bad placement).
  void breakChain() => combo = 0;

  double get multiplier => combo <= 0 ? 1 : 1 + math.min(3, combo) * 0.25;
}

/// A rectangular integer board with 4-way slide support (2048) and row access.
class GridBoard {
  GridBoard(this.size, [math.Random? rng]) : rng = rng ?? math.Random(1) {
    cells = List<List<int>>.generate(size, (_) => List<int>.filled(size, 0));
  }

  final int size;
  final math.Random rng;
  late List<List<int>> cells;

  int cell(int row, int col) => cells[row][col];
  void set(int row, int col, int v) => cells[row][col] = v;

  /// Sum of all tiles (used for score deltas).
  int get total {
    int t = 0;
    for (final List<int> row in cells) {
      for (final int v in row) {
        t += v;
      }
    }
    return t;
  }

  int get maxTile {
    int m = 0;
    for (final List<int> row in cells) {
      for (final int v in row) {
        if (v > m) m = v;
      }
    }
    return m;
  }

  int get emptyCount => cells.expand((List<int> r) => r).where((int v) => v == 0).length;

  bool get hasEmpty => emptyCount > 0;

  /// Places a random tile (2 or 4) in an empty cell. Returns the cell, or null when full.
  ({int row, int col})? spawn({double fourChance = 0.1}) {
    final List<({int row, int col})> free = <({int row, int col})>[
      for (int r = 0; r < size; r++)
        for (int c = 0; c < size; c++)
          if (cells[r][c] == 0) (row: r, col: c),
    ];
    if (free.isEmpty) return null;
    final ({int row, int col}) spot = free[rng.nextInt(free.length)];
    cells[spot.row][spot.col] = rng.nextDouble() < fourChance ? 4 : 2;
    return spot;
  }

  /// Slide + merge one row to the left, 2048 rules: equal neighbours merge once.
  /// Returns (newRow, gainedScore, merged).
  static (List<int>, int, bool) slideRow(List<int> row) {
    final List<int> packed = row.where((int v) => v != 0).toList();
    final List<int> out = <int>[];
    int gained = 0;
    bool merged = false;
    for (int i = 0; i < packed.length; i++) {
      if (i + 1 < packed.length && packed[i] == packed[i + 1]) {
        final int v = packed[i] * 2;
        out.add(v);
        gained += v;
        merged = true;
        i++; // consume the pair
      } else {
        out.add(packed[i]);
      }
    }
    while (out.length < row.length) {
      out.add(0);
    }
    return (out, gained, merged);
  }

  /// Applies a slide in [dir] (0 left, 1 up, 2 right, 3 down). Returns score gained, or
  /// null when nothing moved (the caller then does not spawn a tile).
  int? slide(int dir) {
    final List<List<int>> before = <List<int>>[for (final List<int> r in cells) List<int>.of(r)];
    int gained = 0;
    bool moved = false;
    for (int line = 0; line < size; line++) {
      List<int> row = _line(line, dir);
      final (List<int> next, int g, bool merged) = slideRow(row);
      if (merged) gained += g;
      if (!_listEq(row, next)) moved = true;
      _writeLine(line, dir, next);
    }
    if (!moved) {
      cells = before; // no-op slides must not mutate the board
      return null;
    }
    return gained;
  }

  /// True when at least one legal slide exists.
  bool get canMove {
    for (int d = 0; d < 4; d++) {
      final List<List<int>> copy = <List<int>>[for (final List<int> r in cells) List<int>.of(r)];
      if (slide(d) != null) {
        cells = copy;
        return true;
      }
      cells = copy;
    }
    return false;
  }

  List<int> _line(int index, int dir) {
    switch (dir) {
      case 0: // left: read rows as-is
        return List<int>.of(cells[index]);
      case 2: // right: read rows reversed
        return List<int>.of(cells[index].reversed);
      case 1: // up: read the column top→bottom
        return <int>[for (int r = 0; r < size; r++) cells[r][index]];
      default: // down: read the column bottom→top
        return <int>[for (int r = size - 1; r >= 0; r--) cells[r][index]];
    }
  }

  void _writeLine(int index, int dir, List<int> values) {
    switch (dir) {
      case 0:
        cells[index] = List<int>.of(values);
      case 2:
        cells[index] = List<int>.of(values.reversed);
      case 1:
        for (int r = 0; r < size; r++) {
          cells[r][index] = values[r];
        }
      default:
        for (int r = 0; r < size; r++) {
          cells[size - 1 - r][index] = values[r];
        }
    }
  }

  static bool _listEq(List<int> a, List<int> b) {
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void reset() {
    for (final List<int> row in cells) {
      for (int i = 0; i < row.length; i++) {
        row[i] = 0;
      }
    }
  }
}

/// The seven tetromino shapes of Tetris Rush, each as rotation states of (x, y) cells on
/// a 4x4 grid. Rotation is done on the fly so no two games can disagree about a shape.
enum SoloPiece { i, o, t, s, z, j, l }

class Tetromino {
  const Tetromino(this.kind, this.x, this.y, this.rotation);
  final SoloPiece kind;
  final int x;
  final int y;
  final int rotation;

  static const Map<SoloPiece, List<List<(int, int)>>> _shapes = <SoloPiece, List<List<(int, int)>>>{
    SoloPiece.i: <List<(int, int)>>[
      <(int, int)>[(0, 1), (1, 1), (2, 1), (3, 1)],
      <(int, int)>[(2, 0), (2, 1), (2, 2), (2, 3)],
    ],
    SoloPiece.o: <List<(int, int)>>[
      <(int, int)>[(1, 0), (2, 0), (1, 1), (2, 1)],
    ],
    SoloPiece.t: <List<(int, int)>>[
      <(int, int)>[(1, 0), (0, 1), (1, 1), (2, 1)],
      <(int, int)>[(1, 0), (1, 1), (2, 1), (1, 2)],
      <(int, int)>[(0, 1), (1, 1), (2, 1), (1, 2)],
      <(int, int)>[(1, 0), (0, 1), (1, 1), (1, 2)],
    ],
    SoloPiece.s: <List<(int, int)>>[
      <(int, int)>[(1, 0), (2, 0), (0, 1), (1, 1)],
      <(int, int)>[(1, 0), (1, 1), (2, 1), (2, 2)],
    ],
    SoloPiece.z: <List<(int, int)>>[
      <(int, int)>[(0, 0), (1, 0), (1, 1), (2, 1)],
      <(int, int)>[(2, 0), (1, 1), (2, 1), (1, 2)],
    ],
    SoloPiece.j: <List<(int, int)>>[
      <(int, int)>[(0, 0), (0, 1), (1, 1), (2, 1)],
      <(int, int)>[(1, 0), (2, 0), (1, 1), (1, 2)],
      <(int, int)>[(0, 1), (1, 1), (2, 1), (2, 2)],
      <(int, int)>[(1, 0), (1, 1), (0, 2), (1, 2)],
    ],
    SoloPiece.l: <List<(int, int)>>[
      <(int, int)>[(2, 0), (0, 1), (1, 1), (2, 1)],
      <(int, int)>[(1, 0), (1, 1), (1, 2), (2, 2)],
      <(int, int)>[(0, 1), (1, 1), (2, 1), (0, 2)],
      <(int, int)>[(0, 0), (1, 0), (1, 1), (1, 2)],
    ],
  };

  List<(int, int)> get cells {
    final List<List<(int, int)>> rots = _shapes[kind]!;
    final List<(int, int)> base = rots[rotation % rots.length];
    return <(int, int)>[for (final (int, int) c in base) (x + c.$1, y + c.$2)];
  }

  Tetromino moved(int dx, int dy) => Tetromino(kind, x + dx, y + dy, rotation);
  Tetromino rotated([int turns = 1]) => Tetromino(kind, x, y, (rotation + turns) % _shapes[kind]!.length);
}
