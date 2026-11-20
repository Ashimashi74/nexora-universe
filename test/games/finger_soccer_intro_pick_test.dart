import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/storage/local_store.dart';
import 'package:nexora/games/finger_soccer/intro/fs_formation_select.dart';
import 'package:nexora/games/finger_soccer/intro/fs_intro_ui.dart';
import 'package:nexora/games/finger_soccer/intro/fs_team_select.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// v3 (owner request 2026-11-20): in the pre-match intro the team on screen is the team that plays (arrows pick an
/// owned / opponent team) and a formation is picked by tapping anywhere on its card.
const List<FsSidePlayer> _players = <FsSidePlayer>[
  FsSidePlayer(name: 'A', portrait: 'assets/ui/anix/avatars/01-vanguard.webp', badge: '1'),
  FsSidePlayer(name: 'B', portrait: 'assets/ui/anix/avatars/04-iron-warden.webp', badge: '2'),
];

Widget _app(Widget child) => MaterialApp(home: Scaffold(backgroundColor: Colors.black, body: child));

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(<String, Object>{'settings.lang': 'fa', 'settings.sound': false});
    await LocalStore.init();
  });

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('team select: the arrows pick the team shown (free team / opponent side)', (WidgetTester tester) async {
    phone(tester);
    final List<String> teams = <String>['club32', 'club9'];
    List<String>? ready;
    await tester.pumpWidget(_app(FsTeamSelect(
      fa: true,
      teams: teams,
      players: _players,
      onReady: (List<String> t) => ready = t,
      onShop: () {},
      onBar: () {},
      freeze: true,
    )));
    await tester.pump(const Duration(milliseconds: 300));
    // side one: club32 (Persepolis) -> next is club33 (Esteghlal), a free team
    await tester.tap(find.byWidgetPredicate((Widget w) => w is FsArrow && !w.left));
    await tester.pump(const Duration(milliseconds: 300));
    expect(teams[0], 'club33');
    // side two (opponent, no ownership needed): club9 -> club10
    await tester.tap(find.text('تیم دو'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byWidgetPredicate((Widget w) => w is FsArrow && !w.left));
    await tester.pump(const Duration(milliseconds: 300));
    expect(teams[1], 'club10');
    await tester.tap(find.text('آماده'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(ready, <String>['club33', 'club10']);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('formation select: tapping the mini pitch picks the formation', (WidgetTester tester) async {
    phone(tester);
    int? done;
    await tester.pumpWidget(_app(FsFormationSelect(
      discAsset: 'assets/games/bermuda/discs/germany.webp',
      initial: 0,
      onDone: (int f) => done = f,
      onBar: () {},
    )));
    await tester.pump(const Duration(milliseconds: 100));
    final Finder pitches =
        find.byWidgetPredicate((Widget w) => w is CustomPaint && w.painter is FsMiniPitchPainter);
    expect(pitches, findsNWidgets(9));
    await tester.tap(pitches.at(4));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('انتخاب شده'), findsOneWidget);
    // a pick runs the loading bar out in ~0.9 s, then the picked index is handed on
    for (int i = 0; i < 40 && done == null; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(done, 4);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
