import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/settings/app_settings.dart';
import 'package:nexora/core/storage/local_store.dart';
import 'package:nexora/core/theme/nx_theme.dart';
import 'package:nexora/games/game_registry.dart';
import 'package:nexora/worlds/arcade/game_host_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'render_util.dart';

/// Every game inside the real host (exit + ORACLE buttons) on a POCO C65-sized phone
/// (720x1600 px = 360x800 dp) with status-bar and gesture-bar insets.
const String only = String.fromEnvironment('ONLY');
const int kW = int.fromEnvironment('W', defaultValue: 360);
const int kH = int.fromEnvironment('H', defaultValue: 800);

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(<String, Object>{'settings.lang': 'en'});
    await LocalStore.init();
    await loadFonts();
    mockAudio();
  });
  for (final GameInfo g in kGames) {
    if (only.isNotEmpty && !only.split(',').contains(g.id)) continue;
    testWidgets('host ${g.id}', (WidgetTester tester) async {
      phone(tester, w: kW.toDouble(), h: kH.toDouble());
      tester.view.padding = const FakeViewPadding(top: 64, bottom: 40);
      addTearDown(tester.view.resetPadding);
      final ProviderContainer c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(settingsProvider).languageCode = 'en';
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildNxTheme(),
          builder: (BuildContext context, Widget? child) =>
              RepaintBoundary(key: kShotKey, child: child ?? const SizedBox.shrink()),
          home: GameHostPage(
              game: g, mode: GameMode.vsBot, difficulty: BotDifficulty.normal, players: g.defaultPlayers),
        ),
      ));
      await settle(tester, frames: 30);
      await shoot(tester, 'host/${g.id}_${kW}x$kH.png');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
