import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/settings/app_settings.dart';
import 'package:nexora/core/storage/local_store.dart';
import 'package:nexora/core/theme/nx_theme.dart';
import 'package:nexora/games/finger_soccer/core/bm_engine.dart';
import 'package:nexora/games/finger_soccer/ui/bm_painter.dart';
import 'package:nexora/games/game_registry.dart';
import 'package:nexora/worlds/arcade/game_host_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'render_util.dart';

/// Finger soccer inside the real host on a 360x800 phone (status + gesture insets), game sound OFF
/// (settings.sound=false -> launch.soundOn=false, so BmAudio never touches a player):
/// the setup screen, then a mid-match frame after START MATCH.
const int kW = int.fromEnvironment('W', defaultValue: 360);
const int kH = int.fromEnvironment('H', defaultValue: 800);
const int kMatchMs = int.fromEnvironment('MATCH_MS', defaultValue: 420);

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(<String, Object>{'settings.lang': 'en', 'settings.sound': false});
    await LocalStore.init();
    await loadFonts();
    mockAudio();
  });

  testWidgets('finger soccer setup + mid-match (sound off)', (WidgetTester tester) async {
    phone(tester, w: kW.toDouble(), h: kH.toDouble());
    tester.view.padding = const FakeViewPadding(top: 64, bottom: 40);
    addTearDown(tester.view.resetPadding);
    final ProviderContainer c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(settingsProvider).sound, isFalse);
    final GameInfo g = kGames.firstWhere((GameInfo x) => x.id == 'finger_soccer');
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildNxTheme(),
        builder: (BuildContext context, Widget? child) =>
            RepaintBoundary(key: kShotKey, child: child ?? const SizedBox.shrink()),
        home: GameHostPage(game: g, mode: GameMode.vsBot, difficulty: BotDifficulty.normal, players: g.defaultPlayers),
      ),
    ));
    await settle(tester, frames: 30);
    await shoot(tester, 'final/finger_soccer_setup.png');

    final Finder start = find.text('START MATCH');
    expect(start, findsOneWidget);
    await tester.ensureVisible(start);
    await tester.pump();
    await tester.tap(start);
    // Let kickoff happen and the ORACLE tutorial banner (9 s) pass.
    await _run(tester, 10500);
    // Mid-match: flick one of our discs at the ball the way a finger would (drag back, release),
    // then catch the ball while it is rolling (rotating ball sprite frames) a moment later.
    final BmPainter p = tester.widget<CustomPaint>(find.byWidgetPredicate(
            (Widget w) => w is CustomPaint && w.painter is BmPainter)).painter! as BmPainter;
    for (int i = 0; i < 300 && !(p.e.phase == 'aim' && p.e.turn == 0); i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(p.e.phase, 'aim');
    final BmBody ball = p.e.ball!;
    final List<BmBody> mine = p.e.bodies.where((BmBody b) => b.team == 0 && !identical(b, ball)).toList()
      ..sort((BmBody a, BmBody b) =>
          ((a.x - ball.x) * (a.x - ball.x) + (a.y - ball.y) * (a.y - ball.y))
              .compareTo((b.x - ball.x) * (b.x - ball.x) + (b.y - ball.y) * (b.y - ball.y)));
    final BmBody d = mine.first;
    Offset scr(double x, double y) => Offset(x * p.view.s + p.view.ox, y * p.view.s + p.view.oy);
    final Offset from = scr(d.x, d.y);
    final Offset toBall = scr(ball.x, ball.y) - from;
    final Offset pull = -toBall / toBall.distance * 70;
    final TestGesture gst = await tester.startGesture(from);
    for (int i = 1; i <= 10; i++) {
      await gst.moveTo(from + pull * (i / 10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gst.up();
    await _run(tester, kMatchMs);
    await shoot(tester, 'final/finger_soccer_midmatch.png');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}

Future<void> _run(WidgetTester tester, int ms) async {
  for (int i = 0; i < ms ~/ 16; i++) {
    if (i % 20 == 0) await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 16));
  }
}
