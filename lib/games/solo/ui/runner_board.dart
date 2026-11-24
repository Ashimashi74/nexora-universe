import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../arcade_kit/arcade_skin.dart';
import '../core/solo_rules_b.dart';
import '../solo_kit.dart';

/// =====================================================================================
/// ENDLESS RUNNER — three lanes, sidestep the barriers, distance is the score.
///
/// A pseudo-3D neon highway: the lane band is projected with a perspective curve, the road
/// scrolls with the distance travelled, barriers rise from the horizon with contact shadows
/// and headlight bloom, and the runner is a carved cube seen from behind with a lean that
/// follows the lane change. City skyline, sunset and light trails sell the depth.
/// =====================================================================================
class RunnerBoard extends SoloBoard {
  const RunnerBoard({super.key, required super.run});
  @override
  RunnerBoardState createState() => RunnerBoardState();
}

class RunnerBoardState extends SoloBoardState<RunnerBoard> {
  late RunnerWorld world;
  double _laneVisual = 1;
  double _lean = 0;
  bool _wasCrashed = false;
  double _crashedFor = 0;
  double _scroll = 0;

  @override
  void reset() {
    world = RunnerWorld(seed: widget.run.seed);
    _laneVisual = 1;
    _lean = 0;
    _wasCrashed = false;
    _crashedFor = 0;
    _scroll = 0;
    widget.run.set(0);
  }

  @override
  void step(double dt) {
    final Rect play = playRect(viewport);
    world.update(dt);
    final double prev = _laneVisual;
    _laneVisual = soloLerp(_laneVisual, world.lane.toDouble(), soloApproach(0.00002, dt));
    _lean = soloLerp(_lean, ((_laneVisual - prev) / math.max(dt, 0.001) * 0.05).clamp(-0.35, 0.35), soloApproach(0.01, dt));
    _scroll += world.speed * dt * play.height * 0.75;
    widget.run.set(world.metres);
    if (!_wasCrashed && world.crashed) {
      _wasCrashed = true;
      final Offset at = _runner(play);
      burst(play, at, SoloArt.danger, count: 28, speed: 340);
      burst(play, at, SoloArt.gold, count: 10, speed: 180);
      fx.shake(16);
      fx.flashScreen(SoloArt.danger, 0.2);
    }
    if (world.crashed) {
      _crashedFor += dt;
      if (_crashedFor > 0.42) widget.run.gameOver();
    }
  }

  void _sidestep(int dir) {
    if (!simulating) return;
    world.sidestep(dir);
  }

  Offset _runner(Rect play) {
    final double laneW = play.width * 0.5;
    return Offset(play.center.dx + (_laneVisual - 1) * laneW * 0.42, play.bottom - play.height * 0.16);
  }

  /// Projects a lane/height pair onto the screen: u=0 at the horizon, u=1 at the player.
  ///
  /// Every projection in this board (dashes, barriers, lane lines) goes through this one
  /// function, so the painted lane a barrier sits in is exactly the lane the rules collide.
  Offset _project(Rect play, double u, double lane, double laneW, double bottomY, double horizon) {
    final double k = u.clamp(0.0, 1.0);
    final double y = horizon + math.pow(k, 1.75).toDouble() * (bottomY - horizon);
    return Offset(play.center.dx + (lane - 1) * laneW * k, y);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final ArcadeSkin skin = widget.run.skin;
    final Color accent = skin.accent;
    final Color accent2 = skin.accent2;
    final Rect play = playRect(size);
    final double horizon = play.top + play.height * 0.24;
    final double bottomY = play.bottom + 6;

    // ---------------------------------------------------------------- sky + city
    SoloArt.backdrop(canvas, size, skin: skin, time: clock, halo: 0.22,
        haloAt: Offset(size.width * 0.5, horizon));
    SoloArt.sunset(canvas, Offset(size.width * 0.26, horizon - play.height * 0.055), play.height * 0.10,
        SoloArt.a(const Color(0xFFFFD166), 0.9), SoloArt.a(const Color(0xFFFF5B8A), 0.85), glow: const Color(0xFFFF9F7A));
    SoloArt.skyline(canvas, size, horizon + 2, SoloArt.a(const Color(0xFF070B16), 0.98), seed: 7, count: 22);
    SoloArt.skyline(canvas, size, horizon + 2, SoloArt.a(SoloArt.mix(accent, const Color(0xFF04060E), 0.8), 0.85),
        seed: 31, count: 13, windowAlpha: 0.35);

    // ---------------------------------------------------------------- road
    final double bottomW = play.width * 1.16;
    final double topW = play.width * 0.20;
    final Path road = Path()
      ..moveTo(play.center.dx - topW / 2, horizon)
      ..lineTo(play.center.dx + topW / 2, horizon)
      ..lineTo(play.center.dx + bottomW / 2, bottomY)
      ..lineTo(play.center.dx - bottomW / 2, bottomY)
      ..close();
    canvas.drawPath(
      road,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[SoloArt.a(const Color(0xFF0A0E1A), 0.98), SoloArt.a(SoloArt.mix(accent, const Color(0xFF05070E), 0.86), 0.98)],
        ).createShader(Rect.fromLTRB(0, horizon, size.width, bottomY)),
    );
    // edge light strips
    for (final double side in <double>[-1, 1]) {
      final Path edge = Path()
        ..moveTo(play.center.dx + side * topW / 2, horizon)
        ..lineTo(play.center.dx + side * bottomW / 2, bottomY);
      canvas.drawPath(edge, SoloArt.stroke(SoloArt.a(accent, 0.12), 10));
      canvas.drawPath(edge, SoloArt.stroke(SoloArt.a(accent2, 0.85), 2.2));
    }
    // lane dividers + scrolling dashes
    const int lanes = 3;
    for (int i = 1; i < lanes; i++) {
      final Path lane = Path()
        ..moveTo(play.center.dx + (i - 1.5) * topW / 3, horizon)
        ..lineTo(play.center.dx + (i - 1.5) * bottomW / 3, bottomY);
      canvas.drawPath(lane, SoloArt.stroke(SoloArt.a(accent, 0.18), 1.2));
    }
    const int dashes = 16;
    for (int i = 0; i < dashes; i++) {
      final double phase = (_scroll / 70) % 1;
      final double u = ((i + phase) / dashes).clamp(0.02, 1.0);
      final double alpha = (0.08 + u * 0.55).clamp(0.0, 0.9);
      for (int l = 1; l < lanes; l++) {
        final Offset a = _project(play, u, l - 0.03, bottomW / 3, bottomY, horizon);
        final Offset b = _project(play, u, l.toDouble(), bottomW / 3, bottomY, horizon);
        canvas.drawLine(
          a,
          b,
          SoloArt.stroke(SoloArt.a(const Color(0xFFFFFFFF), alpha), 1.5 + u * 5),
        );
      }
    }

    // ---------------------------------------------------------------- barriers (far → near)
    final List<RunnerObstacle> sorted = <RunnerObstacle>[...world.obstacles]
      ..sort((RunnerObstacle a, RunnerObstacle b) => b.distance.compareTo(a.distance));
    for (final RunnerObstacle o in sorted) {
      final double u = (1 - o.distance / 6).clamp(0.0, 1.0);
      if (u <= 0.004) continue;
      final double sc = 0.14 + 0.86 * math.pow(u, 1.4).toDouble();
      final double w = play.width * 0.13 * sc;
      final double h = play.height * 0.20 * sc * o.height;
      final Offset at = _project(play, u, o.lane.toDouble(), bottomW / 3, bottomY, horizon);
      final Rect r = Rect.fromLTWH(at.dx - w / 2, at.dy - h, w, h);
      SoloArt.barrier(canvas, r, o.height > 1.2 ? SoloArt.gold : SoloArt.danger);
      // headlight bloom in front of the barrier
      paintGlow(canvas, Offset(at.dx, bottomY - 2), w * 0.9, SoloArt.gold, 0.12 * u);
    }

    // ---------------------------------------------------------------- runner
    final Offset p = _runner(play);
    final double rw = play.width * 0.115;
    final double rh = play.height * 0.085;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(p.dx, p.dy + rh * 0.42), width: rw * 1.5, height: rh * 0.5),
      Paint()..color = SoloArt.a(const Color(0xFF000000), 0.5),
    );
    paintGlow(canvas, p, rw * 2.4, accent, 0.28);
    canvas.save();
    canvas.translate(p.dx, p.dy);
    canvas.rotate(_lean);
    final Rect body = Rect.fromCenter(center: Offset.zero, width: rw, height: rh * 1.5);
    SoloArt.cube(canvas, body, accent, radius: rw * 0.28, depth: rh * 0.22, glow: 0.4,
        edge: SoloArt.a(const Color(0xFFFFFFFF), 0.6));
    // head + visor
    canvas.drawCircle(Offset(0, -rh * 0.72), rw * 0.26, Paint()..color = SoloArt.lift(accent2, 0.1));
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(0, -rh * 0.74), width: rw * 0.42, height: rw * 0.13),
          Radius.circular(rw * 0.07)),
      Paint()..color = SoloArt.a(const Color(0xFF061020), 0.85),
    );
    // boots
    final double step = math.sin(clock * 14) * rh * 0.12;
    for (final double side in <double>[-1, 1]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(side * rw * 0.22, rh * 0.78 + step * side), width: rw * 0.26, height: rh * 0.22),
          Radius.circular(rw * 0.07),
        ),
        Paint()..color = SoloArt.a(accent2, 0.9),
      );
    }
    canvas.restore();
    // motion streaks behind the runner
    for (int i = 0; i < 5; i++) {
      final double y = p.dy - rh + i * rh * 0.42;
      canvas.drawLine(Offset(p.dx - rw * 1.4, y), Offset(p.dx - rw * 3.2, y), SoloArt.stroke(SoloArt.a(accent2, 0.14), 2));
    }

    // ---------------------------------------------------------------- readouts
    SoloArt.chip(canvas, Offset(16, horizon - 18), '${world.metres} m', SoloArt.ink);
    SoloArt.chip(canvas, Offset(16, horizon + 14), 'LANE ${world.lane + 1}/3', SoloArt.a(SoloArt.mute, 0.95), size: 10, height: 20);
    if (world.crashed) {
      SoloArt.label(canvas, 'CRASHED', Offset(size.width / 2, play.center.dy), size: 30,
          color: SoloArt.danger, glow: SoloArt.danger);
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
              onLeft: () => _sidestep(-1),
              onRight: () => _sidestep(1),
            ),
          ),
        ],
      );
}
