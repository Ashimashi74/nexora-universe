// v12 (owner upload 2026-11-24): eleven new pitch arts, 18 new cut balls, the new goal sprite, half ball roll time,
// round corner cushions the ball rolls round, a longer pitch.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/finger_soccer/core/bm_data.dart';
import 'package:nexora/games/finger_soccer/core/bm_engine.dart';

class _Hooks implements BmHooks {
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
  void emit(String event, Map<String, dynamic> data) {}
}

BmEngine _ballOnly(int field) {
  final BmEngine e = BmEngine(_Hooks(), rng: math.Random(1));
  e.startMatch(BmConfig(
    mode: 'bot',
    teams: const <String>['club0', 'club1'],
    form: const <int>[0, 3],
    names: const <String>['A', 'B'],
    field: field,
    ball: 0,
    matchTime: 300,
    ai: true,
    aiLvl: 2,
  ));
  e.bodies.removeWhere((BmBody b) => b != e.ball);
  return e;
}

void main() {
  test('catalog: the eleven owner pitches, their art and thumbs, the separate white goal', () {
    expect(kBmFieldsRaw.map((BmField f) => f.id).toList(), <String>[
      'tropical', 'psg', 'campnou', 'pitch', 'checker', 'futsal', 'arena', 'blackice', 'autumn', 'frost', 'glacier',
    ]);
    for (final BmField f in kBmFieldsRaw) {
      expect(f.gs, 'white', reason: f.id);
      expect(f.faName, isNotEmpty, reason: f.id);
      expect(File('assets/games/bermuda/fields/${f.id}.webp').existsSync(), isTrue, reason: f.id);
      expect(File('assets/games/bermuda/thumbs/${f.id}.webp').existsSync(), isTrue, reason: f.id);
      expect(kBmRemovedFieldIds, isNot(contains(f.id)));
    }
    expect(Directory('assets/games/bermuda/fields').listSync().length, kBmFieldsRaw.length);
    expect(kBmGS.keys, <String>['white']);
    expect(kBmGS['white']![0], 1024);
    expect(File('assets/games/bermuda/goals/white.webp').existsSync(), isTrue);
  });

  test('balls: the 18 owner balls, one cut art each', () {
    expect(kBmBallN.length, 18);
    expect(kBmBallFa.length, 18);
    expect(kBmBallSlug.toSet().length, 18);
    for (int i = 0; i < 18; i++) {
      expect(File(bmBallArt(i)).existsSync(), isTrue, reason: bmBallArt(i));
    }
    expect(Directory('assets/games/bermuda/balls/v9').listSync().length, 18);
  });

  test('longer pitch: lengthwise world stretched, corners at least the cushion radius', () {
    for (final BmFieldS f in kBmFields) {
      expect(f.rc, greaterThanOrEqualTo(kBmCornerR), reason: f.id);
      expect(f.rc, greaterThan(PR), reason: f.id);
    }
    final BmFieldS f = kBmFields.first;
    expect(f.H, (1448 * FS * kBmFieldStretchY).roundToDouble());
    expect(f.W, (1086 * FS).roundToDouble());
  });

  test('half roll time: a hard free ball settles in well under 3 s', () {
    final BmEngine e = _ballOnly(0);
    final BmBody b = e.ball!;
    b
      ..x = e.CX
      ..y = e.CY
      ..vx = 0
      ..vy = 0;
    b.vx = 3000 * K * .2;
    b.vy = 3000 * K;
    double t = 0;
    while ((b.vx != 0 || b.vy != 0) && t < 10) {
      e.sim(STEP);
      t += STEP;
    }
    expect(t, lessThan(3.0));
  });

  test('corners: a ball running up the left rail rolls round the corner onto the top rail', () {
    for (int fi = 0; fi < kBmFields.length; fi++) {
      final BmEngine e = _ballOnly(fi);
      final BmBody b = e.ball!;
      b
        ..x = e.Fl + b.r
        ..y = e.Ft + e.RC + 40
        ..vx = 0
        ..vy = -1200 * K;
      final double v0 = 1200 * K;
      double t = 0;
      while (t < .2) {
        e.sim(STEP);
        t += STEP;
      }
      final double sp = math.sqrt(b.vx * b.vx + b.vy * b.vy);
      expect(b.vx, greaterThan(0), reason: '${kBmFields[fi].id}: now runs along the top rail');
      expect(b.vy.abs(), lessThan(b.vx * .35), reason: kBmFields[fi].id);
      expect(sp, greaterThan(v0 * .45), reason: '${kBmFields[fi].id}: rolled round, not stopped dead');
      expect(b.y, closeTo(e.Ft + b.r, 6), reason: kBmFields[fi].id);
    }
  });
}
