import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../arcade_kit/arcade_controls.dart';
import '../../arcade_kit/arcade_fx.dart';
import '../../arcade_kit/arcade_joystick.dart';
import '../../arcade_kit/arcade_loop.dart';
import '../../arcade_kit/arcade_net.dart';
import '../../arcade_kit/arcade_result.dart';
import '../../arcade_kit/arcade_skin.dart';
import '../../core/game_contract.dart';
import '../core/bomb_core.dart';
import 'bomb_layout.dart';

/// Sprite keys: player_0..3, bomb, crate, wall, floor, pu_range, pu_bomb, pu_speed, pu_trap.
ArcadeSkin bombSkin() => ArcadeSkin(
      gameId: 'bomb_arena',
      bgTop: const Color(0xFF1A1030),
      bgBottom: const Color(0xFF07040F),
      accent: const Color(0xFFFF4D3D),
      accent2: const Color(0xFFFFB13D),
      glow: const Color(0xFFFF7A3D),
      players: const <Color>[Color(0xFFF5F7FF), Color(0xFF39C6FF), Color(0xFFFF4F9A), Color(0xFF7CFF7A)],
    );

/// Match result from this phone's point of view: a drawn match (leaders tied on round wins) reports
/// [GameOutcome.draw] to the tied players and an empty winner list.
GameResult bombResult(GameLaunch l, BombMatch m) {
  final List<int> order = m.ranking();
  final int me = l.mySeat;
  final int kos = m.totalKills[me];
  final String fa = '$kos حذف · ${m.wins[me]} راند', en = '$kos KOs · ${m.wins[me]} rounds';
  if (!m.isDraw) return rankedResult(l, order, whatFa: fa, whatEn: en);
  final List<int> leaders = m.leaders;
  final GameResult base = rankedResult(l, order, whatFa: fa, whatEn: en);
  final bool tied = leaders.contains(me);
  return GameResult(
    outcome: tied ? GameOutcome.draw : GameOutcome.loss,
    score: base.score,
    opponentScore: base.opponentScore,
    winnerSeats: const <int>[],
    scores: base.scores,
    summaryFa: tied ? '$fa · مساوی' : base.summaryFa,
    summaryEn: tied ? '$en · draw' : base.summaryEn,
    tournamentMatchId: l.tournamentMatchId,
  );
}

class BombGame extends StatefulWidget {
  const BombGame({super.key, required this.launch});
  final GameLaunch launch;

  @override
  State<BombGame> createState() => _BombGameState();
}

class _BombGameState extends ArcadeLoopState<BombGame> {
  late final BombMatch match;
  late final ArcadeSkin skin = bombSkin();
  late final ArcadeFx fx;
  ArcadeRt? rt;
  double _jx = 0, _jy = 0;
  bool _bombTap = false, _trapTap = false;
  int _bombSeq = 0, _trapSeq = 0;
  final Map<int, int> _seenBomb = <int, int>{}, _seenTrap = <int, int>{};
  bool _done = false;
  String _banner = '';
  double _bannerFor = 0;
  double _spectate = -1;
  BombLayout? _layout;

  /// Last layout (tests check alignment and safe areas against it).
  @visibleForTesting
  BombLayout? get debugLayout => _layout;

  BombArena get arena => match.arena;
  GameLaunch get l => widget.launch;
  int get me => l.mySeat;
  int get seats => (l.net?.seatCount ?? l.playerCount).clamp(2, 4);
  bool get host => rt == null || rt!.isHost;

  @override
  void initState() {
    super.initState();
    fx = ArcadeFx(enabled: l.fancyEffects && !l.reducedMotion, skin: skin);
    final double sk = botSkillFor(l.daily ? BotDifficulty.hard : l.difficulty);
    match = BombMatch(
      seed: l.net?.seed ?? l.seed ?? 5,
      count: seats,
      botSkill: l.online ? const <double>[] : <double>[for (int i = 0; i < seats; i++) i == me ? 0 : sk],
    );
    unawaited(skin.load().then((_) => mounted ? setState(() {}) : null));
    final NetLink? n = l.net;
    if (n != null) {
      rt = ArcadeRt(n, hz: 14)
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
    if (m.data['t'] == 'end') {
      if (m.data['s'] is Map<String, dynamic>) match.applySnapshot(m.data['s'] as Map<String, dynamic>);
      _finish();
    }
  }

  /// Stick → input: radial dead zone, full speed past it (Bomberman movement is digital); the minor axis is
  /// kept so the core can use it to turn corners.
  (double, double) _stick() {
    final double mag = math.sqrt(_jx * _jx + _jy * _jy);
    if (mag < 0.28) return (0, 0);
    return (_jx / mag, _jy / mag);
  }

  @override
  void tick(double dt) {
    final (double dx, double dy) = _stick();
    final ArcadeRt? r = rt;
    if (host) {
      match.input(me, dx, dy);
      if (_bombTap) match.placeBomb(me);
      if (_trapTap) match.placeTrap(me);
      if (r != null) {
        r.states.forEach((int seat, Map<String, dynamic> st) {
          if (seat == me || seat >= arena.players.length) return;
          match.input(seat, ((st['x'] as num?) ?? 0).toDouble(), ((st['y'] as num?) ?? 0).toDouble());
          final int b = ((st['b'] as num?) ?? 0).toInt(), t = ((st['t'] as num?) ?? 0).toInt();
          if (b > (_seenBomb[seat] ?? 0)) {
            _seenBomb[seat] = b;
            match.placeBomb(seat);
          }
          if (t > (_seenTrap[seat] ?? 0)) {
            _seenTrap[seat] = t;
            match.placeTrap(seat);
          }
        });
        for (final int s in r.net.forfeitedSeats) {
          if (s < arena.players.length) match.forfeit(s);
        }
        for (final int s in r.activeSeats) {
          if (s != me && s < arena.players.length && r.isStale(s, const Duration(seconds: 3))) match.input(s, 0, 0);
        }
      }
      // offline, once knocked out: watch the rest of the round at 4x
      int speed = 1;
      if (r == null && !arena.players[me].alive && !arena.over && match.intermission <= 0) {
        _spectate = _spectate < 0 ? 1.2 : _spectate - dt;
        if (_spectate <= 0) speed = 4;
      } else {
        _spectate = -1;
      }
      if (!_done) match.step(dt, speedUp: speed);
      if (r != null) r.pumpSnapshot(dt, match.snapshot);
      if (!_done && match.over) {
        if (r != null) unawaited(r.log(<String, dynamic>{'t': 'end', 'o': match.ranking(), 's': match.snapshot()}));
        _finish();
      }
    } else if (r != null) {
      if (_bombTap) _bombSeq++;
      if (_trapTap) _trapSeq++;
      r.pump(dt, () => <String, dynamic>{'x': dx, 'y': dy, 'b': _bombSeq, 't': _trapSeq}, event: 'in');
      final Map<String, dynamic>? s = r.snapshot;
      if (s != null) {
        match.applySnapshot(s);
        r.snapshot = null;
      }
      // countdown runs locally until the first snapshot
      if (arena.time == 0 && arena.countdown > 0) arena.countdown = math.max(0, arena.countdown - dt);
    }
    _bombTap = false;
    _trapTap = false;
    _updateBanner(dt);
    _consumeEvents();
    fx.update(dt);
  }

  String _seatName(int s) => l.netName(s) ?? (s == me ? l.tx('شما', 'YOU') : l.tx('ربات ${s + 1}', 'BOT ${s + 1}'));

  void _say(String text, double seconds) {
    _banner = text;
    _bannerFor = seconds;
  }

  void _updateBanner(double dt) {
    if (_bannerFor > 0) {
      _bannerFor -= dt;
      if (_bannerFor <= 0) _banner = '';
      return;
    }
    if (match.intermission > 0 || match.over) return;
    if (arena.countdown > 0) {
      _banner = arena.countdown > 1 || match.round == 1
          ? '${arena.countdown.ceil()}'
          : l.tx('راند ${match.round}', 'ROUND ${match.round}');
    } else if (arena.time < 0.8) {
      _banner = l.tx('برو!', 'GO!');
    } else {
      _banner = '';
    }
  }

  void _consumeEvents() {
    final BombLayout? lay = _layout;
    final double t = lay?.tile ?? 28;
    for (final BEvent e in match.events) {
      final Offset at = lay?.toScreen(e.x, e.y) ?? Offset.zero;
      switch (e.kind) {
        case 'boom':
          fx.burst(at, const Color(0xFFFFB13D), count: 26, speed: t * 6, size: t * 0.12, life: 0.5, kind: ParticleKind.orb);
          fx.burst(at, const Color(0xFF555566), count: 8, speed: t * 1.6, size: t * 0.3, life: 1.0, kind: ParticleKind.smoke);
          fx.shake(7);
          HapticFeedback.mediumImpact();
        case 'crate':
          fx.burst(at, const Color(0xFFB07A3E), count: 12, speed: t * 4, size: t * 0.14, life: 0.6, kind: ParticleKind.shard, gravity: t * 6);
        case 'pickup':
          fx.ring(at, skin.accent2, size: t * 0.4, life: 0.4);
          if (e.seat == me) HapticFeedback.lightImpact();
        case 'stun':
          fx.burst(at, const Color(0xFFFFE14D), count: 14, speed: t * 3, size: t * 0.1);
        case 'drop':
          fx.burst(at, const Color(0xFF8A93B5), count: 6, speed: t * 2, size: t * 0.12, life: 0.4, kind: ParticleKind.shard);
          fx.shake(2);
        case 'hurry':
          _say(l.tx('عجله کن!', 'HURRY UP!'), 1.6);
        case 'out':
          fx.burst(at, skin.player(e.seat), count: 30, speed: t * 5, size: t * 0.12, kind: ParticleKind.orb);
          if (e.seat == me) {
            _say(l.tx('حذف شدی!', 'KNOCKED OUT!'), 1.4);
            fx.flashScreen(const Color(0xFFFF2D55));
            HapticFeedback.heavyImpact();
          }
        case 'roundEnd':
          _say(
              e.seat < 0
                  ? l.tx('مساوی!', 'DRAW!')
                  : e.seat == me
                      ? l.tx('راند مال تو!', 'ROUND WON!')
                      : l.tx('${_seatName(e.seat)} برد', '${_seatName(e.seat)} WINS'),
              BombMatch.intermissionTime - 0.4);
      }
    }
    match.events.clear();
  }

  void _finish() {
    if (_done) return;
    _done = true;
    if (match.isDraw) {
      _say(l.tx('مساوی!', 'DRAW!'), 99);
    } else if (match.winner == me) {
      _say(l.tx('برنده!', 'WINNER!'), 99);
      final BombLayout? lay = _layout;
      if (lay != null) fx.confetti(lay.toScreen(arena.players[me].x, arena.players[me].y), count: 50);
    } else {
      _say(l.tx('${_seatName(match.winner)} برد', '${_seatName(match.winner)} WINS'), 99);
    }
    l.onFinish(bombResult(l, match));
  }

  // ------------------------------------------------------------------ render
  void _paint(Canvas canvas, Size size) {
    paintBackdrop(canvas, size, skin, time);
    final BombLayout lay = _layout ?? BombLayout.compute(size, MediaQuery.paddingOf(context), MediaQuery.devicePixelRatioOf(context));
    final double tile = lay.tile;
    final Offset sh = fx.shakeOffset;
    canvas.save();
    canvas.translate(lay.origin.dx + sh.dx * 0.6, lay.origin.dy + sh.dy * 0.6);
    canvas.scale(tile);
    const double fr = BombLayout.frame;
    paintBlock(canvas, Rect.fromLTWH(-fr, -fr, BombArena.w + 2 * fr, BombArena.h + 2 * fr), const Color(0xFF2B1F4A),
        radius: 0.4, depth: 0.2);
    canvas.save();
    canvas.clipRect(const Rect.fromLTWH(0, 0, BombArena.w * 1.0, BombArena.h * 1.0));
    for (int y = 0; y < BombArena.h; y++) {
      for (int x = 0; x < BombArena.w; x++) {
        final Rect r = Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1);
        if (arena.grid[y][x] != '#' || !BombArena.isFixedWall(x, y)) {
          if (!skin.drawSprite(canvas, 'floor', r)) {
            canvas.drawRect(r, Paint()..color = (x + y).isEven ? const Color(0xFF3A6B4E) : const Color(0xFF336147));
          }
        }
      }
    }
    // soft contact shadows under walls / crates (inside the tile below, never outside the board)
    for (int y = 0; y < BombArena.h; y++) {
      for (int x = 0; x < BombArena.w; x++) {
        if (arena.grid[y][x] != '.') {
          canvas.drawRect(Rect.fromLTWH(x + 0.08, y + 0.86, 0.92, 0.14), Paint()..color = const Color(0x40000000));
        }
      }
    }
    // traps (own traps visible, enemy traps faint)
    for (final Trap t in arena.traps) {
      final Offset c = Offset(t.tx + 0.5, t.ty + 0.5);
      final double a = t.owner == me ? 0.9 : 0.18;
      for (int i = 0; i < 4; i++) {
        final double ang = i * math.pi / 2 + math.pi / 4;
        canvas.drawLine(c, c + Offset(math.cos(ang), math.sin(ang)) * 0.3, Paint()
          ..strokeWidth = 0.07
          ..color = Color.fromRGBO(255, 225, 77, a));
      }
      canvas.drawCircle(c, 0.12, Paint()..color = Color.fromRGBO(180, 180, 200, a));
    }
    // power-ups
    arena.powerups.forEach((int k, Pu p) {
      final Offset c = Offset(k % BombArena.w + 0.5, k ~/ BombArena.w + 0.5 + math.sin(time * 4 + k) * 0.04);
      final (Color col, IconData icon, String key) = switch (p) {
        Pu.range => (const Color(0xFFFF7A3D), Icons.local_fire_department_rounded, 'pu_range'),
        Pu.bomb => (const Color(0xFF39C6FF), Icons.add_circle_rounded, 'pu_bomb'),
        Pu.speed => (const Color(0xFF7CFF7A), Icons.bolt_rounded, 'pu_speed'),
        Pu.trap => (const Color(0xFFFFE14D), Icons.warning_amber_rounded, 'pu_trap'),
      };
      paintGlow(canvas, c, 0.5, col, 0.5);
      if (!skin.drawSprite(canvas, key, Rect.fromCenter(center: c, width: 0.72, height: 0.72))) {
        paintBlock(canvas, Rect.fromCenter(center: c, width: 0.66, height: 0.66), col, radius: 0.16, depth: 0.06, shadow: false);
        _icon(canvas, icon, c, 0.46);
      }
    });
    // walls + crates: drawn exactly inside their tile (what you see is what blocks you)
    for (int y = 0; y < BombArena.h; y++) {
      for (int x = 0; x < BombArena.w; x++) {
        final String c = arena.grid[y][x];
        final Rect r = Rect.fromLTWH(x + 0.02, y + 0.02, 0.96, 0.96);
        if (c == '#') {
          if (!skin.drawSprite(canvas, 'wall', Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1))) {
            final bool sd = !BombArena.isFixedWall(x, y);
            paintBlock(canvas, r, sd ? const Color(0xFF7A6B9C) : const Color(0xFF5E6B8C), radius: 0.12, depth: 0.14, shadow: false);
            canvas.drawRect(Rect.fromLTWH(x + 0.18, y + 0.1, 0.64, 0.07), Paint()..color = const Color(0x33FFFFFF));
          }
        } else if (c == 'c') {
          if (!skin.drawSprite(canvas, 'crate', Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1))) {
            paintBlock(canvas, r, const Color(0xFFB9803F), radius: 0.08, depth: 0.12, shadow: false);
            final Paint plank = Paint()
              ..color = const Color(0xFF7A4E22)
              ..strokeWidth = 0.05;
            canvas.drawLine(Offset(r.left + 0.12, r.top + 0.12), Offset(r.right - 0.12, r.bottom - 0.12), plank);
            canvas.drawLine(Offset(r.right - 0.12, r.top + 0.12), Offset(r.left + 0.12, r.bottom - 0.12), plank);
            canvas.drawRect(r.deflate(0.07), Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.05
              ..color = const Color(0xFF8C5A2A));
          }
        }
      }
    }
    // bombs: centred on their tile
    for (final Bomb b in arena.bombs) {
      final Offset c = Offset(b.tx + 0.5, b.ty + 0.5);
      final double pulse = 1 + 0.07 * math.sin(time * (8 + (BombArena.fuseTime - b.fuse) * 10));
      paintShadow(canvas, c + const Offset(0.03, 0.3), 0.6, 0.18, 0.5);
      if (!skin.drawSprite(canvas, 'bomb', Rect.fromCenter(center: c, width: 0.82 * pulse, height: 0.82 * pulse))) {
        paintSphere(canvas, c + const Offset(0, 0.04), 0.33 * pulse, b.fuse < 0.6 ? const Color(0xFF6B1A1A) : const Color(0xFF22222E),
            shadow: false);
        canvas.drawLine(c + const Offset(0.1, -0.22), c + const Offset(0.2, -0.36), Paint()
          ..strokeWidth = 0.06
          ..color = const Color(0xFFCDB38A));
        paintGlow(canvas, c + const Offset(0.21, -0.38), 0.18, const Color(0xFFFFD34E), 0.9);
      }
    }
    // fire: every flame fills exactly its tile
    for (final Flame f in arena.flames) {
      final Offset c = Offset(f.tx + 0.5, f.ty + 0.5);
      final double k = (f.life / BombArena.flameLife).clamp(0.0, 1.0);
      final Rect r = f.dir == 0
          ? Rect.fromCenter(center: c, width: 0.94, height: 0.94)
          : f.dir == 1
              ? Rect.fromCenter(center: c, width: 1.0, height: 0.62 * k + 0.24)
              : Rect.fromCenter(center: c, width: 0.62 * k + 0.24, height: 1.0);
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(0.3)), Paint()
        ..color = const Color(0xFFFF4D1D).withValues(alpha: 0.55 * k)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.12));
      canvas.drawRRect(RRect.fromRectAndRadius(r.deflate(0.06), const Radius.circular(0.26)), Paint()
        ..shader = ui.Gradient.radial(c, 0.6, <Color>[
          Colors.white.withValues(alpha: k),
          const Color(0xFFFFE14D).withValues(alpha: k),
          const Color(0xFFFF6A1D).withValues(alpha: 0.8 * k),
        ], const <double>[0, 0.4, 1]));
    }
    canvas.restore(); // board clip
    // players last (their heads may rise over the row above, like a sprite), sorted back to front
    final List<BPlayer> ps = List<BPlayer>.of(arena.players)..sort((BPlayer a, BPlayer b) => a.y.compareTo(b.y));
    for (final BPlayer p in ps) {
      _paintPlayer(canvas, p);
    }
    canvas.restore();
    canvas.save();
    canvas.translate(sh.dx * 0.6, sh.dy * 0.6);
    fx.paint(canvas);
    canvas.restore();
    fx.paintFlash(canvas, size);
  }

  void _icon(Canvas canvas, IconData i, Offset c, double s) {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: String.fromCharCode(i.codePoint), style: TextStyle(fontFamily: i.fontFamily, package: i.fontPackage, fontSize: s, color: Colors.white)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  /// The body is drawn centred on the player's position and inside its tile: the footprint matches the
  /// collision box (1 tile) and the fire hit test (centre tile).
  void _paintPlayer(Canvas canvas, BPlayer p) {
    if (!p.alive && arena.time - p.outAt > 0.6) return;
    final Color c = skin.player(p.seat);
    final Offset at = Offset(p.x, p.y);
    final double bob = p.moving ? math.sin(time * 16) * 0.03 : 0;
    paintShadow(canvas, at + const Offset(0, 0.36), 0.56, 0.16, 0.5);
    canvas.save();
    canvas.translate(at.dx, at.dy + bob);
    if (!p.alive) canvas.scale(math.max(0.2, 1 - (arena.time - p.outAt) / 0.6));
    if (!skin.drawSprite(canvas, 'player_${p.seat % 4}', const Rect.fromLTWH(-0.42, -0.46, 0.84, 0.92))) {
      final Rect body = Rect.fromCenter(center: const Offset(0, 0.18), width: 0.62, height: 0.5);
      canvas.drawRRect(RRect.fromRectAndRadius(body, const Radius.circular(0.22)), Paint()
        ..shader = ui.Gradient.linear(body.topCenter, body.bottomCenter, <Color>[shade(c, 0.1), shade(c, -0.25)]));
      paintSphere(canvas, const Offset(0, -0.16), 0.27, c, shadow: false);
      final double look = p.facing == 1 ? 0.05 : p.facing == 3 ? -0.05 : 0;
      final Rect v = Rect.fromCenter(center: Offset(look, -0.14), width: 0.38, height: 0.15);
      canvas.drawRRect(RRect.fromRectAndRadius(v, const Radius.circular(0.07)), Paint()..color = const Color(0xFF16182A));
      if (p.facing != 0) {
        canvas.drawCircle(Offset(look - 0.08, -0.14), 0.032, Paint()..color = const Color(0xFF7FF3FF));
        canvas.drawCircle(Offset(look + 0.08, -0.14), 0.032, Paint()..color = const Color(0xFF7FF3FF));
      }
      paintGlow(canvas, const Offset(0, -0.46), 0.08, c, 0.9);
    }
    if (p.stun > 0) {
      for (int i = 0; i < 3; i++) {
        final double a = time * 6 + i * 2.1;
        canvas.drawCircle(Offset(math.cos(a) * 0.28, -0.5 + math.sin(a) * 0.07), 0.05, Paint()..color = const Color(0xFFFFE14D));
      }
    }
    canvas.restore();
    if (p.seat == me && p.alive) {
      canvas.drawPath(
          Path()
            ..moveTo(p.x - 0.1, p.y - 0.78)
            ..lineTo(p.x + 0.1, p.y - 0.78)
            ..lineTo(p.x, p.y - 0.62)
            ..close(),
          Paint()..color = Colors.white);
    }
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets pad = MediaQuery.paddingOf(context);
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints box) {
      final Size size = box.biggest;
      final BombLayout lay = BombLayout.compute(size, pad, dpr);
      _layout = lay;
      final double band = BombLayout.controlsHeight + pad.bottom;
      final double bombSize = math.min(96, math.max(72, size.width * 0.22));
      return Stack(fit: StackFit.expand, children: <Widget>[
        CustomPaint(painter: ArcadePainter(_paint, frame), size: Size.infinite),
        ValueListenableBuilder<int>(
          valueListenable: frame,
          builder: (_, __, ___) {
            final BPlayer mine = arena.players[me];
            final int left = arena.timeLeft.ceil();
            final bool hurry = arena.time >= BombArena.suddenDeathAt - 3;
            return Stack(children: <Widget>[
              Positioned(
                top: lay.hudTop,
                left: pad.left + 12,
                right: pad.right + 12,
                height: BombLayout.hudHeight,
                child: Row(children: <Widget>[
                  Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                          for (final BPlayer p in arena.players)
                            Padding(padding: const EdgeInsets.only(right: 5), child: _seatPill(p)),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _pill(
                    hurry ? const Color(0xFFFF2D55) : skin.accent2,
                    Text('R${match.round}  ${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')}',
                        style: const TextStyle(fontSize: 13)),
                  ),
                ]),
              ),
              Positioned(
                bottom: pad.bottom + bombSize + 34,
                right: pad.right + 16,
                child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  _stat(Icons.local_fire_department_rounded, mine.range),
                  _stat(Icons.circle, mine.maxBombs),
                  _stat(Icons.bolt_rounded, mine.speedLevel),
                ]),
              ),
              if (_banner.isNotEmpty) Center(child: ArcadeBanner(_banner, color: skin.accent, size: _banner.length > 4 ? 40 : 64)),
            ]);
          },
        ),
        Positioned(
          left: 0,
          bottom: 0,
          width: size.width * 0.55,
          height: band,
          child: Padding(
            padding: EdgeInsets.only(left: pad.left, bottom: pad.bottom),
            child: ArcadeJoystick(color: skin.accent2, onChanged: (double x, double y) {
              _jx = x;
              _jy = y;
            }),
          ),
        ),
        Positioned(
          right: pad.right + 16,
          bottom: pad.bottom + 20,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
            ValueListenableBuilder<int>(
              valueListenable: frame,
              builder: (_, __, ___) => ArcadePadButton(
                icon: Icons.warning_amber_rounded,
                color: const Color(0xFFE0B21A),
                size: 54,
                enabled: arena.players[me].traps > 0,
                badge: arena.players[me].traps > 0
                    ? CircleAvatar(radius: 10, backgroundColor: Colors.white, child: Text('${arena.players[me].traps}',
                        style: const TextStyle(fontSize: 11, color: Colors.black, fontWeight: FontWeight.w900)))
                    : null,
                onDown: () => _trapTap = true,
              ),
            ),
            const SizedBox(width: 12),
            ArcadePadButton(icon: Icons.brightness_7_rounded, label: l.tx('بمب', 'BOMB'), color: skin.accent, size: bombSize,
                onDown: () => _bombTap = true),
          ]),
        ),
      ]);
    });
  }

  Widget _pill(Color color, Widget child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.black.withValues(alpha: 0.45),
          border: Border.all(color: color.withValues(alpha: 0.7)),
        ),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontFamily: 'ChakraPetch'),
          child: child,
        ),
      );

  /// Seat chip: colour, round wins (stars) and knock-outs this match.
  Widget _seatPill(BPlayer p) {
    final Color c = skin.player(p.seat);
    final int kos = match.totalKills[p.seat] + (match.over ? 0 : p.kills);
    return Opacity(
      opacity: p.alive ? 1 : 0.4,
      child: _pill(
        c,
        Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Icon(p.alive ? Icons.smart_toy_rounded : Icons.close_rounded, size: 13, color: c),
          const SizedBox(width: 2),
          Text('${match.wins[p.seat]}', style: const TextStyle(fontSize: 12)),
          const Icon(Icons.star_rounded, size: 11, color: Color(0xFFFFD34E)),
          const SizedBox(width: 2),
          Text('$kos', style: const TextStyle(fontSize: 11, color: Colors.white70)),
        ]),
      ),
    );
  }

  Widget _stat(IconData i, int v) => Padding(
        padding: const EdgeInsets.only(left: 6),
        child: _pill(
          Colors.white38,
          Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Icon(i, size: 13, color: Colors.white70),
            const SizedBox(width: 3),
            Text('$v', style: const TextStyle(fontSize: 12)),
          ]),
        ),
      );
}
