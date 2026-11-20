import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/settings/app_settings.dart';
import 'package:nexora/core/storage/local_store.dart';
import 'package:nexora/core/theme/nx_theme.dart';
import 'package:nexora/games/finger_soccer/core/bm_engine.dart';
import 'package:nexora/games/finger_soccer/ui/bm_painter.dart';
import 'package:nexora/games/finger_soccer/ui/bm_view.dart';
import 'package:nexora/games/game_registry.dart';
import 'package:nexora/worlds/arcade/game_host_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'render_util.dart';

/// Finger soccer inside the real host on a 360x800 phone (status + gesture insets), game sound OFF
/// (settings.sound=false -> launch.soundOn=false, so BmAudio never touches a player):
/// the intro's team select and formation select, then a mid-match frame.
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
    // Pre-match intro (lib/games/finger_soccer/intro): splash -> team select -> formation select -> match.
    await settle(tester, frames: 10);
    for (int i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await settle(tester, frames: 30);
    await shoot(tester, 'final/finger_soccer_setup.png');
    final Finder ready = find.text('آماده');
    expect(ready, findsOneWidget);
    await tester.tap(ready);
    await settle(tester, frames: 30);
    await shoot(tester, 'final/finger_soccer_formation.png');
    // pick Nish (7th card; the formation the reference player used) so the match frames compare with the reference
    final Finder pickF = find.text('انتخاب');
    await tester.tap(pickF.evaluate().length > 6 ? pickF.at(6) : pickF.first);
    for (int i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await settle(tester, frames: 10);
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
    await shoot(tester, 'final/finger_soccer_kickoff.png');
    // v3: the formation picked in the intro reaches the match (it used to look stuck on the first one).
    expect(p.e.form[0], 6);
    // In-match "تغییر ترکیب": open the 3 x 3 picker on our kickoff and keep Nish (applies at once).
    expect(find.byType(BmChangeFormButton), findsOneWidget);
    await tester.tap(find.byType(BmChangeFormButton));
    await settle(tester, frames: 20);
    expect(find.byType(BmFormationCard), findsNWidgets(kBmForms.length));
    await shoot(tester, 'final/finger_soccer_change_formation.png');
    await tester.tap(find.byType(BmFormationCard).at(6));
    await settle(tester, frames: 20);
    expect(find.byType(BmFormationCard), findsNothing);
    expect(p.e.form[0], 6);
    for (int i = 0; i < 300 && !(p.e.phase == 'aim' && p.e.turn == 0); i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final BmBody ball = p.e.ball!;
    final List<BmBody> mine = p.e.bodies.where((BmBody b) => b.team == 0 && !identical(b, ball)).toList()
      ..sort((BmBody a, BmBody b) =>
          ((a.x - ball.x) * (a.x - ball.x) + (a.y - ball.y) * (a.y - ball.y))
              .compareTo((b.x - ball.x) * (b.x - ball.x) + (b.y - ball.y) * (b.y - ball.y)));
    final BmBody d = mine.first;
    Offset scr(double x, double y) => Offset(x * p.view.s + p.view.ox, y * p.view.s + p.view.oy);
    final Offset from = scr(d.x, d.y);
    final Offset toBall = scr(ball.x, ball.y) - from;
    final Offset pull = -toBall / toBall.distance * 110;
    final TestGesture gst = await tester.startGesture(from);
    for (int i = 1; i <= 10; i++) {
      await gst.moveTo(from + pull * (i / 10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    // Mid-drag: reference aim arrow, pull dots and pull circle, with the turn rings on our discs.
    await shoot(tester, 'final/finger_soccer_aim.png');
    await gst.up();
    await tester.pump(const Duration(milliseconds: 16));
    // Pieces in motion: ball streak, disc water ribbon, rings staying on through the shot.
    await shoot(tester, 'final/finger_soccer_motion.png');
    await _run(tester, kMatchMs);
    await shoot(tester, 'final/finger_soccer_midmatch.png');
    // v6.1: the last minute (score banner pulsing red + "one minute left" toast), then the end-of-match table.
    final dynamic st = tester.state(find.byType(BermudaView));
    final BmEngine me = st.matchEngine as BmEngine;
    me.mleft = 60.4;
    await _run(tester, 2400);
    await shoot(tester, 'final/finger_soccer_last_minute.png');
    me.score = <int>[2, 1];
    me.end();
    await _run(tester, 2200);
    await settle(tester, frames: 6);
    await shoot(tester, 'final/finger_soccer_score_table.png');
    expect(tester.takeException(), isNull);
    // the host's result overlay follows the 20 s table (GameResult.holdMs)
    await tester.pump(const Duration(seconds: 21));
    await tester.pump(const Duration(milliseconds: 100));
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
