import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../arcade_kit/arcade_controls.dart';
import '../../arcade_kit/arcade_fx.dart';
import '../../arcade_kit/arcade_loop.dart';
import '../../arcade_kit/arcade_result.dart';
import '../../arcade_kit/arcade_skin.dart';
import '../../arcade_kit/arcade_turns.dart';
import '../../core/game_contract.dart';
import '../core/golf_core.dart';
import 'golf_layout.dart';
import 'golf_scorecard.dart';

/// Sprite keys: ball_0..3 (or ball), hole, turf (seamless tile), wall, flag, bumper, windmill.
ArcadeSkin golfSkin() => ArcadeSkin(
      gameId: 'mini_golf',
      bgTop: const Color(0xFF0E2A1E),
      bgBottom: const Color(0xFF04120B),
      accent: const Color(0xFF7CFF7A),
      accent2: const Color(0xFFFFD34E),
      glow: const Color(0xFF3DDC84),
      players: const <Color>[Color(0xFFF7F7F7), Color(0xFFFF4F9A), Color(0xFF39C6FF), Color(0xFFFFC94A)],
    );

/// How long a bot "lines up" its putt (the windmill keeps turning; the bot plans for the blade position at the end).
const double kGolfBotThink = 0.9;

class GolfGame extends StatefulWidget {
  const GolfGame({super.key, required this.launch});
  final GameLaunch launch;

  @override
  State<GolfGame> createState() => _GolfGameState();
}

class _GolfGameState extends ArcadeLoopState<GolfGame> {
  late final GolfMatch g;
  late final ArcadeSkin skin = golfSkin();
  late final ArcadeFx fx;
  ArcadeTurnNet? tn;
  final math.Random _rng = math.Random(11);
  Offset? _dragFrom, _dragTo;
  int _shownHole = -1;
  String _banner = '';
  double _bannerT = 0;
  bool _done = false;
  bool _cardOpen = false;
  double _cardT = 0;
  int? _cardHole;
  GolfLayout _lay = const GolfLayout(1, Offset.zero, Rect.zero);
  final List<Offset> _trail = <Offset>[];
  int _trailSeat = -1;

  // bot turn
  GolfBotPlanner? _plan;
  String _planKey = '';
  double _planClock = 0, _planWait = 0;

  GameLaunch get l => widget.launch;
  int get me => l.mySeat;
  int get seats => (l.net?.seatCount ?? l.playerCount).clamp(2, 4);
  bool get _local => !l.online && l.mode == GameMode.local;
  bool _isBot(int s) => !l.online && !_local && s != me;

  /// This phone may putt for [s] (online: own seat; pass-and-play: every seat; vs bots: seat 0).
  bool _controls(int s) => l.online ? s == me : !_isBot(s);
  bool get _canAim => !g.over && !g.simulating && _controls(g.current) && !_cardOpen;

  @override
  void initState() {
    super.initState();
    fx = ArcadeFx(enabled: l.fancyEffects && !l.reducedMotion, skin: skin);
    g = GolfMatch(players: seats, seed: l.net?.seed ?? l.seed ?? 1);
    unawaited(skin.load().then((_) => mounted ? setState(() {}) : null));
    final NetLink? n = l.net;
    if (n != null) {
      tn = ArcadeTurnNet(n, onMove: _onNet, onReplayDone: () => tn?.turn = g.current)..start();
      for (final int s in n.forfeitedSeats) {
        g.forfeit(s);
      }
    }
  }

  @override
  void dispose() {
    tn?.dispose();
    super.dispose();
  }

  void _say(String s, [double t = 1.6]) {
    _banner = s;
    _bannerT = t;
  }

  Offset _px(double x, double y) => _lay.toScreen(x, y);

  double? _clk(NetMove m) => (m.data['clk'] as num?)?.toDouble();

  Future<void> _onNet(NetMove m) async {
    if (!m.replay && m.seat == me) return;
    while (g.simulating && mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    if (m.isForfeit) {
      g.forfeit((m.data['seat'] as num?)?.toInt() ?? m.seat);
    } else if (m.isTimeout) {
      // absent player: a sensible putt along the walking route keeps the round moving (same on every phone)
      final (double a, double p) = g.autoPutt();
      g.shoot(a, p, clock: _clk(m));
      if (m.replay) g.runToEnd();
    } else if (m.data['a'] == 'shot' && m.seat == g.current) {
      g.shoot((m.data['ang'] as num).toDouble(), (m.data['p'] as num).toDouble(), clock: _clk(m));
      if (m.replay) g.runToEnd();
    } else if (m.data['a'] == 'sync' && !m.replay) {
      final List<dynamic> ps = m.data['b'] as List<dynamic>;
      if ((m.data['h'] as num).toInt() == g.hole && !g.simulating) {
        for (int i = 0; i < ps.length && i < g.balls.length; i++) {
          final List<dynamic> e = ps[i] as List<dynamic>;
          if (g.balls[i].finished || !g.balls[i].onCourse) continue;
          g.balls[i]
            ..x = (e[0] as num).toDouble()
            ..y = (e[1] as num).toDouble();
        }
        final double? c = _clk(m);
        if (c != null) g.millClock = c;
      }
    }
    if (m.replay) g.events.clear();
    tn?.turn = g.current;
  }

  void _shoot(double ang, double p) {
    if (!_canAim) return;
    final double clock = g.millClock;
    if (tn != null) unawaited(tn!.send(<String, dynamic>{'a': 'shot', 'ang': ang, 'p': p, 'clk': clock}));
    g.shoot(ang, p, clock: clock);
    HapticFeedback.mediumImpact();
    _trail.clear();
  }

  @override
  void tick(double dt) {
    if (_bannerT > 0) {
      _bannerT -= dt;
      if (_bannerT <= 0) _banner = '';
    }
    if (_cardT > 0) {
      _cardT -= dt;
      if (_cardT <= 0 && !g.over) _cardOpen = false;
    }
    if (g.over) {
      _finish();
      fx.update(dt);
      return;
    }
    if (_shownHole != g.hole) {
      _shownHole = g.hole;
      _say(l.tx('حفره‌ی ${g.hole + 1} · پار ${g.h.par}', 'HOLE ${g.hole + 1} · PAR ${g.h.par}'), 1.8);
      _trail.clear();
    }
    if (g.simulating) {
      final int shooter = g.current, holeAt = g.hole;
      final bool done = g.advance(dt);
      if (g.hole == holeAt && !g.balls[shooter].finished) {
        if (_trailSeat != shooter) _trail.clear();
        _trailSeat = shooter;
        _trail.add(Offset(g.balls[shooter].x, g.balls[shooter].y));
        if (_trail.length > 24) _trail.removeAt(0);
      }
      _events(holeAt);
      if (done) {
        _trail.clear();
        if (g.hole != holeAt) _openCard(holeAt, 2.6);
        if (tn != null && shooter == me) {
          unawaited(tn!.send(<String, dynamic>{
            'a': 'sync',
            'h': g.hole,
            'clk': g.millClock,
            'b': <List<double>>[for (final GBall x in g.balls) <double>[x.x, x.y]],
          }));
        }
        tn?.turn = g.current;
      }
    } else {
      g.idle(dt);
      if (_isBot(g.current) && _bannerT <= 0.6 && !_cardOpen) _botTurn(dt);
    }
    fx.update(dt);
  }

  void _botTurn(double dt) {
    final String key = '${g.hole}|${g.shotsTaken}|${g.current}';
    if (key != _planKey) {
      _planKey = key;
      _planClock = g.millClock + kGolfBotThink;
      _planWait = 0;
      _plan = GolfBotPlanner(g, _rng, botSkillFor(l.daily ? BotDifficulty.hard : l.difficulty), samples: 30, clock: _planClock);
    }
    _planWait += dt;
    final GolfBotPlanner p = _plan!;
    if (!p.work(6)) return;
    // shoot when the blades reach the planned position (or a jammed windmill made us wait long enough)
    if (g.millClock + 1e-9 >= _planClock || _planWait > kGolfBotThink + 0.8) {
      final (double a, double pw) = p.shot;
      g.shoot(a, pw, clock: _planClock);
      _plan = null;
      _trail.clear();
    }
  }

  void _openCard(int hole, double t) {
    _cardOpen = true;
    _cardHole = hole;
    _cardT = t;
  }

  String _scoreText(int strokes, int par) => switch (golfScoreName(strokes, par)) {
        'ace' => l.tx('هول این وان!', 'HOLE IN ONE!'),
        'albatross' => l.tx('آلباتروس!', 'ALBATROSS!'),
        'eagle' => l.tx('ایگل!', 'EAGLE!'),
        'birdie' => l.tx('بردی!', 'BIRDIE!'),
        'par' => l.tx('پار', 'PAR'),
        'bogey' => l.tx('بوگی', 'BOGEY'),
        'double' => l.tx('دبل بوگی', 'DOUBLE BOGEY'),
        'pickup' => l.tx('حداکثر ضربه', 'PICKED UP'),
        _ => l.tx('داخل شد · $strokes ضربه', 'IN · $strokes STROKES'),
      };

  void _events(int holeAt) {
    for (final GEvent e in g.events) {
      final Offset at = _px(e.x, e.y);
      switch (e.kind) {
        case 'cup':
          fx.confetti(at, count: 30);
          fx.ring(at, skin.accent2, size: 16);
          _say(_scoreText(e.strokes, g.course[holeAt].par));
          HapticFeedback.heavyImpact();
        case 'pickup':
          _say(_scoreText(e.strokes, g.course[holeAt].par));
        case 'lip':
          _say(l.tx('لب حفره!', 'LIPPED OUT!'), 1.0);
        case 'water':
          fx.burst(at, const Color(0xFF39C6FF), count: 20, speed: 120, size: 3, kind: ParticleKind.orb, gravity: 200);
          if (e.seat == g.current) _say(l.tx('آب! +۱ ضربه', 'SPLASH! +1'));
        case 'oob':
          if (e.seat == g.current) _say(l.tx('بیرون! +۱ ضربه', 'OUT OF BOUNDS! +1'));
        case 'bumper':
          fx.burst(at, skin.accent, count: 8, speed: 90, size: 2.5);
          fx.shake(2);
        case 'ball':
          if (e.strength > 120) fx.burst(at, Colors.white, count: 6, speed: 70, size: 2, life: 0.3);
        case 'wall':
        case 'mill':
          if (e.strength > 200) fx.burst(at, Colors.white, count: 5, speed: 60, size: 2, life: 0.3);
      }
    }
    g.events.clear();
  }

  void _finish() {
    if (_done) return;
    _done = true;
    final List<int> order = g.ranking();
    if (order.first == me) fx.confetti(MediaQuery.sizeOf(context).center(Offset.zero), count: 60);
    _say(order.first == me ? l.tx('قهرمان!', 'CHAMPION!') : l.tx('پایان مسابقه', 'ROUND OVER'), 3);
    _openCard(g.course.length - 1, 99);
    Timer(const Duration(milliseconds: 3200), () {
      if (!mounted) return;
      final int tot = g.total(me);
      final int diff = g.toPar(me);
      l.onFinish(rankedResult(l, order,
          whatFa: '$tot ضربه (${diff >= 0 ? '+' : ''}$diff)', whatEn: '$tot strokes (${diff >= 0 ? '+' : ''}$diff)'));
    });
  }

  // ------------------------------------------------------------------ render
  void _paint(Canvas canvas, Size size) {
    paintBackdrop(canvas, size, skin, time);
    if (g.over) return;
    final Offset sh = fx.shakeOffset;
    canvas.save();
    canvas.translate(_lay.origin.dx + sh.dx, _lay.origin.dy + sh.dy);
    canvas.scale(_lay.scale);
    _paintCourse(canvas);
    canvas.restore();
    canvas.save();
    canvas.translate(sh.dx, sh.dy);
    fx.paint(canvas);
    canvas.restore();
    fx.paintFlash(canvas, size);
  }

  void _paintCourse(Canvas canvas) {
    final GHole h = g.h;
    final GRect bb = h.bounds;
    final Rect turf = Rect.fromLTRB(bb.l, bb.t, bb.r, bb.b);
    canvas.drawRRect(RRect.fromRectAndRadius(turf.inflate(6).shift(const Offset(0, 6)), const Radius.circular(10)), Paint()
      ..color = const Color(0x88000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    if (!skin.drawSprite(canvas, 'turf', turf)) {
      canvas.drawRect(turf, Paint()..color = const Color(0xFF2FA34F));
      final Paint stripe = Paint()..color = const Color(0xFF38B65A);
      for (double y = bb.t; y < bb.b; y += 40) {
        canvas.drawRect(Rect.fromLTRB(bb.l, y, bb.r, math.min(bb.b, y + 20)), stripe);
      }
      canvas.drawRect(turf, Paint()
        ..shader = ui.Gradient.radial(turf.center, turf.longestSide * 0.7, <Color>[const Color(0x22FFFFFF), const Color(0x33000000)]));
    }
    // tee box
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(h.start.x, h.start.y), width: 40, height: 20), const Radius.circular(4)),
        Paint()..color = const Color(0x33FFFFFF));
    // slopes: shaded band with chevrons pointing downhill
    for (final GSlope s in h.slopes) {
      final Rect rr = Rect.fromLTRB(s.area.l, s.area.t, s.area.r, s.area.b);
      canvas.drawRect(rr, Paint()..color = const Color(0x22000000));
      final double len = math.sqrt(s.ax * s.ax + s.ay * s.ay);
      if (len > 0) {
        final Offset d = Offset(s.ax, s.ay) / len;
        final Offset n = Offset(-d.dy, d.dx);
        final Paint chev = Paint()
          ..color = const Color(0x55FFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;
        for (double x = rr.left + 20; x < rr.right - 10; x += 30) {
          final Offset c = Offset(x, rr.center.dy);
          canvas.drawPath(
              Path()
                ..moveTo((c - d * 5 + n * 7).dx, (c - d * 5 + n * 7).dy)
                ..lineTo((c + d * 5).dx, (c + d * 5).dy)
                ..lineTo((c - d * 5 - n * 7).dx, (c - d * 5 - n * 7).dy),
              chev);
        }
      }
    }
    // sand
    for (final GRect s in h.sand) {
      final Rect rr = Rect.fromLTRB(s.l, s.t, s.r, s.b);
      canvas.drawRRect(RRect.fromRectAndRadius(rr, const Radius.circular(6)), Paint()..color = const Color(0xFFE9D39A));
      final math.Random rnd = math.Random(s.l.toInt() * 7 + s.t.toInt());
      final Paint dot = Paint()..color = const Color(0x55B08A44);
      for (int i = 0; i < 40; i++) {
        canvas.drawCircle(Offset(s.l + rnd.nextDouble() * (s.r - s.l), s.t + rnd.nextDouble() * (s.b - s.t)), 1.2, dot);
      }
    }
    // water (drawn exactly on the hazard rect: the ball splashes when its centre crosses the edge)
    for (final GRect w in h.water) {
      final Rect rr = Rect.fromLTRB(w.l, w.t, w.r, w.b);
      canvas.drawRect(rr, Paint()..shader = ui.Gradient.linear(rr.topCenter, rr.bottomCenter, <Color>[const Color(0xFF1F8FE0), const Color(0xFF0B4FA0)]));
      final Paint wave = Paint()
        ..color = const Color(0x55FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      for (double y = w.t + 8; y < w.b - 4; y += 12) {
        final Path p = Path()..moveTo(w.l + 4, y);
        for (double x = w.l + 4; x < w.r - 4; x += 6) {
          p.lineTo(x, y + math.sin(x * 0.2 + time * 3 + y) * 1.6);
        }
        canvas.drawPath(p, wave);
      }
    }
    // cup + flag
    final Offset cup = Offset(h.cup.x, h.cup.y);
    if (!skin.drawSprite(canvas, 'hole', Rect.fromCircle(center: cup, radius: kCupR))) {
      canvas.drawCircle(cup, kCupR + 1.5, Paint()..color = const Color(0x55FFFFFF));
      canvas.drawCircle(cup, kCupR, Paint()..shader = ui.Gradient.radial(cup + const Offset(0, -2), kCupR, <Color>[const Color(0xFF000000), const Color(0xFF1D2B1F)]));
    }
    paintGlow(canvas, cup, kCupR * 2, skin.accent2, 0.25 + 0.1 * math.sin(time * 3));
    if (!skin.drawSprite(canvas, 'flag', Rect.fromLTWH(cup.dx - 1, cup.dy - 46, 24, 46))) {
      canvas.drawLine(cup, cup - const Offset(0, 44), Paint()
        ..color = Colors.white
        ..strokeWidth = 1.6);
      final double wv = math.sin(time * 4) * 2;
      canvas.drawPath(
          Path()
            ..moveTo(cup.dx, cup.dy - 44)
            ..quadraticBezierTo(cup.dx + 11, cup.dy - 42 + wv, cup.dx + 22, cup.dy - 38)
            ..lineTo(cup.dx, cup.dy - 32)
            ..close(),
          Paint()..color = const Color(0xFFFF3D5A));
    }
    // bumpers (drawn radius == collision radius)
    for (final GBumper p in h.bumpers) {
      final Offset c = Offset(p.x, p.y);
      if (!skin.drawSprite(canvas, 'bumper', Rect.fromCircle(center: c, radius: p.r))) {
        paintGlow(canvas, c, p.r * 1.6, skin.accent, 0.3);
        paintSphere(canvas, c, p.r, const Color(0xFFE23D8B));
        canvas.drawCircle(c, p.r * 0.55, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white70);
      }
    }
    // rails: stroke width == collision thickness (2 * kRailHalf), round caps == capsule ends
    final Paint railShadow = Paint()
      ..strokeWidth = kRailHalf * 2
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x66000000);
    final Paint rail = Paint()
      ..strokeWidth = kRailHalf * 2
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF8B5A2B);
    final Paint railTop = Paint()
      ..strokeWidth = kRailHalf * 0.7
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFD9A066);
    for (final GWall w in h.walls) {
      canvas.drawLine(Offset(w.x1 + 1.5, w.y1 + 3), Offset(w.x2 + 1.5, w.y2 + 3), railShadow);
    }
    for (final GWall w in h.walls) {
      canvas.drawLine(Offset(w.x1, w.y1), Offset(w.x2, w.y2), rail);
    }
    for (final GWall w in h.walls) {
      canvas.drawLine(Offset(w.x1, w.y1 - 1), Offset(w.x2, w.y2 - 1), railTop);
    }
    // windmills: blade width == 2 * kBladeHalf, hub radius == kHubR
    for (final GWindmill m in h.mills) {
      final double a = g.millAngle(m);
      final Offset c = Offset(m.x, m.y);
      for (int k = 0; k < 2; k++) {
        final double aa = a + k * math.pi / 2;
        final Offset d = Offset(math.cos(aa), math.sin(aa)) * m.len;
        canvas.drawLine(c - d + const Offset(2, 4), c + d + const Offset(2, 4), Paint()
          ..strokeWidth = kBladeHalf * 2
          ..strokeCap = StrokeCap.round
          ..color = const Color(0x55000000));
        canvas.drawLine(c - d, c + d, Paint()
          ..strokeWidth = kBladeHalf * 2
          ..strokeCap = StrokeCap.round
          ..shader = ui.Gradient.linear(c - d, c + d, <Color>[const Color(0xFFF2F2F2), const Color(0xFFB0B8C8)]));
      }
      paintSphere(canvas, c, kHubR, const Color(0xFFFF7A1A));
    }
    // trail
    for (int i = 0; i < _trail.length; i++) {
      canvas.drawCircle(_trail[i], kBallR * (i / _trail.length) * 0.8, Paint()..color = Colors.white.withValues(alpha: 0.25 * i / _trail.length));
    }
    // balls (only those teed up and still playing)
    for (int i = 0; i < g.balls.length; i++) {
      final GBall b = g.balls[i];
      if (b.finished || !b.onCourse || g.out.contains(i)) continue;
      final Offset c = Offset(b.x, b.y);
      paintShadow(canvas, c + const Offset(1.5, 3), kBallR * 2.1, kBallR * 1.1, 0.5);
      if (!skin.drawSprite(canvas, 'ball_$i', Rect.fromCircle(center: c, radius: kBallR)) &&
          !skin.drawSprite(canvas, 'ball', Rect.fromCircle(center: c, radius: kBallR))) {
        paintSphere(canvas, c, kBallR, skin.player(i), shadow: false);
      }
      if (i == g.current && !g.simulating) {
        canvas.drawCircle(c, kBallR + 5 + math.sin(time * 6) * 1.5, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = skin.player(i).withValues(alpha: 0.9));
      }
    }
    // aim: direction dots + power arc
    if (_dragFrom != null && _dragTo != null && _canAim) {
      final (double, double)? aim = golfAim(_dragFrom!, _dragTo!, _lay.scale);
      if (aim != null) {
        final (double ang, double p) = aim;
        final GBall b = g.balls[g.current];
        final Offset dir = Offset(math.cos(ang), math.sin(ang));
        final Offset c = Offset(b.x, b.y);
        final Color col = Color.lerp(skin.accent, const Color(0xFFFF2D55), p)!;
        for (int i = 1; i <= 10; i++) {
          canvas.drawCircle(c + dir * (kBallR + i * 8.0 * (0.4 + p)), 1.6, Paint()..color = col.withValues(alpha: 1 - i / 12));
        }
        canvas.drawArc(Rect.fromCircle(center: c, radius: kBallR + 9), -math.pi / 2, math.pi * 2 * p, false, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..color = col);
      }
    }
  }

  void _toggleCard() {
    if (g.over) return;
    setState(() {
      _cardOpen = !_cardOpen;
      _cardHole = null;
      _cardT = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets pad = MediaQuery.paddingOf(context);
    final Size size = MediaQuery.sizeOf(context);
    _lay = golfLayout(size, pad);
    return Stack(fit: StackFit.expand, children: <Widget>[
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (DragStartDetails d) {
          if (_canAim) {
            _dragFrom = d.localPosition;
            _dragTo = d.localPosition;
          }
        },
        onPanUpdate: (DragUpdateDetails d) => _dragTo = _dragFrom == null ? null : d.localPosition,
        onPanEnd: (_) {
          if (_dragFrom != null && _dragTo != null) {
            final (double, double)? aim = golfAim(_dragFrom!, _dragTo!, _lay.scale);
            if (aim != null) _shoot(aim.$1, aim.$2);
          }
          _dragFrom = null;
          _dragTo = null;
        },
        onPanCancel: () {
          _dragFrom = null;
          _dragTo = null;
        },
        child: CustomPaint(painter: ArcadePainter(_paint, frame), size: Size.infinite),
      ),
      ValueListenableBuilder<int>(
        valueListenable: frame,
        builder: (_, __, ___) => Stack(children: <Widget>[
          Positioned(
            top: pad.top + kGolfHudTop,
            left: pad.left + 12,
            right: pad.right + 12,
            height: kGolfHudH,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                GestureDetector(
                  onTap: _toggleCard,
                  child: ArcadeHudPill(
                    color: skin.accent2,
                    child: Text(g.over ? '—' : '${g.hole + 1}/${g.course.length} · P${g.h.par}', style: const TextStyle(fontSize: 13)),
                  ),
                ),
                for (int i = 0; i < g.players; i++)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 6),
                    child: Opacity(
                      opacity: g.out.contains(i) ? 0.35 : (i == g.current ? 1 : 0.7),
                      child: ArcadeHudPill(
                        color: i == g.current ? skin.player(i) : Colors.white24,
                        child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                          Container(width: 9, height: 9, decoration: BoxDecoration(shape: BoxShape.circle, color: skin.player(i))),
                          const SizedBox(width: 5),
                          Text('${_short(i)} ${g.total(i)}${g.over ? '' : '+${g.balls[i].strokes}'}', style: const TextStyle(fontSize: 12)),
                        ]),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
          if (_banner.isNotEmpty)
            Positioned(left: 0, right: 0, top: size.height * 0.4, child: Center(child: ArcadeBanner(_banner, color: skin.accent, size: 34))),
          if (_cardOpen)
            Positioned(
              left: pad.left + 10,
              right: pad.right + 10,
              top: _lay.safe.top + 8,
              child: GestureDetector(
                onTap: _toggleCard,
                child: GolfScorecard(
                  match: g,
                  names: <String>[for (int i = 0; i < g.players; i++) _short(i)],
                  colors: skin.players,
                  isFa: l.isFa,
                  highlightHole: _cardHole,
                ),
              ),
            ),
          if (_canAim && _dragFrom == null && _bannerT <= 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: pad.bottom + 14,
              child: Center(
                child: Text(
                    _local
                        ? l.tx('${_short(g.current)}: بکش و رها کن', '${_short(g.current)}: pull back & release')
                        : l.tx('بکش و رها کن تا ضربه بزنی', 'Pull back & release to putt'),
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontWeight: FontWeight.w700)),
              ),
            ),
        ]),
      ),
    ]);
  }

  String _short(int i) {
    final String n = l.netName(i) ??
        (i == me ? l.playerName : (_local ? '${l.tx('بازیکن', 'P')}${i + 1}' : '${l.tx('ربات', 'Bot')} $i'));
    return n.length > 7 ? '${n.substring(0, 7)}…' : n;
  }
}
