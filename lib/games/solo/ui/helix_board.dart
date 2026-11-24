import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../arcade_kit/arcade_skin.dart';
import '../core/solo_rules_b.dart';
import '../solo_kit.dart';

/// =====================================================================================
/// HELIX JUMP — spin the tower, drop through the ring gaps, never touch a red band.
///
/// A vertical colonnade rendered as stacked elliptical platforms with a lit inner edge and a
/// deep shaft behind them; red rings glow in warning colours with hazard chevrons in their gap.
/// The ball has a metallic sheen and a soft bounce glow that pulses with its falling speed.
/// =====================================================================================
class HelixBoard extends SoloBoard {
  const HelixBoard({super.key, required super.run});
  @override
  HelixBoardState createState() => HelixBoardState();
}

class HelixBoardState extends SoloBoardState<HelixBoard> {
  late HelixWorld world;
  double _tilt = 0;
  double _tiltMomentum = 0;
  double _scroll = 0;
  bool _wasDead = false;
  double _deadFor = 0;

  /// Visible rings below the ball.
  static const int _visible = 9;
  static const double _ringGap = 0.10;

  @override
  void reset() {
    world = HelixWorld(seed: widget.run.seed);
    _tilt = 0;
    _tiltMomentum = 0;
    _scroll = 0;
    _wasDead = false;
    _deadFor = 0;
    widget.run.set(0);
  }

  @override
  void step(double dt) {
    world.update(dt, tilt: _tilt + _tiltMomentum);
    _tiltMomentum = soloLerp(_tiltMomentum, 0, soloApproach(0.02, dt));
    _scroll = soloLerp(_scroll, world.depth, soloApproach(0.00001, dt));
    widget.run.set(world.ring * 5);
    if (!_wasDead && (world.dead || world.finished)) {
      _wasDead = true;
      final Rect play = playRect(viewport);
      final Offset at = _ballCentre(play);
      burst(play, at, world.dead ? SoloArt.danger : widget.run.skin.accent, count: 26, speed: 320);
      fx.shake(world.dead ? 18 : 8);
      if (!world.dead) fx.flashScreen(widget.run.skin.accent, 0.2);
    }
    if (world.dead || world.finished) {
      _deadFor += dt;
      if (_deadFor > 0.45) widget.run.gameOver();
    }
  }

  void _press() {
    if (!simulating) return;
    world.jump();
    final Rect play = playRect(viewport);
    final Offset at = _ballCentre(play);
    burst(play, at + const Offset(0, 12), widget.run.skin.accent2, count: 8, speed: 140);
  }

  Offset _ballCentre(Rect play) => Offset(play.center.dx, play.top + play.height * 0.30);

  @override
  void onPointer(Offset at, SoloGesture kind) {
    switch (kind) {
      case SoloGesture.down:
        _press();
      case SoloGesture.drag:
      case SoloGesture.dragStart:
        _tilt = ((at.dx - viewport.width / 2) / (viewport.width / 2)).clamp(-1.0, 1.0) * 1.6;
      case SoloGesture.dragEnd:
        _tilt = 0;
      default:
        break;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final ArcadeSkin skin = widget.run.skin;
    final Color accent = skin.accent;
    final Color accent2 = skin.accent2;
    final Rect play = playRect(size);
    final Offset ball = _ballCentre(play);
    final double ringDepth = play.height * _ringGap;

    // ---------------------------------------------------------------- shaft backdrop
    SoloArt.backdrop(canvas, size, skin: skin, time: clock, halo: 0.18, haloAt: ball);
    // deep shaft: vertical gradient column behind the tower
    final Rect shaft = Rect.fromLTRB(0, play.top, size.width, play.bottom + 20);
    canvas.drawRect(
      shaft,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[SoloArt.a(const Color(0xFF04060E), 0.0), SoloArt.a(const Color(0xFF04060E), 0.85)],
        ).createShader(shaft),
    );
    // distance markers scrolling down the walls
    for (int i = 0; i < 22; i++) {
      final double y = play.top + ((i * 46 + _scroll * ringDepth * 3) % (play.height + 60)) - 30;
      canvas.drawLine(Offset(8, y), Offset(26, y), SoloArt.stroke(SoloArt.a(accent2, 0.10), 2));
      canvas.drawLine(Offset(size.width - 26, y), Offset(size.width - 8, y), SoloArt.stroke(SoloArt.a(accent2, 0.10), 2));
    }

    // ---------------------------------------------------------------- rings (far → near)
    final int base = world.ring;
    for (int i = _visible; i >= 0; i--) {
      final int index = base + i;
      if (index < 0 || index >= world.ringCount) continue;
      final double k = i / _visible;
      final double scale = 1 - k * 0.42;
      final double y = ball.dy + i * ringDepth * (0.72 + k * 0.18);
      if (y > play.bottom + ringDepth) continue;
      final bool red = world.rings[index] == HelixRing.red;
      final double rx = play.width * 0.46 * scale;
      final double ry = rx * 0.30;
      final double gapCentre = (index * 1.7) % (math.pi * 2) + world.spin;

      // platform shadow on the ring below
      canvas.drawOval(
        Rect.fromCenter(center: Offset(play.center.dx, y + ry * 0.72), width: rx * 1.9, height: ry * 1.5),
        Paint()
          ..color = SoloArt.a(const Color(0xFF000000), 0.35)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8 * scale),
      );
      // platform body
      final Rect ringRect = Rect.fromCenter(center: Offset(play.center.dx, y), width: rx * 2, height: ry * 2);
      canvas.drawOval(
        ringRect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: red
                ? <Color>[const Color(0xFF4A2027), const Color(0xFF220D12)]
                : <Color>[SoloArt.mix(accent, const Color(0xFF101624), 0.72), const Color(0xFF0A0E18)],
          ).createShader(ringRect),
      );
      // the gap: an opening carved out of the ring, aligned to the gap angle
      final double gapHalf = 0.42;
      final double start = gapCentre - gapHalf;
      canvas.drawArc(
        ringRect,
        start + gapHalf * 2,
        math.pi * 2 - gapHalf * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(6.0, ry * 0.5)
          ..color = red ? const Color(0xFF3A1016) : SoloArt.a(const Color(0xFF060A14), 0.94),
      );
      // lit inner edge
      canvas.drawArc(
        ringRect.deflate(ry * 0.22),
        start + gapHalf * 2,
        math.pi * 2 - gapHalf * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.4, ry * 0.10)
          ..color = red ? SoloArt.a(SoloArt.danger, 0.95) : SoloArt.a(accent2, 0.55 - k * 0.3),
      );
      // outer rim
      canvas.drawOval(ringRect, SoloArt.stroke(red ? SoloArt.a(SoloArt.danger, 0.7) : SoloArt.a(accent, 0.4), math.max(1.2, 2.2 * scale)));
      if (red) {
        paintGlow(canvas, Offset(play.center.dx, y), rx * 0.8, SoloArt.danger, 0.22 * (1 - k));
        // hazard chevrons on the red band
        for (int c = 0; c < 8; c++) {
          final double a = c / 8 * math.pi * 2;
          if (((a - gapCentre + math.pi * 3) % (math.pi * 2)) < gapHalf * 2) continue;
          final Offset p = Offset(play.center.dx + math.cos(a) * rx * 0.86, y + math.sin(a) * ry * 0.86);
          SoloArt.diamond(canvas, p, math.max(2.0, 4 * scale), SoloArt.a(SoloArt.danger, 0.65), rotation: a);
        }
      } else {
        // subtle top light on safe platforms
        canvas.drawArc(ringRect.deflate(1), math.pi * 1.08, math.pi * 0.84, false,
            SoloArt.stroke(SoloArt.a(const Color(0xFFFFFFFF), 0.16 * (1 - k)), math.max(1.0, ry * 0.14)));
      }
    }

    // ---------------------------------------------------------------- ball
    final double radius = play.width * 0.072;
    // trail based on falling speed
    final double speed = world.fallSpeed.clamp(0.0, 8.0) / 8.0;
    for (int i = 1; i <= 4; i++) {
      canvas.drawOval(
        Rect.fromCenter(center: ball - Offset(0, i * radius * 0.55), width: radius * 1.7 * (1 - i * 0.14), height: radius * 2.1 * (1 - i * 0.14)),
        Paint()
          ..color = SoloArt.a(accent, 0.16 * (1 - i / 5))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
    canvas.drawOval(
      Rect.fromCenter(center: ball + Offset(0, ringDepth * 0.9), width: radius * 2.2, height: radius * 0.7),
      Paint()
        ..color = SoloArt.a(const Color(0xFF000000), 0.4 + speed * 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    paintGlow(canvas, ball, radius * (2.6 + speed), accent, 0.3);
    SoloArt.orb(canvas, ball, radius, accent2, rim: accent, ring: 0.6);
    // stripe / highlight detail
    canvas.drawArc(
      Rect.fromCircle(center: ball, radius: radius * 0.9),
      -2.4 + clock * 1.5,
      1.5,
      false,
      SoloArt.stroke(SoloArt.a(accent, 0.75), math.max(1.4, radius * 0.12)),
    );

    // ---------------------------------------------------------------- readouts
    SoloArt.chip(canvas, Offset(16, play.top + 18), 'DEPTH ${world.ring}', accent2);
    SoloArt.chip(canvas, Offset(size.width - 16, play.top + 18), '${(100 - (world.ring / world.ringCount) * 100).round()}%', SoloArt.ink, alignRight: true);
    final Rect meter = Rect.fromLTWH(16, play.top + 46, size.width - 32, 5);
    SoloArt.meter(canvas, meter, world.depth / world.ringCount, accent);
    if (world.finished) {
      SoloArt.label(canvas, 'TOWER CLEARED', Offset(size.width / 2, play.center.dy), size: 26, color: accent2, glow: accent);
    } else if (world.dead) {
      SoloArt.label(canvas, 'CRUSHED', Offset(size.width / 2, play.center.dy), size: 32, color: SoloArt.danger, glow: SoloArt.danger);
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
              actionIcon: Icons.bolt_rounded,
              actionLabel: 'JUMP',
              onAction: _press,
            ),
          ),
        ],
      );
}
