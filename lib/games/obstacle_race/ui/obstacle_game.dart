import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../arcade_kit/arcade_controls.dart';
import '../../arcade_kit/arcade_fx.dart';
import '../../arcade_kit/arcade_loop.dart';
import '../../arcade_kit/arcade_net.dart';
import '../../arcade_kit/arcade_result.dart';
import '../../arcade_kit/arcade_skin.dart';
import '../../core/game_contract.dart';
import '../core/obstacle_core.dart';

/// Sprite keys: runner_0..runner_3, sweeper, block (see docs/ARCADE_ASSETS.md).
ArcadeSkin obstacleSkin() => ArcadeSkin(
      gameId: 'obstacle_race',
      bgTop: const Color(0xFF241046),
      bgBottom: const Color(0xFF0B0620),
      accent: const Color(0xFFFF4FA3),
      accent2: const Color(0xFF8C5BFF),
      glow: const Color(0xFFFF8AD8),
      players: const <Color>[Color(0xFFFF5C93), Color(0xFF39C6FF), Color(0xFFFFC83D), Color(0xFF6CF06C)],
    );

class ObstacleGame extends StatefulWidget {
  const ObstacleGame({super.key, required this.launch});
  final GameLaunch launch;

  @override
  State<ObstacleGame> createState() => _ObstacleGameState();
}

class _ObstacleGameState extends ArcadeLoopState<ObstacleGame> {
  late final ObstacleRace race;
  late final ArcadeSkin skin = obstacleSkin();
  late final ArcadeFx fx;
  ArcadeRt? rt;
  double? _touchX;
  bool _jump = false;
  bool _done = false;
  bool _loggedFinish = false;
  String _banner = '';
  double _bannerT = 0;
  double _endIn = -1;
  ObViewport _vp = ObViewport.fit(360, 640);

  GameLaunch get l => widget.launch;
  int get me => l.mySeat;
  int get seats => l.net?.seatCount ?? l.playerCount.clamp(2, 4);

  @override
  void initState() {
    super.initState();
    fx = ArcadeFx(enabled: l.fancyEffects && !l.reducedMotion, skin: skin);
    final double sk = botSkillFor(l.daily ? BotDifficulty.hard : l.difficulty);
    race = ObstacleRace(
      seed: l.net?.seed ?? l.seed ?? 3,
      count: seats,
      botSkill: l.online ? const <double>[] : <double>[for (int i = 0; i < seats; i++) i == me ? 0 : sk],
    )..focus = me;
    race.camera.snap(race.runners[me].y);
    unawaited(skin.load().then((_) => mounted ? setState(() {}) : null));
    final NetLink? n = l.net;
    if (n != null) {
      rt = ArcadeRt(n, hz: 12)
        ..onMove = _onMove
        ..start();
    }
  }

  @override
  void dispose() {
    rt?.dispose();
    super.dispose();
  }

  void _onMove(NetMove m) {
    final int s = (m.data['s'] as num?)?.toInt() ?? -1;
    if (s < 0 || s >= race.runners.length) return;
    final double at = ((m.data['ms'] as num?)?.toInt() ?? 0) / 1000;
    if (m.data['t'] == 'fin') race.markFinished(s, at);
    if (m.data['t'] == 'out') race.eliminate(s, at);
  }

  void _say(String text, [double secs = 1.4]) {
    _banner = text;
    _bannerT = secs;
  }

  @override
  void tick(double dt) {
    final double before = race.countdown;
    final Runner mine = race.runners[me];
    if (!_done) {
      double steer = 0;
      if (_touchX != null && mine.alive) {
        steer = ((_touchX! - _vp.sx(mine.x)) / (40 * _vp.scale)).clamp(-1.0, 1.0);
      }
      race.camera.viewH = _vp.worldH;
      race.input(me, steer, _jump);
      _jump = false;
      race.step(dt, simulate: rt == null ? null : <int>{me});
      if (mine.finished && !_loggedFinish && rt != null) {
        _loggedFinish = true;
        unawaited(rt!.log(<String, dynamic>{'t': 'fin', 's': me, 'ms': (mine.finishTime * 1000).round()}));
      }
    }
    if (before > 0) {
      if (race.countdown <= 0) {
        _say('GO!', 0.8);
        HapticFeedback.mediumImpact();
      } else {
        _say('${race.countdown.ceil()}', 1);
        if (before.ceil() != race.countdown.ceil()) HapticFeedback.selectionClick();
      }
    } else if (_bannerT > 0) {
      _bannerT -= dt;
      if (_bannerT <= 0) _banner = '';
    }
    final ArcadeRt? r = rt;
    if (r != null) {
      r.pump(dt, () => <String, dynamic>{
            'x': mine.x.round(),
            'y': mine.y.round(),
            'z': mine.z.round(),
            'p': mine.phase.index,
          });
      r.states.forEach((int seat, Map<String, dynamic> st) {
        if (seat == me || seat >= race.runners.length) return;
        final Runner k = race.runners[seat];
        final double ny = (st['y'] as num).toDouble();
        // A respawn teleports: snap instead of sliding across the course.
        final bool jumpCut = (ny - k.y).abs() > 200;
        k.x = jumpCut ? (st['x'] as num).toDouble() : rtLerp(k.x, (st['x'] as num).toDouble(), dt);
        k.y = jumpCut ? ny : rtLerp(k.y, ny, dt);
        k.z = (st['z'] as num?)?.toDouble() ?? 0;
        k.bestY = math.max(k.bestY, k.y);
        final int p = (st['p'] as num?)?.toInt() ?? 0;
        if (!k.done && p >= 0 && p <= RunPhase.falling.index) k.phase = RunPhase.values[p];
      });
      for (final int s in r.net.forfeitedSeats) {
        if (s < race.runners.length && !race.runners[s].done) race.eliminate(s, race.time);
      }
      final List<int> active = r.activeSeats;
      final bool allDone = active.every((int s) => race.runners[s].done);
      if (!_done && race.countdown <= 0 && (allDone || active.length <= 1)) _finish();
    } else if (!_done && mine.done) {
      _endIn = _endIn < 0 ? 1.6 : _endIn - dt;
      if (_endIn <= 0) {
        // Fast-forward the bots to a final ranking (deterministic: same fixed-step simulation).
        int guard = 0;
        while (!race.over && guard++ < 120 * 200) {
          race.step(ObstacleRace.fixedDt);
        }
        _finish();
      }
    }
    for (final ObEvent e in race.events) {
      final Offset at = Offset(e.x, e.y);
      final bool mineEv = e.seat == me;
      switch (e.kind) {
        case 'jump':
          fx.burst(at, Colors.white70, count: 6, speed: 90, kind: ParticleKind.smoke, size: 6, life: 0.5);
          if (mineEv) HapticFeedback.selectionClick();
        case 'land':
          if (mineEv) fx.burst(at, Colors.white38, count: 4, speed: 60, kind: ParticleKind.smoke, size: 5, life: 0.35);
        case 'knock' || 'squash':
          fx.burst(at, const Color(0xFFFFD34E), count: 18, speed: 260);
          if (mineEv) {
            fx.shake(8);
            HapticFeedback.mediumImpact();
          }
        case 'bump':
          fx.ring(at, skin.accent2, size: 26, life: 0.3);
          if (mineEv) HapticFeedback.lightImpact();
        case 'fall':
          fx.ring(at, const Color(0xFFFF2D55), size: 34, life: 0.5);
          if (mineEv) {
            _say(l.tx('افتادی!', 'FELL!'), 0.9);
            fx.flashScreen(const Color(0xFFFF2D55), 0.25);
            HapticFeedback.heavyImpact();
          }
        case 'respawn':
          fx.ring(at, skin.accent, size: 30, life: 0.5);
        case 'checkpoint':
          if (mineEv) {
            _say(l.tx('ایست بازرسی', 'CHECKPOINT'), 1.0);
            fx.ring(at, const Color(0xFF7CFF7A), size: 40, life: 0.5);
            HapticFeedback.lightImpact();
          }
        case 'finish':
          fx.burst(at, skin.player(e.seat), count: 30, speed: 260, kind: ParticleKind.orb, size: 5);
          if (mineEv) {
            final int place = race.finishedCount;
            _say(l.tx('رسیدی! نفر ${ordinalFa(place)}', 'FINISHED ${ordinalEn(place)}!'), 3);
            fx.confetti(at, count: 60);
            HapticFeedback.heavyImpact();
          }
        case 'dnf':
          if (mineEv) {
            _say(l.tx('حذف شدی!', 'ELIMINATED!'), 3);
            fx.flashScreen(const Color(0xFFFF2D55), 0.35);
            HapticFeedback.heavyImpact();
          }
        case 'out':
          fx.burst(at, skin.player(e.seat), count: 24, speed: 220, kind: ParticleKind.orb, size: 5);
      }
    }
    race.events.clear();
    fx.update(dt);
  }

  void _finish() {
    if (_done) return;
    _done = true;
    final List<int> order = race.ranking();
    final Runner mine = race.runners[me];
    if (order.first == me) {
      _say(l.tx('قهرمان مسابقه!', 'YOU WIN!'), 4);
      fx.confetti(Offset(mine.x, mine.y), count: 70);
    }
    final bool fin = mine.finished;
    l.onFinish(rankedResult(l, order,
        whatFa: fin ? '${mine.finishTime.toStringAsFixed(1)} ثانیه' : 'نرسید',
        whatEn: fin ? '${mine.finishTime.toStringAsFixed(1)} s' : 'DNF'));
  }

  // ------------------------------------------------------------------ render
  void _paint(Canvas canvas, Size size) {
    paintBackdrop(canvas, size, skin, time);
    final ObViewport vp = _vp;
    final double s = vp.scale;
    final double cam = race.cam;
    final Offset sh = fx.shakeOffset;
    canvas.save();
    canvas.translate(sh.dx, sh.dy);
    // world → screen: y up, camera y at the bottom of the safe area, course centred horizontally.
    canvas.translate(vp.left, vp.bottom);
    canvas.scale(s, -s);
    canvas.translate(0, -cam);
    final double y0 = cam - (size.height - vp.bottom) / s - 20;
    final double y1 = cam + vp.bottom / s + 20;
    _paintFloor(canvas, y0, y1);
    for (final Obstacle o in race.near(y0 - 40, y1 + 40)) {
      _paintObstacleBase(canvas, o);
    }
    _paintLines(canvas, y0, y1);
    final List<Runner> rs = List<Runner>.of(race.runners)..sort((Runner a, Runner b) => b.y.compareTo(a.y));
    for (final Runner r in rs) {
      if (r.phase == RunPhase.falling) _paintRunner(canvas, r);
    }
    for (final Runner r in rs) {
      if (r.phase != RunPhase.falling) _paintRunner(canvas, r);
    }
    for (final Obstacle o in race.near(y0 - 40, y1 + 40)) {
      _paintObstacleTop(canvas, o);
    }
    fx.paint(canvas);
    canvas.restore();
    // danger hint at the bottom edge of the safe area
    canvas.drawRect(Rect.fromLTWH(0, vp.bottom - 60, size.width, 60),
        Paint()..shader = ui.Gradient.linear(Offset(0, vp.bottom - 60), Offset(0, vp.bottom),
            <Color>[const Color(0x000B0620), const Color(0x660B0620)]));
    fx.paintFlash(canvas, size);
  }

  void _paintFloor(Canvas canvas, double y0, double y1) {
    const double w = ObstacleRace.width;
    final double top = math.min(y1, race.finishY + ObstacleRace.finishRunway);
    final int a = (y0 / 120).floor(), b = (top / 120).ceil();
    for (int i = a; i <= b; i++) {
      final double ty = i * 120.0;
      final Rect r = Rect.fromLTRB(0, ty, w, math.min(ty + 120, top));
      if (r.height <= 0) continue;
      final Color c = i.isEven ? const Color(0xFF5B3FD0) : const Color(0xFF6A4BE6);
      canvas.drawRect(r, Paint()..shader = ui.Gradient.linear(r.centerLeft, r.centerRight,
          <Color>[shade(c, -0.12), c, shade(c, -0.12)], <double>[0, 0.5, 1]));
      canvas.drawLine(Offset(0, r.top), Offset(w, r.top), Paint()
        ..color = const Color(0x55FFFFFF)
        ..strokeWidth = 2);
      if (i % 3 == 0) {
        final Path chev = Path()
          ..moveTo(w / 2 - 30, r.top + 40)
          ..lineTo(w / 2, r.top + 70)
          ..lineTo(w / 2 + 30, r.top + 40);
        canvas.drawPath(chev, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round
          ..color = const Color(0x22FFFFFF));
      }
    }
    // neon side rails just outside the course (the runner's hitbox touches x = 0 / x = width)
    for (final double x in <double>[-3, w + 3]) {
      final Path p = Path()
        ..moveTo(x, y0)
        ..lineTo(x, top);
      paintNeonPath(canvas, p, skin.accent, width: 5, glow: 14);
    }
  }

  void _paintLines(Canvas canvas, double y0, double y1) {
    const double w = ObstacleRace.width;
    // start line
    if (ObstacleRace.startY + 30 > y0 && ObstacleRace.startY - 30 < y1) {
      canvas.drawRect(const Rect.fromLTWH(0, ObstacleRace.startY - 34, w, 6), Paint()..color = const Color(0x88FFFFFF));
    }
    for (final ObSection sec in race.sections) {
      final double cy = sec.checkpointY;
      if (cy < y0 - 20 || cy > y1 + 20) continue;
      final bool reached = race.runners[me].checkpoint >= sec.index;
      final Color c = reached ? const Color(0xFF7CFF7A) : const Color(0xFFFFFFFF);
      for (int i = 0; i < 14; i++) {
        canvas.drawRect(Rect.fromLTWH(i * w / 14 + 4, cy - 3, w / 14 - 8, 6), Paint()..color = c.withValues(alpha: 0.55));
      }
      paintSphere(canvas, Offset(8, cy), 7, c);
      paintSphere(canvas, Offset(w - 8, cy), 7, c);
    }
    final double fy = race.finishY;
    if (fy > y0 - 40 && fy < y1 + 40) {
      const int n = 14;
      for (int i = 0; i < n; i++) {
        for (int j = 0; j < 2; j++) {
          canvas.drawRect(Rect.fromLTWH(i * w / n, fy + j * 15, w / n, 15),
              Paint()..color = (i + j).isEven ? Colors.white : const Color(0xFF14102A));
        }
      }
    }
  }

  void _paintObstacleBase(Canvas canvas, Obstacle o) {
    switch (o.kind) {
      case ObKind.pit:
        final Rect r = Rect.fromLTWH(o.x, o.y, o.w, o.h);
        canvas.drawRect(r, Paint()..color = const Color(0xFF05020D));
        canvas.drawRect(r.deflate(3), Paint()
          ..shader = ui.Gradient.radial(r.center, r.longestSide * 0.6, <Color>[const Color(0xFF000000), const Color(0xFF2A0E4A)]));
        final Path edge = Path()..addRect(r);
        paintNeonPath(canvas, edge, const Color(0xFFFF2D55), width: 3, glow: 10);
      case ObKind.drop:
        final double c = o.dropCycle(race.time);
        if (c > 0.35 && c < 0.75) {
          final double k = (c - 0.35) / 0.4;
          final Rect foot = Rect.fromCenter(center: Offset(o.x, o.y), width: o.w, height: o.h);
          canvas.drawRect(foot, Paint()..color = Color.fromRGBO(255, 45, 85, 0.12 + 0.3 * k));
          canvas.drawRect(foot, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Color.fromRGBO(255, 45, 85, 0.3 + 0.5 * k));
        }
      default:
        break;
    }
  }

  void _paintObstacleTop(Canvas canvas, Obstacle o) {
    switch (o.kind) {
      case ObKind.sweeper:
        final double a = o.angle(race.time);
        final Offset p0 = Offset(o.x, o.y);
        final Offset p1 = Offset(o.x + math.cos(a) * o.w, o.y + math.sin(a) * o.w);
        // stroke width = 2 × arm half-thickness, round caps = the capsule hitbox
        canvas.drawLine(p0 + const Offset(6, -8), p1 + const Offset(6, -8), Paint()
          ..strokeWidth = ObstacleRace.armHalf * 2
          ..strokeCap = StrokeCap.round
          ..color = const Color(0x44000000));
        canvas.drawLine(p0, p1, Paint()
          ..strokeWidth = ObstacleRace.armHalf * 2
          ..strokeCap = StrokeCap.round
          ..shader = ui.Gradient.linear(p0, p1, const <Color>[Color(0xFFFF3B3B), Color(0xFFFF8A3D)]));
        for (int i = 1; i < 6; i++) {
          final Offset q = Offset.lerp(p0, p1, i / 6)!;
          canvas.drawCircle(q, 3.5, Paint()..color = Colors.white.withValues(alpha: 0.85));
        }
        paintSphere(canvas, p0, ObstacleRace.hubR, const Color(0xFFB0B8C8));
      case ObKind.gate:
        final double g = o.gateGap(race.time, ObstacleRace.width);
        final double gl = g - o.w / 2, gr = g + o.w / 2;
        paintBlock(canvas, Rect.fromLTWH(0, o.y, math.max(0, gl), o.h), const Color(0xFF39C6FF), radius: 6, depth: -6);
        paintBlock(canvas, Rect.fromLTWH(gr, o.y, math.max(0, ObstacleRace.width - gr), o.h), const Color(0xFF39C6FF), radius: 6, depth: -6);
        paintGlow(canvas, Offset(g, o.y + o.h / 2), o.w * 0.5, const Color(0xFF7CFF7A), 0.25);
      case ObKind.drop:
        final double c = o.dropCycle(race.time);
        if (c > 0.55 && c < 1.0) {
          final double fall = c < 0.75 ? (0.75 - c) / 0.2 : 0;
          final double lift = c > 0.95 ? (c - 0.95) / 0.05 : 0;
          final double sc = 1 + fall * 0.9 + lift * 0.5;
          final double op = c > 0.95 ? 1 - lift : 1;
          final Rect r = Rect.fromCenter(center: Offset(o.x, o.y), width: o.w * sc, height: o.h * sc);
          if (!skin.drawSprite(canvas, 'block', r, opacity: op)) {
            paintBlock(canvas, r, Color.fromRGBO(255, 200, 61, op), radius: 8, depth: -6 * sc, glow: fall > 0 ? 0 : 0.4);
          }
          if (c > 0.75 && c < 0.78 && (o.y - race.runners[me].y).abs() < 300) fx.shake(2);
        }
      case ObKind.bumper:
        final double pulse = 0.5 + 0.5 * math.sin(race.time * 6 + o.x);
        paintShadow(canvas, Offset(o.x + 4, o.y - 6), o.w * 2.2, o.w * 1.2, 0.35);
        paintGlow(canvas, Offset(o.x, o.y), o.w * (1.25 + 0.15 * pulse), const Color(0xFFFF4FA3), 0.25);
        paintSphere(canvas, Offset(o.x, o.y), o.w, const Color(0xFFFF4FA3), rim: Colors.white, shadow: false);
      case ObKind.pit:
        break;
    }
  }

  void _paintRunner(Canvas canvas, Runner r) {
    final Color c = skin.player(r.seat);
    double alpha = 1;
    double shrink = 1;
    if (r.phase == RunPhase.falling) {
      shrink = math.max(0.15, 1 - r.fallT / ObstacleRace.fallTime);
      alpha = shrink;
    } else if (r.phase == RunPhase.dnf || r.phase == RunPhase.out) {
      alpha = 0.35;
    } else if (r.ghost > 0) {
      alpha = (r.ghost * 10).floor().isEven ? 0.45 : 0.85;
    }
    const double rad = ObstacleRace.runnerR;
    final double lift = math.max(0, r.z);
    if (r.phase != RunPhase.falling) {
      // ground shadow = exact hitbox footprint
      paintShadow(canvas, Offset(r.x, r.y), rad * 2 * (1 - lift / 300), rad * 2 * (1 - lift / 300), 0.4 * alpha);
    }
    canvas.save();
    canvas.translate(r.x, r.y + lift * 0.6);
    final double sc = (1 + lift / 220) * shrink;
    canvas.scale(sc, -sc); // upright
    if (!skin.drawSprite(canvas, 'runner_${r.seat % 4}', const Rect.fromLTWH(-rad, -rad * 1.5, rad * 2, rad * 2.5), opacity: alpha)) {
      final Rect body = Rect.fromCenter(center: const Offset(0, -rad * 0.25), width: rad * 2, height: rad * 2.5);
      canvas.drawRRect(RRect.fromRectAndRadius(body, const Radius.circular(rad)), Paint()
        ..shader = ui.Gradient.radial(body.center + const Offset(-5, -8), rad * 2,
            <Color>[shade(c, 0.25).withValues(alpha: alpha), c.withValues(alpha: alpha), shade(c, -0.3).withValues(alpha: alpha)], <double>[0, 0.5, 1]));
      final Rect visor = Rect.fromCenter(center: const Offset(0, -8), width: rad * 1.5, height: rad * 0.8);
      canvas.drawRRect(RRect.fromRectAndRadius(visor, const Radius.circular(8)), Paint()..color = const Color(0xFF14102A).withValues(alpha: alpha));
      canvas.drawCircle(const Offset(-5, -8), 3, Paint()..color = Colors.white.withValues(alpha: alpha));
      canvas.drawCircle(const Offset(5, -8), 3, Paint()..color = Colors.white.withValues(alpha: alpha));
    }
    if (r.seat == me && r.phase != RunPhase.falling) {
      drawLabel(canvas, l.tx('تو', 'YOU'), const Offset(0, -rad * 2.4), size: 10, color: Colors.white, glow: c);
    }
    canvas.restore();
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets pad = MediaQuery.paddingOf(context);
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints box) {
      _vp = ObViewport.fit(box.maxWidth, box.maxHeight,
          padTop: pad.top, padBottom: pad.bottom, padLeft: pad.left, padRight: pad.right);
      return Stack(fit: StackFit.expand, children: <Widget>[
        Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (PointerDownEvent e) => _touchX = e.localPosition.dx,
          onPointerMove: (PointerMoveEvent e) => _touchX = e.localPosition.dx,
          onPointerUp: (_) => _touchX = null,
          onPointerCancel: (_) => _touchX = null,
          child: CustomPaint(painter: ArcadePainter(_paint, frame), size: Size.infinite),
        ),
        ValueListenableBuilder<int>(
          valueListenable: frame,
          builder: (_, __, ___) {
            final Runner mine = race.runners[me];
            final bool qualifying = race.firstFinish >= 0 && !mine.done;
            return Stack(children: <Widget>[
              Positioned(
                top: pad.top + 64,
                left: pad.left + 12,
                child: ArcadeHudPill(
                  color: skin.accent,
                  child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                    const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 6),
                    Text('${race.placeOf(me)}/${race.count}', style: const TextStyle(fontSize: 18)),
                  ]),
                ),
              ),
              Positioned(
                top: pad.top + 64,
                right: pad.right + 12,
                child: ArcadeHudPill(
                  color: qualifying ? const Color(0xFFFF2D55) : skin.accent2,
                  child: Text(
                      qualifying ? '⏱ ${race.timeLeft.ceil()}' : '${(race.progress(me) * 100).round()}%',
                      style: const TextStyle(fontSize: 16)),
                ),
              ),
              if (_banner.isNotEmpty) Center(child: ArcadeBanner(_banner, color: skin.accent, size: _banner.length > 6 ? 40 : 64)),
            ]);
          },
        ),
        Positioned(
          right: pad.right + 18,
          bottom: pad.bottom + 22,
          child: ArcadePadButton(
            icon: Icons.keyboard_double_arrow_up_rounded,
            label: l.tx('پرش', 'JUMP'),
            color: skin.accent,
            size: 92,
            onDown: () => _jump = true,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: pad.bottom + 8,
          child: IgnorePointer(
            child: Text(l.tx('انگشتت را بکش تا حرکت کنی', 'Drag anywhere to steer'),
                textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ),
        ),
      ]);
    });
  }
}
