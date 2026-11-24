/// ===================== SOLO ARCADE ART LAYER =====================
/// One premium drawing kit shared by the ten solo arcade boards.
///
/// The old boards drew flat rectangles on a near-black rectangle: no depth, no light, no
/// feedback. This layer gives them a common language instead:
///  * [SoloArt.backdrop] — layered night sky (gradient + aurora ribbons + starfield + vignette),
///  * environment builders (synthwave sun, horizon grid, ridges, skyline, caustics, road),
///  * material helpers ([SoloArt.cube], [SoloArt.orb], [SoloArt.panel], [SoloArt.spike],
///    [SoloArt.diamond], [SoloArt.blade]) built on the arcade kit's shaded primitives,
///  * HUD furniture ([SoloArt.meter], [SoloArt.chip], [SoloArt.label]).
///
/// Everything is resolution independent: sizes are derived from the play rect, never from
/// fixed pixel values, and every effect respects reduced motion through the board's `fx`.
/// =================================================================
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../arcade_kit/arcade_fx.dart';
import '../../arcade_kit/arcade_skin.dart';

/// Fixed vertical bands of a solo board: the shell owns the score HUD at the top, the board
/// owns the control deck at the bottom, gameplay lives in between.
class SoloMetrics {
  SoloMetrics._();

  /// Top band reserved for the shell's score / best / daily chips.
  static const double hudTop = 88;

  /// Height of the bottom control deck.
  static const double deck = 98;
}

/// Drawing kit: every method is safe to call with zero/degenerate rects.
class SoloArt {
  SoloArt._();

  static const Color ink = Color(0xFFF4F8FF);
  static const Color mute = Color(0xFF9FB2CE);
  static const Color gold = Color(0xFFFFD166);
  static const Color danger = Color(0xFFFF5B62);
  static const Color haze = Color(0xFF0A0F1E);

  /// Convenience tints for hazard bands that are not the board accent.
  static const Color hazard = danger;

  // ------------------------------------------------------------------ colour
  static Color a(Color c, double alpha) => c.withValues(alpha: alpha.clamp(0.0, 1.0));

  static Color lift(Color c, [double amount = 0.18]) {
    final HSLColor h = HSLColor.fromColor(c);
    return h.withLightness((h.lightness + amount).clamp(0.0, 1.0)).toColor();
  }

  static Color sink(Color c, [double amount = 0.18]) {
    final HSLColor h = HSLColor.fromColor(c);
    return h.withLightness((h.lightness - amount).clamp(0.0, 1.0)).toColor();
  }

  static Color mix(Color x, Color y, double t) => Color.lerp(x, y, t.clamp(0.0, 1.0))!;

  static Paint fill(Color c) => Paint()..color = c;

  static Paint stroke(Color c, double w) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = c;

  // ------------------------------------------------------------------ text
  /// Glowing label centred on [at] (or left aligned when [center] is false).
  static void label(
    Canvas canvas,
    String text,
    Offset at, {
    double size = 14,
    Color color = ink,
    Color? glow,
    FontWeight weight = FontWeight.w900,
    bool center = true,
  }) {
    if (text.isEmpty) return;
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'ChakraPetch',
          fontSize: size,
          fontWeight: weight,
          color: color,
          height: 1.05,
          letterSpacing: 0.6,
          shadows: <Shadow>[
            const Shadow(color: Color(0xCC000000), offset: Offset(0, 1.5), blurRadius: 3),
            if (glow != null) Shadow(color: a(glow, 0.85), blurRadius: size * 0.65),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: center ? TextAlign.center : TextAlign.left,
    )..layout();
    tp.paint(canvas, center ? at - Offset(tp.width / 2, tp.height / 2) : at - Offset(0, tp.height / 2));
  }

  /// Big score readout with a soft neon aura (used inside the playfield, the shell owns the top HUD).
  static void score(
    Canvas canvas,
    String text,
    Offset at, {
    required Color accent,
    double size = 30,
  }) {
    paintGlow(canvas, at + Offset(0, size * 0.15), size * 1.5, accent, 0.24);
    label(canvas, text, at, size: size, color: ink, glow: accent);
  }

  // ------------------------------------------------------------------ stage
  /// Full-board backdrop: vertical night gradient, accent halo top, aurora ribbons, stars, vignette.
  static void backdrop(
    Canvas canvas,
    Size size, {
    required ArcadeSkin skin,
    required double time,
    bool aurora = true,
    bool stars = true,
    double halo = 0.24,
    Offset? haloAt,
  }) {
    final Rect r = Offset.zero & size;
    canvas.drawRect(
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[skin.bgTop, mix(skin.bgTop, skin.bgBottom, 0.6), skin.bgBottom],
          stops: const <double>[0, 0.55, 1],
        ).createShader(r),
    );
    final Offset h = haloAt ?? Offset(size.width * 0.5, size.height * 0.18);
    canvas.drawCircle(
      h,
      size.longestSide * 0.75,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[a(skin.glow, halo), Colors.transparent],
        ).createShader(Rect.fromCircle(center: h, radius: size.longestSide * 0.75)),
    );
    if (stars) starfield(canvas, size, time, tint: lift(skin.accent, 0.35));
    if (aurora) ribbons(canvas, size, time, skin.accent, skin.accent2);
    paintVignette(canvas, size, 0.5);
  }

  /// Soft drifting aurora bands across the top half.
  static void ribbons(Canvas canvas, Size size, double time, Color one, Color two) {
    for (int band = 0; band < 3; band++) {
      final double baseY = size.height * (0.06 + band * 0.055);
      final Path p = Path()..moveTo(-4, baseY);
      for (double x = -4; x <= size.width + 4; x += 14) {
        final double y = baseY +
            math.sin(x / (78 + band * 26) + time * (0.45 + band * 0.16)) * (16 + band * 10) +
            math.sin(x / 34 - time * 0.6) * 4;
        p.lineTo(x, y);
      }
      p
        ..lineTo(size.width + 4, -10)
        ..lineTo(-4, -10)
        ..close();
      canvas.drawPath(
        p,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[a(band.isEven ? one : two, 0.16), Colors.transparent],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height * 0.42))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
      );
    }
  }

  /// Twinkling drifting stars (deterministic per board, so a replay looks identical).
  static void starfield(Canvas canvas, Size size, double time, {int count = 54, Color tint = const Color(0xFFBFE0FF), int seed = 11}) {
    final math.Random r = math.Random(seed);
    final Paint p = Paint();
    for (int i = 0; i < count; i++) {
      final double x = r.nextDouble() * size.width;
      final double y0 = r.nextDouble() * size.height;
      final double speed = 5 + r.nextDouble() * 16;
      final double y = (y0 + time * speed) % size.height;
      final double tw = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(time * (0.8 + r.nextDouble()) + i));
      final double rad = 0.6 + r.nextDouble() * 1.5;
      p.color = a(tint, 0.08 + 0.5 * tw);
      canvas.drawCircle(Offset(x, y), rad, p);
      if (rad > 1.8) {
        p.color = a(tint, 0.06 + 0.22 * tw);
        canvas.drawCircle(Offset(x, y), rad * 2.6, p);
      }
    }
  }

  /// Synthwave sun: gradient disc with clipped horizontal scan gaps and a bloom.
  static void sunset(Canvas canvas, Offset centre, double radius, Color top, Color bottom, {Color? glow}) {
    if (radius <= 0) return;
    paintGlow(canvas, centre, radius * 2.3, glow ?? top, 0.3);
    final Rect disc = Rect.fromCircle(center: centre, radius: radius);
    canvas.save();
    canvas.clipPath(Path()..addOval(disc));
    canvas.drawRect(
      disc,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[top, bottom],
        ).createShader(disc),
    );
    final Paint gap = Paint()..color = const Color(0xE6050712);
    for (double y = centre.dy + radius * 0.06; y < centre.dy + radius; y += radius * 0.17) {
      final double t = (y - (centre.dy + radius * 0.06)) / (radius * 0.94);
      canvas.drawRect(Rect.fromLTWH(centre.dx - radius, y, radius * 2, radius * (0.03 + 0.09 * t)), gap);
    }
    canvas.restore();
    canvas.drawCircle(centre, radius, stroke(a(const Color(0xFFFFFFFF), 0.16), 1.2));
  }

  /// Perspective floor grid vanishing at [horizon].
  static void floorGrid(
    Canvas canvas,
    Size size,
    double horizon,
    Color color, {
    double scroll = 0,
    int rows = 18,
    int cols = 22,
    double alpha = 0.2,
    double vanishingX = 0.5,
    double topWidth = 1.6,
  }) {
    if (size.height <= horizon) return;
    final Offset vp = Offset(size.width * vanishingX, horizon);
    final Paint p = stroke(a(color, alpha), 1.1);
    for (int i = 0; i <= cols; i++) {
      final double bx = -size.width * (topWidth - 1) * 0.5 + (i / cols) * size.width * topWidth;
      canvas.drawLine(vp, Offset(bx, size.height), p);
    }
    final double frac = scroll - scroll.floorToDouble();
    for (int j = 0; j < rows; j++) {
      final double k = (j + frac) / rows;
      final double y = horizon + (size.height - horizon) * k * k;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), stroke(a(color, alpha * (0.25 + k)), 1 + k * 0.8));
    }
  }

  /// Rolling mountain / debris ridge silhouette.
  static void ridge(
    Canvas canvas,
    Size size,
    double baseY,
    Color color, {
    double amplitude = 54,
    double seed = 2,
    double speed = 0,
    double time = 0,
    double from = 0,
    double to = 1,
  }) {
    final Path p = Path()..moveTo(size.width * from, size.height + 2);
    p.lineTo(size.width * from, baseY);
    for (double x = size.width * from; x <= size.width * to; x += 9) {
      final double s = x / 60 + seed + time * speed;
      final double y = baseY -
          (math.sin(s) * 0.5 + math.sin(s * 2.3 + 1.7) * 0.26 + math.sin(s * 0.43 + 0.4) * 0.24) * amplitude -
          amplitude * 0.35;
      p.lineTo(x, y);
    }
    p
      ..lineTo(size.width * to, size.height + 2)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  /// Night city skyline with lit windows.
  static void skyline(
    Canvas canvas,
    Size size,
    double baseY,
    Color color, {
    int seed = 4,
    double windowAlpha = 0.55,
    int count = 16,
  }) {
    final math.Random r = math.Random(seed);
    double x = -20;
    int i = 0;
    while (x < size.width + 20 && i < count) {
      final double w = 26 + r.nextDouble() * 40;
      final double h = 40 + r.nextDouble() * size.height * 0.22;
      final Rect b = Rect.fromLTWH(x, baseY - h, w, h);
      canvas.drawRect(b, Paint()..color = color);
      canvas.drawRect(Rect.fromLTWH(b.left, b.top, w, 1.6), Paint()..color = a(const Color(0xFFFFFFFF), 0.10));
      final Paint win = Paint()..color = a(const Color(0xFFFFE6A8), windowAlpha * (0.4 + r.nextDouble() * 0.6));
      for (double wy = b.top + 7; wy < b.bottom - 6; wy += 11) {
        for (double wx = b.left + 5; wx < b.right - 5; wx += 9) {
          if (r.nextDouble() < 0.45) canvas.drawRect(Rect.fromLTWH(wx, wy, 3.4, 5), win);
        }
      }
      x += w + 6 + r.nextDouble() * 12;
      i++;
    }
  }

  /// Underwater caustics for the bubble reef.
  static void caustics(Canvas canvas, Size size, double time, Color color) {
    final Paint p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = a(color, 0.10);
    for (int i = 0; i < 7; i++) {
      final Path path = Path();
      final double y0 = size.height * (0.1 + i * 0.13);
      for (double x = -10; x <= size.width + 10; x += 12) {
        final double y = y0 + math.sin(x / 48 + time * (0.5 + i * 0.08) + i) * 12 + math.sin(x / 19 - time * 0.7) * 4;
        if (x <= -9) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, p);
    }
  }

  /// Seamless neon road/highway band between [left] and [right] with scrolling dashes.
  static void road(
    Canvas canvas,
    Size size,
    Rect band,
    Color edge,
    double scroll, {
    int lanes = 3,
    double dashLength = 46,
    Color? asphalt,
  }) {
    final Rect r = band;
    canvas.drawRect(
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[
            a(asphalt ?? const Color(0xFF10131C), 1),
            a(lift(asphalt ?? const Color(0xFF10131C), 0.05), 1),
            a(asphalt ?? const Color(0xFF10131C), 1),
          ],
          stops: const <double>[0, 0.5, 1],
        ).createShader(r),
    );
    // Asphalt grain: a few faint horizontal streaks that scroll.
    final Paint grain = Paint()..color = a(const Color(0xFFFFFFFF), 0.025);
    for (double y = (scroll * 40) % 26 - 26; y < r.height; y += 26) {
      canvas.drawRect(Rect.fromLTWH(r.left, r.top + y, r.width, 1.4), grain);
    }
    // Neon edges.
    for (final double x in <double>[r.left, r.right]) {
      canvas.drawLine(Offset(x, r.top), Offset(x, r.bottom), stroke(a(edge, 0.16), 7));
      canvas.drawLine(Offset(x, r.top), Offset(x, r.bottom), stroke(a(edge, 0.95), 2.2));
    }
    // Lane dashes.
    final double laneW = r.width / lanes;
    final Paint dash = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[a(const Color(0xFFFFFFFF), 0.16), a(const Color(0xFFFFFFFF), 0.5)],
      ).createShader(r);
    for (int l = 1; l < lanes; l++) {
      final double x = r.left + laneW * l;
      for (double y = r.top - dashLength + (scroll % dashLength); y < r.bottom; y += dashLength * 2.1) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x - 2.2, y, 4.4, dashLength), const Radius.circular(3)),
          dash,
        );
      }
    }
  }

  /// Speed streaks: thin light lines rushing toward the viewer.
  static void speedLines(Canvas canvas, Size size, double time, Color color, {int count = 20, double amount = 1, double fromTop = 0}) {
    if (amount <= 0) return;
    final math.Random r = math.Random(21);
    for (int i = 0; i < count; i++) {
      final double x = r.nextDouble() * size.width;
      final double len = 40 + r.nextDouble() * 150;
      final double span = size.height - fromTop;
      final double y = fromTop + ((r.nextDouble() * span + time * (260 + r.nextDouble() * 420)) % span);
      canvas.drawLine(
        Offset(x, y),
        Offset(x, y + len * amount),
        stroke(a(color, (0.05 + r.nextDouble() * 0.14) * amount), 1 + r.nextDouble() * 1.6),
      );
    }
  }

  // ------------------------------------------------------------------ materials
  /// Glass panel with a bevelled gradient border, drop shadow and optional bloom.
  static void panel(
    Canvas canvas,
    Rect r,
    Color accent, {
    double radius = 18,
    double border = 1.2,
    double glow = 0.3,
    Color? top,
    Color? bottom,
    bool shadow = true,
  }) {
    if (r.width <= 0 || r.height <= 0) return;
    final RRect rr = RRect.fromRectAndRadius(r, Radius.circular(radius));
    if (shadow) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(r.deflate(1).shift(const Offset(0, 5)), Radius.circular(radius)),
        Paint()
          ..color = const Color(0x77000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }
    if (glow > 0) {
      canvas.drawRRect(rr, Paint()..color = a(accent, 0.10 * glow)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
    }
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[top ?? const Color(0xEE1B2740), bottom ?? const Color(0xEE080D19)],
        ).createShader(r),
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = border
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[a(accent, 0.85), a(accent, 0.22), a(accent, 0.5)],
        ).createShader(r),
    );
    // Top light sheet: makes the panel read as glass rather than a flat box.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(r.left + radius * 0.5, r.top + 1.6, r.width - radius, math.min(r.height * 0.34, 26)),
        Radius.circular(radius * 0.6),
      ),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[a(const Color(0xFFFFFFFF), 0.16), a(const Color(0xFFFFFFFF), 0.0)],
        ).createShader(Rect.fromLTWH(r.left, r.top, r.width, math.min(r.height, 30))),
    );
  }

  /// Bevelled 3D cube (blocks, cars, crates, the geo-dash runner).
  static void cube(Canvas canvas, Rect r, Color base, {double depth = 5, double radius = 4, double glow = 0, bool shadow = true, Color? edge}) {
    if (r.width <= 1 || r.height <= 1) return;
    paintBlock(canvas, r, base, radius: radius, depth: depth, shadow: shadow, glow: glow);
    final double inset = math.min(r.width, r.height) * 0.09;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(r.left + inset, r.top + inset, r.width - inset * 2, r.height * 0.34),
        Radius.circular(radius * 0.7),
      ),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[a(const Color(0xFFFFFFFF), 0.30), a(const Color(0xFFFFFFFF), 0.0)],
        ).createShader(r),
    );
    if (edge != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(r.deflate(0.8), Radius.circular(radius)),
        stroke(a(edge, 0.75), 1.2),
      );
    }
  }

  /// Glossy sphere with rim light and optional orbit ring (fruit, bubbles, the helix ball).
  static void orb(Canvas canvas, Offset c, double radius, Color base, {bool shadow = true, double gloss = 1, Color? rim, double ring = 0}) {
    if (radius <= 0.5) return;
    paintSphere(canvas, c, radius, base, shadow: shadow, gloss: gloss, rim: rim);
    if (ring > 0) {
      canvas.drawCircle(c, radius * (1 + ring * 0.12), stroke(a(rim ?? lift(base, 0.3), 0.35), math.max(0.8, radius * 0.06)));
    }
  }

  /// Danger spike (ground hazard).
  static void spike(Canvas canvas, Offset base, double width, double height, Color color) {
    if (width <= 0.5 || height <= 0.5) return;
    final Path p = Path()
      ..moveTo(base.dx - width / 2, base.dy)
      ..lineTo(base.dx - width * 0.12, base.dy - height * 0.72)
      ..lineTo(base.dx, base.dy - height)
      ..lineTo(base.dx + width * 0.12, base.dy - height * 0.72)
      ..lineTo(base.dx + width / 2, base.dy)
      ..close();
    paintGlow(canvas, Offset(base.dx, base.dy - height * 0.35), width * 0.9, color, 0.3);
    canvas.drawPath(
      p,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[lift(color, 0.34), color, sink(color, 0.22)],
        ).createShader(Rect.fromLTWH(base.dx - width / 2, base.dy - height, width, height)),
    );
    canvas.drawPath(p, stroke(a(const Color(0xFFFFFFFF), 0.42), 1.1));
  }

  /// Rotating hazard diamond (flying block).
  static void diamond(Canvas canvas, Offset at, double radius, Color color, {double rotation = 0, Color? inner, double glow = 0.35}) {
    if (radius <= 0.5) return;
    paintGlow(canvas, at, radius * 1.7, color, glow);
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(rotation);
    final Path p = Path()
      ..moveTo(0, -radius)
      ..lineTo(radius, 0)
      ..lineTo(0, radius)
      ..lineTo(-radius, 0)
      ..close();
    canvas.drawPath(
      p,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[lift(color, 0.3), color, sink(color, 0.26)],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius)),
    );
    canvas.drawPath(p, stroke(a(const Color(0xFFFFFFFF), 0.4), 1.2));
    if (inner != null) canvas.drawCircle(Offset.zero, radius * 0.24, Paint()..color = inner);
    canvas.restore();
  }

  /// Hazard barrier: striped plate with a lit cap (runner / racer obstacles).
  static void barrier(Canvas canvas, Rect r, Color color, {bool lit = true}) {
    if (r.width <= 1 || r.height <= 1) return;
    paintShadow(canvas, Offset(r.center.dx, r.bottom + 2), r.width * 1.15, r.height * 0.2, 0.45);
    cube(canvas, r, color, radius: math.min(6.0, r.width * 0.16), depth: math.max(2.0, r.width * 0.08), glow: 0.2);
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(r, Radius.circular(math.min(6.0, r.width * 0.16))));
    final Paint stripe = Paint()..color = a(const Color(0xFF0B0E16), 0.30);
    for (double y = r.bottom + r.width; y > r.top - r.width; y -= r.width * 0.55) {
      canvas.save();
      canvas.translate(0, y);
      canvas.rotate(-0.5);
      canvas.drawRect(Rect.fromLTWH(r.left - 10, -r.width * 0.13, r.width + 20, r.width * 0.26), stripe);
      canvas.restore();
    }
    canvas.restore();
    if (lit) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(r.left, r.top, r.width, math.max(2.4, r.height * 0.09)), const Radius.circular(2)),
        Paint()..color = a(const Color(0xFFFFFFFF), 0.55),
      );
    }
  }

  /// Tapered glowing blade trail (fruit slicing, knife flight).
  static void blade(Canvas canvas, List<Offset> points, Color inner, Color outer, double width) {
    if (points.length < 2) return;
    for (int i = 1; i < points.length; i++) {
      final double t = i / (points.length - 1);
      final Offset p0 = points[i - 1];
      final Offset p1 = points[i];
      canvas.drawLine(p0, p1, stroke(a(outer, 0.20 * t * t), width * 1.9 * t));
      canvas.drawLine(p0, p1, stroke(a(inner, 0.65 * t), width * t));
      canvas.drawLine(p0, p1, stroke(a(const Color(0xFFFFFFFF), 0.8 * t), math.max(0.8, width * 0.28 * t)));
    }
  }

  /// Filled progress meter (level, speed, daily target).
  static void meter(Canvas canvas, Rect r, double value, Color color, {Color? track}) {
    if (r.width <= 2 || r.height <= 1) return;
    final RRect rr = RRect.fromRectAndRadius(r, Radius.circular(r.height / 2));
    canvas.drawRRect(rr, Paint()..color = track ?? const Color(0x66000000));
    final double v = value.clamp(0.0, 1.0);
    if (v <= 0) return;
    final Rect part = Rect.fromLTWH(r.left, r.top, math.max(r.height, r.width * v), r.height);
    canvas.save();
    canvas.clipRRect(rr);
    canvas.drawRect(
      part,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[a(color, 0.55), color],
        ).createShader(part),
    );
    canvas.drawRect(part, Paint()..color = a(const Color(0xFFFFFFFF), 0.18));
    canvas.restore();
    canvas.drawRRect(rr, stroke(a(color, 0.5), 1));
  }

  /// Small HUD pill with a dot marker (canvas-side, e.g. level / combo badges).
  static void chip(Canvas canvas, Offset at, String text, Color color, {bool alignRight = false, double size = 12, double padH = 10, double height = 24}) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'ChakraPetch',
          fontSize: size,
          fontWeight: FontWeight.w900,
          color: color,
          letterSpacing: 0.8,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final double w = tp.width + padH * 2 + 10;
    final Rect r = Rect.fromLTWH(alignRight ? at.dx - w : at.dx, at.dy - height / 2, w, height);
    final RRect rr = RRect.fromRectAndRadius(r, Radius.circular(height / 2));
    canvas.drawRRect(rr, Paint()..color = a(const Color(0xFF050A14), 0.62));
    canvas.drawRRect(rr, stroke(a(color, 0.55), 1));
    canvas.drawCircle(Offset(r.left + padH * 0.8, r.center.dy), 2.6, Paint()..color = a(color, 0.95));
    tp.paint(canvas, Offset(r.left + padH + 6, r.center.dy - tp.height / 2));
  }

  /// Inset frame with short illuminated corner ticks. Drawn last by every board so the ten
  /// games share one bezel; it never competes with gameplay.
  static void frame(Canvas canvas, Size size, Color accent) {
    if (size.width < 60 || size.height < 60) return;
    const double m = 8;
    const double len = 18;
    final Rect r = Rect.fromLTWH(m, m, size.width - 2 * m, size.height - 2 * m);
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(20)),
      stroke(a(const Color(0xFFB8D4FF), 0.10), 0.8),
    );
    final Paint p = stroke(a(accent, 0.75), 1.6);
    for (final Offset c in <Offset>[r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
      final double sx = c.dx == r.left ? 1 : -1;
      final double sy = c.dy == r.top ? 1 : -1;
      canvas.drawLine(c, c + Offset(len * sx, 0), p);
      canvas.drawLine(c, c + Offset(0, len * sy), p);
      canvas.drawCircle(c + Offset(len * sx * 0.44, len * sy * 0.44), 2, fill(accent));
    }
  }

  /// Soft scrim so controls and the deck never fight a busy playfield.
  static void bottomScrim(Canvas canvas, Size size, {double height = 250}) {
    final Rect r = Rect.fromLTWH(0, size.height - height, size.width, height);
    canvas.drawRect(
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Colors.transparent, a(const Color(0xFF02040A), 0.9)],
        ).createShader(r),
    );
  }

  /// Overshooting ease used for spawn / pop animations.
  static double easeOutBack(double t) {
    const double c = 1.70158;
    final double u = t.clamp(0.0, 1.0) - 1;
    return 1 + (c + 1) * u * u * u + c * u * u;
  }

  /// Deterministic pseudo-random in [0,1) from an integer (used for stable decoration).
  static double hash01(int n) {
    final int x = (n * 1103515245 + 12345) & 0x7FFFFFFF;
    return (x % 10000) / 10000.0;
  }
}
