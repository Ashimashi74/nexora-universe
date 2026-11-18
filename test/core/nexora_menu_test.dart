import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexora/core/navigation/nexora_menu.dart';
import 'package:nexora/core/storage/local_store.dart';
import 'package:nexora/core/theme/nx_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalStore.init();
  });

  test('menu destinations are unique and map to registered app routes', () {
    const registeredRoutes = <String>{
      '/hub',
      '/world/nexora_arcade',
      '/tournaments',
      '/leaderboard',
      '/world/nova_gallery',
      '/world/orbit_network',
      '/world/social_station',
      '/world/personal_orbit',
      '/world/nexora_exchange',
      '/account',
      '/oracle',
      '/settings',
      '/journey',
    };
    final destinations = kNexoraMenuSections
        .expand((NexoraMenuSection section) => section.destinations)
        .toList(growable: false);

    expect(destinations.map((NexoraMenuDestination d) => d.path).toSet().length,
        destinations.length);
    for (final destination in destinations) {
      expect(registeredRoutes, contains(destination.path),
          reason: '${destination.path} must have a real route');
    }
  });

  test('deep game routes keep the arcade destination selected', () {
    final arcade = kNexoraMenuSections
        .expand((NexoraMenuSection section) => section.destinations)
        .firstWhere(
            (NexoraMenuDestination d) => d.path == '/world/nexora_arcade');

    expect(arcade.matches('/world/nexora_arcade'), isTrue);
    expect(arcade.matches('/arcade/billiards'), isTrue);
    expect(arcade.matches('/world/nova_gallery'), isFalse);
  });

  testWidgets('shared menu opens and navigates to the selected page',
      (WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/hub',
      routes: <RouteBase>[
        GoRoute(
          path: '/hub',
          builder: (BuildContext context, GoRouterState state) => Scaffold(
            body: Builder(
              builder: (BuildContext context) => Center(
                child: FilledButton(
                  onPressed: () => showNexoraMenu(context),
                  child: const Text('open menu'),
                ),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/world/nova_gallery',
          builder: (BuildContext context, GoRouterState state) =>
              const Scaffold(body: Center(child: Text('gallery destination'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: NxColors.gold),
            extensions: const <ThemeExtension<dynamic>>[NxThemeColors.gold],
          ),
          locale: const Locale('fa'),
          supportedLocales: const <Locale>[Locale('fa'), Locale('en')],
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        ),
      ),
    );

    await tester.tap(find.text('open menu'));
    await tester.pumpAndSettle();
    expect(find.text('منوی جهان'), findsOneWidget);
    expect(find.text('نوا گالری'), findsOneWidget);

    await tester.ensureVisible(find.text('نوا گالری'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('نوا گالری'));
    await tester.pumpAndSettle();
    expect(find.text('gallery destination'), findsOneWidget);
  });
}
