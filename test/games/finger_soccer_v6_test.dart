// Finger soccer v6 (owner request 2026-11-20, two reference recordings with 10 / 10 sides): power-10 calibration,
// proportional power scale, the classic reference ball, the post-goal hold + glide home, the end-of-match score table.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/core/game_contract.dart';
import 'package:nexora/games/finger_soccer/core/bm_data.dart';
import 'package:nexora/games/finger_soccer/core/bm_engine.dart';
import 'package:nexora/games/finger_soccer/intro/fs_score_table.dart';

class _H implements BmHooks {
  final List<String> events = <String>[];
  @override
  void sfx(String k, [double v = 1]) {}
  @override
  void tone(String k) {}
  @override
  void vib(List<int> p) {}
  @override
  void toast(String t, bool b) {}
  @override
  void goalFx() {}
  @override
  void emit(String e, Map<String, dynamic> d) => events.add(e);
}

BmEngine _eng({String mode = 'local', bool mirror = false, int seed = 1}) => BmEngine(_H(), rng: math.Random(seed))
  ..startMatch(BmConfig(
      mode: mode,
      teams: const <String>['nx_frost', 'club0'],
      form: const <int>[0, 0],
      names: const <String>['A', 'B'],
      field: 0,
      ball: kBmDefaultBall,
      matchTime: 300,
      mirror: mirror));

/// Power-10 disc fired at a resting ball (straight up the pitch, nothing else on it); returns the ball's ON-SCREEN
/// speed averaged over its first 0.2 s, in playing widths per second (the unit of docs/FS_V6_CALIBRATION.md).
double _ball02(double pull, {String team = 'nx_frost'}) {
  final BmEngine e = BmEngine(_H(), rng: math.Random(1))
    ..startMatch(BmConfig(
        mode: 'local', teams: <String>[team, 'club0'], form: const <int>[0, 0], names: const <String>['A', 'B'], field: 0, ball: 0));
  final BmBody d = e.bodies.firstWhere((BmBody x) => x.team == 0 && x != e.ball);
  final BmBody bl = e.ball!;
  for (final BmBody o in e.bodies) {
    if (o != d && o != bl) {
      o.x = -5000 - o.cid * 300.0;
      o.y = -5000;
    }
  }
  d
    ..x = e.CX
    ..y = e.Fb - 70;
  bl
    ..x = e.CX
    ..y = e.Fb - 70 - PR - BR - 30;
  e.fire(d, 0, -LMAX * pull, LMAX * pull);
  double? t0, y0;
  double t = 0;
  for (int i = 0; i < 240 * 3; i++) {
    e.sim(STEP);
    t += STEP / kBmSimRate; // on-screen time
    if (bl.vy != 0 && t0 == null) {
      t0 = t;
      y0 = bl.y;
      d
        ..x = -4000
        ..y = -9000
        ..vx = 0
        ..vy = 0; // the shooter leaves so it cannot hit the ball twice
    }
    if (t0 != null && t - t0 >= .2) return (y0! - bl.y) / (t - t0) / e.Fw;
  }
  return 0;
}

void main() {
  test('v6 calibration: a power-10 full pull gives the recordings\' hardest ball (4.57 widths/s over 0.2 s)', () {
    expect(_ball02(1), closeTo(4.57, .12));
    // a softer pull is slower, never faster
    expect(_ball02(.5), lessThan(_ball02(1)));
    // the caps never clip a power-10 full pull
    final BmEngine e = _eng();
    final BmBody d = e.bodies.firstWhere((BmBody x) => x.team == 0 && x != e.ball);
    e.fire(d, 0, -LMAX, LMAX);
    expect(math.sqrt(d.vx * d.vx + d.vy * d.vy), lessThan(kBmDiscVMax * K));
  });

  test('v6 power scale: 10 is the calibrated maximum, every lower power a fixed share below it', () {
    expect(BmEngine.powerShare(10), 1);
    expect(BmEngine.powerShare(2), closeTo(.40, .01)); // reference: Japan (2) vs PSG (10)
    for (int p = 1; p < 10; p++) {
      expect(BmEngine.powerShare(p), lessThan(BmEngine.powerShare(p + 1)));
    }
    // a team's launch is exactly its share of the power-10 launch
    double launch(String team) {
      final BmEngine e = BmEngine(_H(), rng: math.Random(5))
        ..startMatch(BmConfig(
            mode: 'local', teams: <String>[team, 'club1'], form: const <int>[0, 0], names: const <String>['A', 'B'], field: 0, ball: 0));
      final BmBody b = e.bodies.firstWhere((BmBody x) => x.team == 0 && x != e.ball);
      e.fire(b, 0, -LMAX, LMAX);
      return math.sqrt(b.vx * b.vx + b.vy * b.vy) / BmEngine.powerShare(b.power);
    }

    expect(launch('nx_core'), closeTo(launch('nx_frost'), 1e-6));
    expect(launch('nx_cyan'), closeTo(launch('nx_frost'), 1e-6));
  });

  test('v6 classic ball is gone (v9: the owner art is the only ball set); a Classic art ball exists', () {
    expect(kBmBallN.contains('Classic'), isTrue);
    expect(kBmBallFa.length, NB);
    expect(File(bmBallArt(kBmBallN.indexOf('Classic'))).existsSync(), isTrue);
    expect(kBmBallPref, 'bm.ball.v9');
  });

  test('v6 goal: banner hold, then the pieces glide home (render only) before the kickoff turn', () {
    final BmEngine e = _eng();
    final Map<int, List<double>> kick = <int, List<double>>{for (final BmBody b in e.bodies) b.cid: <double>[b.x, b.y]};
    // move pieces off their slots, then score
    for (final BmBody b in e.bodies) {
      b.x += 40;
      b.y -= 30;
    }
    e.shots = 3;
    e.scored(1);
    expect(e.phase, 'goal');
    expect(e.pause, kBmGoalHold);
    double t = 0;
    while (e.phase == 'goal' && t < 5) {
      e.frame(1 / 60);
      t += 1 / 60;
    }
    expect(t, closeTo(kBmGoalHold, .05));
    // the bodies already stand on their kickoff slots; only the drawing glides
    for (final BmBody b in e.bodies) {
      expect(b.x, closeTo(kick[b.cid]![0], 1e-9));
      expect(b.y, closeTo(kick[b.cid]![1], 1e-9));
    }
    expect(e.glide, greaterThan(0));
    expect(e.glideK, greaterThan(.9));
    expect(e.canCtl(), isFalse);
    final double tl = e.tleft;
    for (int i = 0; i < 30; i++) {
      e.frame(1 / 60);
    }
    expect(e.tleft, tl); // the turn clock waits for the glide
    while (e.glide > 0) {
      e.frame(1 / 60);
    }
    expect(e.glideK, 0);
    expect(e.canCtl(), isTrue);
  });

  test('v6 goal glide never desyncs two phones (mirrored guest)', () {
    final BmEngine h = _eng(mode: 'online'), g = _eng(mode: 'online', mirror: true);
    for (final BmEngine e in <BmEngine>[h, g]) {
      e.shots = 2;
      e.scored(0);
      for (int i = 0; i < 60 * 4; i++) {
        e.frame(1 / 60);
      }
    }
    expect(g.snapshot()['b'], h.snapshot()['b']);
  });

  test('GameResult.holdMs defaults to the host pause', () {
    expect(const GameResult(outcome: GameOutcome.win).holdMs, isNull);
    expect(const GameResult(outcome: GameOutcome.win, holdMs: 20000).holdMs, 20000);
  });

  testWidgets('v6 score table: winner first, countdown in Persian digits', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: FsScoreTable(
          seconds: 16,
          rows: <FsScoreRow>[
            FsScoreRow(name: 'ORGIFANS', score: 3, crest: 'assets/games/bermuda/discs/v9/nx_core.webp', winner: true),
            FsScoreRow(name: 'Arefe', score: 1, crest: 'assets/games/bermuda/discs/v9/nx_core.webp'),
          ],
        ),
      ),
    ));
    expect(find.text('جدول امتیازات'), findsOneWidget);
    expect(find.text('۱۶ ثانیه تا بازگشت به جمع'), findsOneWidget);
    expect(find.byIcon(Icons.emoji_events_rounded), findsOneWidget);
    expect(kFsScoreTableSeconds, 20);
    await tester.binding.setSurfaceSize(null);
  });
}
