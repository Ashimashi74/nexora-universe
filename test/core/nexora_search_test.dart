import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexora/core/storage/local_store.dart';
import 'package:nexora/core/theme/nx_theme.dart';
import 'package:nexora/core/widgets/nx_widgets.dart';
import 'package:nexora/worlds/hub/hub_search.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalStore.init();
  });

  testWidgets('global search opens from a world and navigates to a real result',
      (WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/social',
      routes: <RouteBase>[
        GoRoute(
          path: '/social',
          builder: (BuildContext context, GoRouterState state) =>
              const NxWorldScaffold(
            title: 'Social Station',
            palette: WorldPalette.hub,
            body: Center(child: Text('Social Station page')),
          ),
        ),
        GoRoute(
          path: '/search',
          builder: (BuildContext context, GoRouterState state) =>
              const NexoraSearchPage(),
        ),
        GoRoute(
          path: '/tournaments/inbox',
          builder: (BuildContext context, GoRouterState state) =>
              const Scaffold(body: Center(child: Text('Inbox page opened'))),
        ),
        GoRoute(
          path: '/arcade/:gameId',
          builder: (BuildContext context, GoRouterState state) => Scaffold(
            body: Center(
                child: Text('Game route: ${state.pathParameters['gameId']}')),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
          theme: buildNxTheme(NxVisualTheme.gold, NxAppearanceMode.dark),
          locale: const Locale('en'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open global search'));
    await tester.pumpAndSettle();
    expect(find.text('Global search'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'tournament inbox');
    await tester.pumpAndSettle();
    expect(find.text('Tournament inbox'), findsOneWidget);

    await tester.tap(find.text('Tournament inbox'));
    await tester.pumpAndSettle();
    expect(find.text('Inbox page opened'), findsOneWidget);

    router.go('/social');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open global search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'تخته نرد');
    await tester.pumpAndSettle();
    expect(find.text('Backgammon'), findsOneWidget);

    await tester.tap(find.text('Backgammon'));
    await tester.pumpAndSettle();
    expect(find.text('Game route: backgammon'), findsOneWidget);
  });
}
