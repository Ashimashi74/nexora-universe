import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../arcade_kit/arcade_skin.dart';
import '../core/solo_rules_b.dart';
import '../solo_kit.dart';

/// =====================================================================================
/// FRUIT NINJA — carve the flying fruit, never the bombs.
///
/// Each fruit is a shaded sphere with a highlight, a leaf and a rind arc; slicing it emits
/// two juice-coloured halves that spin away with a splash of droplets, plus a short-lived
/// blade trail that follows the finger. Bombs are lit fuses with a pulsing danger ring.
/// =====================================================================================
class FruitBoard extends SoloBoard {
  const FruitBoard({super.key, required super.run});
  @override
  FruitBoardState createState() => FruitBoardState();
}

/// One half of a sliced fruit (purely visual, decays on its own).
class _Half {
  _Half(this.at, this.velocity, this.radius, this.color, this.spin, this.cut, this.skin);
  Offset at;
  Offset velocity;
  final double radius;
  final Color color;
  final Color skin;
  final double spin;

  /// Direction of the blade at the moment of the cut (halves split across it).
  final double cut;

  double angle = 0;
  double life = 0.9;
}

/// Small juice droplet.
class _Drop {
  _Drop(this.at, this.velocity, this.color, this.radius);
  Offset at;
  Offset velocity;
  final Color color;
  final double radius;
  double life = 0.55;
}

/// A fruit remembered as "already cut" so the board only bursts once per fruit.
class FruitBoardState extends SoloBoardState<FruitBoard> {
  late FruitWorld world;
  final List<Offset> _trail = <Offset>[];
  final List<_Half> _halves = <_Half>[];
  final List<_Drop> _drops = <_Drop>[];
  final Set<int> _cut = <int>{};
  Offset? _lastPoint;
  double _comboFlash = 0;
  int _lastCombo = 0;
  bool _wasExploded = false;
  double _explodedFor = 0;

  /// Fruit palette: [flesh, skin]. `kind` comes from the rules, so a fruit keeps its colour
  /// for its whole flight and its two halves are painted in the same flesh tone.
  static const List<List<Color>> _fruitPalette = <List<Color>>[
    <Color>[Color(0xFFFF5A6A), Color(0xFF2E8B57)], // watermelon
    <Color>[Color(0xFFFFC93C), Color(0xFFFFE38A)], // lemon
    <Color>[Color(0xFF8BE06B), Color(0xFF4E8C3A)], // kiwi
    <Color>[Color(0xFFB47CFF), Color(0xFF7A4FD6)], // plum
    <Color>[Color(0xFFFF8FD1), Color(0xFFD94FA0)], // dragon fruit
    <Color>[Color(0xFF4FD2FF), Color(0xFF2A9CD6)], // ice berry
  ];

  Color _flesh(int kind) => _fruitPalette[kind % _fruitPalette.length][0];
  Color _skin(int kind) => _fruitPalette[kind % _fruitPalette.length][1];

  @override
  void reset() {
    world = FruitWorld(seed: widget.run.seed);
    _trail.clear();
    _halves.clear();
    _drops.clear();
    _cut.clear();
    _lastPoint = null;
    _comboFlash = 0;
    _lastCombo = 0;
    _wasExploded = false;
    _explodedFor = 0;
    widget.run.set(0);
  }

  @override
  void step(double dt) {
    world.update(dt);
    final Rect play = playRect(viewport);
    for (final _Half h in _halves) {
      h.velocity += Offset(0, 900 * dt);
      h.at += h.velocity * dt;
      h.angle += h.spin * dt;
      h.life -= dt;
    }
    _halves.removeWhere((_Half h) => h.life <= 0);
    for (final _Drop d in _drops) {
      d.velocity += Offset(0, 1300 * dt);
      d.at += d.velocity * dt;
      d.life -= dt;
    }
    _drops.removeWhere((_Drop d) => d.life <= 0);
    if (_comboFlash > 0) _comboFlash -= dt;
    if (world.combo != _lastCombo) {
      _lastCombo = world.combo;
      if (world.combo >= 3) _comboFlash = 0.8;
    }
    widget.run.set(world.sliced * 10);
    if (!_wasExploded && world.exploded) {
      _wasExploded = true;
      fx.shake(22);
      fx.flashScreen(const Color(0xFFFF6B4A), 0.32);
      fx.burst(play.center, const Color(0xFFFFB347), count: 46, speed: 420, kind: ParticleKind.orb);
      fx.burst(play.center, const Color(0xFFFF5B62), count: 30, speed: 300, kind: ParticleKind.smoke);
    }
    if (world.exploded) {
      _explodedFor += dt;
      if (_explodedFor > 0.38) widget.run.gameOver();
    }
  }

  void _slice(Offset at) {
    final Rect play = playRect(viewport);
    if (!play.contains(at)) return;
    final double nx = at.dx / viewport.width;
    final double ny = at.dy / viewport.height;
    _trail.add(at);
    if (_trail.length > 26) _trail.removeAt(0);
    final Offset? prev = _lastPoint;
    if (prev != null && (at - prev).distance < 2) return;
    _lastPoint = at;
    final Offset swipe = prev == null ? Offset.zero : at - prev;

    // Track fruit before/after so the burst spawns exactly on what was cut.
    final List<FruitSlice> before = <FruitSlice>[...world.items];
    final int cut = world.sliceAt(nx, ny);
    if (world.exploded && !_wasExploded) return;
    if (cut > 0) {
      for (final FruitSlice f in before) {
        if (!f.sliced) continue;
        final Offset p = Offset(f.x * viewport.width, f.y * viewport.height);
        final int key = f.hashCode;
        if (!_cut.add(key)) continue;
        final Color c = _flesh(f.kind);
        // Two halves split along the blade direction (fall back to the fruit's tilt when the
        // finger barely moved between frames).
        final Offset dir = swipe.distance > 1
            ? Offset(swipe.dx, swipe.dy) / swipe.distance
            : Offset(math.cos(f.rotation), math.sin(f.rotation));
        for (final double side in <double>[-1, 1]) {
          final Offset perp = Offset(-dir.dy, dir.dx);
          _halves.add(_Half(
            p + perp * f.radius * viewport.width * 0.35 * side,
            perp * (60 + 150 * side.abs()) + Offset(dir.dx * 90, -240 + dir.dy * 40),
            f.radius * viewport.width,
            c,
            side * (2.6 + math.Random(key + side.toInt()).nextDouble()),
            dir.direction,
            _skin(f.kind),
          ));
        }
        for (int i = 2; i > 0; i--) {
          for (int k = 0; k < 9; k++) {
            final double a = math.Random(key + i * 31 + k).nextDouble() * math.pi * 2;
            _drops.add(_Drop(p, Offset(math.cos(a), math.sin(a)) * (90 + 190 * math.Random(key + k).nextDouble()),
                c, 1.8 + 3.4 * math.Random(key * 7 + k).nextDouble()));
          }
        }
        burst(play, p, c, count: 12, speed: 260, kind: ParticleKind.shard);
        fx.ring(p, c, size: f.radius * viewport.width * 1.4);
        fx.text('+10', p - const Offset(0, 18), SoloArt.ink, size: 16);
      }
    }
    if (!simulating) return;
    setState(() {});
  }

  @override
  void onPointer(Offset at, SoloGesture kind) {
    switch (kind) {
      case SoloGesture.down:
      case SoloGesture.dragStart:
        _trail.clear();
        _slice(at);
        _lastPoint = at;
      case SoloGesture.drag:
        _slice(at);
      case SoloGesture.up:
      case SoloGesture.cancel:
      case SoloGesture.dragEnd:
        _lastPoint = null;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final ArcadeSkin skin = widget.run.skin;
    final Color accent = skin.accent;
    final Color accent2 = skin.accent2;
    final Rect play = playRect(size);

    // ---------------------------------------------------------------- dojo backdrop
    SoloArt.backdrop(canvas, size, skin: skin, time: clock, halo: 0.26,
        haloAt: Offset(size.width * 0.5, size.height * 0.52));
    // paper lanterns hanging from the top
    for (int i = 0; i < 5; i++) {
      final double x = size.width * (0.12 + i * 0.19);
      final double drop = 18 + (i.isEven ? 10 : 0);
      canvas.drawLine(Offset(x, 0), Offset(x, drop), SoloArt.stroke(SoloArt.a(const Color(0xFFFFFFFF), 0.18), 1.2));
      final double swing = math.sin(clock * 0.9 + i) * 3;
      canvas.drawCircle(Offset(x + swing, drop + 12), 8.5, Paint()..color = SoloArt.a(const Color(0xFFFF6B4A), 0.85));
      paintGlow(canvas, Offset(x + swing, drop + 12), 22, const Color(0xFFFFB347), 0.28);
    }
    // soft ground pool
    canvas.drawOval(
      Rect.fromCenter(center: Offset(size.width / 2, play.bottom + 10), width: size.width * 0.9, height: 90),
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[SoloArt.a(accent, 0.16), Colors.transparent],
        ).createShader(Rect.fromCenter(center: Offset(size.width / 2, play.bottom + 10), width: size.width * 0.9, height: 90)),
    );

    // ---------------------------------------------------------------- fruit
    for (final FruitSlice f in world.items) {
      final Offset at = Offset(f.x * size.width, f.y * size.height);
      if (at.dy < -40 || at.dy > size.height + 60) continue;
      final double r = f.radius * size.width;
      if (f.bomb) {
        _paintBomb(canvas, at, r);
      } else {
        _paintFruit(canvas, at, r, f);
      }
    }

    // ---------------------------------------------------------------- juice halves + drops
    for (final _Half h in _halves) {
      final double a = (h.life / 0.9).clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(h.at.dx, h.at.dy);
      canvas.rotate(h.angle);
      final Rect disc = Rect.fromCircle(center: Offset.zero, radius: h.radius);
      // flesh: a half-disc facing away from the cut line
      canvas.drawArc(disc, h.cut + math.pi, math.pi, true, Paint()..color = SoloArt.a(h.color, a));
      // bright core
      canvas.drawArc(Rect.fromCircle(center: Offset.zero, radius: h.radius * 0.62), h.cut + math.pi, math.pi, true,
          Paint()..color = SoloArt.a(SoloArt.lift(h.color, 0.24), a * 0.85));
      // rind along the arc
      canvas.drawArc(disc.deflate(h.radius * 0.06), h.cut + math.pi, math.pi, false,
          SoloArt.stroke(SoloArt.a(h.skin, a), math.max(1.6, h.radius * 0.16)));
      // wet cut face
      canvas.drawLine(Offset(-h.radius, 0), Offset(h.radius, 0), SoloArt.stroke(SoloArt.a(const Color(0xFFFFFFFF), a * 0.5), 1.4));
      canvas.restore();
    }
    for (final _Drop d in _drops) {
      canvas.drawCircle(d.at, d.radius, Paint()..color = SoloArt.a(d.color, (d.life / 0.55).clamp(0.0, 1.0) * 0.85));
    }

    // ---------------------------------------------------------------- blade trail
    if (_trail.length > 1) {
      SoloArt.blade(canvas, _trail, accent2, accent, 7);
      final Offset head = _trail.last;
      paintGlow(canvas, head, 26, accent, 0.4);
      canvas.drawCircle(head, 4.5, Paint()..color = const Color(0xFFFFFFFF));
    }

    // ---------------------------------------------------------------- readouts
    SoloArt.chip(canvas, Offset(16, play.top + 20), '${world.sliced} SLICED', SoloArt.ink);
    SoloArt.chip(canvas, Offset(size.width - 16, play.top + 20), '${world.combo} COMBO', SoloArt.gold, alignRight: true);
    final double target = 60;
    final Rect meter = Rect.fromLTWH(size.width / 2 - 60, play.top + 48, 120, 5);
    SoloArt.meter(canvas, meter, world.sliced / target, accent2);
    if (_comboFlash > 0) {
      final double k = (0.8 - _comboFlash) / 0.8;
      paintCallout(canvas, Offset(size.width / 2, play.center.dy - 40), 'COMBO ×${world.combo}', accent,
          scale: 1 + k * 0.25, alpha: (1 - k).clamp(0.0, 1.0));
    }
    if (world.exploded) {
      SoloArt.label(canvas, 'BOOM', Offset(size.width / 2, play.center.dy), size: 44,
          color: const Color(0xFFFF6B4A), glow: const Color(0xFFFFB347));
    }

    SoloArt.frame(canvas, size, accent);
    paintFx(canvas, size);
  }

  void _paintFruit(Canvas canvas, Offset at, double r, FruitSlice f) {
    final Color base = _flesh(f.kind);
    final Color skin = _skin(f.kind);
    paintGlow(canvas, at, r * 2.0, base, 0.16);
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(f.rotation);
    SoloArt.orb(canvas, Offset.zero, r, base, rim: SoloArt.lift(base, 0.3));
    // rind band
    canvas.drawCircle(Offset.zero, r, SoloArt.stroke(SoloArt.a(skin, 0.95), math.max(1.8, r * 0.20)));
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: r * 0.72),
      -2.3,
      1.7,
      false,
      SoloArt.stroke(SoloArt.a(const Color(0xFFFFFFFF), 0.35), math.max(1.4, r * 0.12)),
    );
    // seeds / detail
    canvas.drawCircle(Offset(r * 0.18, r * 0.30), math.max(1.2, r * 0.10), Paint()..color = SoloArt.a(const Color(0xFF3B2A1C), 0.6));
    canvas.drawCircle(Offset(-r * 0.22, r * 0.36), math.max(1.0, r * 0.075), Paint()..color = SoloArt.a(const Color(0xFF3B2A1C), 0.5));
    // leaf
    final Path leaf = Path()
      ..moveTo(-r * 0.1, -r * 0.95)
      ..quadraticBezierTo(r * 0.5, -r * 1.5, r * 0.7, -r * 0.95)
      ..quadraticBezierTo(r * 0.32, -r * 0.82, -r * 0.1, -r * 0.95)
      ..close();
    canvas.drawPath(leaf, Paint()..color = const Color(0xFF7BD46A));
    canvas.restore();
  }

  void _paintBomb(Canvas canvas, Offset at, double r) {
    final double pulse = 0.5 + 0.5 * math.sin(clock * 9);
    paintGlow(canvas, at, r * (2.2 + pulse * 0.5), const Color(0xFFFF4D3D), 0.3 + pulse * 0.12);
    canvas.drawCircle(at, r * (1.15 + pulse * 0.06), SoloArt.stroke(SoloArt.a(SoloArt.danger, 0.55 + pulse * 0.3), 2));
    // body
    canvas.drawCircle(
      at,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.45),
          radius: 1.1,
          colors: <Color>[const Color(0xFF4A525E), const Color(0xFF1A1E26), const Color(0xFF070A10)],
        ).createShader(Rect.fromCircle(center: at, radius: r)),
    );
    canvas.drawCircle(at - Offset(r * 0.3, r * 0.34), r * 0.26, Paint()..color = SoloArt.a(const Color(0xFFFFFFFF), 0.5));
    // cap + fuse
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: at + Offset(0, -r * 0.95), width: r * 0.5, height: r * 0.34),
          Radius.circular(r * 0.1)),
      Paint()..color = const Color(0xFF8A94A6),
    );
    final Path fuse = Path()
      ..moveTo(at.dx, at.dy - r * 1.05)
      ..quadraticBezierTo(at.dx + r * 0.6, at.dy - r * 1.5, at.dx + r * 0.3, at.dy - r * 1.85);
    canvas.drawPath(fuse, SoloArt.stroke(const Color(0xFFC9A27A), math.max(1.6, r * 0.1)));
    final Offset spark = Offset(at.dx + r * 0.3, at.dy - r * 1.85);
    paintGlow(canvas, spark, r * (0.7 + pulse * 0.5), const Color(0xFFFFC047), 0.75);
    canvas.drawCircle(spark, r * 0.16 * (0.8 + pulse * 0.4), Paint()..color = const Color(0xFFFFF3C4));
    SoloArt.label(canvas, '✕', at + Offset(0, r * 0.05), size: r * 0.85, color: SoloArt.a(const Color(0xFFFF6B6B), 0.85));
  }
}
