import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/solo_rules.dart';
import '../core/solo_rules_b.dart';
import '../core/solo_rules_c.dart';
import '../solo_kit.dart';

// =====================================================================================
// NX 2048 — slide a 4x4 board, merge equal tiles, reach 2048.
// =====================================================================================
class World2048Board extends SoloBoard {
  const World2048Board({super.key, required super.run});
  @override
  World2048BoardState createState() => World2048BoardState();
}

class World2048BoardState extends SoloBoardState<World2048Board> {
  late World2048Game world;
  final Map<String, double> _pop = <String, double>{};
  int _moves = 0;

  static const List<Color> _tileColours = <Color>[
    Color(0xFF111A2B), // empty
    Color(0xFF172742), // 2
    Color(0xFF1D3454), // 4
    Color(0xFF1D526C), // 8
    Color(0xFF267B91), // 16
    Color(0xFF3499A4), // 32
    Color(0xFF49B9AA), // 64
    Color(0xFF67D2A0), // 128
    Color(0xFF95E47D), // 256
    Color(0xFFD2EA70), // 512
    Color(0xFFF5D876), // 1024
    Color(0xFFFFF0BA), // 2048+
  ];

  @override
  void reset() {
    world = World2048Game(seed: widget.run.seed);
    world.board.spawn();
    world.board.spawn();
    widget.run.set(0);
    _moves = 0;
  }

  @override
  void step(double dt) {}

  void _move(int dir) {
    if (world.over) return;
    final List<List<int>> before = <List<int>>[for (final List<int> r in world.board.cells) List<int>.of(r)];
    final int gained = world.move(dir);
    final List<List<int>> after = world.board.cells;
    for (int r = 0; r < 4; r++) {
      for (int c = 0; c < 4; c++) {
        if (before[r][c] != after[r][c]) _pop['$r:$c'] = 0;
      }
    }
    if (gained == 0 && _sameBoard(before, after)) return;
    _moves++;
    widget.run.set(world.score);
    if (world.over) widget.run.gameOver();
    setState(() {});
  }

  bool _sameBoard(List<List<int>> a, List<List<int>> b) {
    for (int r = 0; r < 4; r++) {
      for (int c = 0; c < 4; c++) {
        if (a[r][c] != b[r][c]) return false;
      }
    }
    return true;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Color accent = widget.run.skin.accent;
    LuxeBoardPainter.background(canvas, size, accent);
    final double board = math.min(size.width - 32, size.height - 220);
    final Rect area = Rect.fromCenter(center: Offset(size.width / 2, size.height * 0.52), width: board, height: board);
    final double gap = board * 0.028;
    final double cell = (board - gap * 5) / 4;

    LuxeBoardPainter.roundedRect(canvas, area.inflate(gap * 0.6), 22, const Color(0xE612110D), border: accent.withValues(alpha: 0.35));
    for (int r = 0; r < 4; r++) {
      for (int c = 0; c < 4; c++) {
        final int v = world.board.cell(r, c);
        final Rect rr = Rect.fromLTWH(
          area.left + gap + c * (cell + gap),
          area.top + gap + r * (cell + gap),
          cell,
          cell,
        );
        final double pop = _pop['$r:$c'] == null ? 1.0 : math.min(1.0, (_pop['$r:$c']! + 0.18));
        _pop['$r:$c'] = pop;
        final double scale = 0.82 + 0.18 * LuxeBoardPainter.easeOutBack(pop);
        final Rect scaled = Rect.fromCenter(center: rr.center, width: rr.width * scale, height: rr.height * scale);
        final int idx = v == 0 ? 0 : (math.log(v) / math.ln2).round();
        final Color colour = _tileColours[idx.clamp(0, _tileColours.length - 1)];
        LuxeBoardPainter.roundedRect(
          canvas,
          scaled,
          cell * 0.18,
          colour,
          border: v == 0 ? null : LuxeBoardPainter.champagne.withValues(alpha: 0.22),
        );
        if (v != 0) {
          LuxeBoardPainter.text(
            canvas,
            '$v',
            rr.center,
            color: idx >= 4 ? const Color(0xFF1A1408) : LuxeBoardPainter.ink,
            size: cell * (v >= 1000 ? 0.28 : v >= 100 ? 0.32 : 0.38),
            weight: FontWeight.w900,
          );
        }
      }
    }
    LuxeBoardPainter.text(canvas, 'SCORE ${world.score}', Offset(size.width / 2, area.top - 28),
        color: LuxeBoardPainter.champagne, size: 15);
    LuxeBoardPainter.text(canvas, '$_moves MOVES', Offset(size.width / 2, area.bottom + 26),
        color: LuxeBoardPainter.mute, size: 12, weight: FontWeight.w600);
  }

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: <Widget>[
        super.build(context),
        Positioned(
          left: 18,
          bottom: 28,
          right: 18,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: <Widget>[
            Row(children: <Widget>[
              _arrow(Icons.chevron_left_rounded, () => _move(0)),
              const SizedBox(width: 8),
              _arrow(Icons.keyboard_arrow_down_rounded, () => _move(3)),
            ]),
            Row(children: <Widget>[
              _arrow(Icons.keyboard_arrow_up_rounded, () => _move(1)),
              const SizedBox(width: 8),
              _arrow(Icons.chevron_right_rounded, () => _move(2)),
            ]),
          ]),
        ),
      ]);

  Widget _arrow(IconData i, VoidCallback tap) => SoloPad(icon: i, onTap: tap, size: 62);
}

// =====================================================================================
// TETRIS RUSH — a 10x18 wall, clear lines, gravity accelerates.
// =====================================================================================
class TetrisBoard extends SoloBoard {
  const TetrisBoard({super.key, required super.run});
  @override
  TetrisBoardState createState() => TetrisBoardState();
}

class TetrisBoardState extends SoloBoardState<TetrisBoard> {
  late TetrisWorld world;

  static const List<Color> _pieceColours = <Color>[
    Color(0xFFD9B872), // i gold
    Color(0xFFF6E7BD), // o champagne
    Color(0xFFB08A3A), // t bronze
    Color(0xFF8FB98A), // s moss
    Color(0xFFC97A6A), // z clay
    Color(0xFF9A8FC9), // j lilac
    Color(0xFF6FA8B8), // l teal
  ];

  @override
  void reset() {
    world = TetrisWorld(seed: widget.run.seed);
    widget.run.set(0);
  }

  @override
  void step(double dt) {
    world.tick(dt);
    widget.run.set(world.score + world.lines * 100);
    if (world.over) {
      widget.run.gameOver();
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Color accent = widget.run.skin.accent;
    LuxeBoardPainter.background(canvas, size, accent);
    final double cell = math.min((size.width - 48) / TetrisWorld.cols, (size.height - 210) / TetrisWorld.rows);
    final double w = cell * TetrisWorld.cols;
    final double h = cell * TetrisWorld.rows;
    final Rect well = Rect.fromCenter(center: Offset(size.width / 2, size.height * 0.5 - 8), width: w, height: h);
    LuxeBoardPainter.roundedRect(canvas, well.inflate(6), 14, const Color(0xE612110D),
        border: accent.withValues(alpha: 0.4));

    for (int r = 0; r < TetrisWorld.rows; r++) {
      for (int c = 0; c < TetrisWorld.cols; c++) {
        final int v = world.board[r][c];
        final Rect cellRect = Rect.fromLTWH(well.left + c * cell, well.top + r * cell, cell - 1.5, cell - 1.5);
        if (v == 0) {
          canvas.drawRect(cellRect, LuxeBoardPainter.fill(const Color(0x0DFFFFFF)));
        } else {
          LuxeBoardPainter.roundedRect(canvas, cellRect, cell * 0.16, _pieceColours[(v - 1) % _pieceColours.length],
              border: LuxeBoardPainter.champagne.withValues(alpha: 0.18));
        }
      }
    }
    final Tetromino? p = world.current;
    if (p != null) {
      LuxeBoardPainter.glow(canvas, well.center, w * 0.5, _pieceColours[p.kind.index], 0.10);
      for (final (int, int) c in p.cells) {
        if (c.$2 < 0) continue;
        final Rect cellRect = Rect.fromLTWH(well.left + c.$1 * cell, well.top + c.$2 * cell, cell - 1.5, cell - 1.5);
        LuxeBoardPainter.roundedRect(canvas, cellRect, cell * 0.16, _pieceColours[p.kind.index],
            border: LuxeBoardPainter.champagne.withValues(alpha: 0.35));
      }
    }
    LuxeBoardPainter.text(canvas, 'LINES ${world.lines}', Offset(size.width / 2, well.top - 26),
        color: LuxeBoardPainter.champagne, size: 15);
  }

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: <Widget>[
        super.build(context),
        Positioned(
          left: 16,
          right: 16,
          bottom: 26,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: <Widget>[
            Row(children: <Widget>[
              SoloPad(icon: Icons.chevron_left_rounded, onTap: () => setState(world.moveLeft), size: 62),
              const SizedBox(width: 8),
              SoloPad(icon: Icons.chevron_right_rounded, onTap: () => setState(world.moveRight), size: 62),
            ]),
            Row(children: <Widget>[
              SoloPad(icon: Icons.rotate_right_rounded, onTap: () => setState(world.rotate), size: 62),
              const SizedBox(width: 8),
              SoloPad(
                icon: Icons.keyboard_double_arrow_down_rounded,
                onTap: () => setState(world.hardDrop),
                size: 62,
                accent: LuxeBoardPainter.champagne,
              ),
            ]),
          ]),
        ),
      ]);
}

// =====================================================================================
// STACK TOWER — drop sliding blocks, keep the overlap, perfect drops grow the combo.
// =====================================================================================
class StackBoard extends SoloBoard {
  const StackBoard({super.key, required super.run});
  @override
  StackBoardState createState() => StackBoardState();
}

class StackBoardState extends SoloBoardState<StackBoard> {
  late StackWorld world;
  String _flash = '';
  double _flashT = 0;

  @override
  void reset() {
    world = StackWorld(seed: widget.run.seed);
    widget.run.set(0);
    _flash = '';
  }

  @override
  void step(double dt) {
    world.update(dt);
    if (_flashT > 0) _flashT -= dt;
  }

  void _drop() {
    if (world.over) return;
    final String r = world.drop();
    if (r == 'perfect') {
      _flash = 'PERFECT';
      _flashT = 0.7;
      widget.run.set(world.floors * 10 + world.perfect * 15);
    } else if (r == 'ok') {
      widget.run.set(world.floors * 10 + world.perfect * 15);
    } else {
      widget.run.gameOver();
    }
    setState(() {});
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Color accent = widget.run.skin.accent;
    LuxeBoardPainter.background(canvas, size, accent);
    final double boardW = math.min(size.width * 0.82, 420);
    final double left = (size.width - boardW) / 2;
    final double bottom = size.height - 120;
    final double blockH = math.min(26, (bottom - 90) / math.max(8, world.blocks.length + 2));
    final double top = bottom - blockH * world.blocks.length;

    for (int i = 0; i < world.blocks.length; i++) {
      final StackBlock b = world.blocks[i];
      final Rect r = Rect.fromLTWH(left + b.left * boardW, bottom - blockH * (i + 1), b.width * boardW - 2, blockH - 2);
      final Color c = i == world.blocks.length - 1 ? LuxeBoardPainter.champagne : accent;
      LuxeBoardPainter.roundedRect(canvas, r, blockH * 0.22, c.withValues(alpha: 0.9),
          border: const Color(0xFF1A1408).withValues(alpha: 0.4));
    }

    if (!world.over) {
      final Rect moving = Rect.fromLTWH(left + world.movingLeft * boardW, top - blockH, world.movingWidth * boardW - 2, blockH - 2);
      LuxeBoardPainter.glow(canvas, moving.center, moving.width * 0.6, LuxeBoardPainter.champagne, 0.12);
      LuxeBoardPainter.roundedRect(canvas, moving, blockH * 0.22, LuxeBoardPainter.champagne,
          border: accent.withValues(alpha: 0.7));
    }

    LuxeBoardPainter.text(canvas, '${world.floors} FLOORS', Offset(size.width / 2, top - blockH * 2.6),
        color: LuxeBoardPainter.champagne, size: 15);
    if (_flashT > 0) {
      LuxeBoardPainter.text(canvas, _flash, Offset(size.width / 2, top - blockH * 4.2),
          color: LuxeBoardPainter.champagne, size: 22, weight: FontWeight.w900);
    }
  }

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: <Widget>[
        super.build(context),
        Positioned(
          left: 0,
          right: 0,
          bottom: 26,
          child: Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _drop,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(40),
                  gradient: LinearGradient(colors: <Color>[widget.run.skin.accent, const Color(0xFFEAFBFF)]),
                  boxShadow: <BoxShadow>[BoxShadow(color: widget.run.skin.accent.withValues(alpha: 0.42), blurRadius: 24)],
                ),
                child: const Text('DROP',
                    style: TextStyle(
                        fontFamily: 'ChakraPetch',
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        letterSpacing: 1.4,
                        color: Color(0xFF1A1408))),
              ),
            ),
          ),
        ),
      ]);
}

// =====================================================================================
// KNIFE HIT — throw knives into a spinning log; never hit your own.
// =====================================================================================
class KnifeBoard extends SoloBoard {
  const KnifeBoard({super.key, required super.run});
  @override
  KnifeBoardState createState() => KnifeBoardState();
}

class KnifeBoardState extends SoloBoardState<KnifeBoard> {
  late KnifeWorld world;
  double _fly = 0;
  bool _thrown = false;

  @override
  void reset() {
    world = KnifeWorld(seed: widget.run.seed);
    widget.run.set(0);
    _fly = 0;
    _thrown = false;
  }

  @override
  void step(double dt) {
    world.update(dt);
    if (_thrown) {
      _fly += dt * 3.4;
      if (_fly >= 1) {
        _thrown = false;
        _fly = 0;
        final bool ok = world.throwAt();
        widget.run.set(world.thrown * 10 + world.stage * 25);
        if (!ok) widget.run.gameOver();
        setState(() {});
      }
    }
  }

  void _throw() {
    if (_thrown || world.hit) return;
    _thrown = true;
    _fly = 0;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Color accent = widget.run.skin.accent;
    LuxeBoardPainter.background(canvas, size, accent);
    final Offset c = Offset(size.width / 2, size.height * 0.42);
    final double r = math.min(size.width * 0.36, 150);

    LuxeBoardPainter.glow(canvas, c, r, accent, 0.16);
    canvas.drawCircle(c, r, LuxeBoardPainter.fill(const Color(0xFF17140F)));
    canvas.drawCircle(c, r, LuxeBoardPainter.stroke(accent.withValues(alpha: 0.55), 2));
    canvas.drawCircle(c, r * 0.2, LuxeBoardPainter.fill(accent.withValues(alpha: 0.18)));

    for (final double a in world.stuckAngles) {
      final double worldAngle = a + world.rotation;
      final Offset tip = c + Offset(math.cos(worldAngle), math.sin(worldAngle)) * (r * 0.92);
      canvas.save();
      canvas.translate(tip.dx, tip.dy);
      canvas.rotate(worldAngle + math.pi / 2);
      LuxeBoardPainter.roundedRect(canvas, Rect.fromCenter(center: Offset.zero, width: 6, height: 46), 3,
          LuxeBoardPainter.champagne);
      canvas.restore();
    }

    // The knife in hand (flies up to the log when thrown).
    final double startY = size.height * 0.86;
    final double endY = c.dy + r * 0.92;
    final double y = LuxeBoardPainter.lerp(startY, endY, _fly);
    LuxeBoardPainter.glow(canvas, Offset(c.dx, y), 12, LuxeBoardPainter.champagne, 0.3);
    LuxeBoardPainter.roundedRect(canvas, Rect.fromCenter(center: Offset(c.dx, y - 20), width: 8, height: 62), 4,
        LuxeBoardPainter.champagne, border: accent.withValues(alpha: 0.7));

    LuxeBoardPainter.text(canvas, 'STAGE ${world.stage + 1}', Offset(size.width / 2, c.dy - r - 34),
        color: LuxeBoardPainter.champagne, size: 15);
    LuxeBoardPainter.text(canvas, '${world.thrown} KNIVES', Offset(size.width / 2, c.dy + r + 34),
        color: LuxeBoardPainter.mute, size: 12, weight: FontWeight.w600);
  }

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: <Widget>[
        super.build(context),
        Positioned(
          right: 22,
          bottom: 30,
          child: SoloPad(icon: Icons.gps_fixed_rounded, onTap: _throw, size: 78),
        ),
      ]);
}
