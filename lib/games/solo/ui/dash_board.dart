import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../arcade_kit/arcade_skin.dart';
import '../core/solo_rules_c.dart';
import '../solo_kit.dart';

/// =====================================================================================
/// GEO DASH — neon one-button runner. Tap / hold to jump and glide over spikes and blades.
///
/// Everything is drawn side-on in the play band between the shell HUD and the control deck:
/// a synthwave sunset, two parallax ridge layers, a scrolling neon floor grid, graded spike
/// fields, spinning hazard diamonds and a glowing cube that squashes and stretches with its
/// vertical velocity. The cube's bottom edge is exactly `ground - y * band`, so what the
/// player sees is what the rules collide.
/// =====================================================================================
class DashBoard extends SoloBoard {
  const DashBoard({super.key, required super.run});
  @override
  DashBoardState createState() => DashBoardState();
}

class DashBoardState extends SoloBoardState<DashBoard> {
  late DashWorld world;
  bool _holding = false;
  double _squash = 1;
  double _scroll = 0;
  bool _wasDead = false;
  double _deadFor = 0;

  /// Cube centre X as a fraction of the playfield width.
  static const double _playerX = 0.21;

  @override
  void reset() {
    world = DashWorld(seed: widget.run.seed);
    _holding = false;
    _squash = 1;
    _scroll = 0;
    _deadFor = 0;
    _wasDead = false;
    widget.run.set(0);
  }

  @override
  void step(double dt) {
    final Rect play = playRect(viewport);
    final double before = world.distance;
    world.update(dt, holding: _holding);
    _scroll += (world.distance - before) * play.width * 0.5;
    _squash = soloLerp(_squash, 1 + (world.vy * 0.05).clamp(-0.24, 0.28), soloApproach(0.0008, dt));
    widget.run.set(world.metres);
    if (!_wasDead && world.dead) {
      _wasDead = true;
      final Offset at = _cubeCentre(play);
      burst(play, at, SoloArt.danger, count: 24, speed: 330);
      burst(play, at, SoloArt.gold, count: 12, speed: 210);
      fx.shake(15);
      fx.flashScreen(SoloArt.danger, 0.2);
    }
    if (world.dead) {
      _deadFor += dt;
      if (_deadFor > 0.4) widget.run.gameOver();
    }
  }

  double _groundY(Rect play) => play.bottom - play.height * 0.14;
  double _ceilingY(Rect play) => play.top + play.height * 0.10;

  Offset _cubeCentre(Rect play) {
    final double ground = _groundY(play);
    final double band = ground - _ceilingY(play);
    final double s = band * 0.105;
    return Offset(play.left + play.width * _playerX, ground - world.y * band - s * 0.5);
  }

  void _press() {
    if (!simulating) return;
    _holding = true;
    world.leap();
  }

  void _release() => _holding = false;

  @override
  void onPointer(Offset at, SoloGesture kind) {
    switch (kind) {
      case SoloGesture.down:
        _press();
      case SoloGesture.up:
      case SoloGesture.cancel:
      case SoloGesture.dragEnd:
        _release();
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
    final double ground = _groundY(play);
    final double ceiling = _ceilingY(play);
    final double band = ground - ceiling;

    // ---------------------------------------------------------------- sky
    SoloArt.backdrop(canvas, size, skin: skin, time: clock, halo: 0.20,
        haloAt: Offset(size.width * 0.70, ceiling + band * 0.2));
    SoloArt.sunset(canvas, Offset(size.width * 0.74, ceiling + band * 0.26), band * 0.30,
        SoloArt.a(accent2, 0.9), SoloArt.a(accent, 0.5), glow: accent);
    SoloArt.ridge(canvas, size, ground, SoloArt.a(SoloArt.mix(accent, const Color(0xFF060A18), 0.84), 0.95),
        amplitude: band * 0.20, seed: 1.4, speed: 0.015, time: clock);
    SoloArt.ridge(canvas, size, ground + 3, SoloArt.a(SoloArt.mix(accent, const Color(0xFF04060E), 0.92), 1),
        amplitude: band * 0.11, seed: 3.9, speed: 0.03, time: clock);

    // ---------------------------------------------------------------- floor
    final Rect floorRect = Rect.fromLTRB(0, ground, size.width, size.height);
    canvas.drawRect(
      floorRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[SoloArt.a(accent, 0.14), const Color(0xFF02040A)],
        ).createShader(floorRect),
    );
    SoloArt.floorGrid(canvas, Size(size.width, size.height), ground, accent,
        scroll: _scroll / 54, rows: 10, cols: 18, alpha: 0.15);
    canvas.drawLine(Offset(0, ground), Offset(size.width, ground), SoloArt.stroke(SoloArt.a(accent, 0.28), 10));
    canvas.drawLine(Offset(0, ground), Offset(size.width, ground), SoloArt.stroke(SoloArt.a(accent2, 0.95), 2.2));
    canvas.drawLine(Offset(0, ceiling), Offset(size.width, ceiling), SoloArt.stroke(SoloArt.a(const Color(0xFFFFFFFF), 0.10), 1.2));
    // chevrons between the floor line and the deck: motion cue, not gameplay
    for (double x = size.width - (_scroll % 64); x > -40; x -= 64) {
      canvas.drawLine(Offset(x, ground + 8), Offset(x - 16, ground + 30), SoloArt.stroke(SoloArt.a(accent2, 0.14), 2.4));
    }

    // ---------------------------------------------------------------- hazards
    for (final DashHazard z in world.hazards) {
      final double x = z.x * size.width;
      if (x < -50 || x > size.width + 50) continue;
      if (z.flying) {
        final double y = ground - z.height * band;
        SoloArt.diamond(canvas, Offset(x, y), band * 0.055, SoloArt.danger,
            rotation: clock * 1.8 + z.height * 6, inner: const Color(0xFFFFE6E6));
        SoloArt.diamond(canvas, Offset(x, y), band * 0.028, SoloArt.a(SoloArt.danger, 0.65), rotation: -clock * 2.2);
      } else {
        final double h = z.height * band;
        for (int i = -1; i <= 1; i++) {
          final double dh = h * (i == 0 ? 1 : 0.7);
          SoloArt.spike(canvas, Offset(x + i * band * 0.055, ground + 3), band * 0.092, dh, SoloArt.danger);
        }
      }
    }

    // ---------------------------------------------------------------- cube
    final Offset c = _cubeCentre(play);
    final double s = band * 0.105;
    final double lift = ((ground - (c.dy + s * 0.5)) / math.max(1.0, band)).clamp(0.0, 1.0);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(c.dx, ground + 4), width: s * (1.5 - lift * 0.7), height: s * (0.42 - lift * 0.16)),
      Paint()..color = SoloArt.a(const Color(0xFF000000), 0.45),
    );
    paintGlow(canvas, c, s * 3.2, accent, 0.30);
    final Rect cube = Rect.fromCenter(center: c, width: s / _squash, height: s * _squash);
    SoloArt.cube(canvas, cube, accent, radius: s * 0.2, depth: s * 0.15, glow: 0.5, edge: SoloArt.a(const Color(0xFFFFFFFF), 0.66));
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(clock * 1.2);
    canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: s * 0.24, height: s * 0.24),
        Paint()..color = SoloArt.a(const Color(0xFF04101C), 0.75));
    canvas.restore();
    if (_holding && !world.dead) {
      for (int i = 0; i < 3; i++) {
        final double t = (clock * 3.4 + i * 0.33) % 1;
        canvas.drawCircle(c + Offset(-s * 0.55, s * 0.35 + t * s * 0.8), s * 0.15 * (1 - t),
            Paint()..color = SoloArt.a(accent2, 0.45 * (1 - t)));
      }
    }

    // ---------------------------------------------------------------- in-field readouts (shell owns the score)
    SoloArt.chip(canvas, Offset(16, ceiling + 20), '${world.metres} m', SoloArt.ink);
    final Rect meter = Rect.fromLTWH(16, ceiling + 42, math.min(140.0, size.width * 0.36), 6);
    SoloArt.meter(canvas, meter, ((world.speed - 0.55) / 0.95).clamp(0.0, 1.0), accent2);
    SoloArt.label(canvas, 'SPEED', meter.bottomLeft + const Offset(0, 10), size: 9, center: false,
        color: SoloArt.a(SoloArt.mute, 0.9), weight: FontWeight.w700);
    if (world.dead) {
      SoloArt.label(canvas, 'CRASH', Offset(size.width / 2, ceiling + band * 0.42), size: 30,
          color: SoloArt.danger, glow: SoloArt.danger, weight: FontWeight.w900);
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
              actionIcon: Icons.arrow_upward_rounded,
              actionLabel: 'JUMP',
              onAction: _press,
              onActionDown: () => _holding = true,
              onActionUp: _release,
            ),
          ),
        ],
      );
}
