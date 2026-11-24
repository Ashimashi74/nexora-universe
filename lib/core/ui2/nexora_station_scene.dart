import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/app_settings.dart';

/// Native Flutter rebuild of the NEXORA orbital station scene (Source B visual reference, §6.2 / §4 3D language).
///
/// Draws, with a single [CustomPainter]:
///  * a controlled star field (count from [AppSettings.starCount], twinkle only when effects are on),
///  * a distant planet with a gold rim light,
///  * concentric metallic orbital rings rotating slowly around the station core,
///  * a central station core with a soft gold glow,
///  * an occasional spacecraft drifting along an outer orbit.
///
/// This is decorative depth — the tappable world portals are the world-card ring on top of it, so essential
/// navigation never depends on this art. Respects [AppSettings.reducedMotion] (static render) and
/// [AppSettings.fancyEffects] (animations/particles); a static 2D fallback is what reduced-motion produces.
class NexoraStationScene extends ConsumerStatefulWidget {
  const NexoraStationScene({super.key, this.opacity = 1.0});

  /// Overall opacity of the scene (the Hub layers it over its base gradient).
  final double opacity;

  @override
  ConsumerState<NexoraStationScene> createState() => _NexoraStationSceneState();
}

class _NexoraStationSceneState extends ConsumerState<NexoraStationScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;
  late final List<_Star> _stars;
  late final _Ship _ship;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 90),
    )..repeat();
    _stars = _makeStars();
    _ship = _Ship();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final AppSettings s = ref.read(settingsProvider);
    // Pause the loop when the user asked for reduced motion (static scene instead).
    if (s.reducedMotion || MediaQuery.maybeDisableAnimationsOf(context) == true) {
      _spin.stop();
    } else if (!_spin.isAnimating) {
      _spin.forward();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  List<_Star> _makeStars() {
    final math.Random r = math.Random(20261124);
    final List<_Star> out = <_Star>[];
    // A fixed seed keeps the field identical on every build (no flicker between frames/rebuilds).
    for (int i = 0; i < 240; i++) {
      out.add(_Star(
        x: r.nextDouble(),
        y: r.nextDouble(),
        r: 0.4 + r.nextDouble() * 1.6,
        twinkle: r.nextDouble() * math.pi * 2,
        speed: 0.6 + r.nextDouble() * 1.8,
      ));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings settings = ref.watch(settingsProvider);
    final bool motion = settings.fancyEffects && !settings.reducedMotion;
    final int count = settings.starCount;
    return Opacity(
      opacity: widget.opacity,
      child: AnimatedBuilder(
        animation: _spin,
        builder: (BuildContext context, Widget? child) => CustomPaint(
          painter: _StationPainter(
            phase: motion ? _spin.value * math.pi * 2 : 0.0,
            stars: _stars.take(count).toList(),
            ship: _ship,
            motion: motion,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _Star {
  const _Star({required this.x, required this.y, required this.r, required this.twinkle, required this.speed});
  final double x;
  final double y;
  final double r;
  final double twinkle;
  final double speed;
}

class _Ship {
  _Ship() : angle = math.Random(7).nextDouble() * math.pi * 2;
  double angle;
}

class _StationPainter extends CustomPainter {
  _StationPainter({required this.phase, required this.stars, required this.ship, required this.motion});

  final double phase;
  final List<_Star> stars;
  final _Ship ship;
  final bool motion;

  @override
  bool shouldRepaint(covariant _StationPainter old) =>
      old.phase != phase ||
      old.motion != motion ||
      old.ship.angle != ship.angle ||
      old.stars.length != stars.length;

  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width / 2;
    final double cy = size.height * 0.52;
    final double unit = math.min(size.width, size.height);

    // ---- star field ----
    final Paint starPaint = Paint()
      ..color = const Color(0xB8F4EAD2)
      ..style = PaintingStyle.fill;
    final double t = motion ? phase : 0;
    for (final _Star s in stars) {
      final double tw = motion ? (math.sin(t * s.speed + s.twinkle) * 0.5 + 0.5) : 1.0;
      starPaint.color = const Color(0xB8F4EAD2).withValues(alpha: (0.25 + tw * 0.6).clamp(0.0, 1.0));
      canvas.drawCircle(
        Offset(s.x * size.width, s.y * size.height),
        s.r,
        starPaint,
      );
    }

    // ---- distant planet (upper-left, behind the station) ----
    final double planetR = unit * 0.16;
    final Offset planet = Offset(cx - unit * 0.26, cy - unit * 0.30);
    canvas.drawCircle(
      planet,
      planetR,
      Paint()..shader = RadialGradient(
        center: Alignment.topLeft,
        radius: 0.9,
        colors: <Color>[const Color(0xFF2A2350), const Color(0xFF15102E), const Color(0xFF0B0A2A)],
      ).createShader(Rect.fromCircle(center: planet, radius: planetR)),
    );
    // gold rim light on the planet's right edge
    canvas.drawArc(
      Rect.fromCircle(center: planet, radius: planetR),
      -math.pi / 2.6,
      math.pi / 2.2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = planetR * 0.06
        ..color = const Color(0xFFD9B872).withValues(alpha: 0.5),
    );

    // ---- orbital rings (metallic, concentric, slowly rotating) ----
    final List<double> ringRadii = <double>[unit * 0.30, unit * 0.40, unit * 0.50];
    for (int i = 0; i < ringRadii.length; i++) {
      final double r = ringRadii[i];
      final double tilt = 0.34 - i * 0.05; // ellipse flattening for a 3/4 view
      final double rot = motion ? phase * (i % 2 == 0 ? 1 : -1) * 0.25 : 0;
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(rot);
      final Paint ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, unit * 0.004)
        ..color = i == 1
            ? const Color(0xFFD9B872).withValues(alpha: 0.55)
            : const Color(0x99F6E7BD).withValues(alpha: 0.35);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: r * 2, height: r * 2 * tilt),
        ring,
      );
      // a few bright nodes on the rings (orbital stations / debris)
      final int nodes = 4 + i;
      for (int n = 0; n < nodes; n++) {
        final double a = (n / nodes) * math.pi * 2 + rot;
        final double nx = math.cos(a) * r;
        final double ny = math.sin(a) * r * tilt;
        canvas.drawCircle(
          Offset(nx, ny),
          math.max(1.5, unit * 0.006),
          Paint()..color = const Color(0xFFF6E7BD).withValues(alpha: 0.8),
        );
      }
      canvas.restore();
    }

    // ---- central station core ----
    final double coreR = unit * 0.085;
    // soft gold glow
    canvas.drawCircle(
      Offset(cx, cy),
      coreR * 2.4,
      Paint()..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.0,
        colors: <Color>[const Color(0x33D9B872), const Color(0x00D9B872)],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: coreR * 2.4)),
    );
    // core body: dark disc with a gold inner ring
    canvas.drawCircle(
      Offset(cx, cy),
      coreR,
      Paint()..color = const Color(0xFF12101E),
    );
    canvas.drawCircle(
      Offset(cx, cy),
      coreR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, unit * 0.005)
        ..color = const Color(0xFFD9B872),
    );
    // core detail: a rotating inner ring
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(motion ? phase : 0);
    canvas.drawArc(
      Rect.fromCenter(center: Offset.zero, width: coreR * 1.3, height: coreR * 1.3 * 0.4),
      0,
      math.pi * 1.4,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, unit * 0.004)
        ..color = const Color(0xFFF6E7BD).withValues(alpha: 0.7),
    );
    canvas.restore();

    // ---- spacecraft on the outer orbit ----
    final double orbitR = unit * 0.46;
    final double sa = motion ? ship.angle + phase * 0.35 : ship.angle;
    final double sx = cx + math.cos(sa) * orbitR;
    final double sy = cy + math.sin(sa) * orbitR * 0.34;
    canvas.save();
    canvas.translate(sx, sy);
    canvas.rotate(sa + math.pi / 2);
    // tiny ship: gold hull + glow
    final Path p = Path()
      ..moveTo(0, -unit * 0.022)
      ..lineTo(unit * 0.012, unit * 0.014)
      ..lineTo(0, unit * 0.004)
      ..lineTo(-unit * 0.012, unit * 0.014)
      ..close();
    canvas.drawPath(
      p,
      Paint()
        ..color = const Color(0xFFF6E7BD)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      Offset.zero,
      unit * 0.03,
      Paint()..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.0,
        colors: <Color>[const Color(0x44F6E7BD), const Color(0x00F6E7BD)],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: unit * 0.03)),
    );
    canvas.restore();
  }
}
