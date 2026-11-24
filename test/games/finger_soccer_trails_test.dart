// v13 disc trails (bm_trails.dart): render-only, time based, side coloured.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/finger_soccer/core/bm_data.dart';
import 'package:nexora/games/finger_soccer/core/bm_engine.dart';
import 'package:nexora/games/finger_soccer/ui/bm_trails.dart';

class _H implements BmHooks {
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
  void emit(String e, Map<String, dynamic> d) {}
}

BmConfig _cfg() => const BmConfig(
    mode: 'bot',
    teams: <String>['nx_frost', 'realmadrid'],
    form: <int>[0, 1],
    names: <String>['A', 'B'],
    field: 0,
    ball: kBmDefaultBall,
    matchTime: 300,
    ai: false);

void main() {
  test('sides use different trail palettes from kBmTR', () {
    expect(kBmTR.contains(bmSideTrail(0)), isTrue);
    expect(kBmTR.contains(bmSideTrail(1)), isTrue);
    expect(bmSideTrail(0).c.first, isNot(bmSideTrail(1).c.first));
  });

  test('a sliding disc leaves points that fade within the trail life', () {
    final BmEngine e = BmEngine(_H(), rng: math.Random(1))..startMatch(_cfg());
    final BmBody d = e.bodies.firstWhere((BmBody b) => b != e.ball);
    final BmDiscTrails tr = BmDiscTrails();
    Offset pos(BmBody b) => Offset(b.x, b.y);
    double t = 1000;
    d.vx = 900;
    d.vy = 0;
    for (int i = 0; i < 10; i++) {
      d.x += 10;
      tr.sample(e, pos, t);
      t += 16;
    }
    expect(tr.pointsOf(d).length, greaterThan(5));
    // the disc stops: no new points, the old ones expire after kBmTrailLifeMs
    d.vx = 0;
    tr.sample(e, pos, t + kBmTrailLifeMs + 1);
    expect(tr.pointsOf(d), isEmpty);
  });

  test('a jump (snapshot / reset) clears the trail instead of smearing it', () {
    final BmEngine e = BmEngine(_H(), rng: math.Random(2))..startMatch(_cfg());
    final BmBody d = e.bodies.firstWhere((BmBody b) => b != e.ball);
    final BmDiscTrails tr = BmDiscTrails();
    Offset pos(BmBody b) => Offset(b.x, b.y);
    d.vx = 900;
    tr.sample(e, pos, 0);
    d.x += 10;
    tr.sample(e, pos, 16);
    expect(tr.pointsOf(d).length, 2);
    d.x += d.r * 10;
    tr.sample(e, pos, 32);
    expect(tr.pointsOf(d).length, 1);
  });

  test('sampling never touches physics state', () {
    final BmEngine e = BmEngine(_H(), rng: math.Random(3))..startMatch(_cfg());
    final BmBody d = e.bodies.firstWhere((BmBody b) => b != e.ball);
    d.vx = 1200;
    final String before = e.bodies.map((BmBody b) => '${b.x},${b.y},${b.vx},${b.vy}').join(';');
    final BmDiscTrails tr = BmDiscTrails();
    for (int i = 0; i < 20; i++) {
      tr.sample(e, (BmBody b) => Offset(b.x + i, b.y), i * 16.0);
    }
    expect(e.bodies.map((BmBody b) => '${b.x},${b.y},${b.vx},${b.vy}').join(';'), before);
  });
}
