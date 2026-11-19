import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/core/game_contract.dart';
import 'package:nexora/games/obstacle_race/core/obstacle_core.dart';
import 'package:nexora/games/obstacle_race/obstacle_race_entry.dart';

/// Screen size + typical safe-area insets (status bar / notch, gesture bar) in logical px.
class Device {
  const Device(this.name, this.w, this.h, this.top, this.bottom, {this.left = 0, this.right = 0});
  final String name;
  final double w, h, top, bottom, left, right;
}

const List<Device> devices = <Device>[
  Device('360x640', 360, 640, 24, 0),
  Device('393x873 (notch + gesture bar)', 393, 873, 47, 34),
  Device('412x915', 412, 915, 24, 24),
  Device('800x1280 tablet', 800, 1280, 24, 20),
  Device('873x393 landscape with side cut-out', 873, 393, 0, 21, left: 47),
];

// HUD pills sit at pad.top + 64 and are ~40 px tall; the jump button is 92 px at pad.bottom + 22, right + 18.
const double hudBottom = 64 + 44;
const double jumpTop = 22 + 92;

void main() {
  group('viewport', () {
    for (final Device d in devices) {
      test('${d.name}: course fits the safe area at a uniform scale', () {
        final ObViewport vp = ObViewport.fit(d.w, d.h, padTop: d.top, padBottom: d.bottom, padLeft: d.left, padRight: d.right);
        // whole course + rails inside the safe left/right edges
        expect(vp.sx(-ObstacleRace.margin), greaterThanOrEqualTo(d.left - 0.01));
        expect(vp.sx(ObstacleRace.width + ObstacleRace.margin), lessThanOrEqualTo(d.w - d.right + 0.01));
        // centred horizontally inside the safe area
        expect(vp.sx(ObstacleRace.width / 2), closeTo(d.left + (d.w - d.left - d.right) / 2, 0.01));
        // top/bottom follow the insets, nothing drawn for play under the notch or gesture bar
        expect(vp.top, d.top);
        expect(vp.bottom, d.h - d.bottom);
        expect(vp.worldH, greaterThanOrEqualTo(ObstacleRace.minViewH - 0.01));
        // the round-trip is exact (touch steering uses it)
        expect(vp.toWorldX(vp.sx(123)), closeTo(123, 1e-9));
      });

      test('${d.name}: the followed runner sits clear of the HUD, the jump button and the bars', () {
        final ObViewport vp = ObViewport.fit(d.w, d.h, padTop: d.top, padBottom: d.bottom, padLeft: d.left, padRight: d.right);
        final ObCamera cam = ObCamera()..viewH = vp.worldH;
        const double ry = 5000;
        cam.snap(ry);
        final double cy = vp.sy(ry, cam.y);
        final double rad = ObstacleRace.runnerR * vp.scale;
        expect(cy - rad, greaterThan(d.top + hudBottom), reason: 'runner below the HUD');
        expect(cy + rad, lessThan(d.h - d.bottom - jumpTop), reason: 'runner above the jump button row');
        // look-ahead: at least 300 world units of course visible in front
        expect((cy - vp.top) / vp.scale, greaterThan(300));
      });
    }

    test('same proportions on every phone: runner / course / obstacle ratios do not change', () {
      final List<double> ratios = <double>[];
      for (final Device d in devices.take(4)) {
        final ObViewport vp = ObViewport.fit(d.w, d.h, padTop: d.top, padBottom: d.bottom);
        final double courseW = ObstacleRace.width * vp.scale;
        final double runnerW = ObstacleRace.runnerR * 2 * vp.scale;
        ratios.add(runnerW / courseW);
        expect(runnerW, greaterThan(20), reason: '${d.name}: runner big enough to read and touch');
      }
      for (final double r in ratios) {
        expect(r, closeTo(ratios.first, 1e-9));
      }
      // world proportions: runner vs obstacles
      expect(ObstacleRace.runnerR * 2 / ObstacleRace.width, closeTo(1 / 14, 1e-9));
      expect(ObstacleRace.armHalf * 2, lessThan(ObstacleRace.runnerR * 2));
      expect(ObstacleRace.hubR, lessThan(ObstacleRace.runnerR));
    });
  });

  group('widget', () {
    GameLaunch launch(List<GameResult> out, {bool fa = false}) => GameLaunch(
          gameId: 'obstacle_race',
          mode: GameMode.vsBot,
          difficulty: BotDifficulty.normal,
          playerName: 'Tester',
          isFa: fa,
          fancyEffects: true,
          reducedMotion: false,
          soundOn: false,
          playerCount: 4,
          seed: 7,
          onFinish: out.add,
        );

    for (final Device d in devices) {
      testWidgets('${d.name}: runs the countdown and the race start without layout or paint errors', (WidgetTester tester) async {
        tester.view.physicalSize = Size(d.w * 2, d.h * 2);
        tester.view.devicePixelRatio = 2;
        tester.view.padding = FakeViewPadding(top: d.top * 2, bottom: d.bottom * 2, left: d.left * 2, right: d.right * 2);
        addTearDown(tester.view.reset);
        final List<GameResult> out = <GameResult>[];
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: buildObstacleRaceGame(launch(out)))));
        for (int i = 0; i < 6 * 30; i++) {
          await tester.pump(const Duration(milliseconds: 33));
        }
        expect(tester.takeException(), isNull);
        expect(find.text('JUMP'), findsOneWidget);
        // the jump button is fully inside the safe area
        final Rect jb = tester.getRect(find.text('JUMP'));
        expect(jb.bottom, lessThanOrEqualTo(d.h - d.bottom));
        expect(jb.right, lessThanOrEqualTo(d.w - d.right));
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('a whole offline race reaches the results exactly once', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(720, 1280);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final List<GameResult> out = <GameResult>[];
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: buildObstacleRaceGame(launch(out, fa: true)))));
      // The idle human auto-runs, falls/respawns and is either through or eliminated within the time limit.
      int frames = 0;
      while (out.isEmpty && frames++ < (ObstacleRace.maxRaceTime + 10) * 20) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(out.length, 1);
      for (int i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(out.length, 1, reason: 'onFinish is called exactly once');
      expect(out.single.scores?.length, 4);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
