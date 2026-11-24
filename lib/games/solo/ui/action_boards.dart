import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/solo_rules_b.dart';
import '../core/solo_rules_c.dart';
import '../solo_kit.dart';

const Color _champagne = Color(0xFFF6E7BD);
const Color _bronze = Color(0xFF8A6A2C);
const Color _hazard = Color(0xFFC97A6A);

// =====================================================================================
// ENDLESS RUNNER — three lanes, sidestep the barriers, distance is the score.
// =====================================================================================
class RunnerBoard extends SoloBoard {
  const RunnerBoard({super.key, required super.run});
  @override
  RunnerBoardState createState() => RunnerBoardState();
}

class RunnerBoardState extends SoloBoardState<RunnerBoard> {
  late RunnerWorld world;
  double _laneVisual = 1;

  @override
  void reset() {
    world = RunnerWorld(seed: widget.run.seed);
    _laneVisual = 1;
    widget.run.set(0);
  }

  @override
  void step(double dt) {
    world.update(dt);
    _laneVisual = LuxeBoardPainter.lerp(_laneVisual, world.lane.toDouble(), 1 - math.pow(0.001, dt).toDouble());
    widget.run.set(world.metres);
    if (world.crashed) widget.run.gameOver();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Color accent = widget.run.skin.accent;
    LuxeBoardPainter.background(canvas, size, accent);
    final double horizon = size.height * 0.28;
    final double roadTopW = size.width * 0.28;
    final double roadBottomW = size.width * 1.1;
    final double bottom = size.height;

    // Road trapezoid.
    final Path road = Path()
      ..moveTo(size.width / 2 - roadTopW / 2, horizon)
      ..lineTo(size.width / 2 + roadTopW / 2, horizon)
      ..lineTo(size.width / 2 + roadBottomW / 2, bottom)
      ..lineTo(size.width / 2 - roadBottomW / 2, bottom)
      ..close();
    canvas.drawPath(road, LuxeBoardPainter.fill(const Color(0xFF0C0B09)));

    // Lane separators + dashes that scroll with the distance.
    for (int i = 1; i < 3; i++) {
      final double t = i / 3;
      final Paint p = LuxeBoardPainter.stroke(accent.withValues(alpha: 0.22), 1.4);
      canvas.drawLine(
        Offset(size.width / 2 - roadTopW / 2 + roadTopW * t, horizon),
        Offset(size.width / 2 - roadBottomW / 2 + roadBottomW * t, bottom),
        p,
      );
    }
    final double phase = (world.metres * 0.06) % 1;
    for (int i = 0; i < 14; i++) {
      final double u = ((i + phase) / 14);
      final double y = horizon + math.pow(u, 1.9).toDouble() * (bottom - horizon);
      final double w = LuxeBoardPainter.lerp(2, 16, u);
      for (int lane = 0; lane < 2; lane++) {
        final double centre = size.width / 2 + (lane == 0 ? -1 : 1) * LuxeBoardPainter.lerp(roadTopW / 3, roadBottomW / 3, u);
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(centre, y), width: w * 0.5, height: w * 1.4), const Radius.circular(3)),
          LuxeBoardPainter.fill(_champagne.withValues(alpha: 0.10 + u * 0.25)),
        );
      }
    }

    // Obstacles.
    for (final RunnerObstacle o in world.obstacles) {
      final double u = (1 - o.distance / 6).clamp(0.0, 1.0);
      final double y = horizon + math.pow(u, 1.8).toDouble() * (bottom - horizon - 40);
      final double roadW = LuxeBoardPainter.lerp(roadTopW, roadBottomW, math.pow(u, 1.6).toDouble());
      final double laneW = roadW / 3;
      final double x = size.width / 2 - roadW / 2 + laneW * (o.lane + 0.5);
      final double h = LuxeBoardPainter.lerp(8, 90 * o.height, u);
      final double w = LuxeBoardPainter.lerp(10, laneW * 0.62, u);
      LuxeBoardPainter.roundedRect(canvas, Rect.fromCenter(center: Offset(x, y - h / 2), width: w, height: h), 5,
          _hazard.withValues(alpha: 0.9),
          border: _champagne.withValues(alpha: 0.35));
    }

    // Player.
    final double playerY = bottom - 96;
    final double laneX = size.width / 2 - roadBottomW / 2 + roadBottomW * ((_laneVisual + 0.5) / 3);
    LuxeBoardPainter.glow(canvas, Offset(laneX, playerY), 22, accent, 0.4);
    LuxeBoardPainter.roundedRect(canvas, Rect.fromCenter(center: Offset(laneX, playerY - 30), width: 26, height: 46), 10,
        _champagne, border: accent.withValues(alpha: 0.8));
    canvas.drawCircle(Offset(laneX, playerY - 62), 11, LuxeBoardPainter.fill(_champagne));

    LuxeBoardPainter.text(canvas, '${world.metres} m', Offset(size.width / 2, horizon - 28),
        color: _champagne, size: 26, weight: FontWeight.w900);
    LuxeBoardPainter.frame(canvas, size, accent);
  }

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: <Widget>[
        super.build(context),
        Positioned(
          left: 18,
          right: 18,
          bottom: 26,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: <Widget>[
            SoloPad(icon: Icons.chevron_left_rounded, onTap: () => setState(() => world.sidestep(-1)), size: 66),
            SoloPad(icon: Icons.chevron_right_rounded, onTap: () => setState(() => world.sidestep(1)), size: 66),
          ]),
        ),
      ]);
}

// =====================================================================================
// FRUIT NINJA — slice flying fruit by dragging; bombs end the run.
// =====================================================================================
class FruitBoard extends SoloBoard {
  const FruitBoard({super.key, required super.run});
  @override
  FruitBoardState createState() => FruitBoardState();
}

class FruitBoardState extends SoloBoardState<FruitBoard> {
  late FruitWorld world;
  final List<Offset> _trail = <Offset>[];

  @override
  void reset() {
    world = FruitWorld(seed: widget.run.seed);
    _trail.clear();
    widget.run.set(0);
  }

  @override
  void step(double dt) {
    world.update(dt);
    widget.run.set(world.sliced * 10);
    if (world.exploded) widget.run.gameOver();
  }

  void _slice(Offset p, Size s) {
    final double nx = p.dx / s.width;
    final double ny = p.dy / s.height;
    _trail.add(Offset(nx, ny));
    if (_trail.length > 24) _trail.removeAt(0);
    if (world.sliceAt(nx, ny) >= 0 && world.exploded) widget.run.gameOver();
    setState(() {});
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Color accent = widget.run.skin.accent;
    LuxeBoardPainter.background(canvas, size, accent);
    for (final FruitSlice f in world.items) {
      final Offset at = Offset(f.x * size.width, f.y * size.height);
      if (f.bomb) {
        LuxeBoardPainter.roundedRect(canvas, Rect.fromCenter(center: at, width: 40, height: 40), 8, const Color(0xFF1A1410),
            border: _hazard, borderWidth: 2);
        LuxeBoardPainter.text(canvas, '✕', at, color: _hazard, size: 20);
      } else {
        LuxeBoardPainter.glow(canvas, at, 16, accent, 0.18);
        canvas.save();
        canvas.translate(at.dx, at.dy);
        canvas.rotate(f.rotation);
        canvas.drawCircle(Offset.zero, f.radius * size.width, LuxeBoardPainter.fill(_champagne));
        canvas.drawCircle(Offset.zero, f.radius * size.width, LuxeBoardPainter.stroke(_bronze, 2));
        canvas.drawArc(Rect.fromCircle(center: Offset.zero, radius: f.radius * size.width * 0.7), -0.6, 2.0, false,
            LuxeBoardPainter.stroke(const Color(0x33000000), 3));
        canvas.restore();
      }
    }
    if (_trail.length > 1) {
      final Path path = Path()..moveTo(_trail.first.dx * size.width, _trail.first.dy * size.height);
      for (final Offset p in _trail.skip(1)) {
        path.lineTo(p.dx * size.width, p.dy * size.height);
      }
      canvas.drawPath(path, LuxeBoardPainter.stroke(_champagne.withValues(alpha: 0.65), 4));
    }
    LuxeBoardPainter.text(canvas, '${world.sliced} SLICED', Offset(size.width / 2, size.height * 0.2),
        color: _champagne, size: 20, weight: FontWeight.w900);
    if (world.combo >= 3) {
      LuxeBoardPainter.text(canvas, 'COMBO ×${world.combo}', Offset(size.width / 2, size.height * 0.24),
          color: accent, size: 14);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (BuildContext c, BoxConstraints box) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (DragStartDetails d) => _slice(d.localPosition, box.biggest),
          onPanUpdate: (DragUpdateDetails d) => _slice(d.localPosition, box.biggest),
          onPanEnd: (_) => _trail.clear(),
          child: super.build(context),
        );
      });
}

// =====================================================================================
// HELIX JUMP — rotate the tower, drop through the gaps, avoid the red rings.
// =====================================================================================
class HelixBoard extends SoloBoard {
  const HelixBoard({super.key, required super.run});
  @override
  HelixBoardState createState() => HelixBoardState();
}

class HelixBoardState extends SoloBoardState<HelixBoard> {
  late HelixWorld world;
  double _tilt = 0;

  @override
  void reset() {
    world = HelixWorld(seed: widget.run.seed);
    _tilt = 0;
    widget.run.set(0);
  }

  @override
  void step(double dt) {
    world.update(dt, tilt: _tilt);
    _tilt *= 0.9;
    widget.run.set(world.ring * 5);
    if (world.dead || world.finished) widget.run.gameOver();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Color accent = widget.run.skin.accent;
    LuxeBoardPainter.background(canvas, size, accent);
    final Offset c = Offset(size.width / 2, size.height * 0.55);
    final int baseRing = world.ring;
    for (int i = 0; i < 9; i++) {
      final int ringIndex = baseRing + i;
      if (ringIndex >= world.ringCount) break;
      final double u = i / 9;
      final double r = LuxeBoardPainter.lerp(size.width * 0.5, size.width * 0.14, u);
      final double y = c.dy + LuxeBoardPainter.lerp(0, size.height * 0.4, u);
      final bool red = world.rings[ringIndex] == HelixRing.red;
      final double gap = (ringIndex * 1.7) % (math.pi * 2);
      canvas.save();
      canvas.translate(c.dx, y);
      canvas.scale(1, 0.34);
      final Paint p = LuxeBoardPainter.stroke(red ? _hazard : accent.withValues(alpha: 0.8), 10 * (1 - u * 0.6));
      canvas.drawArc(Rect.fromCircle(center: Offset.zero, radius: r), gap + 0.45, math.pi * 2 - 0.9, false, p);
      canvas.restore();
    }
    // Ball.
    final double ballY = c.dy + 6;
    LuxeBoardPainter.glow(canvas, Offset(c.dx, ballY), 20, _champagne, 0.35);
    canvas.drawCircle(Offset(c.dx, ballY), 15, LuxeBoardPainter.fill(_champagne));
    canvas.drawCircle(Offset(c.dx, ballY), 15, LuxeBoardPainter.stroke(accent, 1.6));

    LuxeBoardPainter.text(canvas, 'DEPTH ${world.ring}', Offset(size.width / 2, size.height * 0.2),
        color: _champagne, size: 16);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (BuildContext c, BoxConstraints box) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (DragUpdateDetails d) => _tilt = (d.delta.dx / box.maxWidth) * 6,
          onTap: () => setState(world.jump),
          child: super.build(context),
        );
      });
}

// =====================================================================================
// BUBBLE SHOOTER — aim, fire, match three or more.
// =====================================================================================
class BubbleBoard extends SoloBoard {
  const BubbleBoard({super.key, required super.run});
  @override
  BubbleBoardState createState() => BubbleBoardState();
}

class BubbleBoardState extends SoloBoardState<BubbleBoard> {
  late BubbleWorld world;
  double _aim = 0;
  double _cool = 0;

  static const List<Color> _colours = <Color>[Color(0xFF43D9FF), _champagne, Color(0xFF8FB98A), Color(0xFF9A8FC9), _hazard];

  @override
  void reset() {
    world = BubbleWorld(seed: widget.run.seed)..pickColour();
    _aim = 0;
    widget.run.set(0);
  }

  @override
  void step(double dt) {
    if (_cool > 0) _cool -= dt;
  }

  void _fire() {
    if (_cool > 0) return;
    _cool = 0.25;
    world.fire();
    world.pickColour();
    widget.run.set(world.popped * 12);
    if (world.cleared) widget.run.gameOver();
    setState(() {});
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Color accent = widget.run.skin.accent;
    LuxeBoardPainter.background(canvas, size, accent);
    final int cols = world.cols;
    final double cell = math.min(size.width / (cols + 1.2), (size.height * 0.55) / 9);
    final double r = cell * 0.46;
    final double top = size.height * 0.16;
    final double left = size.width / 2 - (cols * cell) / 2;

    for (int row = 0; row < world.rows; row++) {
      for (int col = 0; col < cols; col++) {
        final int v = world.grid[row][col];
        if (v < 0) continue;
        final double dx = left + col * cell + (row.isOdd ? cell / 2 : 0) + cell / 2;
        final double dy = top + row * cell * 0.88;
        if (dy > size.height * 0.8) continue;
        canvas.drawCircle(Offset(dx, dy), r, LuxeBoardPainter.fill(_colours[v % _colours.length]));
        canvas.drawCircle(Offset(dx, dy) - Offset(r * 0.3, r * 0.3), r * 0.32, LuxeBoardPainter.fill(Colors.white.withValues(alpha: 0.35)));
      }
    }

    // Shooter + aim guide.
    final Offset gun = Offset(size.width / 2, size.height - 96);
    final Offset dir = Offset(math.sin(_aim), -math.cos(_aim));
    for (int i = 1; i < 12; i++) {
      canvas.drawCircle(gun + dir * (i * 14), 3, LuxeBoardPainter.fill(_champagne.withValues(alpha: 0.10 + i * 0.03)));
    }
    canvas.drawCircle(gun, 18, LuxeBoardPainter.fill(_colours[world.nextColour % _colours.length]));
    canvas.drawCircle(gun, 18, LuxeBoardPainter.stroke(_bronze, 2));
    LuxeBoardPainter.text(canvas, '${world.remaining} LEFT', Offset(size.width / 2, size.height * 0.10),
        color: _champagne, size: 14);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (BuildContext c, BoxConstraints box) {
        return Stack(fit: StackFit.expand, children: <Widget>[
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (DragUpdateDetails d) {
              _aim = (_aim - d.delta.dx / box.maxWidth * 2.4).clamp(-1.25, 1.25);
              setState(() {});
            },
            onTapDown: (TapDownDetails d) {
              _aim = ((d.localPosition.dx - box.maxWidth / 2) / (box.maxWidth / 2)).clamp(-1.0, 1.0) * 1.25;
              setState(() {});
            },
            child: super.build(context),
          ),
          Positioned(
            right: 20,
            bottom: 30,
            child: SoloPad(icon: Icons.gps_fixed_rounded, onTap: _fire, size: 76),
          ),
        ]);
      });
}

// =====================================================================================
// GEO DASH — one button: tap to jump, hold to fly, thread the spikes.
// =====================================================================================
class DashBoard extends SoloBoard {
  const DashBoard({super.key, required super.run});
  @override
  DashBoardState createState() => DashBoardState();
}

class DashBoardState extends SoloBoardState<DashBoard> {
  late DashWorld world;
  bool _holding = false;

  static const double _playerX = 0.22;

  @override
  void reset() {
    world = DashWorld(seed: widget.run.seed);
    _holding = false;
    widget.run.set(0);
  }

  @override
  void step(double dt) {
    world.update(dt, holding: _holding);
    widget.run.set(world.metres);
    if (world.dead) widget.run.gameOver();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Color accent = widget.run.skin.accent;
    LuxeBoardPainter.background(canvas, size, accent);
    final double ground = size.height * 0.72;
    final double ceil = size.height * 0.24;
    final double h = ground - ceil;

    canvas.drawRect(Rect.fromLTRB(0, ground, size.width, size.height), LuxeBoardPainter.fill(const Color(0x0FFFFFFF)));
    canvas.drawLine(Offset(0, ground), Offset(size.width, ground), LuxeBoardPainter.stroke(accent.withValues(alpha: 0.6), 2));
    canvas.drawLine(Offset(0, ceil), Offset(size.width, ceil), LuxeBoardPainter.stroke(accent.withValues(alpha: 0.25), 1.4));

    for (final DashHazard z in world.hazards) {
      final double x = z.x * size.width;
      if (z.flying) {
        final double y = ground - z.height * h;
        LuxeBoardPainter.roundedRect(canvas, Rect.fromCenter(center: Offset(x, y), width: 34, height: 26), 8, _hazard,
            border: _champagne.withValues(alpha: 0.3));
        LuxeBoardPainter.text(canvas, '✕', Offset(x, y), color: _champagne, size: 14);
      } else {
        final Path spike = Path()
          ..moveTo(x - 18, ground)
          ..lineTo(x, ground - z.height * h)
          ..lineTo(x + 18, ground)
          ..close();
        canvas.drawPath(spike, LuxeBoardPainter.fill(_hazard));
      }
    }

    final Offset player = Offset(_playerX * size.width, ground - world.y * h - 14);
    LuxeBoardPainter.glow(canvas, player, 20, accent, 0.35);
    LuxeBoardPainter.roundedRect(canvas, Rect.fromCenter(center: player, width: 28, height: 28), 8, _champagne,
        border: accent, borderWidth: 1.6);
    LuxeBoardPainter.text(canvas, '${world.metres} m', Offset(size.width / 2, ceil - 36),
        color: _champagne, size: 24, weight: FontWeight.w900);
  }

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: <Widget>[
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) {
            _holding = true;
            world.leap();
          },
          onTapUp: (_) => _holding = false,
          onTapCancel: () => _holding = false,
          child: super.build(context),
        ),
        Positioned(
          right: 20,
          bottom: 30,
          child: SoloPad(
            icon: Icons.arrow_upward_rounded,
            size: 80,
            onTap: () => world.leap(),
            onHold: () => _holding = true,
            onRelease: () => _holding = false,
          ),
        ),
      ]);
}

// =====================================================================================
// TRAFFIC RACER — overtake oncoming traffic in three lanes.
// =====================================================================================
class TrafficBoard extends SoloBoard {
  const TrafficBoard({super.key, required super.run});
  @override
  TrafficBoardState createState() => TrafficBoardState();
}

class TrafficBoardState extends SoloBoardState<TrafficBoard> {
  late TrafficWorld world;
  double _laneX = 1;

  @override
  void reset() {
    world = TrafficWorld(seed: widget.run.seed);
    _laneX = 1;
    widget.run.set(0);
  }

  @override
  void step(double dt) {
    world.update(dt);
    _laneX = LuxeBoardPainter.lerp(_laneX, world.lane.toDouble(), 1 - math.pow(0.0005, dt).toDouble());
    widget.run.set(world.metres);
    if (world.crashed) widget.run.gameOver();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Color accent = widget.run.skin.accent;
    LuxeBoardPainter.background(canvas, size, accent);
    final double roadLeft = size.width * 0.08;
    final double roadRight = size.width * 0.92;
    final double laneW = (roadRight - roadLeft) / 3;
    canvas.drawRect(Rect.fromLTRB(roadLeft, 0, roadRight, size.height), LuxeBoardPainter.fill(const Color(0xFF0C0B09)));

    final double phase = (world.travelled * 0.02) % 1;
    for (int i = 0; i < 12; i++) {
      final double y = ((i + phase) / 12) * size.height;
      for (int l = 1; l < 3; l++) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(roadLeft + laneW * l, y), width: 5, height: 44), const Radius.circular(3)),
          LuxeBoardPainter.fill(_champagne.withValues(alpha: 0.30)),
        );
      }
    }
    for (final TrafficCar c in world.cars) {
      final double y = c.y * size.height;
      final double x = roadLeft + laneW * (c.lane + 0.5);
      LuxeBoardPainter.roundedRect(canvas, Rect.fromCenter(center: Offset(x, y), width: laneW * 0.56, height: 74), 14,
          _hazard.withValues(alpha: 0.92),
          border: _champagne.withValues(alpha: 0.25));
      LuxeBoardPainter.roundedRect(canvas, Rect.fromCenter(center: Offset(x, y + 16), width: laneW * 0.30, height: 24), 6,
          _champagne.withValues(alpha: 0.35));
    }
    final double px = roadLeft + laneW * (_laneX + 0.5);
    final Offset player = Offset(px, size.height * 0.80);
    LuxeBoardPainter.glow(canvas, player, 30, accent, 0.35);
    LuxeBoardPainter.roundedRect(canvas, Rect.fromCenter(center: player, width: laneW * 0.58, height: 86), 16, _champagne,
        border: accent, borderWidth: 2);
    LuxeBoardPainter.roundedRect(canvas, Rect.fromCenter(center: player - const Offset(0, 18), width: laneW * 0.34, height: 28), 8,
        const Color(0x33000000));

    LuxeBoardPainter.text(canvas, '${world.metres} km', Offset(size.width / 2, 70), color: _champagne, size: 22, weight: FontWeight.w900);
    LuxeBoardPainter.text(canvas, '${(world.speed * 90).round()} km/h', Offset(size.width / 2, 96),
        color: accent, size: 12);
    LuxeBoardPainter.frame(canvas, size, accent);
  }

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: <Widget>[
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragEnd: (DragEndDetails d) {
            if (d.primaryVelocity != null) setState(() => world.steer(d.primaryVelocity! < 0 ? -1 : 1));
          },
          child: super.build(context),
        ),
        Positioned(
          left: 18,
          right: 18,
          bottom: 26,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: <Widget>[
            SoloPad(icon: Icons.chevron_left_rounded, onTap: () => setState(() => world.steer(-1)), size: 66),
            SoloPad(icon: Icons.chevron_right_rounded, onTap: () => setState(() => world.steer(1)), size: 66),
          ]),
        ),
      ]);
}
