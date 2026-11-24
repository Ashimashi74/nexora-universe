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
import '../core/kart_core.dart';
import 'kart_layout.dart';

/// Sprite keys (assets/games/kart_racing/skin.json): kart_0..kart_3 (top-down kart, nose pointing right),
/// item_box, missile, oil, grass_tile, asphalt_tile.
ArcadeSkin kartSkin() => ArcadeSkin(
      gameId: 'kart_racing',
      bgTop: const Color(0xFF2E7D32),
      bgBottom: const Color(0xFF1B5E20),
      accent: const Color(0xFFFF7A1A),
      accent2: const Color(0xFFFFD34E),
      glow: const Color(0xFFFFE08A),
      players: const <Color>[Color(0xFFFF3B3B), Color(0xFF2F8BFF), Color(0xFFFFC21A), Color(0xFF2BD96B)],
    );

class KartGame extends StatefulWidget {
  const KartGame({super.key, required this.launch});
  final GameLaunch launch;

  @override
  State<KartGame> createState() => _KartGameState();
}

class _KartGameState extends ArcadeLoopState<KartGame> {
  late final KartRace race;
  late final ArcadeSkin skin = kartSkin();
  late final ArcadeFx fx;
  ArcadeRt? rt;
  final Map<int, V2> _smooth = <int, V2>{};
  int _left = 0, _right = 0;
  bool _drift = false;
  bool _itemTap = false;
  bool _done = false;
  double _endTimer = -1;
  String _banner = '';
  double _bannerTime = 0;
  bool _resolving = false;
  double _dnfTimer = -1;
  EdgeInsets _pad = EdgeInsets.zero;
  // smoothed chase camera
  V2? _camPos;
  double _camHeading = 0;
  double _camZoom = 1;
  late final List<Offset> _tufts;
  final List<Offset> _trees = <Offset>[];

  GameLaunch get l => widget.launch;
  int get me => l.mySeat;
  int get seats => (l.net?.seatCount ?? l.playerCount).clamp(2, 4);

  @override
  void initState() {
    super.initState();
    fx = ArcadeFx(enabled: l.fancyEffects && !l.reducedMotion, skin: skin);
    final int seed = l.net?.seed ?? l.seed ?? 7;
    final double sk = botSkillFor(l.daily ? BotDifficulty.hard : l.difficulty);
    race = KartRace(
      seed: seed,
      racers: seats,
      botSkill: l.online ? const <double>[] : <double>[for (int i = 0; i < seats; i++) i == 0 ? 0 : sk],
    );
    final math.Random r = math.Random(seed);
    _tufts = <Offset>[for (int i = 0; i < 320; i++) Offset(r.nextDouble() * 4400 - 2200, r.nextDouble() * 3200 - 1600)];
    for (int i = 0; i < 500 && _trees.length < 130; i++) {
      final V2 p = V2(r.nextDouble() * 4600 - 2300, r.nextDouble() * 3400 - 1700);
      // trees stand outside the tyre walls (never on the drivable area, so they need no collision)
      if (race.track.project(p).dist > race.track.wallOffset + 46) _trees.add(Offset(p.x, p.y));
    }
    unawaited(skin.load().then((_) => mounted ? setState(() {}) : null));
    final Kart k0 = race.karts[me];
    _camPos = k0.pos;
    _camHeading = k0.heading;
    final NetLink? n = l.net;
    if (n != null) {
      rt = ArcadeRt(n, hz: 12)
        ..onEvent = _onRemoteEvent
        ..onMove = _onMove
        ..start();
    }
  }

  @override
  void dispose() {
    rt?.dispose();
    super.dispose();
  }

  void _onRemoteEvent(int seat, String e, Map<String, dynamic> d) {
    if (e == 'msl') {
      final int t = (d['t'] as num).toInt();
      if (seat >= 0 && seat < race.karts.length) race.launchMissile(seat, t);
    } else if (e == 'oil') {
      race.oils.add(OilSlick(V2((d['x'] as num).toDouble(), (d['y'] as num).toDouble())));
    }
  }

  void _onMove(NetMove m) {
    final String t = '${m.data['t']}';
    if (t == 'fin') {
      final int s = (m.data['s'] as num).toInt();
      race.finish(s, ((m.data['ms'] as num).toInt()) / 1000);
    } else if (t == 'end') {
      _finishRace();
    }
  }

  void _setBanner(String text, [double seconds = 1.4]) {
    _banner = text;
    _bannerTime = seconds;
  }

  @override
  void tick(double dt) {
    final double before = race.countdown;
    if (!_done && !_resolving) {
      final double steer = (_right - _left).toDouble();
      final bool brake = _left == 1 && _right == 1; // both arrows = brake
      final Kart mine = race.karts[me];
      final KartItem held = mine.item;
      race.input(me, brake ? 0 : steer, _drift, _itemTap, brake: brake);
      if (_itemTap && held != KartItem.none && mine.item == KartItem.none && rt != null) {
        if (held == KartItem.missile && race.missiles.isNotEmpty) rt!.event('msl', <String, dynamic>{'t': race.missiles.last.target});
        if (held == KartItem.oil && race.oils.isNotEmpty) {
          rt!.event('oil', <String, dynamic>{'x': race.oils.last.pos.x, 'y': race.oils.last.pos.y});
        }
      }
      _itemTap = false;
      final bool wasFinished = mine.finished;
      race.step(dt, simulate: rt == null ? null : <int>{me});
      if (!wasFinished && mine.finished && rt != null) {
        unawaited(rt!.log(<String, dynamic>{'t': 'fin', 's': me, 'ms': (mine.finishTime * 1000).round()}));
      }
    }
    // countdown banner (3, 2, 1, GO!)
    if (before > 0) {
      final int c = race.countdown.ceil();
      if (race.countdown <= 0) {
        _setBanner('GO!', 0.8);
        HapticFeedback.mediumImpact();
      } else if (before.ceil() != c || _banner.isEmpty) {
        _setBanner('$c', 2);
        HapticFeedback.selectionClick();
      }
    } else if (_bannerTime > 0) {
      _bannerTime -= dt;
      if (_bannerTime <= 0) _banner = '';
    }
    // remote karts (online)
    final ArcadeRt? r = rt;
    if (r != null) {
      r.pump(dt, () {
        final Kart k = race.karts[me];
        return <String, dynamic>{
          'x': k.pos.x.round(), 'y': k.pos.y.round(), 'h': (k.heading * 1000).round(), 's': k.speed.round(),
          'l': k.lap, 'i': k.idx, 'c': k.passed, 'g': (k.raceProgress * 10).round(),
          'd': k.drifting ? 1 : 0, 'b': k.boost > 0 ? 1 : 0, 'p': k.spin > 0 ? 1 : 0, 'sh': k.shield > 0 ? 1 : 0,
        };
      });
      r.states.forEach((int seat, Map<String, dynamic> st) {
        if (seat == me || seat >= race.karts.length) return;
        final Kart k = race.karts[seat];
        final V2 target = V2((st['x'] as num).toDouble(), (st['y'] as num).toDouble());
        final V2 cur = _smooth[seat] ?? target;
        final V2 nx = V2(rtLerp(cur.x, target.x, dt), rtLerp(cur.y, target.y, dt));
        _smooth[seat] = nx;
        k.pos = nx;
        k.heading = (st['h'] as num).toDouble() / 1000;
        k.speed = (st['s'] as num).toDouble();
        k.vel = V2.polar(k.heading, k.speed);
        k.lap = (st['l'] as num).toInt();
        k.idx = (st['i'] as num).toInt();
        k.s = k.idx.toDouble();
        if (st['c'] is num) k.passed = (st['c'] as num).toInt();
        if (st['g'] is num) k.raceProgress = (st['g'] as num).toDouble() / 10;
        k.drifting = st['d'] == 1;
        k.boost = st['b'] == 1 ? 0.2 : 0;
        k.spin = st['p'] == 1 ? 0.2 : 0;
        k.shield = st['sh'] == 1 ? 1 : 0;
      });
      // authority closes the race 40 s after the first finisher, or when everyone active finished
      if (r.isHost && !_done && race.finishOrder.isNotEmpty) {
        final bool all = r.activeSeats.every((int s) => race.karts[s].finished);
        _endTimer = _endTimer < 0 ? 40 : _endTimer - dt;
        if (all || _endTimer <= 0) {
          _endTimer = 1e9;
          unawaited(r.log(<String, dynamic>{'t': 'end'}));
          _finishRace();
        }
      }
    } else if (!_done) {
      final Kart mine = race.karts[me];
      if (mine.finished) {
        // let the finish breathe, then race the remaining bots to the line for the real order
        _endTimer = _endTimer < 0 ? 2.5 : _endTimer - dt;
        if (_endTimer <= 0) {
          _resolving = true;
          race.simulateToEnd();
          _finishRace();
        }
      } else if (race.karts.where((Kart k) => k.seat != me).every((Kart k) => k.finished)) {
        // every bot is home: 30 s to cross the line, then the race closes with the player last
        _dnfTimer = _dnfTimer < 0 ? 30 : _dnfTimer - dt;
        if (_dnfTimer <= 0) _finishRace();
      }
    }
    _updateCamera(dt);
    _consumeEvents();
    fx.update(dt);
  }

  /// Frame-rate independent smoothing: the camera trails the kart's position slightly, turns with the direction
  /// of travel (so a drift does not swing the view) and ignores spin-outs.
  void _updateCamera(double dt) {
    final Kart k = race.karts[me];
    final V2 cp = _camPos ?? k.pos;
    final double ap = 1 - math.exp(-14 * dt);
    _camPos = cp + (k.pos - cp) * ap;
    if (k.spin <= 0) {
      final double travel = k.vel.len > 60 ? math.atan2(k.vel.y, k.vel.x) : k.heading;
      final double aim = k.heading + wrapAngle(travel - k.heading) * 0.6;
      _camHeading += wrapAngle(aim - _camHeading) * (1 - math.exp(-5 * dt));
      _camHeading = wrapAngle(_camHeading);
    }
    final double zt = 1 - (1 - KartLayout.minZoomFactor) * (k.speed / (KartRace.maxSpeed * KartRace.boostTop)).clamp(0.0, 1.0);
    _camZoom += (zt - _camZoom) * (1 - math.exp(-2.5 * dt));
  }

  void _consumeEvents() {
    for (final KartEvent e in race.events) {
      final Offset at = Offset(e.x, e.y);
      final bool mine = e.seat == me;
      switch (e.kind) {
        case 'pickup':
          fx.burst(at, skin.accent2, count: 16, speed: 220, kind: ParticleKind.orb, size: 5);
          if (mine) HapticFeedback.lightImpact();
        case 'boost':
        case 'pad':
          fx.burst(at, e.other >= 2 ? const Color(0xFFB98CFF) : const Color(0xFFFF9D2E), count: 14, speed: 200);
          if (mine) fx.shake(3);
        case 'hit':
        case 'missile_hit':
          fx.burst(at, const Color(0xFFFF5A3D), count: 30, speed: 340, size: 5);
          fx.burst(at, const Color(0xFF555555), count: 10, speed: 80, kind: ParticleKind.smoke, life: 1.2, size: 12);
          if (mine) {
            fx.shake(10);
            HapticFeedback.heavyImpact();
          }
        case 'bump':
        case 'wall':
          if (mine || e.other == me) {
            fx.shake(e.kind == 'wall' ? 4 : 3);
            HapticFeedback.lightImpact();
          }
        case 'shield_break':
          fx.ring(at, const Color(0xFF7FE9FF), size: 24);
        case 'lap':
          if (mine && e.other < race.laps) {
            _setBanner(e.other == race.laps - 1 ? l.tx('دور آخر!', 'FINAL LAP!') : l.tx('دور ${e.other + 1}', 'LAP ${e.other + 1}'));
          }
        case 'finish':
          if (mine) {
            _setBanner('${l.tx('پایان!', 'FINISH!')} ${ordinalEn(e.other)}', 3);
            fx.confetti(at, count: 60);
            HapticFeedback.heavyImpact();
          }
      }
    }
    race.events.clear();
  }

  void _finishRace() {
    if (_done) return;
    _done = true;
    _resolving = false;
    final List<int> order = race.standings().map((Kart k) => k.seat).toList();
    final int place = order.indexOf(me) + 1;
    _setBanner(ordinalEn(place), 1e9);
    final GameResult res = rankedResult(l, order, whatFa: 'مسابقه‌ی کارت', whatEn: 'Kart race');
    l.onFinish(res);
  }

  // ------------------------------------------------------------------ render
  void _paint(Canvas canvas, Size size) {
    final Kart k = race.karts[me];
    final KartLayout lay = KartLayout.compute(size, _pad);
    final Offset sh = fx.shakeOffset;
    final V2 cam = _camPos ?? k.pos;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF1F6B2A));
    canvas.save();
    // chase camera: kart in the lower play area (above the controls), facing up
    canvas.translate(lay.focal.dx + sh.dx, lay.focal.dy + sh.dy);
    canvas.scale(lay.zoomBase * _camZoom);
    canvas.rotate(-_camHeading - math.pi / 2);
    canvas.translate(-cam.x, -cam.y);
    _paintWorld(canvas);
    for (final OilSlick o in race.oils) {
      if (!skin.drawSprite(canvas, 'oil', Rect.fromCenter(center: Offset(o.pos.x, o.pos.y), width: KartProps.oilW, height: KartProps.oilH))) {
        canvas.drawOval(Rect.fromCenter(center: Offset(o.pos.x, o.pos.y), width: KartProps.oilW, height: KartProps.oilH),
            Paint()..shader = ui.Gradient.radial(Offset(o.pos.x - 8, o.pos.y - 6), 30, <Color>[const Color(0xFF4A4A5A), const Color(0xFF0A0A10)]));
        canvas.drawOval(Rect.fromCenter(center: Offset(o.pos.x - 8, o.pos.y - 8), width: 14, height: 6),
            Paint()..color = const Color(0x55B98CFF));
      }
    }
    for (final ItemBox b in race.boxes) {
      if (b.active) _paintBox(canvas, Offset(b.pos.x, b.pos.y));
    }
    final List<Kart> sorted = List<Kart>.of(race.karts);
    for (final Kart o in sorted) {
      _paintKart(canvas, o);
    }
    _paintTrees(canvas);
    for (final Missile m in race.missiles) {
      final Offset c = Offset(m.pos.x, m.pos.y);
      paintGlow(canvas, c, 26, const Color(0xFFFF6A2A), 0.7);
      paintSphere(canvas, c, KartProps.missileR, const Color(0xFFE0262A), shadow: false);
      fx.burst(c, const Color(0xFFFFB13D), count: 1, speed: 40, life: 0.3, kind: ParticleKind.orb, size: 4);
    }
    fx.paint(canvas);
    canvas.restore();
    paintVignette(canvas, size, 0.45);
    // speed lines when boosting
    if (k.boost > 0 && fx.enabled) {
      final Paint p = Paint()
        ..color = Colors.white.withValues(alpha: 0.18)
        ..strokeWidth = 2;
      final math.Random r = math.Random((time * 30).floor());
      for (int i = 0; i < 14; i++) {
        final double x = r.nextDouble() * size.width;
        final double y = r.nextDouble() * size.height * 0.6;
        canvas.drawLine(Offset(x, y), Offset(x, y + 40 + r.nextDouble() * 60), p);
      }
    }
    fx.paintFlash(canvas, size);
  }

  void _paintWorld(Canvas canvas) {
    final KartTrack t = race.track;
    // mowed-lawn stripes + grass tufts
    final Paint stripe = Paint()..color = const Color(0xFF237A31);
    for (double x = -2200; x < 2200; x += 240) {
      canvas.drawRect(Rect.fromLTWH(x, -1700, 120, 3400), stripe);
    }
    final Paint tuft = Paint()..color = const Color(0xFF34A045);
    for (final Offset o in _tufts) {
      canvas.drawCircle(o, 6, tuft);
      canvas.drawCircle(o + const Offset(7, 3), 4, tuft);
    }
    final Path path = Path()..moveTo(t.at(0).x, t.at(0).y);
    for (int i = 1; i <= t.n; i++) {
      path.lineTo(t.at(i).x, t.at(i).y);
    }
    path.close();
    // tyre walls: the inner face sits exactly at wallOffset from the centre line on both sides (= collision)
    const double wallT = 10;
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = (t.wallOffset + wallT + 4) * 2
      ..color = const Color(0x33000000));
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = (t.wallOffset + wallT) * 2
      ..color = const Color(0xFF22252C));
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = (t.wallOffset + wallT * 0.45) * 2
      ..color = const Color(0xFFE8E8E8));
    // run-off grass between the curb and the wall
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = t.wallOffset * 2
      ..color = const Color(0xFF2B9C45));
    // curbs (no slowdown on them)
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = t.width + KartTrack.curb * 2
      ..color = const Color(0xFFE53935));
    final Paint white = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = t.width + KartTrack.curb * 2
      ..color = Colors.white;
    for (int i = 0; i < t.n; i += 2) {
      final Path seg = Path()
        ..moveTo(t.at(i).x, t.at(i).y)
        ..lineTo(t.at(i + 1).x, t.at(i + 1).y);
      canvas.drawPath(seg, white);
    }
    // asphalt (two tones for depth)
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = t.width
      ..color = const Color(0xFF3A3F4A));
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = t.width * 0.62
      ..color = const Color(0xFF454B57));
    // centre dashes
    final Paint dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = const Color(0x88FFFFFF);
    for (int i = 0; i < t.n; i += 4) {
      canvas.drawLine(Offset(t.at(i).x, t.at(i).y), Offset(t.at(i + 1).x, t.at(i + 1).y), dash);
    }
    // boost pads
    for (final int p in race.pads) {
      final V2 c = t.at(p), d = t.dir(p);
      canvas.save();
      canvas.translate(c.x, c.y);
      canvas.rotate(math.atan2(d.y, d.x));
      final double pulse = 0.6 + 0.4 * math.sin(time * 8);
      final double pw = KartProps.padWidth(t.width);
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: KartProps.padLength, height: pw), const Radius.circular(8)),
          Paint()..color = Color.fromRGBO(255, 160, 40, 0.35 + 0.25 * pulse));
      for (int k = -1; k <= 1; k++) {
        final Path chev = Path()
          ..moveTo(k * 18 - 6, -pw * 0.3)
          ..lineTo(k * 18 + 8, 0)
          ..lineTo(k * 18 - 6, pw * 0.3);
        paintNeonPath(canvas, chev, const Color(0xFFFFB13D), width: 4, glow: 8);
      }
      canvas.restore();
    }
    // start / finish checkers
    final V2 s0 = t.at(0), d0 = t.dir(0);
    canvas.save();
    canvas.translate(s0.x, s0.y);
    canvas.rotate(math.atan2(d0.y, d0.x));
    const double cell = 11;
    final int rows = (t.width / cell).floor();
    for (int i = 0; i < rows; i++) {
      for (int j = 0; j < 2; j++) {
        canvas.drawRect(Rect.fromLTWH(j * cell - cell, -t.width / 2 + i * cell, cell, cell),
            Paint()..color = (i + j).isEven ? Colors.white : const Color(0xFF111111));
      }
    }
    canvas.restore();
  }

  void _paintTrees(Canvas canvas) {
    final Kart k = race.karts[me];
    final double reach = 1200;
    for (final Offset t in _trees) {
      if ((t.dx - k.pos.x).abs() > reach || (t.dy - k.pos.y).abs() > reach) continue;
      final double h = 0.6 + ((t.dx * 7 + t.dy * 13).abs() % 40) / 100;
      paintShadow(canvas, t + Offset(10 * h, 12 * h), 70 * h, 52 * h, 0.35);
      for (int i = 0; i < 3; i++) {
        final Offset o = t + Offset(math.cos(i * 2.1) * 12 * h, math.sin(i * 2.1) * 12 * h);
        paintSphere(canvas, o, 22 * h, i.isEven ? const Color(0xFF1E7A2E) : const Color(0xFF2A9140), shadow: false, gloss: 0.35);
      }
      paintSphere(canvas, t, 18 * h, const Color(0xFF3DB352), shadow: false, gloss: 0.5);
    }
  }

  void _paintBox(Canvas canvas, Offset c) {
    canvas.save();
    canvas.translate(c.dx, c.dy + math.sin(time * 3 + c.dx) * 2);
    canvas.rotate(time * 1.6);
    paintGlow(canvas, Offset.zero, KartProps.boxSize * 1.1, skin.accent2, 0.45);
    final Rect r = Rect.fromCenter(center: Offset.zero, width: KartProps.boxSize, height: KartProps.boxSize);
    if (!skin.drawSprite(canvas, 'item_box', r)) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(7)),
          Paint()
            ..shader = ui.Gradient.sweep(Offset.zero, const <Color>[
              Color(0xFFFF4F9A), Color(0xFFFFD34E), Color(0xFF39E1FF), Color(0xFFB98CFF), Color(0xFFFF4F9A)
            ], const <double>[0, 0.25, 0.5, 0.75, 1]));
      canvas.drawRRect(RRect.fromRectAndRadius(r.deflate(3), const Radius.circular(5)),
          Paint()..color = const Color(0x66FFFFFF));
      canvas.rotate(-time * 1.6);
      drawLabel(canvas, '?', Offset.zero, size: 20, color: Colors.white, glow: Colors.white);
    }
    canvas.restore();
  }

  void _paintKart(Canvas canvas, Kart k) {
    final Color col = skin.player(k.seat);
    canvas.save();
    canvas.translate(k.pos.x, k.pos.y);
    canvas.rotate(k.heading);
    paintShadow(canvas, const Offset(4, 6), KartDims.length, KartDims.width * 0.95, 0.45);
    if (k.boost > 0) {
      for (int i = 0; i < 2; i++) {
        final double fl = 18 + math.Random((time * 40).floor() + i).nextDouble() * 14;
        const double tail = -KartDims.length / 2;
        canvas.drawOval(Rect.fromCenter(center: Offset(tail - fl / 2, (i == 0 ? -7 : 7)), width: fl, height: 9),
            Paint()
              ..shader = ui.Gradient.linear(const Offset(tail, 0), Offset(tail - fl, 0),
                  <Color>[const Color(0xFFFFFFFF), const Color(0xFF39E1FF), const Color(0x00396BFF)], <double>[0, 0.3, 1]));
      }
    }
    // the drawn kart fills exactly the KartDims box (= the collision capsule's bounding box)
    if (!skin.drawSprite(canvas, 'kart_${k.seat % 4}',
        const Rect.fromLTWH(-KartDims.length / 2, -KartDims.width / 2, KartDims.length, KartDims.width))) {
      final Paint tyre = Paint()..color = const Color(0xFF15151A);
      for (final Offset w in const <Offset>[Offset(-14, -14), Offset(-14, 14), Offset(14, -14), Offset(14, 14)]) {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: w, width: 15, height: 8), const Radius.circular(3)), tyre);
      }
      // body
      final Path body = Path()
        ..moveTo(-22, -11)
        ..quadraticBezierTo(-24, 0, -22, 11)
        ..lineTo(14, 12)
        ..quadraticBezierTo(25, 8, 26, 0)
        ..quadraticBezierTo(25, -8, 14, -12)
        ..close();
      canvas.drawPath(body, Paint()
        ..shader = ui.Gradient.linear(const Offset(0, -12), const Offset(0, 12),
            <Color>[shade(col, 0.22), col, shade(col, -0.25)], <double>[0, 0.45, 1]));
      canvas.drawPath(body, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withValues(alpha: 0.35));
      // spoiler + nose stripe
      canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-26, -13, 6, 26), const Radius.circular(2)),
          Paint()..color = shade(col, -0.32));
      canvas.drawRect(const Rect.fromLTWH(4, -2.5, 20, 5), Paint()..color = Colors.white.withValues(alpha: 0.85));
      // driver helmet
      paintSphere(canvas, const Offset(-4, 0), 8.5, k.seat == me ? const Color(0xFFFFFFFF) : const Color(0xFFDADDE6), shadow: false);
      canvas.drawArc(Rect.fromCircle(center: const Offset(-4, 0), radius: 8.5), -0.9, 1.8, false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.4
            ..color = const Color(0xFF1B1F2A));
    }
    if (k.drifting && fx.enabled) {
      final Color sc = k.driftCharge > KartRace.driftLv2
          ? const Color(0xFFB98CFF)
          : k.driftCharge > KartRace.driftLv1
              ? const Color(0xFFFF9D2E)
              : const Color(0xFF6FD3FF);
      canvas.restore();
      final double c = math.cos(k.heading), s = math.sin(k.heading);
      for (final double side in <double>[-14, 14]) {
        final Offset w = Offset(k.pos.x + c * -14 - s * side, k.pos.y + s * -14 + c * side);
        fx.burst(w, sc, count: 2, speed: 120, life: 0.25, size: 3, direction: k.heading + math.pi, spread: 1.4);
        if (math.Random().nextDouble() < 0.3) {
          fx.burst(w, const Color(0xFFBBBBBB), count: 1, speed: 30, life: 0.6, kind: ParticleKind.smoke, size: 6);
        }
      }
      canvas.save();
      canvas.translate(k.pos.x, k.pos.y);
      canvas.rotate(k.heading);
    }
    if (k.shield > 0) {
      final double sr = KartDims.halfDiagonal + 2;
      canvas.drawCircle(Offset.zero, sr, Paint()
        ..shader = ui.Gradient.radial(Offset.zero, sr, <Color>[const Color(0x0039E1FF), const Color(0x8839E1FF)]));
      canvas.drawCircle(Offset.zero, sr, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xCCB8F4FF));
    }
    canvas.restore();
    // name tag for others
    if (k.seat != me) {
      final String name = l.netName(k.seat) ?? (l.online ? 'P${k.seat + 1}' : 'BOT ${k.seat}');
      canvas.save();
      canvas.translate(k.pos.x, k.pos.y);
      canvas.rotate(_camHeading + math.pi / 2);
      drawLabel(canvas, name, Offset(0, -KartDims.halfDiagonal - 8), size: 12, color: Colors.white, glow: col);
      canvas.restore();
    }
  }

  void _paintMinimap(Canvas canvas, Size size) {
    final KartTrack t = race.track;
    double minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9;
    for (final V2 p in t.points) {
      minX = math.min(minX, p.x);
      minY = math.min(minY, p.y);
      maxX = math.max(maxX, p.x);
      maxY = math.max(maxY, p.y);
    }
    final double s = math.min((size.width - 12) / (maxX - minX), (size.height - 12) / (maxY - minY));
    Offset map(V2 p) => Offset(6 + (p.x - minX) * s, 6 + (p.y - minY) * s);
    final Path path = Path()..moveTo(map(t.at(0)).dx, map(t.at(0)).dy);
    for (int i = 1; i <= t.n; i += 3) {
      path.lineTo(map(t.at(i)).dx, map(t.at(i)).dy);
    }
    path.close();
    paintNeonPath(canvas, path, Colors.white.withValues(alpha: 0.8), width: 2.5, glow: 4);
    for (final Kart k in race.karts) {
      canvas.drawCircle(map(k.pos), k.seat == me ? 5 : 4, Paint()..color = skin.player(k.seat));
      if (k.seat == me) {
        canvas.drawCircle(map(k.pos), 6, Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.white);
      }
    }
  }

  IconData _itemIcon(KartItem i) => switch (i) {
        KartItem.turbo => Icons.bolt_rounded,
        KartItem.missile => Icons.rocket_launch_rounded,
        KartItem.shield => Icons.shield_rounded,
        KartItem.oil => Icons.water_drop_rounded,
        KartItem.none => Icons.help_outline_rounded,
      };

  @override
  Widget build(BuildContext context) {
    _pad = MediaQuery.paddingOf(context);
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
      final KartLayout lay = KartLayout.compute(Size(c.maxWidth, c.maxHeight), _pad);
      Positioned at(Rect r, Widget child) => Positioned(left: r.left, top: r.top, width: r.width, height: r.height, child: child);
      return Stack(fit: StackFit.expand, children: <Widget>[
        CustomPaint(painter: ArcadePainter(_paint, frame)),
        // HUD
        ValueListenableBuilder<int>(
          valueListenable: frame,
          builder: (BuildContext context, _, __) {
            final Kart k = race.karts[me];
            final int place = race.placeOf(me);
            final String banner = _banner.isNotEmpty
                ? _banner
                : (k.isWrongWay && !k.finished ? l.tx('مسیر اشتباه!', 'WRONG WAY!') : '');
            return Stack(children: <Widget>[
              Positioned(
                top: lay.hudLeft.top,
                left: lay.hudLeft.left,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  ArcadeHudPill(
                    color: skin.accent2,
                    child: Text.rich(TextSpan(children: <InlineSpan>[
                      TextSpan(text: '$place', style: const TextStyle(fontSize: 30)),
                      TextSpan(text: '/${race.racers}', style: const TextStyle(fontSize: 15, color: Colors.white70)),
                    ])),
                  ),
                  const SizedBox(height: 6),
                  ArcadeHudPill(
                    color: skin.accent,
                    child: Text(
                        l.tx('دور ${math.min(k.lap + 1, race.laps)}/${race.laps}', 'LAP ${math.min(k.lap + 1, race.laps)}/${race.laps}'),
                        style: const TextStyle(fontSize: 14)),
                  ),
                ]),
              ),
              at(
                lay.minimap,
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: CustomPaint(painter: ArcadePainter(_paintMinimap, frame)),
                ),
              ),
              if (banner.isNotEmpty)
                Positioned(
                  left: lay.safe.left,
                  right: c.maxWidth - lay.safe.right,
                  top: lay.hudLeft.bottom,
                  bottom: c.maxHeight - lay.steerLeft.top,
                  child: Center(child: ArcadeBanner(banner, color: skin.accent)),
                ),
            ]);
          },
        ),
        // controls (both arrows together = brake)
        at(
            lay.steerLeft,
            ArcadePadButton(
                icon: Icons.arrow_back_rounded, color: const Color(0xFF2F8BFF), size: lay.steerLeft.width,
                onDown: () => _left = 1, onUp: () => _left = 0)),
        at(
            lay.steerRight,
            ArcadePadButton(
                icon: Icons.arrow_forward_rounded, color: const Color(0xFF2F8BFF), size: lay.steerRight.width,
                onDown: () => _right = 1, onUp: () => _right = 0)),
        at(
          lay.itemButton,
          ValueListenableBuilder<int>(
            valueListenable: frame,
            builder: (_, __, ___) {
              final KartItem it = race.karts[me].item;
              return ArcadePadButton(
                icon: _itemIcon(it),
                color: it == KartItem.none ? const Color(0xFF555A66) : const Color(0xFFFF4F9A),
                size: lay.itemButton.width,
                enabled: it != KartItem.none,
                onDown: () => _itemTap = true,
              );
            },
          ),
        ),
        at(
            lay.driftButton,
            ArcadePadButton(
                icon: Icons.u_turn_right_rounded, label: l.tx('دریفت', 'DRIFT'), color: skin.accent, size: lay.driftButton.width,
                onDown: () => _drift = true, onUp: () => _drift = false)),
      ]);
    });
  }
}
