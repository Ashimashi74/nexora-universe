import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexora/core/ui2/anix_kit.dart';
import 'package:nexora/core/settings/app_settings.dart';
import 'package:nexora/core/storage/local_store.dart';
import 'package:nexora/core/theme/nx_theme.dart';
import 'package:nexora/worlds/settings/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalStore.init();
  });

  test('appearance mode defaults to dark and persists after reload', () {
    final settings = AppSettings(LocalStore.instance);
    expect(settings.appearanceMode, NxAppearanceMode.dark);

    settings.appearanceMode = NxAppearanceMode.light;
    final restored = AppSettings(LocalStore.instance);
    expect(restored.appearanceMode, NxAppearanceMode.light);
  });

  test('appearance changes notify MaterialApp listeners', () {
    final settings = AppSettings(LocalStore.instance);
    var notifications = 0;
    settings.addListener(() => notifications++);

    settings.appearanceMode = NxAppearanceMode.light;

    expect(notifications, 1);
  });

  test('light and dark modes create matching Material themes', () {
    final light = buildNxTheme(NxVisualTheme.neon, NxAppearanceMode.light);
    final dark = buildNxTheme(NxVisualTheme.neon, NxAppearanceMode.dark);

    expect(light.brightness, Brightness.light);
    expect(light.colorScheme.brightness, Brightness.light);
    expect(light.extension<NxThemeColors>()?.background,
        NxThemeColors.goldLight.background);
    expect(dark.brightness, Brightness.dark);
    expect(dark.colorScheme.brightness, Brightness.dark);
    expect(dark.extension<NxThemeColors>()?.background,
        NxThemeColors.neon.background);
    expect(light.colorScheme.onPrimary, Colors.white);
  });

  testWidgets('settings UI switches the actual app appearance',
      (WidgetTester tester) async {
    final container = ProviderContainer();
    final router = GoRouter(
      initialLocation: '/settings',
      routes: <RouteBase>[
        GoRoute(
          path: '/settings',
          builder: (BuildContext context, GoRouterState state) =>
              const SettingsPage(),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _SettingsTestApp(router: router),
      ),
    );
    final settingsPage = find.byType(SettingsPage);
    expect(
        container.read(settingsProvider).appearanceMode, NxAppearanceMode.dark);
    expect(Theme.of(tester.element(settingsPage)).brightness, Brightness.dark);

    final lightModeTile =
        find.widgetWithText(AnixSwitchTile, 'Light appearance');
    await tester.ensureVisible(lightModeTile);
    await tester.pumpAndSettle();
    await tester.tap(lightModeTile);
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).appearanceMode,
        NxAppearanceMode.light);
    expect(Theme.of(tester.element(settingsPage)).brightness, Brightness.light);
    expect(
      NxThemeColors.of(tester.element(settingsPage)).background,
      NxThemeColors.goldLight.background,
    );
  });
}

class _SettingsTestApp extends ConsumerWidget {
  const _SettingsTestApp({required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return MaterialApp.router(
      routerConfig: router,
      theme: buildNxTheme(settings.visualTheme, settings.appearanceMode),
      locale: const Locale('en'),
      supportedLocales: const <Locale>[Locale('fa'), Locale('en')],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
