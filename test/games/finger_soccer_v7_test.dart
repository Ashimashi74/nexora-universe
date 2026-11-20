// Finger soccer v7 (owner request 2026-11-20): goal posts and the inside of the goal rebound exactly like the rails
// (ball and discs), the six owner art pack pitches are removed (saved / synced picks fall back to the default
// pitch), the GIF balls NX Spin (new default) and NX Star play the GIF's own frames at 90 ms, and the in-match
// formation button sits beside the game bar.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/storage/local_store.dart';
import 'package:nexora/games/core/game_contract.dart';
import 'package:nexora/games/finger_soccer/core/bm_data.dart';
import 'package:nexora/games/finger_soccer/core/bm_engine.dart';
import 'package:nexora/games/finger_soccer/intro/fs_intro_data.dart';
import 'package:nexora/games/finger_soccer/intro/fs_intro_ui.dart';
import 'package:nexora/games/finger_soccer/ui/bm_painter.dart';
import 'package:nexora/games/finger_soccer/ui/bm_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

BmConfig _cfg({int field = 0, int ball = kBmDefaultBall}) => BmConfig(
    mode: 'local',
    teams: const <String>['lux0', 'lux1'],
    form: const <int>[0, 0],
    names: const <String>['A', 'B'],
    field: field,
    ball: ball,
    matchTime: 300);

/// Engine with only the ball (and optionally one disc) on the pitch, play running, no goal detection (remote).
BmEngine _lone({bool disc = false, int field = 0}) {
  final BmEngine e = BmEngine(_H(), rng: math.Random(3))..startMatch(_cfg(field: field));
  final BmBody keep = e.bodies.firstWhere((BmBody x) => x != e.ball);
  e.bodies.removeWhere((BmBody o) => o != e.ball && !(disc && o == keep));
  e.phase = 'move';
  e.remote = true;
  if (disc) {
    // park the ball in the opposite half, out of the way
    e.ball!
      ..x = e.CX
      ..y = e.CY
      ..vx = 0
      ..vy = 0;
  }
  return e;
}

BmBody _body(BmEngine e, bool disc) => disc ? e.bodies.firstWhere((BmBody x) => x != e.ball) : e.ball!;

const double _v = 1800;
const int _steps = 3;

/// Speed after / speed before for a body fired with ([vx], [vy]) from ([x], [y]) for a few fixed steps.
double _ratio(bool disc, double Function(BmEngine e, double r) x, double Function(BmEngine e, double r) y, double vx,
    double vy,
    {int field = 0}) {
  final BmEngine e = _lone(disc: disc, field: field);
  final BmBody b = _body(e, disc);
  b
    ..x = x(e, b.r)
    ..y = y(e, b.r)
    ..vx = vx
    ..vy = vy
    ..spin = 0;
  for (int i = 0; i < _steps; i++) {
    e.sim(STEP);
  }
  // the rebound reversed the travel direction
  if (vx != 0) expect(b.vx.sign, -vx.sign, reason: 'x not reversed');
  if (vy != 0) expect(b.vy.sign, -vy.sign, reason: 'y not reversed');
  return math.sqrt(b.vx * b.vx + b.vy * b.vy) / math.sqrt(vx * vx + vy * vy);
}

double _rail(bool disc, {int field = 0}) =>
    _ratio(disc, (BmEngine e, double r) => e.Fl + r + 2, (BmEngine e, double r) => e.CY, -_v, 0, field: field);

/// Into the back net of the top goal (team side 0 shoots at GOALS[?]: use whichever goal has d == -1).
double _backNet(bool disc, {int field = 0}) {
  final BmEngine probe = _lone(field: field);
  final int gi = probe.GOALS.indexWhere((BmGoal g) => g.d < 0);
  return _ratio(disc, (BmEngine e, double r) => (e.GOALS[gi].x1 + e.GOALS[gi].x2) / 2,
      (BmEngine e, double r) => e.GOALS[gi].y - (e.DEPTH - r - 2), 0, -_v,
      field: field);
}

/// Into the left side net, deep inside the top goal.
double _sideNet(bool disc, {int field = 0}) {
  final BmEngine probe = _lone(field: field);
  final int gi = probe.GOALS.indexWhere((BmGoal g) => g.d < 0);
  return _ratio(disc, (BmEngine e, double r) => e.GOALS[gi].x1 + r + 2,
      (BmEngine e, double r) => e.GOALS[gi].y - math.max(r * .9, e.DEPTH * .5), -_v, 0,
      field: field);
}

/// Head-on into the left post of the top goal, from the pitch side.
double _post(bool disc, {int field = 0}) {
  final BmEngine probe = _lone(field: field);
  final int gi = probe.GOALS.indexWhere((BmGoal g) => g.d < 0);
  return _ratio(disc, (BmEngine e, double r) => e.GOALS[gi].px1,
      (BmEngine e, double r) => e.GOALS[gi].y + r + e.GOALS[gi].pr + 2, 0, -_v,
      field: field);
}

void main() {
  group('v7 rebound parity: posts and goal nets bounce exactly like the rails', () {
    for (final bool disc in <bool>[false, true]) {
      final String who = disc ? 'disc' : 'ball';
      for (final int field in <int>[0, 6]) {
        test('$who on field $field: back net, side net and post = rail', () {
          final double rail = _rail(disc, field: field);
          expect(rail, closeTo(kBmRailE, .06), reason: 'rail keeps ~kBmRailE (minus a few steps of felt friction)');
          expect(_backNet(disc, field: field), closeTo(rail, .005), reason: 'back net');
          expect(_sideNet(disc, field: field), closeTo(rail, .005), reason: 'side net');
          expect(_post(disc, field: field), closeTo(rail, .005), reason: 'post');
        });
      }
    }

    test('post restitution no longer depends on speed (old ball post was 1.54-1.7 speed dependent)', () {
      double at(double v) {
        final BmEngine e = _lone();
        final BmGoal g = e.GOALS.firstWhere((BmGoal x) => x.d < 0);
        final BmBody b = e.ball!
          ..x = g.px1
          ..y = g.y + BR + g.pr + 2
          ..vx = 0
          ..vy = -v;
        for (int i = 0; i < _steps; i++) {
          e.sim(STEP);
        }
        return b.vy / v;
      }

      expect(at(600), closeTo(at(2600), .02));
    });
  });

  group('v7 pitches: six art pack pitches removed, old picks fall back to the default pitch', () {
    test('catalog, ids and assets', () {
      expect(kBmFieldsRaw.length, 30);
      expect(kBmFields.length, 30);
      final Set<String> ids = kBmFieldsRaw.map((BmField f) => f.id).toSet();
      for (final String id in kBmRemovedFieldIds) {
        expect(ids.contains(id), isFalse, reason: id);
        expect(File('assets/games/bermuda/fields/$id.webp').existsSync(), isFalse, reason: id);
        expect(File('assets/games/bermuda/thumbs/$id.webp').existsSync(), isFalse, reason: id);
      }
      const List<String> names = <String>['Street Cage', 'Neon Cup', 'Gold Leather', 'Sockerbox', 'Royal Gold', 'Neon Grass'];
      for (final BmField f in kBmFieldsRaw) {
        expect(names.contains(f.name), isFalse, reason: f.name);
        expect(File(f.asset ?? 'assets/games/bermuda/fields/${f.id}.webp').existsSync(), isTrue, reason: f.id);
        expect(File('assets/games/bermuda/thumbs/${f.id}.webp').existsSync(), isTrue, reason: f.id);
      }
      // the remaining order is unchanged, so every saved index below 30 still names the same pitch
      expect(kBmFieldsRaw.first.id, 'nexora_green');
      expect(kBmFieldsRaw[6].id, 'lava');
      expect(kBmFieldsRaw.last.id, 'mancity');
    });

    test('a removed (or any invalid) pitch index falls back to the default pitch', () {
      for (int i = 30; i < 36; i++) {
        expect(bmFieldIndex(i), 0);
      }
      expect(bmFieldIndex(null), 0);
      expect(bmFieldIndex(-1), 0);
      expect(bmFieldIndex(7), 7);
      expect(bmFieldIndex(29), 29);
      final BmEngine e = BmEngine(_H(), rng: math.Random(1))..startMatch(_cfg(field: 33));
      expect(e.setFld, 0);
      expect(e.field.id, 'nexora_green');
    });
  });

  group('v7 balls: NX Spin is the default, both GIF balls play the GIF frames at 90 ms', () {
    test('catalog and default', () {
      expect(kBmDefaultBall, kBmNxSpinBallIndex);
      expect(kBmBallN[kBmNxSpinBallIndex], 'NX Spin');
      expect(kBmBallN[kBmNxStarBallIndex], 'NX Star');
      expect(kBmBallFa.length, NB);
      final BmAnimBall spin = kBmAnimBalls[kBmNxSpinBallIndex]!;
      final BmAnimBall star = kBmAnimBalls[kBmNxStarBallIndex]!;
      expect(spin.frames, 24);
      expect(star.frames, 16);
      expect(spin.frameMs, 90);
      expect(star.frameMs, 90);
      expect(spin.gifTimed, isTrue);
      expect(star.gifTimed, isTrue);
      expect(kBmAnimBalls[0]!.gifTimed, isFalse); // older balls keep their roll animation
      for (final BmAnimBall b in <BmAnimBall>[spin, star]) {
        expect(File(b.sheet).existsSync(), isTrue, reason: b.sheet);
        expect(File(b.thumb).existsSync(), isTrue, reason: b.thumb);
      }
      expect(bmBallThumb(kBmNxSpinBallIndex), spin.thumb);
    });

    test('saved / synced ball index: missing or unknown = the new default; v7 preference key', () {
      expect(kBmBallPref, 'bm.ball.v7');
      expect(bmBallIndex(null), kBmNxSpinBallIndex);
      expect(bmBallIndex(99), kBmNxSpinBallIndex);
      expect(bmBallIndex(-1), kBmNxSpinBallIndex);
      expect(bmBallIndex(kBmClassicBallIndex), kBmClassicBallIndex);
      final BmEngine e = BmEngine(_H(), rng: math.Random(1))..startMatch(_cfg(ball: 42));
      expect(e.setBall, kBmNxSpinBallIndex);
    });

    test('GIF playback: GIF order, exactly 90 ms per frame, looping; only while the ball moves', () {
      expect(bmGifFrame(0, 90, 24), 0);
      expect(bmGifFrame(89.9, 90, 24), 0);
      expect(bmGifFrame(90, 90, 24), 1);
      expect(bmGifFrame(90.0 * 23, 90, 24), 23);
      expect(bmGifFrame(90.0 * 24, 90, 24), 0);
      expect(bmGifFrame(90.0 * 17 + 45, 90, 16), 1);
      final List<int> seq = <int>[for (int ms = 0; ms < 24 * 90; ms += 90) bmGifFrame(ms.toDouble(), 90, 24)];
      expect(seq, List<int>.generate(24, (int i) => i));
      expect(kBmAnimBalls[kBmNxSpinBallIndex]!.frameAt(180), 2);
      expect(bmGifBallPlays(0), isFalse);
      expect(bmGifBallPlays(300), isTrue);
    });
  });

  group('v7 widgets', () {
    void phone(WidgetTester tester) {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    Future<void> pumpFor(WidgetTester tester, num seconds) async {
      for (int i = 0; i < (seconds * 4).round(); i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
    }

    GameLaunch launch() => GameLaunch(
          gameId: 'finger_soccer',
          mode: GameMode.vsBot,
          difficulty: BotDifficulty.normal,
          playerName: 'Ali',
          isFa: true,
          fancyEffects: false,
          reducedMotion: true,
          soundOn: false,
          seed: 7,
          onFinish: (_) {},
        );

    Widget host() => ProviderScope(
        child: MaterialApp(
            home: Scaffold(
                backgroundColor: Colors.black,
                // the intro flow's pick: the match starts once the saved prefs are loaded (as in the app)
                body: BermudaView(
                    launch: launch(),
                    autoStart: true,
                    pick: const FsMatchPick(teams: <String>['club0', 'club1'], forms: <int>[0, 0])))));

    Future<BmEngine> start(WidgetTester tester, Map<String, Object> prefs) async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues(<String, Object>{'settings.lang': 'fa', 'settings.sound': false, ...prefs});
      await LocalStore.init();
      phone(tester);
      await tester.pumpWidget(host());
      await pumpFor(tester, 1);
      return (tester.state(find.byType(BermudaView)) as dynamic).matchEngine as BmEngine;
    }

    Future<void> close(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('an account that had a removed pitch and the old v6 ball starts on the default pitch + NX Spin',
        (WidgetTester tester) async {
      final BmEngine e = await start(tester, <String, Object>{'bm.field': 33, 'bm.ball.v6': 1});
      expect(e.setFld, 0);
      expect(e.setBall, kBmNxSpinBallIndex);
      expect(tester.takeException(), isNull);
      await close(tester);
    });

    testWidgets('a ball picked under the v7 key is kept', (WidgetTester tester) async {
      final BmEngine e = await start(tester, <String, Object>{'bm.field': 7, kBmBallPref: kBmNxStarBallIndex});
      expect(e.setFld, 7);
      expect(e.setBall, kBmNxStarBallIndex);
      await close(tester);
    });

    testWidgets('the formation button is shown and sits beside the game bar, on its row', (WidgetTester tester) async {
      await start(tester, const <String, Object>{});
      expect(find.byType(BmChangeFormButton), findsOneWidget);
      expect(find.text('تغییر ترکیب'), findsOneWidget);
      final Rect bar = tester.getRect(find.byType(FsBarHandle));
      final Rect btn = tester.getRect(find.byType(BmChangeFormButton));
      expect(btn.left, greaterThanOrEqualTo(bar.right));
      expect(btn.left - bar.right, lessThanOrEqualTo(12));
      expect(btn.center.dy, closeTo(bar.center.dy, 1));
      expect(btn.bottom, lessThanOrEqualTo(800));
      // still works: opens the formation picker
      await tester.tap(find.byType(BmChangeFormButton));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(BmFormationCard), findsNWidgets(kBmForms.length));
      expect(tester.takeException(), isNull);
      await close(tester);
    });
  });
}
