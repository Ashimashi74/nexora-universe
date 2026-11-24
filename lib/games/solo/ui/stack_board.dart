import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../arcade_kit/arcade_skin.dart';
import '../core/solo_rules_b.dart';
import '../solo_kit.dart';

/// =====================================================================================
/// STACK TOWER — drop sliding slabs, keep the overlap, chase the perfect combo.
///
/// A dusk skyline with depth haze, a tower of individually shaded slabs that casts a long
/// shadow on the plaza, the sliding slab with a laser drop guide and a shrink line, and
/// "PERFECT" callouts with confetti that grow with the combo.
/// =====================================================================================
class StackBoard extends SoloBoard {
  const StackBoard({super.key, required super.run});
  @override
  StackBoardState createState() => StackBoardState();
}

class StackBoardState extends SoloBoardState<StackBoard> {
  late StackWorld world;
  String _flash = '';
  double _flashT = 0;
  int _flashCombo = 0;
  double _dropImpact = 0;
  double _squash = 0;

  static const List<Color> _slabTints = <Color>[
    Color(0xFFFF7A9A),
    Color(0xFFFFC42E),
    Color(0xFF7CF7C1),
    Color(0xFF6BC6FF),
    Color(0xFFB98CFF),
  ];

  @override
  void reset() {
    world = StackWorld(seed: widget.run.seed);
    _flash = '';
    _flashT = 0;
    _flashCombo = 0;
    _dropImpact = 0;
    _squash = 0;
    widget.run.set(0);
  }

  @override
  void step(double dt) {
    world.update(dt);
    if (_flashT > 0) _flashT -= dt;
    if (_dropImpact > 0) _dropImpact -= dt;
    _squash = soloLerp(_squash, 0, soloApproach(0.0005, dt));
  }

  void _drop() {
    if (world.over || !simulating) return;
    final String r = world.drop();
    _squash = 1;
    _dropImpact = 0.25;
    final Rect play = playRect(viewport);
    final _StackLayout lay = _StackLayout.of(play, world);
    if (r == 'perfect') {
      _flash = 'PERFECT';
      _flashT = 0.85;
      _flashCombo++;
      fx.confetti(lay.topCentre, count: 18 + _flashCombo * 4);
      fx.shake(4);
      fx.flashScreen(widget.run.skin.accent2, 0.10);
      widget.run.set(world.floors * 10 + world.perfect * 15);
    } else if (r == 'ok') {
      _flash = '';
      _flashCombo = 0;
      burst(play, lay.topCentre, widget.run.skin.accent, count: 10, speed: 160);
      widget.run.set(world.floors * 10 + world.perfect * 15);
    } else {
      _flash = 'MISS';
      _flashT = 0.9;
      _flashCombo = 0;
      burst(play, lay.topCentre, SoloArt.danger, count: 24, speed: 280);
      fx.shake(16);
      fx.flashScreen(SoloArt.danger, 0.2);
      widget.run.gameOver();
    }
    setState(() {});
  }

  @override
  void onPointer(Offset at, SoloGesture kind) {
    if (kind == SoloGesture.down) _drop();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final ArcadeSkin skin = widget.run.skin;
    final Color accent = skin.accent;
    final Color accent2 = skin.accent2;
    final Rect play = playRect(size);
    final _StackLayout lay = _StackLayout.of(play, world);
    final double boardW = lay.boardW;
    final double left = lay.left;
    final double bottom = lay.bottom;
    final double blockH = lay.blockH;

    // ---------------------------------------------------------------- dusk city
    SoloArt.backdrop(canvas, size, skin: skin, time: clock, halo: 0.20,
        haloAt: Offset(size.width * 0.5, bottom));
    SoloArt.sunset(canvas, Offset(size.width * 0.72, lay.top - blockH * 3.4), play.height * 0.17,
        SoloArt.a(accent2, 0.8), SoloArt.a(accent, 0.3), glow: accent);
    SoloArt.skyline(canvas, size, bottom + 4, SoloArt.a(SoloArt.mix(accent, const Color(0xFF0A0F1C), 0.86), 0.95),
        seed: 12, count: 18);
    // plaza reflection
    final Rect plaza = Rect.fromLTWH(0, bottom, size.width, size.height - bottom);
    canvas.drawRect(
      plaza,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[SoloArt.a(accent, 0.18), SoloArt.a(const Color(0xFF04060D), 0.0)],
        ).createShader(plaza),
    );

    // ---------------------------------------------------------------- towers shadow
    final double towerH = blockH * world.blocks.length;
    canvas.drawRect(
      Rect.fromLTWH(left + boardW * 0.12, bottom - towerH + blockH * 0.5, boardW * 0.9, towerH + blockH * 0.6),
      Paint()
        ..color = SoloArt.a(const Color(0xFF000000), 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );

    // ---------------------------------------------------------------- slabs (bottom → top)
    for (int i = 0; i < world.blocks.length; i++) {
      final StackBlock b = world.blocks[i];
      final Rect r = Rect.fromLTWH(left + b.left * boardW, bottom - blockH * (i + 1), b.width * boardW, blockH);
      final Color tint = _slabTints[i % _slabTints.length];
      final bool top = i == world.blocks.length - 1;
      _paintSlab(canvas, r.deflate(0.8), tint, top: top, accent: accent2);
    }

    // ---------------------------------------------------------------- moving slab + guide
    if (!world.over) {
      final Rect moving = Rect.fromLTWH(left + world.movingLeft * boardW, lay.top - blockH, world.movingWidth * boardW, blockH);
      final Rect guide = Rect.fromLTWH(moving.left, lay.top, moving.width, bottom - lay.top);
      // drop guide column
      canvas.drawRect(
        guide,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[SoloArt.a(accent2, 0.16), SoloArt.a(accent2, 0.0)],
          ).createShader(guide),
      );
      for (double x = guide.left; x < guide.right; x += 8) {
        canvas.drawLine(Offset(x, guide.top + 6), Offset(x, guide.bottom), SoloArt.stroke(SoloArt.a(accent2, 0.10), 1));
      }
      for (final double x in <double>[guide.left, guide.right]) {
        canvas.drawLine(Offset(x, guide.top), Offset(x, guide.bottom), SoloArt.stroke(SoloArt.a(accent2, 0.55), 1.4));
      }
      // the slab itself
      paintGlow(canvas, moving.center, moving.width * 0.8, accent2, 0.16);
      _paintSlab(canvas, moving, accent2, top: true, accent: accent2, bounce: _squash);
      // direction arrows
      final double ax = world.direction > 0 ? moving.right + 10 : moving.left - 10;
      for (int i = 0; i < 2; i++) {
        final double dx = world.direction > 0 ? i * 6 : -i * 6;
        canvas.drawLine(Offset(ax + dx, moving.center.dy - 5), Offset(ax + dx + world.direction * 5, moving.center.dy),
            SoloArt.stroke(SoloArt.a(accent2, 0.7), 1.6));
        canvas.drawLine(Offset(ax + dx, moving.center.dy + 5), Offset(ax + dx + world.direction * 5, moving.center.dy),
            SoloArt.stroke(SoloArt.a(accent2, 0.7), 1.6));
      }
    }

    // ---------------------------------------------------------------- readouts
    SoloArt.chip(canvas, Offset(16, play.top + 16), '${world.floors} FLOORS', SoloArt.ink);
    SoloArt.chip(canvas, Offset(size.width - 16, play.top + 16), '${world.perfect} PERFECT', accent2, alignRight: true);
    if (_flashT > 0) {
      final double k = 1 - (_flashT / 0.85).clamp(0.0, 1.0);
      paintCallout(canvas, Offset(size.width / 2, lay.top - blockH * 3.2), _flash,
          _flash == 'MISS' ? SoloArt.danger : accent, scale: 1 + k * 0.3, alpha: (1 - k).clamp(0.0, 1.0));
    }
    if (_flashCombo >= 2 && _flashT > 0) {
      paintCallout(canvas, Offset(size.width / 2, lay.top - blockH * 4.4), 'COMBO ×$_flashCombo', accent2,
          scale: 0.9, alpha: (_flashT / 0.85).clamp(0.0, 1.0));
    }

    SoloArt.frame(canvas, size, accent);
    paintFx(canvas, size);
  }

  void _paintSlab(Canvas canvas, Rect r, Color tint, {required bool top, required Color accent, double bounce = 0}) {
    final Rect body = bounce > 0 ? Rect.fromCenter(center: r.center + Offset(0, bounce * 2), width: r.width * (1 + bounce * 0.04), height: r.height) : r;
    SoloArt.cube(canvas, body, tint, radius: 3.4, depth: 5, glow: top ? 0.35 : 0.1,
        edge: SoloArt.a(const Color(0xFFFFFFFF), top ? 0.5 : 0.22));
    // floor label lines
    for (double y = body.top + body.height * 0.35; y < body.bottom - 2; y += body.height * 0.32) {
      canvas.drawLine(Offset(body.left + 3, y), Offset(body.right - 3, y), SoloArt.stroke(SoloArt.a(const Color(0xFF000000), 0.14), 1));
    }
    // right-hand shading to sell the 3D read
    canvas.drawRect(
      Rect.fromLTWH(body.right - body.width * 0.14, body.top, body.width * 0.14, body.height),
      Paint()..color = SoloArt.a(const Color(0xFF000000), 0.16),
    );
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
              actionIcon: Icons.south_rounded,
              actionLabel: 'DROP',
              onAction: _drop,
            ),
          ),
        ],
      );
}

/// Vertical layout of the tower so the painter and the drop guide agree.
class _StackLayout {
  _StackLayout({required this.left, required this.boardW, required this.bottom, required this.blockH, required this.top});
  final double left;
  final double boardW;
  final double bottom;
  final double blockH;

  /// Top edge of the tower (bottom - blockH * floors).
  final double top;

  Offset get topCentre => Offset(left + boardW / 2, top);

  static _StackLayout of(Rect play, StackWorld world) {
    final double boardW = math.min(play.width * 0.74, 380);
    final double left = play.center.dx - boardW / 2;
    final double bottom = play.bottom - play.height * 0.03;
    final double blockH = math.min(play.height * 0.055, (bottom - play.top - play.height * 0.22) / math.max(6.0, (world.blocks.length + 3).toDouble()));
    final double top = bottom - blockH * world.blocks.length;
    return _StackLayout(left: left, boardW: boardW, bottom: bottom, blockH: blockH, top: top);
  }
}
