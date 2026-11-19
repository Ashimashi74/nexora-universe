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
import '../core/basket_core.dart';

/// Sprite keys: ball (round, drawn into the ball's projected circle), hoop (backboard, drawn into the projected
/// board rectangle), court (portrait background, drawn into the 360x640 canvas).
ArcadeSkin basketSkin() => ArcadeSkin(
      gameId: 'basketball_battle',
      bgTop: const Color(0xFF1B0F2E),
      bgBottom: const Color(0xFF07040F),
      accent: const Color(0xFFFF8A2A),
      accent2: const Color(0xFFFFD34E),
      glow: const Color(0xFFFF6A1D),
    );

/// m:ss for the shot clock (60 → "1:00").
String basketClock(double secondsLeft) {
  final int s = secondsLeft.ceil().clamp(0, 5999);
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// Final result for this phone from every seat's line (same ranking on every phone).
GameResult basketResult(GameLaunch l, Map<int, BasketLine> lines, {Set<int> forfeited = const <int>{}, int? durationMs}) {
  final ({List<int> order, List<int> top}) r = rankBasket(lines, forfeited: forfeited);
  final BasketLine mine = lines[l.mySeat] ?? const BasketLine(0, 0, 0);
  final GameResult base = rankedResult(l, r.order,
      whatFa: '${mine.score} امتیاز · ${mine.made}/${mine.shots}', whatEn: '${mine.score} pts · ${mine.made}/${mine.shots}');
  final bool shared = r.top.length > 1;
  final int active = lines.keys.where((int s) => !forfeited.contains(s)).length;
  final GameOutcome outcome = !r.top.contains(l.mySeat)
      ? GameOutcome.loss
      : shared
          ? GameOutcome.draw
          : GameOutcome.win;
  return GameResult(
    outcome: outcome,
    score: base.score,
    opponentScore: base.opponentScore,
    winnerSeats: shared && r.top.length == active ? <int>[] : r.top,
    scores: base.scores,
    summaryFa: outcome == GameOutcome.draw ? '${mine.score} امتیاز · مساوی' : base.summaryFa,
    summaryEn: outcome == GameOutcome.draw ? '${mine.score} pts · tie for first' : base.summaryEn,
    tournamentMatchId: l.tournamentMatchId,
    durationMs: durationMs,
  );
}

class BasketGame extends StatefulWidget {
  const BasketGame({super.key, required this.launch});
  final GameLaunch launch;

  @override
  State<BasketGame> createState() => _BasketGameState();
}

class _BasketGameState extends ArcadeLoopState<BasketGame> {
  late final BasketMatch match;
  late final ArcadeSkin skin = basketSkin();
  late final ArcadeFx fx;
  ArcadeRt? rt;
  final Map<int, BasketLine> _fin = <int, BasketLine>{};
  double _endWait = -1;
  bool _done = false;
  bool _sentFin = false;
  String _banner = '';
  double _bannerT = 0;
  double _netSway = 0;
  double _netStretch = 0;
  Offset? _swipeA;
  final List<Offset> _swipe = <Offset>[];
  final List<Offset> _trail = <Offset>[];
  BasketLayout _lay = BasketLayout.fit(kCanvasW, kCanvasH);
  EdgeInsets _pad = EdgeInsets.zero;

  GameLaunch get l => widget.launch;
  int get me => l.mySeat;
  int get seats => l.net?.seatCount ?? l.playerCount.clamp(2, 4);
  BasketCourt get court => match.me;

  @override
  void initState() {
    super.initState();
    fx = ArcadeFx(enabled: l.fancyEffects && !l.reducedMotion, skin: skin);
    final int seed = l.net?.seed ?? l.seed ?? 9;
    final double sk = botSkillFor(l.daily ? BotDifficulty.hard : l.difficulty);
    match = BasketMatch(
      seed: seed + me * 101,
      botSkills: l.online ? const <double>[] : <double>[for (int i = 1; i < seats; i++) (sk + (i - 1) * 0.04).clamp(0.0, 1.0)],
    );
    unawaited(skin.load().then((_) => mounted ? setState(() {}) : null));
    final NetLink? n = l.net;
    if (n != null) {
      rt = ArcadeRt(n, hz: 6)
        ..onMove = (NetMove m) {
          if (m.data['t'] == 'fin') {
            _fin[(m.data['s'] as num).toInt()] = BasketLine(
                (m.data['sc'] as num?)?.toInt() ?? 0, (m.data['m'] as num?)?.toInt() ?? 0, (m.data['sh'] as num?)?.toInt() ?? 0);
          }
        }
        ..start();
    }
  }

  @override
  void dispose() {
    rt?.dispose();
    super.dispose();
  }

  void _say(String s, [double t = 1.1]) {
    _banner = s;
    _bannerT = t;
  }

  /// World → screen.
  Offset _scr(double x, double y, double z) {
    final CanvasPoint p = BasketCamera.project(x, y, z);
    return Offset(_lay.ox + p.x * _lay.scale, _lay.oy + p.y * _lay.scale);
  }

  BasketLine lineOf(int seat) {
    if (seat == me) return BasketLine(court.score, court.made, court.shots);
    if (!l.online) {
      final BasketBot b = match.bots[seat - 1];
      return BasketLine(b.score, b.made, b.shots);
    }
    final BasketLine? f = _fin[seat];
    if (f != null) return f;
    final Map<String, dynamic>? st = rt?.states[seat];
    int v(String k) => (st?[k] as num?)?.toInt() ?? 0;
    return BasketLine(v('sc'), v('m'), v('sh'));
  }

  int scoreOf(int seat) => lineOf(seat).score;

  @override
  void tick(double dt) {
    if (_bannerT > 0) {
      _bannerT -= dt;
      if (_bannerT <= 0) _banner = '';
    }
    match.step(dt);
    if (court.countdown > 0) _banner = '${court.countdown.ceil()}';
    for (int i = 0; i < match.bots.length; i++) {
      final int pts = match.botPoints[i];
      if (pts > 0) fx.text('+$pts', Offset(70.0 + i * 74, _pad.top + 100), skin.player(i + 1), size: 16);
    }
    for (final BEvent e in court.events) {
      final Offset at = _scr(e.x, e.y, e.z);
      switch (e.kind) {
        case 'go':
          _say('GO!', 0.7);
          HapticFeedback.lightImpact();
        case 'horn':
          _say(l.tx('پایان وقت!', "TIME'S UP!"), 2);
          HapticFeedback.heavyImpact();
        case 'swish':
        case 'score':
          _netSway = 1;
          _netStretch = 1;
          fx.burst(at + Offset(0, 14 * _lay.scale), court.shotOnFire ? const Color(0xFFFF6A1D) : skin.accent2,
              count: 26, speed: 220, size: 3.5, kind: ParticleKind.orb, gravity: 300);
          fx.text('+${e.value}', at - Offset(0, 46 * _lay.scale), e.kind == 'swish' ? const Color(0xFF7CFF7A) : Colors.white,
              size: 30);
          if (e.kind == 'swish') _say(l.tx('سوییش!', 'SWISH!'));
          HapticFeedback.mediumImpact();
        case 'fire':
          _say(l.tx('آتشین! امتیاز دوبرابر', 'ON FIRE! x2'), 1.4);
          fx.flashScreen(const Color(0xFFFF6A1D), 0.25);
        case 'fireout':
          _say(l.tx('آتش خاموش شد', 'Fire out'), 0.9);
        case 'rim':
          _netSway = math.max(_netSway, 0.5);
          fx.burst(at, Colors.white, count: 6, speed: 100, size: 2);
          HapticFeedback.selectionClick();
        case 'board':
          fx.shake(1.5);
          HapticFeedback.selectionClick();
        case 'floor':
        case 'miss':
          break;
      }
    }
    court.events.clear();
    _netSway = math.max(0, _netSway - dt * 1.6);
    _netStretch = math.max(0, _netStretch - dt * 2.5);
    if (court.phase == BallPhase.flying || court.phase == BallPhase.dead) {
      final CanvasPoint p = BasketCamera.project(court.x, court.y, court.z);
      _trail.add(Offset(p.x, p.y));
      if (_trail.length > 14) _trail.removeAt(0);
    } else if (_trail.isNotEmpty) {
      _trail.clear();
    }
    final ArcadeRt? r = rt;
    if (r != null) {
      r.pump(dt, () => <String, dynamic>{'sc': court.score, 'st': court.streak, 'm': court.made, 'sh': court.shots});
    }
    if (match.over && !_done) {
      if (!_sentFin) {
        _sentFin = true;
        _fin[me] = BasketLine(court.score, court.made, court.shots);
        if (r != null) {
          unawaited(r.log(<String, dynamic>{'t': 'fin', 's': me, 'sc': court.score, 'm': court.made, 'sh': court.shots}));
        }
        _endWait = 0;
      }
      _endWait += dt;
      final bool all = r == null || r.activeSeats.every((int s) => _fin.containsKey(s));
      if (all || _endWait > 5) _finish();
    }
    fx.update(dt);
  }

  void _finish() {
    if (_done) return;
    _done = true;
    final Set<int> forfeited = rt?.net.forfeitedSeats ?? const <int>{};
    final Map<int, BasketLine> lines = <int, BasketLine>{for (int s = 0; s < seats; s++) s: lineOf(s)};
    final GameResult res = basketResult(l, lines, forfeited: forfeited, durationMs: (court.time * 1000).round());
    if (res.outcome == GameOutcome.win) fx.confetti(_scr(court.hoopX, kRimHeight, kRimZ), count: 70);
    Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      l.onFinish(res);
    });
  }

  // ------------------------------------------------------------------ input
  void _panStart(DragStartDetails d) {
    if (!court.ready || !court.clockRunning) return;
    _swipeA = d.localPosition;
    _swipe
      ..clear()
      ..add(d.localPosition);
  }

  void _panUpdate(DragUpdateDetails d) {
    if (_swipeA == null) return;
    _swipe.add(d.localPosition);
    if (_swipe.length > 16) _swipe.removeAt(1);
  }

  void _panEnd(DragEndDetails d) {
    final Offset? a = _swipeA;
    _swipeA = null;
    if (a == null || _swipe.isEmpty) return;
    final Offset v = (_swipe.last - a) / _lay.scale;
    if (court.throwBall(v.dx, v.dy)) HapticFeedback.lightImpact();
    _swipe.clear();
  }

  void _panCancel() {
    _swipeA = null;
    _swipe.clear();
  }

  // ------------------------------------------------------------------ render
  void _paint(Canvas canvas, Size size) {
    paintBackdrop(canvas, size, skin, time);
    final Offset sh = fx.shakeOffset;
    canvas.save();
    canvas.translate(_lay.ox + sh.dx, _lay.oy + sh.dy);
    canvas.scale(_lay.scale);
    // the canvas' visible extent (the court continues past the 360x640 frame into the letterbox)
    final Rect vis = Rect.fromLTRB(-_lay.ox / _lay.scale, -_lay.oy / _lay.scale, (size.width - _lay.ox) / _lay.scale,
        (size.height - _lay.oy) / _lay.scale);
    if (!skin.drawSprite(canvas, 'court', const Rect.fromLTWH(0, 0, kCanvasW, kCanvasH))) _paintArena(canvas, vis);
    _paintStanchion(canvas);
    final double bx = court.x, bz = court.z;
    final double hd = math.sqrt((bx - court.hoopX) * (bx - court.hoopX) + (bz - kRimZ) * (bz - kRimZ));
    final bool behindBoard = bz > kBoardZ;
    final bool aroundRim = hd < kRimRingR + kBallR;
    final bool behindRim = !aroundRim && bz > kRimZ;
    if (behindBoard) _paintBall(canvas);
    _paintBoard(canvas);
    if (!behindBoard && behindRim) _paintBall(canvas);
    _paintRim(canvas, front: false);
    if (aroundRim && !behindBoard) _paintBall(canvas);
    _paintRim(canvas, front: true);
    if (!behindBoard && !behindRim && !aroundRim) _paintBall(canvas);
    canvas.restore();
    // swipe trail (screen space)
    if (_swipe.length > 1) {
      final Path p = Path()..moveTo(_swipe.first.dx, _swipe.first.dy);
      for (final Offset o in _swipe.skip(1)) {
        p.lineTo(o.dx, o.dy);
      }
      paintNeonPath(canvas, p, skin.accent2, width: 3, glow: 8);
    }
    fx.paint(canvas);
    fx.paintFlash(canvas, size);
  }

  Offset _p(double x, double y, double z) {
    final CanvasPoint p = BasketCamera.project(x, y, z);
    return Offset(p.x, p.y);
  }

  void _paintArena(Canvas canvas, Rect vis) {
    const double wallZ = kBaselineZ + 2.2;
    final double wallY = _p(0, 0, wallZ).dy;
    // back wall / stands
    final Rect wall = Rect.fromLTRB(vis.left, vis.top, vis.right, wallY);
    canvas.drawRect(
        wall,
        Paint()
          ..shader = ui.Gradient.linear(wall.topCenter, wall.bottomCenter,
              <Color>[const Color(0x00000000), const Color(0x552A1A44)]));
    for (int i = 0; i < 3; i++) {
      final double x = 60.0 + i * 120;
      canvas.drawPath(
          Path()
            ..moveTo(x - 8, vis.top)
            ..lineTo(x + 8, vis.top)
            ..lineTo(x + 70, wallY)
            ..lineTo(x - 70, wallY)
            ..close(),
          Paint()
            ..shader = ui.Gradient.linear(Offset(x, vis.top), Offset(x, wallY),
                <Color>[Colors.white.withValues(alpha: 0.07), Colors.white.withValues(alpha: 0)]));
    }
    // hardwood floor (y = 0), from the wall to the bottom of the screen
    final Rect floor = Rect.fromLTRB(vis.left, wallY, vis.right, vis.bottom);
    canvas.drawRect(
        floor,
        Paint()
          ..shader = ui.Gradient.linear(
              floor.topCenter, floor.bottomCenter, <Color>[const Color(0xFF8A5428), const Color(0xFFC07A3E)]));
    // planks run towards the hoop: lines of constant x on the floor
    final Paint plank = Paint()
      ..color = const Color(0x22000000)
      ..strokeWidth = 0.8;
    for (double x = -8; x <= 8; x += 0.5) {
      canvas.drawLine(_p(x, 0, wallZ), _p(x, 0, -2.4), plank);
    }
    canvas.drawLine(Offset(vis.left, wallY), Offset(vis.right, wallY), Paint()
      ..color = const Color(0x55FFFFFF)
      ..strokeWidth = 1.5);
    final Paint line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = const Color(0xCCFFFFFF);
    // paint (key) and lines: 5 cm wide in reality, kept readable
    final Path key = Path()
      ..moveTo(_p(-kLaneW / 2, 0, kReleaseZ).dx, _p(-kLaneW / 2, 0, kReleaseZ).dy)
      ..lineTo(_p(-kLaneW / 2, 0, kBaselineZ).dx, _p(-kLaneW / 2, 0, kBaselineZ).dy)
      ..lineTo(_p(kLaneW / 2, 0, kBaselineZ).dx, _p(kLaneW / 2, 0, kBaselineZ).dy)
      ..lineTo(_p(kLaneW / 2, 0, kReleaseZ).dx, _p(kLaneW / 2, 0, kReleaseZ).dy)
      ..close();
    canvas.drawPath(key, Paint()..color = const Color(0x33B4410E));
    canvas.drawPath(key, line);
    canvas.drawLine(_p(-8, 0, kBaselineZ), _p(8, 0, kBaselineZ), line);
    // no-charge semicircle (1.25 m around the point under the basket)
    final Path arc = Path();
    for (int i = 0; i <= 24; i++) {
      final double a = math.pi * i / 24;
      final Offset o = _p(1.25 * math.cos(a), 0, kRimZ - 1.25 * math.sin(a));
      i == 0 ? arc.moveTo(o.dx, o.dy) : arc.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(arc, line);
  }

  void _paintStanchion(Canvas canvas) {
    final double hx = court.hoopX;
    const double z = kBaselineZ + 0.9;
    final Offset base = _p(hx, 0, z), top = _p(hx, kBoardBottom + 0.3, z);
    final double w = 0.18 * BasketCamera.project(hx, 0, z).scale;
    canvas.drawRect(Rect.fromLTRB(base.dx - w / 2, top.dy, base.dx + w / 2, base.dy), Paint()..color = const Color(0xFF3A3F4C));
    final double pw = 1.0 * BasketCamera.project(hx, 0, z).scale;
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(base.dx - pw / 2, base.dy - pw * 0.35, base.dx + pw / 2, base.dy), const Radius.circular(2)),
        Paint()..color = const Color(0xFF2B2F3A));
  }

  /// Backboard rectangle on the canvas (exactly the physics plate).
  static Rect boardRect(double hoopX) {
    final ({double l, double t, double r, double b}) q = boardOnCanvas(hoopX, kBoardW, kBoardBottom, kBoardH, kBoardZ);
    return Rect.fromLTRB(q.l, q.t, q.r, q.b);
  }

  void _paintBoard(Canvas canvas) {
    final double hx = court.hoopX;
    final Rect board = boardRect(hx);
    if (skin.drawSprite(canvas, 'hoop', board)) return;
    final double s = BasketCamera.project(hx, 0, kBoardZ).scale;
    canvas.drawRect(board.shift(Offset(0.04 * s, 0.06 * s)), Paint()
      ..color = const Color(0x44000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawRect(board, Paint()..color = const Color(0x40DDEEFF));
    final double bw = math.max(1.2, 0.05 * s);
    canvas.drawRect(board.deflate(bw / 2), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = bw
      ..color = Colors.white);
    final Rect sq = Rect.fromPoints(_p(hx - kSquareW / 2, kRimHeight + kSquareH, kBoardZ), _p(hx + kSquareW / 2, kRimHeight, kBoardZ));
    canvas.drawRect(sq.deflate(bw / 2), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = bw
      ..color = const Color(0xFFFF4D3D));
    if (court.onFire) paintGlow(canvas, board.center, board.width * 0.6, const Color(0xFFFF6A1D), 0.35);
    // bracket from the board to the back of the ring
    final Offset b0 = _p(hx, kRimHeight - 0.03, kBoardZ), b1 = _p(hx, kRimHeight - 0.03, kRimZ + kRimRingR);
    canvas.drawLine(b0, b1, Paint()
      ..color = const Color(0xFF8A2A14)
      ..strokeWidth = math.max(1.5, 0.05 * s));
  }

  /// Ring (exact torus centre line, projected) and the net: back half before the ball, front half after it.
  void _paintRim(Canvas canvas, {required bool front}) {
    final double hx = court.hoopX;
    const int n = 48;
    final double s = BasketCamera.project(hx, kRimHeight, kRimZ).scale;
    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.6, 2 * kRimTubeR * s)
      ..color = front ? const Color(0xFFFF5A2A) : const Color(0xFFB8361E);
    // net: 12 strings to a narrower bottom ring, swaying after makes
    final Paint net = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 0.9
      ..style = PaintingStyle.stroke;
    final double sway = math.sin(time * 18) * _netSway * 0.04;
    final double len = kNetLen * (1 + 0.18 * _netStretch);
    Offset netPt(double a, double t) {
      final double r = kRimRingR * (1 - 0.4 * t);
      return _p(hx + r * math.cos(a) + sway * t, kRimHeight - kRimTubeR - len * t, kRimZ + r * math.sin(a));
    }

    for (int i = 0; i < 12; i++) {
      final double a = math.pi * 2 * i / 12;
      if ((math.sin(a) < 0) != front) continue; // sin < 0: nearer the camera
      final double a2 = a + math.pi / 12;
      // diamond mesh: each string zig-zags to its neighbour
      canvas.drawPath(
          Path()
            ..moveTo(netPt(a, 0).dx, netPt(a, 0).dy)
            ..lineTo(netPt(a2, 0.34).dx, netPt(a2, 0.34).dy)
            ..lineTo(netPt(a, 0.67).dx, netPt(a, 0.67).dy)
            ..lineTo(netPt(a2, 1).dx, netPt(a2, 1).dy),
          net);
      canvas.drawPath(
          Path()
            ..moveTo(netPt(a2 + math.pi / 12, 0).dx, netPt(a2 + math.pi / 12, 0).dy)
            ..lineTo(netPt(a2, 0.34).dx, netPt(a2, 0.34).dy)
            ..lineTo(netPt(a + math.pi / 6, 0.67).dx, netPt(a + math.pi / 6, 0.67).dy)
            ..lineTo(netPt(a2, 1).dx, netPt(a2, 1).dy),
          net);
    }
    final Path p = Path();
    bool open = false;
    for (int i = 0; i <= n; i++) {
      final double a = math.pi * 2 * i / n;
      final bool near = math.sin(a) < 0;
      if (near != front) {
        open = false;
        continue;
      }
      final Offset o = _p(hx + kRimRingR * math.cos(a), kRimHeight - kRimTubeR, kRimZ + kRimRingR * math.sin(a));
      if (!open) {
        p.moveTo(o.dx, o.dy);
        open = true;
      } else {
        p.lineTo(o.dx, o.dy);
      }
    }
    canvas.drawPath(p, ring);
  }

  void _paintBall(Canvas canvas) {
    if (court.phase == BallPhase.idle) return;
    final ({double cx, double cy, double r}) bc = ballOnCanvas(court.x, court.y, court.z, kBallR);
    final Offset c = Offset(bc.cx, bc.cy);
    final double r = bc.r;
    // floor shadow straight below the ball
    final CanvasPoint fp = BasketCamera.project(court.x, 0, court.z);
    final double hgt = (court.y - kBallR).clamp(0.0, 6.0);
    final double sw = kBallR * 2 * fp.scale * (1 + hgt * 0.15);
    final double flat = (BasketCamera.camY / (court.z - BasketCamera.camZ)).clamp(0.08, 1.0);
    paintShadow(canvas, Offset(fp.x, fp.y), sw, sw * flat, 0.45 * (1 - hgt / 6));
    // trail / fire
    for (int i = 0; i < _trail.length; i++) {
      final double k = i / _trail.length;
      canvas.drawCircle(_trail[i], r * k * 0.8,
          Paint()..color = (court.onFire ? const Color(0xFFFF6A1D) : Colors.white).withValues(alpha: 0.14 * k));
    }
    if (court.onFire) paintGlow(canvas, c, r * 2.4, const Color(0xFFFF6A1D), 0.6);
    if (skin.drawSprite(canvas, 'ball', Rect.fromCircle(center: c, radius: r), angle: court.angle)) return;
    paintSphere(canvas, c, r, const Color(0xFFE8731E), shadow: false);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(court.angle);
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: r)));
    final Paint seam = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, r * 0.07)
      ..color = const Color(0xFF2A140A);
    // backspin: the horizontal seam rolls over the top of the ball
    final double ry = math.sin(court.roll) * r;
    canvas.drawLine(Offset(-r, ry), Offset(r, ry), seam);
    canvas.drawLine(Offset(0, -r), Offset(0, r), seam);
    canvas.drawArc(Rect.fromCircle(center: Offset(-r * 1.25, 0), radius: r), -0.9, 1.8, false, seam);
    canvas.drawArc(Rect.fromCircle(center: Offset(r * 1.25, 0), radius: r), math.pi - 0.9, 1.8, false, seam);
    canvas.restore();
  }

  @override
  Widget build(BuildContext context) {
    _pad = MediaQuery.paddingOf(context);
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints box) {
      _lay = BasketLayout.fit(box.maxWidth, box.maxHeight,
          padTop: _pad.top, padBottom: _pad.bottom, padLeft: _pad.left, padRight: _pad.right);
      return Stack(fit: StackFit.expand, children: <Widget>[
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: _panStart,
          onPanUpdate: _panUpdate,
          onPanEnd: _panEnd,
          onPanCancel: _panCancel,
          child: CustomPaint(painter: ArcadePainter(_paint, frame), size: Size.infinite),
        ),
        ValueListenableBuilder<int>(
          valueListenable: frame,
          builder: (_, __, ___) {
            final double left = court.countdown > 0 ? court.duration : court.left;
            return Stack(children: <Widget>[
              Positioned(
                top: _pad.top + 62,
                left: _pad.left + 12,
                right: _pad.right + 12,
                child: Row(children: <Widget>[
                  Expanded(
                    child: Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
                      for (int s = 0; s < seats; s++)
                        ArcadeHudPill(
                          key: ValueKey<String>('bb-seat-$s'),
                          color: s == me ? skin.accent : skin.player(s),
                          child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                            Icon(s == me ? Icons.person_rounded : (l.online ? Icons.public_rounded : Icons.smart_toy_rounded),
                                size: 13, color: skin.player(s)),
                            const SizedBox(width: 4),
                            Text('${scoreOf(s)}', style: const TextStyle(fontSize: 14)),
                          ]),
                        ),
                    ]),
                  ),
                  ArcadeHudPill(
                    key: const ValueKey<String>('bb-clock'),
                    color: left <= 10 ? const Color(0xFFFF2D55) : skin.accent2,
                    child: Text(basketClock(left), style: const TextStyle(fontSize: 16)),
                  ),
                ]),
              ),
              if (court.onFire)
                Positioned(
                  top: _lay.oy + 8 * _lay.scale,
                  left: 0,
                  right: 0,
                  child: Center(
                      child: ArcadeHudPill(
                          color: const Color(0xFFFF6A1D),
                          child: Text(l.tx('آتشین x2', 'ON FIRE x2'), style: const TextStyle(fontSize: 12)))),
                ),
              if (_banner.isNotEmpty)
                Positioned(
                    left: 0,
                    right: 0,
                    top: _lay.oy + 400 * _lay.scale,
                    child: IgnorePointer(
                        child: Center(child: ArcadeBanner(_banner, color: skin.accent, size: _banner.length > 3 ? 36 : 64)))),
              if (court.clockRunning && court.shots == 0)
                Positioned(
                  left: 0,
                  right: 0,
                  top: _lay.oy + 500 * _lay.scale,
                  child: IgnorePointer(
                    child: Center(
                      child: Text(l.tx('انگشتت را رو به سبد بکش', 'Swipe up towards the hoop'),
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
            ]);
          },
        ),
      ]);
    });
  }
}
