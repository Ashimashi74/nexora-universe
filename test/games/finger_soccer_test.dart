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
    expect(PR, 53.0); // reference proportions: disc diameter ~0.12 of the playing width
    expect(BR / PR, closeTo(.47, .01)); // reference: ball ~0.47 of the disc diameter
    // reference calibration v4: one felt law for shot and struck discs (pure 3.25/s drag), no launch glide
    expect(PF2, closeTo(3.25, 1e-9));
    expect(PF1, 0);
    expect(kBmLaunchGlide, 0);
    expect(kBmLaunch, closeTo(1.97, 1e-9)); // v6: 10/10 recordings (docs/FS_V6_CALIBRATION.md)
    expect(BmEngine.strikeOf(2) / BmEngine.strikeOf(10), closeTo(.40, .01));
    expect(STEP, 1 / 240);
    expect(kBmFields.length, 30); // v7: the six owner art pack pitches were removed
    expect(NB, 7); // v6: + the classic reference ball; v7: + NX Spin, NX Star
    expect(kBmBallN.length, NB);
    expect(kBmBallFa.length, NB);
    expect(kBmAnimBalls.keys.toList(), <int>[0, 1, 2, 3, 5, 6]);
    for (final MapEntry<int, BmAnimBall> b in kBmAnimBalls.entries) {
      expect(b.value.frames, b.key == kBmNxSpinBallIndex ? 24 : 16);
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

  test('formations: the nine reference shapes, five discs each, legal kickoff layouts', () {
    expect(kBmForms.map((BmFormation f) => f.fa).toList(),
        <String>['الماس', 'عقاب', 'موج', 'ماه', 'دیوانه', 'لبه', 'نیش', 'بازو', 'حمله همه جانبه']);
    for (final BmFormation f in kBmForms) {
      expect(f.slots.length, 5, reason: f.en);
      expect(f.en, isNotEmpty);
      for (final List<double> s in f.slots) {
        expect(s[0], inInclusiveRange(0, 1), reason: f.en);
        expect(s[1], inInclusiveRange(0, 1), reason: f.en);
      }
    }
    // an old saved index past the list still loads
    expect(bmSlots(42), kBmForms.last.slots);
    for (final int fld in <int>[0, 6]) {
      for (int a = 0; a < kBmForms.length; a++) {
        for (int b = 0; b < kBmForms.length; b++) {
          final BmEngine e = BmEngine(_Hooks(), rng: math.Random(1))
            ..startMatch(BmConfig(
                mode: 'local', teams: const <String>['club0', 'club1'], form: <int>[a, b], names: const <String>['A', 'B'],
                field: fld, ball: 0));
          final List<BmBody> d = e.bodies.where((BmBody x) => x != e.ball).toList();
          expect(d.length, 10);
          for (final BmBody x in d) {
            expect(x.x - x.r, greaterThanOrEqualTo(e.Fl), reason: '$a/$b');
            expect(x.x + x.r, lessThanOrEqualTo(e.Fr), reason: '$a/$b');
            // each side kicks off in its own half
            expect(x.team == 0 ? x.y > e.CY : x.y < e.CY, isTrue, reason: '$a/$b');
            final BmBody bl = e.ball!;
            expect(math.sqrt(math.pow(x.x - bl.x, 2) + math.pow(x.y - bl.y, 2)), greaterThan(x.r + bl.r), reason: '$a/$b');
            for (final BmBody y in d) {
              if (identical(x, y)) continue;
              expect(math.sqrt(math.pow(x.x - y.x, 2) + math.pow(x.y - y.y, 2)), greaterThan(2 * PR), reason: '$a/$b');
            }
          }
        }
      }
    }
  });

  test('formations: depth and width follow the slots; the top side is the same shape turned round', () {
    for (int fi = 0; fi < kBmForms.length; fi++) {
      final BmEngine e = BmEngine(_Hooks(), rng: math.Random(1))
        ..startMatch(BmConfig(
            mode: 'local', teams: const <String>['club0', 'club1'], form: <int>[fi, fi], names: const <String>['A', 'B'],
            field: 0, ball: 0));
      final List<BmBody> bot = e.bodies.where((BmBody x) => x.team == 0).toList();
      final List<BmBody> top = e.bodies.where((BmBody x) => x.team == 1).toList();
      for (int k = 0; k < 5; k++) {
        final List<double> s = kBmForms[fi].slots[k];
        expect(bot[k].y, closeTo(e.Fb - s[1] * e.Fh / 2, 1e-6));
        expect(bot[k].x, closeTo((e.Fl + s[0] * e.Fw).clamp(e.Fl + PR + 6, e.Fr - PR - 6), 1e-6));
        expect(top[k].x, closeTo(2 * e.CX - bot[k].x, 1e-6));
        expect(top[k].y, closeTo(2 * e.CY - bot[k].y, 1e-6));
      }
    }
    // Nish as measured on the reference kickoff: keeper 0.126 deep, wide pair 0.275 / 0.725 of the width.
    final List<List<double>> nish = kBmForms.firstWhere((BmFormation f) => f.fa == 'نیش').slots;
    expect(nish.first, <double>[.5, .126]);
    expect(nish[3], <double>[.275, .898]);
  });

  test('formations online: both phones put every global side in the same place (mirror)', () {
    BmEngine mk(bool mirror) => BmEngine(_Hooks(), rng: math.Random(1))
      ..startMatch(BmConfig(
          mode: 'online', teams: const <String>['club0', 'club1'], form: const <int>[7, 4], names: const <String>['A', 'B'],
          field: 0, ball: 0, mirror: mirror));
    final BmEngine h = mk(false), g = mk(true);
    // snapshots are global and keyed by piece id: identical at kickoff means both phones agree on every disc
    expect(g.snapshot()['b'], h.snapshot()['b']);
    expect((h.snapshot()['b'] as List<dynamic>).length, 11);
  });

  test('calibration v2: reference speeds agree once each side\'s reference power is divided out', () {
    // Full pull at power 10, in reference px/s (1 px = 2.88 world units on the 325 px reference pitch).
    final double full10 = (260 + 1085) * K * kBmLaunch * BmEngine.strikeOf(10) / 2.88;
    expect(full10, inInclusiveRange(1800, 1950));
    // Launch speeds fitted on the reference (px/s) with the side's reference power (Japan 2, PSG 10).
    const List<(String, double)> shots = <(String, double)>[
      ('Japan', 480), ('Japan', 690), ('Japan', 830), // fitted launches (no glide, v2 friction)
      ('Paris Saint-Germain', 1688 / .89), // first-frame mean speed / 1-frame drag loss
    ];
    for (final (String, double) s in shots) {
      final int p = kBmRefPower[s.$1]!;
      final double base = s.$2 * BmEngine.refStrikeOf(10) / BmEngine.refStrikeOf(p);
      // every shot, normalised to power 10, is at most a full pull (+10% fit error)
      // v6: power 10 is now calibrated on the 10/10 recordings (kBmLaunch 1.97); the older tracks stay within 15%
      expect(base, lessThan(full10 * 1.15), reason: '${s.$1} ${s.$2}');
    }
    // ANIX keeps its own team stats (the reference numbers are only used to normalise measurements)
    expect(bmTeam('nat18').power, isNot(2));
  });

  test('calibration v2: a disc slides the same law whether shot or struck, and the shot still stops short', () {
    final BmEngine e = BmEngine(_Hooks(), rng: math.Random(2))..startMatch(_cfg(mode: 'local'));
    final BmBody d = e.bodies.firstWhere((BmBody x) => x.team == 0 && x != e.ball);
    for (final BmBody o in e.bodies) {
      if (o != d) o.x = -9999; // nothing to hit
    }
    d.x = e.CX;
    d.y = e.Fb - 60;
    final double y0 = d.y;
    e.launch(d, 0, -700 * 2.88, false); // a 700 px/s (Japan-like) shot
    expect(d.boost, 0);
    for (int i = 0; i < 240 * 3; i++) {
      e.sim(STEP);
    }
    // reference: such a shot glides ~190 px (= ~550 world) and stops
    expect((y0 - d.y) / 2.88, inInclusiveRange(150, 230));
    expect(d.vx == 0 && d.vy == 0, isTrue);
  });

  test('calibration v2: the ball shoves a resting disc harder, struck discs are not capped', () {
    double struckSpeed() {
      final BmEngine e = BmEngine(_Hooks(), rng: math.Random(2))..startMatch(_cfg(mode: 'local'));
      final BmBody d = e.bodies.firstWhere((BmBody x) => x.team == 0 && x != e.ball);
      final BmBody b = e.ball!;
      for (final BmBody o in e.bodies) {
        if (o != d && o != b) o.x = -9999;
      }
      d
        ..x = e.CX
        ..y = e.CY
        ..vx = 0
        ..vy = 0;
      b
        ..x = e.CX
        ..y = e.CY + PR + BR + 1
        ..vx = 0
        ..vy = -3000;
      e.phase = 'move';
      e.remote = true;
      e.sim(STEP);
      e.sim(STEP);
      return math.sqrt(d.vx * d.vx + d.vy * d.vy);
    }

    final double v = struckSpeed();
    // old tuning: 1/HV impulse then capped at PCAP (190 * K ~ 241 world/s); v2: full mass-ratio push
    expect(v, greaterThan(PCAP * K * 2));
    expect(v, lessThan(3000));
  });

  test('in-match formation change: now on the own kickoff, else at the next kickoff', () {
    BmEngine fresh(int f0, int f1) => BmEngine(_Hooks(), rng: math.Random(1))
      ..startMatch(BmConfig(
          mode: 'local', teams: const <String>['club0', 'club1'], form: <int>[f0, f1], names: const <String>['A', 'B'],
          field: 0, ball: 0));
    final BmEngine e = fresh(0, 0);
    expect(e.turn, 0);
    expect(e.canReformNow(0), isTrue);
    expect(e.canReformNow(1), isFalse);
    // side 0 to kick: applies at once, discs exactly where a match started with that shape puts them
    expect(e.changeForm(0, 6), isTrue);
    expect(e.snapshot()['b'], fresh(6, 0).snapshot()['b']);
    // side 1 is not to play: stored, discs untouched until the next kickoff
    final Object before = e.snapshot()['b'] as Object;
    expect(e.changeForm(1, 4), isFalse);
    expect(e.snapshot()['b'], before);
    expect(e.form, <int>[6, 4]);
    e.reset(0);
    expect(e.snapshot()['b'], fresh(6, 4).snapshot()['b']);
    // after a shot the own side also waits for the next kickoff
    final BmBody d = e.bodies.firstWhere((BmBody x) => x.team == 0 && x != e.ball);
    e.fire(d, 0, -100, 100);
    expect(e.changeForm(0, 2), isFalse);
    expect(e.form[0], 2);
    expect(e.changeForm(0, 99), isFalse); // clamped
    expect(e.form[0], kBmForms.length - 1);
  });

  test('in-match formation change online: both phones apply the logged move identically (mirror)', () {
    BmEngine mk(bool mirror) => BmEngine(_Hooks(), rng: math.Random(1))
      ..startMatch(BmConfig(
          mode: 'online', teams: const <String>['club0', 'club1'], form: const <int>[0, 0], names: const <String>['A', 'B'],
          field: 0, ball: 0, mirror: mirror));
    final BmEngine h = mk(false), g = mk(true);
    // the move as sent over the net: global side + formation index, applied by both phones in log order
    final List<Map<String, int>> log = <Map<String, int>>[
      <String, int>{'side': 0, 'form': 8}, // host kicks off: now
      <String, int>{'side': 1, 'form': 5}, // guest, not its turn: next kickoff
    ];
    for (final Map<String, int> m in log) {
      expect(h.changeForm(m['side']!, m['form']!), g.changeForm(m['side']!, m['form']!));
    }
    expect(g.snapshot()['b'], h.snapshot()['b']);
    expect(h.form, g.form);
    h.reset(1);
    g.reset(g.ct(1));
    expect(g.snapshot()['b'], h.snapshot()['b']);
    // on the guest phone (mirrored) its own side is 1 globally: its kickoff now accepts its own change at once
    expect(g.canReformNow(1), isTrue);
    expect(h.canReformNow(1), isTrue);
    g.changeForm(1, 2);
    h.changeForm(1, 2);
    expect(g.snapshot()['b'], h.snapshot()['b']);
  });

  test('reference aim: arrow, pull circle and dots scale with the pull', () {
    expect(bmAimPower(LMAX * 2), 1);
    expect(bmAimArrowTip(PR, 1) / PR, closeTo(4.0, 1e-9));
    expect(bmAimArrowTip(PR, 0) / PR, closeTo(2.4, 1e-9));
    expect(bmAimCircleRadius(PR, 1) / PR, closeTo(4.8, 1e-9));
    expect(bmAimDots(20, PR), 1);
    expect(bmAimDots(LMAX, PR), 3);
    expect(bmAimDots(LMAX * 3, PR), 5);
  });

  // ------------------------------------------------------------ v3 (owner request 2026-11-20)
  BmEngine lone({bool disc = false}) {
    final BmEngine e = BmEngine(_Hooks(), rng: math.Random(5))..startMatch(_cfg(mode: 'local'));
    final BmBody keep = e.bodies.firstWhere((BmBody x) => x != e.ball);
    e.bodies.removeWhere((BmBody o) => o != e.ball && !(disc && o == keep));
    e.phase = 'move';
    e.remote = true;
    return e;
  }

  test('v3: a spinning ball travels in a straight line', () {
    final BmEngine e = lone();
    final BmBody b = e.ball!
      ..x = e.CX
      ..y = e.CY + 300
      ..vx = 0
      ..vy = -1500
      ..spin = 30;
    for (int i = 0; i < 40; i++) {
      e.sim(STEP);
    }
    expect(b.vx.abs(), lessThan(1e-6));
    expect(b.x, closeTo(e.CX, 1e-6));
  });

  test('v3: ball and discs keep their power off the rails', () {
    final BmEngine e = lone();
    final BmBody b = e.ball!
      ..x = e.Fl + BR + 2
      ..y = e.CY
      ..vx = -2000
      ..vy = 0;
    e.sim(STEP);
    e.sim(STEP);
    expect(b.vx, greaterThan(2000 * kBmRailE * .97));
    final BmEngine f = lone(disc: true);
    f.ball!
      ..x = f.CX
      ..y = f.CY;
    final BmBody d = f.bodies.firstWhere((BmBody x) => x != f.ball)
      ..x = f.Fr - PR - 2
      ..y = f.CY
      ..vx = 2000
      ..vy = 0;
    f.sim(STEP);
    f.sim(STEP);
    expect(d.vx, lessThan(-2000 * kBmRailE * .9));
  });

  double massShare(double discM, double e) => (1 + e) * (1 / discM) / (1 / discM + 1 / BALL_M);

  test('v3: the ball knocks a lighter disc back; a disc strike on the ball is unchanged', () {
    final BmEngine e = BmEngine(_Hooks(), rng: math.Random(2))..startMatch(_cfg(mode: 'local'));
    final BmBody d = e.bodies.firstWhere((BmBody x) => x.team == 0 && x != e.ball);
    final BmBody b = e.ball!;
    for (final BmBody o in e.bodies) {
      if (o != d && o != b) o.x = -9999;
    }
    d
      ..x = e.CX
      ..y = e.CY
      ..vx = 0
      ..vy = 0;
    b
      ..x = e.CX
      ..y = e.CY + PR + BR + 1
      ..vx = 0
      ..vy = -3000;
    e.phase = 'move';
    e.remote = true;
    e.sim(STEP);
    e.sim(STEP);
    final double v = math.sqrt(d.vx * d.vx + d.vy * d.vy);
    // heavier than the old 8-mass share, still below the light-mass share of the full 3000
    expect(v, greaterThan(.97 * 2950 * massShare(DISC_M, .43)));
    expect(v, greaterThan(1.1 * 3000 * massShare(DISC_M, .55)));
    expect(v, lessThan(3000 * massShare(kBmDiscLightM, .55)));

    // disc strikes a resting ball: ball speed follows DISC_M (shot power unchanged)
    final BmEngine g = BmEngine(_Hooks(), rng: math.Random(2))..startMatch(_cfg(mode: 'local'));
    final BmBody s = g.bodies.firstWhere((BmBody x) => x.team == 0 && x != g.ball);
    final BmBody gb = g.ball!;
    for (final BmBody o in g.bodies) {
      if (o != s && o != gb) o.x = -9999;
    }
    gb
      ..x = g.CX
      ..y = g.CY
      ..vx = 0
      ..vy = 0;
    s
      ..x = g.CX
      ..y = g.CY + PR + BR + 1
      ..vx = 0
      ..vy = -3000;
    g.phase = 'move';
    g.remote = true;
    g.sim(STEP);
    g.sim(STEP);
    final double bv = math.sqrt(gb.vx * gb.vx + gb.vy * gb.vy);
    final double share8 = (1 / BALL_M) / (1 / DISC_M + 1 / BALL_M);
    expect(bv, lessThan(1.55 * 3000 * share8 * BKICK));
    expect(bv, greaterThan(1.3 * 2900 * share8 * BKICK));
  });

  test('v3: the match clock runs on real time; the scene plays 5% slower with the same steps', () {
    final BmEngine e = BmEngine(_Hooks(), rng: math.Random(3))..startMatch(_cfg(mode: 'local'));
    e.frame(.2);
    expect(e.mleft, closeTo(299.8, 1e-9));
    expect(kBmSimRate, closeTo(.85, 1e-12)); // v5: 85% speed (was .95)
    // same sequence of fixed steps -> same result whatever the playback rate
    BmEngine run() {
      final BmEngine x = lone();
      x.ball!
        ..x = x.CX
        ..y = x.CY
        ..vx = 900
        ..vy = -1700;
      for (int i = 0; i < 600; i++) {
        x.sim(STEP);
      }
      return x;
    }

    expect(run().ball!.x, run().ball!.x);
  });
}
