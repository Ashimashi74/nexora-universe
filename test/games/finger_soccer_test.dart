import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexora/games/core/game_contract.dart';
import 'package:nexora/games/finger_soccer/ui/bm_painter.dart';
import 'package:nexora/games/finger_soccer/ui/bm_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/finger_soccer/core/bm_data.dart';
import 'package:nexora/games/finger_soccer/core/bm_engine.dart';

class _Hooks implements BmHooks {
  final List<String> events = <String>[];
  @override
  void sfx(String k, [double v = 1]) {}
  @override
  void tone(String k) {}
  @override
  void vib(List<int> pattern) {}
  @override
  void toast(String text, bool big) {}
  @override
  void goalFx() {}
  @override
  void emit(String event, Map<String, dynamic> data) => events.add(event);
}

BmConfig _cfg({bool mirror = false, String mode = 'bot'}) => BmConfig(
      mode: mode,
      teams: const <String>['club0', 'club1'],
      form: const <int>[0, 3],
      names: const <String>['A', 'B'],
      field: 6,
      ball: 0,
      matchTime: 300,
      ai: mode == 'bot',
      aiLvl: 2,
      mirror: mirror,
    );

void main() {
  test('constants, fields and the art-measured goal geometry', () {
    expect(K, 1.27);
    expect(PR, 75.0); // finger-soccer proportions: disc diameter ~1/6 of the playing width
    expect(BR / PR, closeTo(.5, .01)); // ball = half the disc diameter
    expect(PF1, greaterThan(520)); // anti-drift: more felt friction than the old tuning
    expect(PF2, greaterThan(1.1));
    expect(STEP, 1 / 240);
    expect(kBmFields.length, 36);
    expect(NB, 4);
    expect(kBmBallN.length, NB);
    expect(kBmBallFa.length, NB);
    expect(kBmAnimBalls.keys.toList(), <int>[0, 1, 2, 3]);
    for (final BmAnimBall b in kBmAnimBalls.values) {
      expect(b.frames, 16);
    }
    final BmFieldS f = kBmFields.firstWhere((BmFieldS x) => x.id == 'forest');
    expect(f.W, (1086 * FS).roundToDouble());
    expect(f.L, (195 * FS).roundToDouble());
    final BmEngine e = BmEngine(_Hooks(), rng: math.Random(1));
    e.startMatch(_cfg());
    expect(e.bodies.length, 11);
    expect(e.ball!.r, BR);
    expect(e.ball!.m, closeTo(BALL_M, 1e-9));
    expect(e.bodies.first.m, DISC_M);
    expect(DISC_M, greaterThan(2.5 * BALL_M));
  });

  test('every field: posts, mouth and net come from the drawn goal (sprite or built into the art)', () {
    for (int fi = 0; fi < kBmFields.length; fi++) {
      final BmFieldS f = kBmFields[fi];
      final BmEngine e = BmEngine(_Hooks(), rng: math.Random(1))..setFld = fi;
      e.geo();
      for (final BmGoal g in e.GOALS) {
        // posts symmetric about the centre line, the mouth between their inner faces
        expect(g.px1 + g.px2, closeTo(2 * e.CX, 1e-6), reason: f.id);
        expect(g.x1, closeTo(g.px1 + g.pr, 1e-6), reason: f.id);
        expect(g.x2, closeTo(g.px2 - g.pr, 1e-6), reason: f.id);
        expect(g.pr, greaterThan(4), reason: f.id);
        expect(g.x2 - g.x1, greaterThan(6 * BR), reason: f.id);
        expect(g.x2 - g.x1, greaterThan(2.3 * 2 * PR), reason: f.id); // mouth stays ~2.5 discs wide
        expect(g.px1, greaterThan(e.Fl + PR), reason: f.id);
        expect(g.px2, lessThan(e.Fr - PR), reason: f.id);
      }
      expect(e.DEPTH, greaterThan(2 * BR), reason: f.id);
      if (f.builtInGoals) {
        expect(e.GGw, 0, reason: f.id);
        expect(e.GOALS[0].px2 - e.GOALS[0].px1, closeTo(2 * f.gh, 1e-6), reason: f.id);
      } else {
        final List<double> gi = kBmGS[f.gs]!;
        // sprite legs == post colliders, sprite back bar == back net, sprite leg bottoms == goal line
        expect(e.GOALS[0].px1, closeTo(e.GGx + gi[2] * e.GGw, 1e-6), reason: f.id);
        expect(e.GOALS[0].px2, closeTo(e.GGx + gi[3] * e.GGw, 1e-6), reason: f.id);
        expect(e.GOALS[0].pr, closeTo(gi[4] * e.GGw, 1e-6), reason: f.id);
        expect(e.DEPTH, closeTo(e.GGh * (gi[6] - gi[5]), 1e-6), reason: f.id);
      }
      expect(e.RC, f.rc, reason: f.id);
    }
  });

  test('pitch (goals included) is centred between the scoreboard and the gesture bar', () {
    final BmEngine e = BmEngine(_Hooks(), rng: math.Random(1))..startMatch(_cfg());
    final BmView view = BmView()
      ..insetTop = 32 + 64
      ..insetBottom = 20 + 8
      ..layout(e, const Size(360, 800));
    final double half = ((e.Fb - e.Ft) / 2 + e.goalVisualDepth + 24) * view.s;
    final double cy = e.CY * view.s + view.oy;
    expect(cy - half, greaterThanOrEqualTo(96 - 0.01));
    expect(cy + half, lessThanOrEqualTo(800 - 28 + 0.01));
    expect(cy, closeTo((96 + 772) / 2, 0.5));
    expect(e.CX * view.s + view.ox, closeTo(180, 0.01));
  });

  test('sprites are drawn so their rim is exactly the collider', () {
    final BmEngine e = BmEngine(_Hooks(), rng: math.Random(1))..startMatch(_cfg());
    final BmBody disc = e.bodies.first, ball = e.ball!;
    expect(bmDiscSpriteHalf(disc) * kBmDiscArtFill, closeTo(disc.r, 1e-9));
    expect(bmBallSpriteHalf(ball) * kBmBallArtFill, closeTo(ball.r, 1e-9));
    final BmView view = BmView()..layout(e, const Size(360, 800));
    final double pitchWidth = (e.Fr - e.Fl) * view.s;
    expect(pitchWidth, inInclusiveRange(360 * 0.80, 360 * 0.92));
  });

  test('teams: exactly Club / National / Luxury, plausible varied stats, luxury 10/10, art present', () {
    expect(kBmCats.map((List<Object> c) => c[0]).toList(), <String>['club', 'nat', 'lux']);
    expect(kBmTeams.map((BmTeam t) => t.id).toSet().length, kBmTeams.length);
    for (final BmTeam t in kBmTeams) {
      expect(<String>['club', 'nat', 'lux'], contains(t.cat));
      expect(t.power, inInclusiveRange(1, 10));
      expect(t.accuracy, inInclusiveRange(1, 10));
      if (t.cat == 'lux') {
        expect(t.power, 10, reason: t.name);
        expect(t.accuracy, 10, reason: t.name);
      } else {
        expect(t.power + t.accuracy, lessThan(20), reason: t.name);
      }
      expect(File(t.asset).existsSync(), isTrue, reason: t.asset);
    }
    for (final String c in <String>['club', 'nat']) {
      final Iterable<BmTeam> l = kBmTeams.where((BmTeam t) => t.cat == c);
      expect(l.length, greaterThanOrEqualTo(30));
      expect(l.map((BmTeam t) => t.power).toSet().length, greaterThanOrEqualTo(4));
      expect(l.map((BmTeam t) => t.accuracy).toSet().length, greaterThanOrEqualTo(4));
    }
    expect(bmTeam('club0').name, 'Real Madrid');
    expect(bmTeam('club0').power, greaterThan(bmTeam('club38').power));
    expect(kBmTeams.where((BmTeam t) => t.cat == 'lux').length, greaterThanOrEqualTo(40));
    // the ANIX wooden pucks belong to Carrom / Backgammon, never to finger soccer
    expect(kBmTeams.where((BmTeam t) => t.id.startsWith('nx_')), isEmpty);
    for (final BmFieldS f in kBmFields) {
      expect(f.gs, 'white', reason: f.id); // the one goal asset on every pitch
    }
    for (final BmFieldS f in kBmFields) {
      expect(File(f.asset).existsSync(), isTrue, reason: f.asset);
      expect(File('assets/games/bermuda/thumbs/${f.id}.webp').existsSync(), isTrue, reason: f.id);
      if (!f.builtInGoals) expect(File('assets/games/bermuda/goals/${f.gs}.webp').existsSync(), isTrue);
    }
    for (final BmAnimBall b in kBmAnimBalls.values) {
      expect(File(b.sheet).existsSync(), isTrue, reason: b.sheet);
      expect(File(b.thumb).existsSync(), isTrue, reason: b.thumb);
    }
  });

  test('pieces carry their team power and accuracy across resets', () {
    final BmEngine e = BmEngine(_Hooks(), rng: math.Random(1))..startMatch(_cfg());
    final List<BmBody> discs = e.bodies.where((BmBody b) => b != e.ball).toList();
    for (final BmBody b in discs) {
      expect(b.power, bmTeam(e.sel[b.team]).power);
      expect(b.accuracy, bmTeam(e.sel[b.team]).accuracy);
    }
    e.reset(0);
    expect(e.bodies.where((BmBody b) => b != e.ball).map((BmBody b) => b.power).toList(), discs.map((BmBody b) => b.power).toList());
    expect(e.ball!.power, 0);
  });

  test('power changes shot speed; accuracy bounds the aim error; same seed => same shot', () {
    double shotAngleErr(String team, int seed) {
      final BmEngine e = BmEngine(_Hooks(), rng: math.Random(seed))
        ..startMatch(BmConfig(mode: 'local', teams: <String>[team, 'club1'], form: const <int>[0, 0], names: const <String>['A', 'B'], field: 0, ball: 0));
      final BmBody b = e.bodies.firstWhere((BmBody x) => x.team == 0 && x != e.ball);
      e.fire(b, 0, -200, 200);
      return math.atan2(b.vx, -b.vy);
    }

    double shotSpeed(String team) {
      final BmEngine e = BmEngine(_Hooks(), rng: math.Random(5))
        ..startMatch(BmConfig(mode: 'local', teams: <String>[team, 'club1'], form: const <int>[0, 0], names: const <String>['A', 'B'], field: 0, ball: 0));
      final BmBody b = e.bodies.firstWhere((BmBody x) => x.team == 0 && x != e.ball);
      e.fire(b, 0, -320, 320);
      return math.sqrt(b.vx * b.vx + b.vy * b.vy);
    }

    expect(shotSpeed('lux0'), greaterThan(shotSpeed('club0')));
    expect(shotSpeed('club0'), greaterThan(shotSpeed('club38'))); // Real Madrid 9 vs Rangers 6
    expect(shotSpeed('lux0') / shotSpeed('nat30'), closeTo(BmEngine.strikeOf(10) / BmEngine.strikeOf(4), 1e-9));
    // luxury (accuracy 10): exact aim, every seed
    for (int s = 0; s < 20; s++) {
      expect(shotAngleErr('lux0', s).abs(), lessThan(1e-9));
    }
    // a weaker side misses by up to its accuracy bound, and not always by zero
    final List<double> errs = <double>[for (int s = 0; s < 40; s++) shotAngleErr('nat30', s)];
    final double bound = BmEngine.aimErrorOf(5, 1);
    expect(errs.every((double x) => x.abs() <= bound + 1e-9), isTrue);
    expect(errs.where((double x) => x.abs() > bound * .2).length, greaterThan(5));
    expect(shotAngleErr('nat30', 11), shotAngleErr('nat30', 11));
  });

  test('bot vs bot plays a long match without escaping the pitch', () {
    final _Hooks h = _Hooks();
    final BmEngine e = BmEngine(h, rng: math.Random(7));
    e.startMatch(_cfg());
    int shots = 0;
    for (int f = 0; f < 60 * 120 && e.phase != 'over'; f++) {
      if (e.phase == 'aim' && e.turn == 0 && e.drag == null) {
        final BmAiPlan? p = e.aiDecide();
        if (p != null) {
          e.fire(p.b, p.dx * p.l, p.dy * p.l, p.l);
          shots++;
        }
      }
      e.frame(1 / 60);
      for (final BmBody b in e.bodies) {
        expect(b.x.isFinite && b.y.isFinite, isTrue);
        expect(b.x, inInclusiveRange(e.Fl - 1, e.Fr + 1));
        expect(b.y, inInclusiveRange(e.Ft - e.DEPTH - 1, e.Fb + e.DEPTH + 1));
        expect(b.x, inInclusiveRange(e.Fl - 1, e.Fr + 1));
      }
    }
    expect(shots, greaterThan(5));
    expect(h.events.contains('shot'), isTrue);
  });

  test('mirrored snapshot maps back to the same global positions', () {
    final BmEngine host = BmEngine(_Hooks(), rng: math.Random(3))..startMatch(_cfg(mode: 'online'));
    final BmEngine guest = BmEngine(_Hooks(), rng: math.Random(3))..startMatch(_cfg(mode: 'online', mirror: true));
    final Map<String, dynamic> s = host.snapshot();
    guest.applySnapshot(s);
    expect(guest.snapshot()['b'], s['b']);
    expect(guest.ct(guest.turn), host.ct(host.turn));
  });

  testWidgets('BERMUDA match vs bot renders and plays 20 s on a phone screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final List<GameResult> results = <GameResult>[];
    final GameLaunch launch = GameLaunch(
      gameId: 'finger_soccer',
      mode: GameMode.vsBot,
      difficulty: BotDifficulty.hard,
      playerName: 'Tester',
      isFa: false,
      fancyEffects: true,
      reducedMotion: false,
      soundOn: false,
      seed: 3,
      onFinish: results.add,
    );
    await tester.pumpWidget(ProviderScope(child: MaterialApp(home: Scaffold(body: BermudaView(launch: launch, autoStart: true)))));
    for (int i = 0; i < 20 * 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
  });

  test('3v3 online: each side rotates its shooter (0,2,4 / 1,3,5) and replays adopt the rotation', () {
    final BmEngine e = BmEngine(_Hooks(), rng: math.Random(3))
      ..startMatch(const BmConfig(
        mode: 'online',
        teams: <String>['club0', 'club1'],
        form: <int>[0, 3],
        names: <String>['A · C · E', 'B · D · F'],
        field: 0,
        ball: 0,
        perSide: 3,
      ));
    e.localSeat = 0;
    final List<int> seq = <int>[];
    for (int i = 0; i < 8; i++) {
      seq.add(e.shooterSeat(e.ct(e.turn)));
      e.finishTurn(false);
    }
    expect(seq, <int>[0, 1, 2, 3, 4, 5, 0, 1]);
    // seat 0 controls only on its own rotation slot
    expect(e.shooterSeat(0), 2);
    expect(e.canCtl(), isFalse);
    final Map<String, dynamic> snap = e.snapshot();
    final BmEngine r = BmEngine(_Hooks(), rng: math.Random(3))
      ..startMatch(const BmConfig(
          mode: 'online', teams: <String>['club0', 'club1'], form: <int>[0, 3], names: <String>['a', 'b'],
          field: 0, ball: 0, perSide: 3));
    r.applyRotation(snap);
    expect(r.shooterSeat(0), e.shooterSeat(0));
    expect(r.shooterSeat(1), e.shooterSeat(1));
  });
}
