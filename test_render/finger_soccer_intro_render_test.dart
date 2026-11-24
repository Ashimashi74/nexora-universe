import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/storage/local_store.dart';
import 'package:nexora/games/finger_soccer/intro/fs_formation_select.dart';
import 'package:nexora/games/finger_soccer/intro/fs_game_bar.dart';
import 'package:nexora/games/finger_soccer/intro/fs_intro_ui.dart';
import 'package:nexora/games/finger_soccer/intro/fs_score_table.dart';
import 'package:nexora/games/finger_soccer/intro/fs_shop.dart';
import 'package:nexora/games/finger_soccer/intro/fs_splash.dart';
import 'package:nexora/games/finger_soccer/intro/fs_team_select.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'render_util.dart';

/// The finger-soccer pre-match intro screens at 720x1600 (360x800 @2x), each frozen in the state of its reference
/// frame: splash (counter 50), team select, formation select (bar ~75 %), shop (national teams), game bar, exit.
const List<FsSidePlayer> _players = <FsSidePlayer>[
  FsSidePlayer(name: 'HIIS', portrait: 'assets/ui/anix/avatars/01-vanguard.webp', badge: 'سطح ۱۴'),
  FsSidePlayer(name: 'ربات', portrait: 'assets/ui/anix/avatars/04-iron-warden.webp', badge: 'ربات'),
];

Widget _app(Widget child) => ProviderScope(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        builder: (BuildContext context, Widget? c) => RepaintBoundary(key: kShotKey, child: c ?? const SizedBox()),
        home: Scaffold(backgroundColor: Colors.black, body: child),
      ),
    );

FsTeamSelect _team() => FsTeamSelect(
      fa: true,
      teams: <String>['nat18', 'club9'],
      players: _players,
      onReady: (_) {},
      onShop: () {},
      onBar: () {},
      onChat: () {},
      freeze: true,
      countdown: 41,
    );

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(<String, Object>{'settings.lang': 'fa', 'settings.sound': false});
    await LocalStore.init();
    await loadFonts();
    mockAudio();
  });

  Future<void> shot(WidgetTester tester, Widget w, String name) async {
    phone(tester, w: 360, h: 800);
    await tester.pumpWidget(_app(w));
    await settle(tester, frames: 20);
    await shoot(tester, 'intro/$name.png');
  }

  testWidgets('splash', (WidgetTester tester) async {
    await shot(tester, FsSplash(onDone: () {}, freezeAt: 50), 'splash');
    expect(tester.takeException(), isNull);
  });

  testWidgets('team select', (WidgetTester tester) async {
    await shot(tester, _team(), 'team_select');
    expect(find.text('فروشگاه'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('formation select', (WidgetTester tester) async {
    await shot(
        tester,
        FsFormationSelect(
            discAsset: 'assets/games/bermuda/discs/v9/nx_core.webp', initial: 0, onDone: (_) {}, onBar: () {}, freezeAt: .76),
        'formation_select');
    expect(tester.takeException(), isNull);
  });

  testWidgets('shop', (WidgetTester tester) async {
    await shot(tester, FsShop(fa: true, team: 'club32', onTeam: (_) {}, onBack: () {}), 'shop');
    expect(find.text('انتخاب محصول ها'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('game bar', (WidgetTester tester) async {
    await shot(
        tester,
        Stack(fit: StackFit.expand, children: <Widget>[
          _team(),
          const ColoredBox(color: Color(0x55000000)),
          FsGameBar(
            settings: FsBarSettings(),
            players: const <String>['HIIS', 'ربات'],
            online: true,
            connected: false,
            onClose: () {},
            onExit: () {},
          ),
        ]),
        'game_bar');
    expect(find.text('نوار بازی'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('exit confirm', (WidgetTester tester) async {
    phone(tester, w: 360, h: 800);
    await tester.pumpWidget(_app(_team()));
    await settle(tester, frames: 6);
    final BuildContext ctx = tester.element(find.byType(FsTeamSelect));
    // ignore: use_build_context_synchronously
    showFsExitConfirm(ctx, online: true);
    await settle(tester, frames: 20);
    await shoot(tester, 'intro/exit_confirm.png');
    expect(find.text('ماندن'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('score table (v6 outro)', (WidgetTester tester) async {
    await shot(
        tester,
        const FsScoreTable(seconds: 16, topLane: 50, rows: <FsScoreRow>[
          FsScoreRow(name: 'HIIS', score: 3, crest: 'assets/games/bermuda/discs/v9/nx_core.webp', winner: true, avatar: '07-star-fox'),
          FsScoreRow(name: 'ربات', score: 1, crest: 'assets/games/bermuda/discs/v9/nx_core.webp', avatar: '04-iron-warden'),
        ]),
        'score_table');
    expect(find.text('جدول امتیازات'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('canvas fits a short 360x640 phone', (WidgetTester tester) async {
    phone(tester, w: 360, h: 640);
    await tester.pumpWidget(_app(_team()));
    await settle(tester, frames: 4);
    expect(tester.takeException(), isNull);
    expect(find.byType(FsCanvas), findsOneWidget);
  });
}
