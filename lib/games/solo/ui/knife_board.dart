import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../arcade_kit/arcade_skin.dart';
import '../core/solo_rules_b.dart';
import '../solo_kit.dart';

/// =====================================================================================
/// KNIFE HIT — throw blades into a spinning log. Never hit your own knives.
///
/// A wooden log with rings, grain and bevel is lit from the top-left; each thrown knife has a
/// steel gradient, a leather-wrapped handle and a shadow cast on the bark, and every stick
/// pauses the log for a beat (impact freeze + splinters) exactly like the mobile classic.
/// =====================================================================================
class KnifeBoard extends SoloBoard {
  const KnifeBoard({super.key, required super.run});
  @override
  KnifeBoardState createState() => KnifeBoardState();
}

class KnifeBoardState extends SoloBoardState<KnifeBoard> {
  late KnifeWorld world;
  double _fly = 0;
  bool _thrown = false;
  bool _wasHit = false;
  double _hitFor = 0;
  double _freeze = 0;
  double _stageFlash = 0;
  int _shownStage = 0;
  double _spinVisual = 0;

  @override
  void reset() {
    world = KnifeWorld(seed: widget.run.seed);
    _fly = 0;
    _thrown = false;
    _wasHit = false;
    _hitFor = 0;
    _freeze = 0;
    _stageFlash = 0;
    _shownStage = 0;
    _spinVisual = 0;
    widget.run.set(0);
  }

  @override
  void step(double dt) {
    if (_freeze > 0) {
      _freeze -= dt;
    } else {
      _spinVisual += world.spin * dt;
    }
    world.update(dt);
    if (_stageFlash > 0) _stageFlash -= dt;
    if (world.stage != _shownStage) {
      _shownStage = world.stage;
      _stageFlash = 1.1;
      fx.shake(6);
      fx.flashScreen(widget.run.skin.accent, 0.14);
    }
    if (_thrown) {
      _fly += dt * 3.6;
      if (_fly >= 1) {
        _thrown = false;
        _fly = 0;
        final Rect play = playRect(viewport);
        final bool ok = world.throwAt();
        if (ok) {
          _freeze = 0.06;
          final Offset at = _impactPoint(play);
          burst(play, at, const Color(0xFFD9B07A), count: 14, speed: 190);
          fx.shake(5);
          fx.ring(at, widget.run.skin.accent, size: 26);
        } else {
          _freeze = 0.16;
          final Offset at = _impactPoint(play);
          burst(play, at, SoloArt.danger, count: 22, speed: 300);
          fx.shake(20);
          fx.flashScreen(SoloArt.danger, 0.26);
        }
        widget.run.set(world.thrown * 10 + world.stage * 25);
        setState(() {});
      }
    }
    if (!_wasHit && world.hit) {
      _wasHit = true;
      _hitFor = 0;
    }
    if (world.hit) {
      _hitFor += dt;
      if (_hitFor > 0.42) widget.run.gameOver();
    }
  }

  void _throw() {
    if (_thrown || world.hit || !simulating) return;
    _thrown = true;
    _fly = 0;
  }

  Offset _impactPoint(Rect play) {
    final Offset c = _logCentre(play);
    return c + Offset(0, _logRadius(play) * 0.94);
  }

  Offset _logCentre(Rect play) => Offset(play.center.dx, play.top + play.height * 0.42);
  double _logRadius(Rect play) => math.min(play.width * 0.36, play.height * 0.30);

  @override
  void onPointer(Offset at, SoloGesture kind) {
    if (kind == SoloGesture.down) _throw();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final ArcadeSkin skin = widget.run.skin;
    final Color accent = skin.accent;
    final Color accent2 = skin.accent2;
    final Rect play = playRect(size);
    final Offset c = _logCentre(play);
    final double r = _logRadius(play);

    // ---------------------------------------------------------------- dojo + spotlight
    SoloArt.backdrop(canvas, size, skin: skin, time: clock, halo: 0.22,
        haloAt: Offset(size.width / 2, play.top + play.height * 0.4));
    final Rect stage = Rect.fromCenter(center: c, width: r * 3.4, height: r * 2.6);
    canvas.drawOval(
      stage,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[SoloArt.a(accent, 0.18), Colors.transparent],
        ).createShader(stage),
    );
    // hanging beam of light from the top
    final Path beam = Path()
      ..moveTo(size.width / 2 - 26, play.top)
      ..lineTo(size.width / 2 + 26, play.top)
      ..lineTo(size.width / 2 + r * 1.25, c.dy + r)
      ..lineTo(size.width / 2 - r * 1.25, c.dy + r)
      ..close();
    canvas.drawPath(
      beam,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[SoloArt.a(accent2, 0.10), SoloArt.a(accent2, 0.0)],
        ).createShader(Rect.fromLTWH(0, play.top, size.width, r * 2)),
    );

    // ---------------------------------------------------------------- log
    // shadow under the log
    canvas.drawOval(
      Rect.fromCenter(center: c + Offset(6, r * 0.98), width: r * 2.1, height: r * 0.5),
      Paint()
        ..color = const Color(0x77000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );
    paintGlow(canvas, c, r * 1.75, accent, 0.22);
    // lacquered rim so the log reads against a violet sky
    canvas.drawCircle(
      c,
      r * 1.045,
      Paint()
        ..shader = SweepGradient(
          colors: <Color>[
            SoloArt.a(accent, 0.55),
            SoloArt.a(accent2, 0.18),
            SoloArt.a(accent, 0.55),
            SoloArt.a(accent2, 0.18),
            SoloArt.a(accent, 0.55),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: r * 1.045)),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.38, -0.42),
          radius: 1.2,
          colors: <Color>[const Color(0xFFE0A96B), const Color(0xFFA8703C), const Color(0xFF5A3A1B), const Color(0xFF341F0C)],
          stops: const <double>[0, 0.42, 0.82, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    // End-grain: broken growth arcs (not perfect circles) that turn with the log.
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(_spinVisual);
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: r * 0.985)));
    for (int i = 1; i <= 7; i++) {
      final double rr = r * (0.10 + i * 0.115);
      final double start = (i * 1.9) % (math.pi * 2);
      final double sweep = math.pi * (1.15 + 0.45 * math.sin(i * 1.7));
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: rr),
        start,
        sweep,
        false,
        SoloArt.stroke(SoloArt.a(const Color(0xFF4A2C12), 0.30 + 0.05 * (i % 2)), 1.6),
      );
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: rr + 1.6),
        start + 0.4,
        sweep * 0.7,
        false,
        SoloArt.stroke(SoloArt.a(const Color(0xFFF4C98A), 0.16), 1.1),
      );
    }
    // radial drying cracks
    for (int i = 0; i < 9; i++) {
      final double a = i * math.pi * 2 / 9 + 0.3;
      final double r0 = r * (0.32 + 0.1 * (i % 3));
      final double r1 = r * (0.72 + 0.12 * ((i + 1) % 3));
      canvas.drawLine(
        Offset(math.cos(a) * r0, math.sin(a) * r0),
        Offset(math.cos(a) * r1, math.sin(a) * r1),
        SoloArt.stroke(SoloArt.a(const Color(0xFF3A2410), 0.34), 1.8),
      );
    }
    canvas.restore();

    // outer bark wall (bevel), inner shadow ring, lit inner rim
    canvas.drawCircle(c, r * 0.985, SoloArt.stroke(SoloArt.a(const Color(0xFF2A1608), 0.55), 4));
    canvas.drawCircle(c, r * 0.93, SoloArt.stroke(SoloArt.a(const Color(0xFFFFFFFF), 0.20), 2));
    canvas.drawArc(Rect.fromCircle(center: c, radius: r * 0.955), math.pi * 1.05, math.pi * 0.9, false,
        SoloArt.stroke(SoloArt.a(const Color(0xFFFFE0B0), 0.55), 2.4));
    // centre boss: the spin hub
    canvas.drawCircle(c, r * 0.22, Paint()..color = SoloArt.a(const Color(0xFF241206), 0.55));
    canvas.drawCircle(
      c,
      r * 0.16,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.45),
          colors: <Color>[const Color(0xFFF2F7FF), const Color(0xFF93A4BC), const Color(0xFF2C3746)],
          stops: const <double>[0, 0.55, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r * 0.16)),
    );
    canvas.drawCircle(c, r * 0.16, SoloArt.stroke(SoloArt.a(accent2, 0.55), 1.6));
    // hub spokes marking the rotation
    for (int i = 0; i < 6; i++) {
      final double a = _spinVisual + i * math.pi / 3;
      canvas.drawLine(
        Offset(c.dx + math.cos(a) * r * 0.18, c.dy + math.sin(a) * r * 0.18),
        Offset(c.dx + math.cos(a) * r * 0.26, c.dy + math.sin(a) * r * 0.26),
        SoloArt.stroke(SoloArt.a(accent2, 0.35), 1.4),
      );
    }

    // ---------------------------------------------------------------- stuck knives
    for (final double a in world.stuckAngles) {
      final double worldAngle = a + _spinVisual;
      _paintKnife(canvas, c, r + 6, worldAngle, 1);
    }

    // ---------------------------------------------------------------- knife in flight
    final double startY = play.bottom + 30;
    final double endY = c.dy + r * 0.94;
    final double y = soloLerp(startY, endY, _fly);
    canvas.save();
    canvas.translate(c.dx, y);
    // motion smear
    if (_thrown) {
      canvas.drawLine(Offset(0, 90), Offset(0, 26), SoloArt.stroke(SoloArt.a(accent2, 0.28), 6));
      canvas.drawLine(Offset(0, 90), Offset(0, 26), SoloArt.stroke(SoloArt.a(const Color(0xFFFFFFFF), 0.5), 1.6));
    }
    paintGlow(canvas, const Offset(0, 0), 26, accent2, 0.28);
    // blade points up
    canvas.drawPath(_bladePath(0, -30, 9, 40), Paint()..color = const Color(0xFFDCE6F2));
    canvas.drawPath(_bladePath(0, -30, 9, 40), SoloArt.stroke(SoloArt.a(const Color(0xFF8FA6C0), 0.85), 1.2));
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: const Offset(0, 2), width: 7, height: 12), const Radius.circular(3)),
      Paint()..color = const Color(0xFFC08A4A),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: const Offset(0, 30), width: 11, height: 46), const Radius.circular(5)),
      Paint()..color = const Color(0xFF2B2118),
    );
    for (int i = 0; i < 4; i++) {
      canvas.drawLine(Offset(-4.5, 12 + i * 9), Offset(4.5, 9 + i * 9), SoloArt.stroke(const Color(0xFF6B4B32), 1.2));
    }
    canvas.restore();

    // ---------------------------------------------------------------- readouts
    SoloArt.chip(canvas, Offset(16, play.top + 20), 'STAGE ${world.stage + 1}', accent2);
    SoloArt.chip(canvas, Offset(size.width - 16, play.top + 20), '${world.thrown} KNIVES', SoloArt.ink, alignRight: true);
    final Rect meter = Rect.fromLTWH(size.width / 2 - 60, play.top + 46, 120, 6);
    SoloArt.meter(canvas, meter, ((world.spin - 0.9) / 2.2).clamp(0.0, 1.0), accent);
    SoloArt.label(canvas, 'SPIN', meter.bottomLeft + const Offset(0, 10), size: 9, center: false,
        color: SoloArt.a(SoloArt.mute, 0.9), weight: FontWeight.w700);
    if (_stageFlash > 0) {
      final double k = (1.1 - _stageFlash) / 1.1;
      paintCallout(canvas, Offset(size.width / 2, play.top + play.height * 0.68), 'STAGE ${world.stage + 1}',
          accent, scale: 1 + k * 0.3, alpha: (1 - k).clamp(0.0, 1.0));
    }
    if (world.hit) {
      SoloArt.label(canvas, 'MISS', Offset(size.width / 2, play.center.dy), size: 36,
          color: SoloArt.danger, glow: SoloArt.danger);
    }

    SoloArt.frame(canvas, size, accent);
    paintFx(canvas, size);
  }

  Path _bladePath(double cx, double tipY, double w, double length) {
    final double base = tipY + length;
    return Path()
      ..moveTo(cx, tipY)
      ..lineTo(cx + w / 2, tipY + length * 0.55)
      ..lineTo(cx + w / 2.6, base)
      ..lineTo(cx - w / 2.6, base)
      ..lineTo(cx - w / 2, tipY + length * 0.55)
      ..close();
  }

  /// A knife stuck into the log: the blade points at the centre, the handle sticks out.
  void _paintKnife(Canvas canvas, Offset c, double reach, double angle, double scale) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle - math.pi / 2);
    final double tip = reach - 26 * scale;
    // contact shadow on the bark
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(3, tip + 10), width: 9 * scale, height: 34 * scale), const Radius.circular(4)),
      Paint()
        ..color = SoloArt.a(const Color(0xFF000000), 0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    // blade
    final Path blade = Path()
      ..moveTo(0, tip)
      ..lineTo(4.6 * scale, tip + 20 * scale)
      ..lineTo(3 * scale, tip + 30 * scale)
      ..lineTo(-3 * scale, tip + 30 * scale)
      ..lineTo(-4.6 * scale, tip + 20 * scale)
      ..close();
    canvas.drawPath(
      blade,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[const Color(0xFFF2F7FF), const Color(0xFFAFC2D6), const Color(0xFF6E819A)],
        ).createShader(Rect.fromLTWH(-5 * scale, tip, 10 * scale, 30 * scale)),
    );
    canvas.drawPath(blade, SoloArt.stroke(SoloArt.a(const Color(0xFF5A6C82), 0.8), 1));
    // handle
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(0, tip + 52 * scale), width: 10 * scale, height: 46 * scale),
          Radius.circular(4 * scale)),
      Paint()..color = const Color(0xFF2A2018),
    );
    for (int i = 0; i < 4; i++) {
      canvas.drawLine(Offset(-4 * scale, tip + 34 * scale + i * 9 * scale), Offset(4 * scale, tip + 31 * scale + i * 9 * scale),
          SoloArt.stroke(const Color(0xFF6B4B32), 1.1));
    }
    canvas.restore();
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
              actionLabel: 'THROW',
              onAction: _throw,
            ),
          ),
        ],
      );
}
