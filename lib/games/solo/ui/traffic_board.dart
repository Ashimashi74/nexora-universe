import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../arcade_kit/arcade_skin.dart';
import '../core/solo_rules_c.dart';
import '../solo_kit.dart';

/// =====================================================================================
/// TRAFFIC RACER — top-down night highway. Swap lanes and weave through the traffic.
///
/// Seen from above: a wet asphalt band with glowing lane markings that rush at the player,
/// oncoming cars drawn as bevelled body + cabin + tail lights with motion blur, the player
/// car with headlight cones, speed lines and a turbo vignette as the speed climbs.
/// =====================================================================================
class TrafficBoard extends SoloBoard {
  const TrafficBoard({super.key, required super.run});
  @override
  TrafficBoardState createState() => TrafficBoardState();
}

class TrafficBoardState extends SoloBoardState<TrafficBoard> {
  late TrafficWorld world;
  double _laneX = 1;
  double _tilt = 0;
  bool _wasCrashed = false;
  double _crashedFor = 0;
  double _speedShake = 0;

  static const List<Color> _carTints = <Color>[
    Color(0xFFFF6B6B),
    Color(0xFFFFC94A),
    Color(0xFF6BC6FF),
    Color(0xFFB98CFF),
    Color(0xFFFF8FD1),
  ];

  @override
  void reset() {
    world = TrafficWorld(seed: widget.run.seed);
    _laneX = 1;
    _tilt = 0;
    _wasCrashed = false;
    _crashedFor = 0;
    _speedShake = 0;
    widget.run.set(0);
  }

  @override
  void step(double dt) {
    world.update(dt);
    final double prev = _laneX;
    _laneX = soloLerp(_laneX, world.lane.toDouble(), soloApproach(0.0000015, dt));
    _tilt = soloLerp(_tilt, ((_laneX - prev) / math.max(dt, 0.001) * 0.03).clamp(-0.22, 0.22), soloApproach(0.02, dt));
    _speedShake = soloLerp(_speedShake, ((world.speed - 1.4) / 1.0).clamp(0.0, 1.0), soloApproach(0.05, dt));
    widget.run.set(world.metres);
    if (!_wasCrashed && world.crashed) {
      _wasCrashed = true;
      final Rect play = playRect(viewport);
      final Offset at = _player(play);
      burst(play, at, SoloArt.danger, count: 30, speed: 380);
      burst(play, at, SoloArt.gold, count: 18, speed: 260);
      fx.shake(18);
      fx.flashScreen(SoloArt.danger, 0.24);
    }
    if (world.crashed) {
      _crashedFor += dt;
      if (_crashedFor > 0.42) widget.run.gameOver();
    }
  }

  void _steer(int dir) {
    if (!simulating) return;
    world.steer(dir);
  }

  /// Road geometry shared by the painter, the traffic projection and the player.
  Rect _road(Rect play) => Rect.fromLTRB(
        play.width * 0.05,
        play.top + play.height * 0.06,
        play.width * 0.95,
        play.bottom + 4,
      );

  Offset _player(Rect play) {
    final Rect road = _road(play);
    final double laneW = road.width / 3;
    // `TrafficWorld.playerY` is the collision line; the car is drawn centred on it.
    return Offset(road.left + laneW * (_laneX + 0.5), road.top + TrafficWorld.playerY * road.height);
  }

  /// Swipe origin, so a tap (no movement) never steers by accident.
  Offset? _swipeFrom;

  @override
  void onPointer(Offset at, SoloGesture kind) {
    switch (kind) {
      case SoloGesture.down:
        _swipeFrom = at;
      case SoloGesture.dragStart:
        _swipeFrom ??= at;
      case SoloGesture.up:
      case SoloGesture.dragEnd:
        // A real swipe (not a tap) steers to the side it travelled to.
        final Offset? from = _swipeFrom;
        if (from != null && (at - from).distance > 24 && simulating) {
          _steer(at.dx < from.dx ? -1 : 1);
        }
        _swipeFrom = null;
      case SoloGesture.cancel:
        _swipeFrom = null;
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
    final Rect road = _road(play);
    final double left = road.left;
    final double right = road.right;
    final double laneW = road.width / 3;
    final double top = road.top;

    // ---------------------------------------------------------------- backdrop
    SoloArt.backdrop(canvas, size, skin: skin, time: clock, halo: 0.18, haloAt: Offset(size.width / 2, play.top));
    // Desert ridges on both sides so the corridor has depth.
    SoloArt.ridge(canvas, size, play.bottom, SoloArt.a(SoloArt.mix(accent, const Color(0xFF05070F), 0.9), 1),
        amplitude: play.height * 0.07, seed: 2.2, from: 0, to: 0.13, time: clock, speed: 0.01);
    SoloArt.ridge(canvas, size, play.bottom, SoloArt.a(SoloArt.mix(accent, const Color(0xFF05070F), 0.9), 1),
        amplitude: play.height * 0.07, seed: 5.1, from: 0.87, to: 1, time: clock, speed: 0.01);

    // ---------------------------------------------------------------- asphalt
    canvas.drawRect(
      road,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[
            SoloArt.a(const Color(0xFF0B0F1A), 1),
            SoloArt.a(SoloArt.mix(accent, const Color(0xFF0C111E), 0.88), 1),
            SoloArt.a(const Color(0xFF0B0F1A), 1),
          ],
          stops: const <double>[0, 0.5, 1],
        ).createShader(road),
    );
    // wet sheen down the middle
    canvas.drawRect(
      Rect.fromCenter(center: road.center, width: road.width * 0.46, height: road.height),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[SoloArt.a(accent2, 0.05), SoloArt.a(accent2, 0.0)],
        ).createShader(road),
    );

    // edge barriers + cat eyes
    for (final double x in <double>[left, right]) {
      canvas.drawRect(Rect.fromLTWH(x - 3, top, 6, road.height), Paint()..color = SoloArt.a(accent, 0.16));
      canvas.drawLine(Offset(x - 3, top), Offset(x - 3, road.bottom), SoloArt.stroke(SoloArt.a(accent2, 0.9), 2));
      canvas.drawLine(Offset(x + 3, top), Offset(x + 3, road.bottom), SoloArt.stroke(SoloArt.a(accent2, 0.35), 1));
    }
    for (int l = 1; l < 3; l++) {
      final double x = left + laneW * l;
      final double phase = (world.travelled * 0.9) % 1;
      for (int i = 0; i < 18; i++) {
        final double t = (i + phase) / 18;
        final double y = top + t * road.height;
        final double len = 26 + t * 26;
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x - 2.4, y, 4.8, len), const Radius.circular(3)),
          Paint()..color = SoloArt.a(const Color(0xFFDDE6F5), 0.10 + 0.42 * t),
        );
      }
    }
    // cat-eye reflectors on the shoulders
    for (int i = 0; i < 14; i++) {
      final double t = ((i + (world.travelled * 0.9) % 1) / 14);
      final double y = top + t * road.height;
      for (final double x in <double>[left, right]) {
        canvas.drawCircle(Offset(x, y), 2 + 2 * t, Paint()..color = SoloArt.a(SoloArt.gold, 0.35 + 0.4 * t));
      }
    }

    // ---------------------------------------------------------------- traffic (far → near)
    final List<TrafficCar> cars = <TrafficCar>[...world.cars]..sort((TrafficCar a, TrafficCar b) => a.y.compareTo(b.y));
    for (final TrafficCar car in cars) {
      // car.y is normalised over the whole road rect (0 = the player's line, 1.2 = spawn), the
      // same space the rules collide in, so a car that looks like it reaches the player does.
      final double y = top + car.y * road.height;
      if (y < top - 120 || y > road.bottom + 140) continue;
      final double depth = ((y - top) / road.height).clamp(0.05, 1.0);
      final double cw = laneW * (0.32 + 0.26 * depth);
      final double ch = cw * 1.75;
      final Offset c = Offset(left + laneW * (car.lane + 0.5), y);
      final Color tint = _carTints[(car.lane * 3 + (car.y * 100).round().abs()) % _carTints.length];

      // motion smear
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: c + Offset(0, -ch * 0.5), width: cw * 0.9, height: ch * 1.4),
            Radius.circular(cw * 0.4)),
        Paint()
          ..color = SoloArt.a(tint, 0.10)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawOval(
        Rect.fromCenter(center: c + Offset(0, ch * 0.34), width: cw * 1.3, height: cw * 0.42),
        Paint()..color = SoloArt.a(const Color(0xFF000000), 0.5),
      );
      // body
      SoloArt.cube(canvas, Rect.fromCenter(center: c, width: cw, height: ch), tint, radius: cw * 0.26, depth: cw * 0.12, glow: 0.18);
      // windshield + rear window
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: c + Offset(0, -ch * 0.16), width: cw * 0.68, height: ch * 0.24),
            Radius.circular(cw * 0.14)),
        Paint()..color = SoloArt.a(const Color(0xFF0A1424), 0.9),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: c + Offset(0, ch * 0.22), width: cw * 0.62, height: ch * 0.16),
            Radius.circular(cw * 0.12)),
        Paint()..color = SoloArt.a(const Color(0xFF0A1424), 0.75),
      );
      // tail lights (we see their back: they face the player)
      for (final double side in <double>[-1, 1]) {
        final Offset lamp = c + Offset(side * cw * 0.34, ch * 0.40);
        paintGlow(canvas, lamp, cw * 0.5, const Color(0xFFFF3B3B), 0.45);
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: lamp, width: cw * 0.22, height: ch * 0.07), Radius.circular(2)),
          Paint()..color = const Color(0xFFFF5C5C),
        );
      }
    }

    // ---------------------------------------------------------------- player
    final Offset p = _player(play);
    final double pw = laneW * 0.52;
    final double ph = pw * 1.9;
    // headlight cones
    final Path cone = Path()
      ..moveTo(p.dx - pw * 0.32, p.dy - ph * 0.45)
      ..lineTo(p.dx - pw * 1.5, play.top - 40)
      ..lineTo(p.dx + pw * 1.5, play.top - 40)
      ..lineTo(p.dx + pw * 0.32, p.dy - ph * 0.45)
      ..close();
    canvas.drawPath(
      cone,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: <Color>[SoloArt.a(accent2, 0.30), SoloArt.a(accent2, 0.0)],
        ).createShader(Rect.fromLTRB(p.dx - pw * 1.6, play.top, p.dx + pw * 1.6, p.dy)),
    );
    canvas.drawOval(
      Rect.fromCenter(center: p + Offset(0, ph * 0.36), width: pw * 1.5, height: ph * 0.34),
      Paint()..color = SoloArt.a(const Color(0xFF000000), 0.55),
    );
    paintGlow(canvas, p, pw * 2.2, accent, 0.3);
    canvas.save();
    canvas.translate(p.dx, p.dy);
    canvas.rotate(_tilt);
    // body with a nose taper
    final Path body = Path()
      ..moveTo(0, -ph * 0.55)
      ..quadraticBezierTo(pw * 0.52, -ph * 0.18, pw * 0.48, ph * 0.42)
      ..quadraticBezierTo(0, ph * 0.58, -pw * 0.48, ph * 0.42)
      ..quadraticBezierTo(-pw * 0.52, -ph * 0.18, 0, -ph * 0.55)
      ..close();
    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[SoloArt.lift(accent, 0.22), accent, SoloArt.sink(accent, 0.24)],
        ).createShader(Rect.fromCenter(center: Offset.zero, width: pw, height: ph)),
    );
    canvas.drawPath(body, SoloArt.stroke(SoloArt.a(const Color(0xFFFFFFFF), 0.65), 1.4));
    // cockpit
    canvas.drawPath(
      Path()
        ..moveTo(0, -ph * 0.30)
        ..quadraticBezierTo(pw * 0.30, -ph * 0.06, pw * 0.26, ph * 0.14)
        ..quadraticBezierTo(0, ph * 0.24, -pw * 0.26, ph * 0.14)
        ..quadraticBezierTo(-pw * 0.30, -ph * 0.06, 0, -ph * 0.30)
        ..close(),
      Paint()..color = SoloArt.a(const Color(0xFF071322), 0.9),
    );
    canvas.drawCircle(Offset(0, -ph * 0.06), pw * 0.10, Paint()..color = SoloArt.a(accent2, 0.85));
    // exhaust flames
    for (final double side in <double>[-1, 1]) {
      final double flick = 0.6 + 0.4 * math.sin(clock * 26 + side);
      canvas.drawCircle(Offset(side * pw * 0.28, ph * 0.56), pw * 0.12 * flick,
          Paint()..color = SoloArt.a(const Color(0xFFFFB347), 0.75));
      canvas.drawCircle(Offset(side * pw * 0.28, ph * 0.62), pw * 0.2 * flick,
          Paint()..color = SoloArt.a(const Color(0xFFFF6B2C), 0.28));
    }
    canvas.restore();

    // speed lines at the edges
    SoloArt.speedLines(canvas, Size(size.width, size.height), clock, accent2,
        count: (10 + _speedShake * 18).round(), amount: 0.4 + _speedShake, fromTop: play.top);

    // ---------------------------------------------------------------- readouts
    final int kph = (world.speed * 90).round();
    SoloArt.chip(canvas, Offset(16, play.top + 18), '${world.metres} km', SoloArt.ink);
    SoloArt.chip(canvas, Offset(size.width - 16, play.top + 18), '$kph km/h', SoloArt.a(accent2, 1), alignRight: true);
    final Rect meter = Rect.fromLTWH(size.width * 0.5 - 60, play.top + 40, 120, 6);
    SoloArt.meter(canvas, meter, ((world.speed - 0.5) / 1.9).clamp(0.0, 1.0), accent2);
    if (world.crashed) {
      SoloArt.label(canvas, 'CRASH', Offset(size.width / 2, play.center.dy), size: 34,
          color: SoloArt.danger, glow: SoloArt.danger);
    }
    if (_speedShake > 0.55 && !world.crashed) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = RadialGradient(
            radius: 0.85,
            colors: <Color>[Colors.transparent, SoloArt.a(accent, 0.18 * _speedShake)],
          ).createShader(Offset.zero & size),
      );
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
              onLeft: () => _steer(-1),
              onRight: () => _steer(1),
            ),
          ),
        ],
      );
}
