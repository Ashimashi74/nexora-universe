import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../arcade_kit/arcade_skin.dart';
import '../core/solo_rules.dart';
import '../core/solo_rules_c.dart';
import '../solo_kit.dart';

/// =====================================================================================
/// TETRIS RUSH — a 10x18 well with neon glass blocks, ghost landing preview, next-piece
/// card, line-clear flashes and an accelerating gravity bar.
/// =====================================================================================
class TetrisBoard extends SoloBoard {
  const TetrisBoard({super.key, required super.run});
  @override
  TetrisBoardState createState() => TetrisBoardState();
}

class TetrisBoardState extends SoloBoardState<TetrisBoard> {
  late TetrisWorld world;
  double _lineFlash = 0;
  double _piecePulse = 0;
  bool _wasOver = false;

  static const List<Color> _pieceColours = <Color>[
    Color(0xFF35D6F0), // i  cyan
    Color(0xFFFFD166), // o  gold
    Color(0xFFB98CFF), // t  violet
    Color(0xFF7CFF9B), // s  mint
    Color(0xFFFF6B8A), // z  rose
    Color(0xFF6B8CFF), // j  indigo
    Color(0xFFFF9F45), // l  amber
  ];

  @override
  void reset() {
    world = TetrisWorld(seed: widget.run.seed);
    _lineFlash = 0;
    _piecePulse = 0;
    _wasOver = false;
    widget.run.set(0);
  }

  @override
  void step(double dt) {
    final int before = world.lines;
    world.tick(dt);
    if (_lineFlash > 0) _lineFlash -= dt;
    _piecePulse += dt;
    widget.run.set(world.score + world.lines * 100);
    if (world.lines > before) {
      _lineFlash = 0.32;
      final Rect play = playRect(viewport);
      final _Well well = _Well.of(play, world);
      fx.shake(4);
      fx.flashScreen(_pieceColours[0], 0.10);
      for (int i = 0; i < 3; i++) {
        fx.burst(Offset(well.rect.center.dx, well.rect.bottom - i * well.cell * 2), const Color(0xFFFFFFFF), count: 8, speed: 200);
      }
    }
    if (!_wasOver && world.over) {
      _wasOver = true;
      fx.shake(18);
      fx.flashScreen(SoloArt.danger, 0.25);
    }
  }

  void _input(void Function() action) {
    if (!simulating) return;
    setState(action);
  }

  /// Ghost position of the current piece (where a hard drop would land).
  int _ghostY(Tetromino p) {
    int y = p.y;
    while (true) {
      final Tetromino next = Tetromino(p.kind, p.x, y + 1, p.rotation);
      bool collides = false;
      for (final (int, int) c in next.cells) {
        if (c.$2 >= TetrisWorld.rows) collides = true;
        if (c.$1 < 0 || c.$1 >= TetrisWorld.cols) collides = true;
        if (c.$2 >= 0 && c.$2 < TetrisWorld.rows && world.board[c.$2][c.$1] != 0) collides = true;
      }
      if (collides) return y;
      y++;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final ArcadeSkin skin = widget.run.skin;
    final Color accent = skin.accent;
    final Color accent2 = skin.accent2;
    final Rect play = playRect(size);
    final _Well well = _Well.of(play, world);
    final Rect w = well.rect;

    // ---------------------------------------------------------------- backdrop
    SoloArt.backdrop(canvas, size, skin: skin, time: clock, halo: 0.18, haloAt: Offset(size.width / 2, play.center.dy));
    // side columns with scan lines
    for (final double x in <double>[0, size.width]) {
      canvas.drawRect(
        Rect.fromLTWH(x == 0 ? 0 : x - 46, play.top, 46, size.height - play.top),
        Paint()
          ..shader = LinearGradient(
            begin: x == 0 ? Alignment.centerLeft : Alignment.centerRight,
            end: x == 0 ? Alignment.centerRight : Alignment.centerLeft,
            colors: <Color>[SoloArt.a(accent, 0.12), Colors.transparent],
          ).createShader(Rect.fromLTWH(x == 0 ? 0 : x - 46, play.top, 46, size.height - play.top)),
      );
    }

    // ---------------------------------------------------------------- well frame
    SoloArt.panel(canvas, w.inflate(well.cell * 0.30), accent, radius: 16, glow: 0.5, border: 1.4);
    // playfield background + grid
    canvas.drawRect(w, Paint()..color = const Color(0xF4040710));
    for (int r = 0; r < TetrisWorld.rows; r++) {
      for (int c = 0; c < TetrisWorld.cols; c++) {
        final Rect cell = Rect.fromLTWH(w.left + c * well.cell, w.top + r * well.cell, well.cell, well.cell);
        canvas.drawRect(cell, SoloArt.stroke(SoloArt.a(const Color(0xFFFFFFFF), 0.035), 1));
      }
    }
    if (_lineFlash > 0) {
      canvas.drawRect(w, Paint()..color = SoloArt.a(const Color(0xFFFFFFFF), _lineFlash * 0.30));
    }

    // ---------------------------------------------------------------- locked cells
    for (int r = 0; r < TetrisWorld.rows; r++) {
      for (int c = 0; c < TetrisWorld.cols; c++) {
        final int v = world.board[r][c];
        if (v == 0) continue;
        final Rect cell = Rect.fromLTWH(w.left + c * well.cell, w.top + r * well.cell, well.cell, well.cell).deflate(well.cell * 0.06);
        SoloArt.cube(canvas, cell, _pieceColours[(v - 1) % _pieceColours.length], radius: well.cell * 0.18, depth: well.cell * 0.10, glow: 0.18);
      }
    }

    // ---------------------------------------------------------------- current piece + ghost
    final Tetromino? p = world.current;
    if (p != null) {
      final int gy = _ghostY(p);
      final Color tint = _pieceColours[p.kind.index % _pieceColours.length];
      for (final (int, int) c in Tetromino(p.kind, p.x, gy, p.rotation).cells) {
        if (c.$2 < 0) continue;
        final Rect cell = Rect.fromLTWH(w.left + c.$1 * well.cell, w.top + c.$2 * well.cell, well.cell, well.cell).deflate(well.cell * 0.06);
        canvas.drawRRect(
          RRect.fromRectAndRadius(cell, Radius.circular(well.cell * 0.18)),
          Paint()..color = SoloArt.a(tint, 0.16),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(cell, Radius.circular(well.cell * 0.18)),
          SoloArt.stroke(SoloArt.a(tint, 0.45), 1.2),
        );
      }
      for (final (int, int) c in p.cells) {
        if (c.$2 < 0) continue;
        final Rect cell = Rect.fromLTWH(w.left + c.$1 * well.cell, w.top + c.$2 * well.cell, well.cell, well.cell).deflate(well.cell * 0.06);
        paintGlow(canvas, cell.center, well.cell * 1.1, tint, 0.16 + 0.06 * math.sin(_piecePulse * 6));
        SoloArt.cube(canvas, cell, tint, radius: well.cell * 0.18, depth: well.cell * 0.10, glow: 0.35,
            edge: SoloArt.a(const Color(0xFFFFFFFF), 0.5));
      }
    }

    // ---------------------------------------------------------------- side panels
    // score / lines / level column on the left of the well when there is room
    final double panelW = play.width - w.width;
    if (panelW > 120) {
      final Rect side = Rect.fromLTWH(12, play.top + 16, (w.left - 24).clamp(60.0, 150.0), 150);
      SoloArt.panel(canvas, side, accent, radius: 14, glow: 0.25);
      SoloArt.label(canvas, 'SCORE', side.topLeft + const Offset(12, 16), size: 9, center: false, color: SoloArt.a(SoloArt.mute, 0.9), weight: FontWeight.w700);
      SoloArt.label(canvas, '${world.score + world.lines * 100}', side.topLeft + const Offset(12, 36), size: 20, center: false, color: SoloArt.ink, glow: accent);
      SoloArt.label(canvas, 'LINES', side.topLeft + const Offset(12, 68), size: 9, center: false, color: SoloArt.a(SoloArt.mute, 0.9), weight: FontWeight.w700);
      SoloArt.label(canvas, '${world.lines}', side.topLeft + const Offset(12, 88), size: 20, center: false, color: accent2);
      final Rect gravity = Rect.fromLTWH(side.left + 12, side.bottom - 26, side.width - 24, 6);
      SoloArt.meter(canvas, gravity, 1 - (world.gravity / 0.75), accent2);
      SoloArt.label(canvas, 'GRAVITY', gravity.topLeft - const Offset(0, 10), size: 8, center: false,
          color: SoloArt.a(SoloArt.mute, 0.8), weight: FontWeight.w700);
    } else {
      final Rect gravity = Rect.fromLTWH(16, play.top + 16, play.width - 32, 5);
      SoloArt.meter(canvas, gravity, 1 - (world.gravity / 0.75), accent2);
    }
    if (world.over) {
      SoloArt.label(canvas, 'STACK OVERFLOW', Offset(size.width / 2, w.center.dy), size: 22, color: SoloArt.danger, glow: SoloArt.danger);
    }

    SoloArt.frame(canvas, size, accent);
    paintFx(canvas, size);
  }

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: <Widget>[
          super.build(context),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SoloStage(
              accent: widget.run.skin.accent,
              onLeft: () => _input(world.moveLeft),
              onRight: () => _input(world.moveRight),
              extra: SoloPad(
                icon: Icons.rotate_right_rounded,
                onTap: () => _input(world.rotate),
                size: 66,
                accent: widget.run.skin.accent2,
              ),
              actionIcon: Icons.keyboard_double_arrow_down_rounded,
              actionLabel: 'DROP',
              onAction: () => _input(world.hardDrop),
            ),
          ),
        ],
      );
}

/// Well layout shared by the painter and the ghost calculation.
class _Well {
  _Well({required this.rect, required this.cell});
  final Rect rect;
  final double cell;

  static _Well of(Rect play, TetrisWorld world) {
    final double cell = math.min((play.width - 96) / TetrisWorld.cols, (play.height - 12) / TetrisWorld.rows);
    return _Well(
      rect: Rect.fromCenter(
        center: Offset(play.center.dx, play.center.dy),
        width: cell * TetrisWorld.cols,
        height: cell * TetrisWorld.rows,
      ),
      cell: cell,
    );
  }
}
