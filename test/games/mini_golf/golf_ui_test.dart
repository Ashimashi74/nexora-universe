import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/storage/local_store.dart';
import 'package:nexora/games/core/game_contract.dart';
import 'package:nexora/games/mini_golf/core/golf_core.dart';
import 'package:nexora/games/mini_golf/mini_golf_entry.dart';
import 'package:nexora/games/mini_golf/ui/golf_layout.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Logical screen sizes with realistic system insets (status bar / notch on top, gesture bar at the bottom).
const List<(String, Size, EdgeInsets)> _screens = <(String, Size, EdgeInsets)>[
  ('360x640', Size(360, 640), EdgeInsets.only(top: 24)),
  ('393x873', Size(393, 873), EdgeInsets.only(top: 59, bottom: 34)),
  ('412x915', Size(412, 915), EdgeInsets.only(top: 32, bottom: 24)),
  ('800x1280 tablet', Size(800, 1280), EdgeInsets.only(top: 24, bottom: 20)),
  ('360x640 landscape-ish cutout', Size(360, 640), EdgeInsets.only(top: 40, left: 20, right: 20, bottom: 16)),
];

GameLaunch _launch(List<GameResult> results, {GameMode mode = GameMode.vsBot, bool isFa = false, int players = 2}) => GameLaunch(
      gameId: 'mini_golf',
      mode: mode,
      difficulty: BotDifficulty.normal,
      playerName: 'Tester',
      isFa: isFa,
      fancyEffects: true,
      reducedMotion: false,
      soundOn: false,
      playerCount: players,
      seed: 2,
      onFinish: results.add,
    );

void main() {
  group('layout', () {
    for (final (String name, Size size, EdgeInsets pad) in _screens) {
      test('$name: the course fits the safe area with the same aspect, clear of HUD and system bars', () {
        final GolfLayout lay = golfLayout(size, pad);
        final Rect v = lay.viewRect;
        const double aspect = (282.0 - 18.0) / (512.0 - 14.0);
        expect(v.width / v.height, closeTo(aspect, 1e-9));
        // fully on screen and out of the notch / status bar / gesture bar / side cut-outs
        expect(v.left, greaterThanOrEqualTo(pad.left - 1e-9));
        expect(v.right, lessThanOrEqualTo(size.width - pad.right + 1e-9));
        expect(v.top, greaterThanOrEqualTo(pad.top + kGolfHudTop + kGolfHudH - 1e-9), reason: 'below the HUD');
        expect(v.bottom, lessThanOrEqualTo(size.height - pad.bottom - kGolfHintH + 1e-9), reason: 'above the hint');
        expect(v.left >= lay.safe.left - 1e-6 && v.right <= lay.safe.right + 1e-6, isTrue);
        expect(v.top >= lay.safe.top - 1e-6 && v.bottom <= lay.safe.bottom + 1e-6, isTrue);
        // uses the space: one dimension is filled
        expect(v.width >= lay.safe.width - 1e-6 || v.height >= lay.safe.height - 1e-6, isTrue);
        // readable on the smallest phone
        expect(kBallR * lay.scale, greaterThan(4.5));
        // every hole's rails, cup and flag sit inside the view rect
        for (final GHole h in golfCourse(2)) {
          final Offset tl = lay.toScreen(h.bounds.l - kRailHalf, h.bounds.t - kRailHalf);
          final Offset br = lay.toScreen(h.bounds.r + kRailHalf, h.bounds.b + kRailHalf);
          expect(v.inflate(1e-6).contains(tl) && v.inflate(1e-6).contains(br), isTrue);
          expect(v.inflate(1e-6).contains(lay.toScreen(h.cup.x, h.cup.y - 46)), isTrue);
        }
      });

      test('$name: hitboxes map 1:1 to drawn shapes and the putt feels the same', () {
        final GolfLayout lay = golfLayout(size, pad);
        // course <-> screen round trip is exact, so a touch maps onto the drawn ball / cup
        for (final Offset p in const <Offset>[Offset(150, 90), Offset(30, 40), Offset(270, 490)]) {
          final Offset back = lay.toCourse(lay.toScreen(p.dx, p.dy));
          expect((back - p).distance, lessThan(1e-9));
        }
        // a uniform scale: ball and cup are circles of radius r * scale; ratio kept
        final double ballPx = kBallR * lay.scale, cupPx = kCupR * lay.scale;
        expect(cupPx / ballPx, closeTo(kCupR / kBallR, 1e-12));
        // the same pull in course units gives the same power on every screen
        final Offset from = lay.toScreen(150, 300);
        final (double, double)? half = golfAim(from, lay.toScreen(150, 300 + kGolfFullPull / 2), lay.scale);
        expect(half, isNotNull);
        expect(half!.$2, closeTo(0.5, 1e-9));
        expect(half.$1, closeTo(-1.5707963267948966, 1e-9)); // pulled down -> putts up
        expect(golfAim(from, lay.toScreen(150, 300 + kGolfFullPull * 3), lay.scale)!.$2, 1.0);
        expect(golfAim(from, lay.toScreen(150, 301), lay.scale), isNull, reason: 'a tiny pull cancels');
      });
    }
  });

  group('widget', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await LocalStore.init();
    });

    Future<void> run(WidgetTester tester, Size size, GameLaunch launch, {int frames = 300}) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(child: MaterialApp(home: Scaffold(body: buildMiniGolfGame(launch)))));
      for (int i = 0; i < frames; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.takeException(), isNull);
    }

    for (final (String name, Size size, EdgeInsets _) in _screens.take(4)) {
      testWidgets('vs bots runs and accepts a putt on $name', (WidgetTester tester) async {
        final List<GameResult> results = <GameResult>[];
        await run(tester, size, _launch(results, players: 4, isFa: name.startsWith('393')), frames: 160);
        // pull back from mid-screen and release: the human putts
        final Offset c = tester.getCenter(find.byType(CustomPaint).first);
        await tester.dragFrom(c, const Offset(0, 90));
        for (int i = 0; i < 400; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(tester.takeException(), isNull);
        expect(find.textContaining('+'), findsWidgets); // HUD strokes
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('pass-and-play: every seat is a human, no bot shoots', (WidgetTester tester) async {
      final List<GameResult> results = <GameResult>[];
      await run(tester, const Size(393, 873), _launch(results, mode: GameMode.local), frames: 400);
      expect(find.textContaining('pull back'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
