import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../arcade_kit/arcade_skin.dart';
import '../core/solo_rules_b.dart';
import '../solo_kit.dart';

/// =====================================================================================
/// BUBBLE SHOOTER — aim, fire, match three or more, and clear the reef.
///
/// The wall is a hex-packed field of glass marbles with refraction highlights and a lit rim;
/// the cannon is a brass turret that tilts with the aim, a dotted trajectory shows where the
/// bubble will land (including a bounce guide off the side walls), and every pop sprays
/// droplets plus a coloured flash on the cleared cells.
/// =====================================================================================
class BubbleBoard extends SoloBoard {
  const BubbleBoard({super.key, required super.run});
  @override
  BubbleBoardState createState() => BubbleBoardState();
}

class BubbleBoardState extends SoloBoardState<BubbleBoard> {
  late BubbleWorld world;
  double _aim = 0;
  double _aimVisual = 0;
  double _cool = 0;
  double _hitFlash = 0;
  Offset? _impact;
  bool _wasCleared = false;

  static const List<Color> _colours = <Color>[
    Color(0xFF37D9FF),
    Color(0xFFFFD166),
    Color(0xFF7CFF9B),
    Color(0xFFB98CFF),
    Color(0xFFFF6B8A),
  ];

  @override
  void reset() {
    world = BubbleWorld(seed: widget.run.seed)..pickColour();
    _aim = 0;
    _aimVisual = 0;
    _cool = 0;
    _hitFlash = 0;
    _impact = null;
    _wasCleared = false;
    widget.run.set(0);
  }

  @override
  void step(double dt) {
    if (_cool > 0) _cool -= dt;
    if (_hitFlash > 0) _hitFlash -= dt;
    _aimVisual = soloLerp(_aimVisual, _aim, soloApproach(0.00005, dt));
    if (!_wasCleared && world.cleared) {
      _wasCleared = true;
      final Rect play = playRect(viewport);
      fx.confetti(Offset(play.center.dx, play.center.dy), count: 50);
      fx.flashScreen(widget.run.skin.accent, 0.2);
    }
    if (world.cleared) widget.run.gameOver();
  }

  void _fire() {
    if (_cool > 0 || !simulating) return;
    _cool = 0.18;
    final Rect play = playRect(viewport);
    final _BubbleGeometry g = _BubbleGeometry.of(play, world);
    final int before = world.popped;
    world.fire();
    final int gained = world.popped - before;
    widget.run.set(world.popped * 12);
    if (gained > 0) {
      _hitFlash = 0.35;
      final Offset at = Offset(play.center.dx + math.sin(_aim) * play.width * 0.3, g.top + g.cell * 2);
      _impact = at;
      burst(play, at, _colours[world.nextColour % _colours.length], count: 20, speed: 300);
      fx.text('+${gained * 12}', at, SoloArt.ink, size: 18);
    }
    world.pickColour();
    setState(() {});
  }

  @override
  void onPointer(Offset at, SoloGesture kind) {
    final Rect play = playRect(viewport);
    switch (kind) {
      case SoloGesture.down:
      case SoloGesture.dragStart:
      case SoloGesture.drag:
        if (!play.contains(at)) return;
        _aim = ((at.dx - play.width / 2) / (play.width / 2)).clamp(-1.0, 1.0) * 1.2;
        setState(() {});
      case SoloGesture.up:
      case SoloGesture.dragEnd:
        _fire();
      default:
        break;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final ArcadeSkin skin = widget.run.skin;
    final Color accent = skin.accent;
    final Rect play = playRect(size);
    final _BubbleGeometry g = _BubbleGeometry.of(play, world);
    final Offset gun = Offset(play.center.dx, play.bottom - g.cell * 0.55);

    // ---------------------------------------------------------------- reef
    SoloArt.backdrop(canvas, size, skin: skin, time: clock, halo: 0.24, haloAt: Offset(size.width * 0.5, play.top + 80));
    SoloArt.caustics(canvas, size, clock, accent);
    // distant reef silhouettes
    for (int i = 0; i < 4; i++) {
      final double x = size.width * (0.12 + i * 0.28);
      final double h = play.height * (0.10 + (i % 2) * 0.07);
      final Path reef = Path()
        ..moveTo(x - 26, play.bottom)
        ..quadraticBezierTo(x - 10, play.bottom - h, x, play.bottom - h * 0.6)
        ..quadraticBezierTo(x + 12, play.bottom - h * 1.15, x + 30, play.bottom);
      canvas.drawPath(reef, Paint()..color = SoloArt.a(SoloArt.mix(accent, const Color(0xFF04101C), 0.86), 0.85));
    }
    // bubbles floating up (decoration)
    for (int i = 0; i < 14; i++) {
      final double t = (clock * (18 + i * 3) + i * 47) % (play.height + 60);
      final double x = (SoloArt.hash01(i * 13) * size.width + math.sin(clock + i) * 8);
      final double rad = 2 + SoloArt.hash01(i * 7) * 5;
      final double y = play.bottom - t;
      canvas.drawCircle(Offset(x, y), rad, SoloArt.stroke(SoloArt.a(accent, 0.18), 1));
    }

    // ---------------------------------------------------------------- bubble wall
    for (int row = 0; row < world.rows; row++) {
      for (int col = 0; col < world.cols; col++) {
        final int v = world.grid[row][col];
        if (v < 0) continue;
        final Offset c = g.cellCentre(row, col);
        if (c.dy > play.bottom - g.cell * 0.4) continue;
        _paintBubble(canvas, c, g.radius, _colours[v % _colours.length]);
      }
    }
    // ceiling rail
    canvas.drawLine(Offset(g.left - g.radius, g.top - g.radius * 0.9), Offset(g.left + g.cols * g.cell + g.radius, g.top - g.radius * 0.9),
        SoloArt.stroke(SoloArt.a(accent, 0.35), 3));

    // ---------------------------------------------------------------- aim guide + cannon
    final Offset dir = Offset(math.sin(_aimVisual), -math.cos(_aimVisual));
    // march the ray, bouncing off the walls, until it reaches the wall of bubbles
    double t = g.cell * 0.8;
    Offset p = gun;
    Offset d = dir;
    bool bounced = false;
    for (int i = 0; i < 90; i++) {
      p += d * (g.cell * 0.18);
      t += g.cell * 0.18;
      if (p.dx < g.left + g.radius * 0.9 || p.dx > g.left + g.cols * g.cell - g.radius * 0.9) {
        d = Offset(-d.dx, d.dy);
        bounced = true;
      }
      if (p.dy < g.top + g.cell * 1.2) break;
      final int row = ((p.dy - g.top) / (g.cell * 0.88)).round();
      final int col = ((p.dx - g.left - (row.isOdd ? g.cell / 2 : 0)) / g.cell).floor();
      if (row >= 0 && row < world.rows && col >= 0 && col < world.cols && world.grid[row][col] >= 0) break;
    }
    for (double u = t; u > 8; u -= 11) {
      final double k = u / t;
      final Offset q = gun + (p - gun) * (1 - k);
      canvas.drawCircle(q, 2.6 - k * 1.4, Paint()..color = SoloArt.a(SoloArt.ink, 0.35 * (1 - k) + 0.1));
    }
    // landing ghost
    paintGlow(canvas, p, g.radius * 2.2, _colours[world.nextColour % _colours.length], 0.3);
    canvas.drawCircle(p, g.radius * 0.92, SoloArt.stroke(SoloArt.a(_colours[world.nextColour % _colours.length], 0.8), 2));
    if (bounced) {
      canvas.drawCircle(p, g.radius * 1.25, SoloArt.stroke(SoloArt.a(accent, 0.25), 1));
    }

    // turret base
    canvas.save();
    canvas.translate(gun.dx, gun.dy);
    // barrel
    canvas.save();
    canvas.rotate(_aimVisual);
    final Rect barrel = Rect.fromCenter(center: Offset(0, -g.cell * 0.42), width: g.cell * 0.40, height: g.cell * 0.9);
    canvas.drawRRect(
      RRect.fromRectAndRadius(barrel, Radius.circular(g.cell * 0.16)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[const Color(0xFFE8EFF8), const Color(0xFF93A5BB), const Color(0xFF46566B)],
        ).createShader(barrel),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(barrel.deflate(g.cell * 0.06), Radius.circular(g.cell * 0.12)),
      SoloArt.stroke(SoloArt.a(const Color(0xFF2B3546), 0.8), 1.2),
    );
    canvas.restore();
    // base plate
    canvas.drawCircle(Offset.zero, g.cell * 0.52, Paint()..color = const Color(0xFF1D2634));
    canvas.drawCircle(
      Offset.zero,
      g.cell * 0.52,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[const Color(0xFF63748B), const Color(0xFF1D2634)],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: g.cell * 0.52)),
    );
    // loaded bubble
    _paintBubble(canvas, Offset.zero, g.cell * 0.44, _colours[world.nextColour % _colours.length]);
    canvas.restore();

    // ---------------------------------------------------------------- readouts
    SoloArt.chip(canvas, Offset(16, play.top + 16), '${world.remaining} LEFT', SoloArt.ink);
    SoloArt.chip(canvas, Offset(size.width - 16, play.top + 16), '${world.popped} POPPED', accent, alignRight: true);
    // next-bubble preview (the colour after the loaded one is unknown, so show the loaded colour)
    if (_hitFlash > 0 && _impact != null) {
      canvas.drawCircle(_impact!, (0.35 - _hitFlash) * 200, SoloArt.stroke(SoloArt.a(accent, _hitFlash * 2), 3));
    }
    if (world.cleared) {
      SoloArt.label(canvas, 'REEF CLEARED', Offset(size.width / 2, play.center.dy), size: 26, color: accent, glow: accent);
    }

    SoloArt.frame(canvas, size, accent);
    paintFx(canvas, size);
  }

  void _paintBubble(Canvas canvas, Offset c, double r, Color colour) {
    paintGlow(canvas, c, r * 1.7, colour, 0.14);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.42),
          radius: 1.05,
          colors: <Color>[SoloArt.lift(colour, 0.34), colour, SoloArt.sink(colour, 0.26)],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    // glass rim + speculars
    canvas.drawCircle(c, r * 0.97, SoloArt.stroke(SoloArt.a(const Color(0xFFFFFFFF), 0.42), math.max(1.0, r * 0.10)));
    canvas.drawCircle(c, r * 0.99, SoloArt.stroke(SoloArt.a(SoloArt.sink(colour, 0.4), 0.6), math.max(1.0, r * 0.06)));
    canvas.drawOval(
      Rect.fromCenter(center: c - Offset(r * 0.3, r * 0.38), width: r * 0.7, height: r * 0.42),
      Paint()..color = SoloArt.a(const Color(0xFFFFFFFF), 0.55),
    );
    canvas.drawCircle(c + Offset(r * 0.36, r * 0.4), r * 0.14, Paint()..color = SoloArt.a(const Color(0xFFFFFFFF), 0.28));
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
              actionIcon: Icons.gps_fixed_rounded,
              actionLabel: 'FIRE',
              onAction: _fire,
            ),
          ),
        ],
      );
}

/// Layout math shared by the painter and the aim guide.
class _BubbleGeometry {
  _BubbleGeometry({required this.left, required this.top, required this.cell, required this.radius, required this.cols});
  final double left;
  final double top;
  final double cell;
  final double radius;
  final int cols;

  static _BubbleGeometry of(Rect play, BubbleWorld world) {
    final double cellW = play.width / (world.cols + 1.1);
    final double cellH = (play.height * 0.52) / 9;
    final double cell = math.min(cellW, cellH);
    return _BubbleGeometry(
      left: play.center.dx - (world.cols * cell) / 2,
      top: play.top + play.height * 0.10,
      cell: cell,
      radius: cell * 0.46,
      cols: world.cols,
    );
  }

  Offset cellCentre(int row, int col) => Offset(
        left + col * cell + (row.isOdd ? cell / 2 : 0) + cell / 2,
        top + row * cell * 0.88 + cell / 2,
      );
}
