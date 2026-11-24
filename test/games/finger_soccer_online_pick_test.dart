import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/storage/local_store.dart';
import 'package:nexora/games/core/game_contract.dart';
import 'package:nexora/games/finger_soccer/core/bm_engine.dart';
import 'package:nexora/games/finger_soccer/ui/bm_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// v4 (owner request 2026-11-20), 2026-11-24: online matches open straight on the app's black-gold match lobby (the
/// same screen offline uses, never another screen first); each phone picks its own side, the pick goes out as the logged 'setup' move, the match starts when both sides'
/// setups are in the log, and a side that never picks gets a default setup logged for it so a match never hangs.
class _FakeNet implements NetLink {
  _FakeNet({this.seat = 0, Map<String, dynamic>? settings}) : _settings = settings ?? <String, dynamic>{};
  final int seat;
  final Map<String, dynamic> _settings;
  final List<Map<String, dynamic>> sent = <Map<String, dynamic>>[];
  void Function(NetMove move)? onMove;
  VoidCallback? onDone;
  int _seq = 0;

  void deliver(int fromSeat, Map<String, dynamic> d, {bool replay = false}) =>
      onMove!(NetMove(seq: ++_seq, seat: fromSeat, kind: 'move', data: d, replay: replay));

  @override
  String get matchId => 'm1';
  @override
  int get mySeat => seat;
  @override
  int get seatCount => 2;
  @override
  int get seed => 7;
  @override
  Map<String, dynamic> get settings => _settings;
  @override
  List<String> get names => const <String>['Ali', 'Sara'];
  @override
  Set<int> get connectedSeats => <int>{0, 1};
  @override
  Set<int> get forfeitedSeats => <int>{};
  @override
  bool get isAuthority => seat == 0;
  @override
  Listenable get changes => ValueNotifier<int>(0);
  @override
  bool get replaying => false;
  @override
  void listen(void Function(NetMove move) onMove, {VoidCallback? onReplayDone}) {
    this.onMove = onMove;
    onDone = onReplayDone;
  }

  @override
  Future<bool> send(Map<String, dynamic> data, {String kind = 'move', String? hash, int? asSeat}) async {
    sent.add(data);
    return true;
  }

  @override
  void sendLive(String event, Map<String, dynamic> data) {}
  @override
  Stream<NetLiveMessage> get live => const Stream<NetLiveMessage>.empty();
  @override
  set turnSeat(int? seat) {}
  @override
  Future<void> putSecret(int seat, String slot, Map<String, dynamic> data) async {}
  @override
  Future<Map<String, dynamic>?> readSecret(String slot) async => null;
  @override
  void verify(int seq, String? expected, String actual) {}
  @override
  int get desyncs => 0;
}

GameLaunch _launch(NetLink net) => GameLaunch(
      gameId: 'finger_soccer',
      mode: GameMode.online,
      difficulty: BotDifficulty.normal,
      playerName: 'Ali',
      isFa: true,
      fancyEffects: false,
      reducedMotion: true,
      soundOn: false,
      seed: 7,
      net: net,
      onFinish: (_) {},
    );

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

  Future<void> pumpFor(WidgetTester tester, int seconds) async {
    for (int i = 0; i < seconds * 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  Future<_FakeNet> open(WidgetTester tester, {int seat = 0, Map<String, dynamic>? settings}) async {
    phone(tester);
    final _FakeNet net = _FakeNet(seat: seat, settings: settings);
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(home: Scaffold(backgroundColor: Colors.black, body: BermudaView(launch: _launch(net))))));
    await tester.pump(const Duration(milliseconds: 100));
    net.onDone!();
    await tester.pump(const Duration(milliseconds: 300));
    return net;
  }

  BmEngine? engineOf(WidgetTester tester) {
    final dynamic st = tester.state(find.byType(BermudaView));
    return st.matchEngine as BmEngine?;
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('online: the lobby shows from the first frame, the pick is sent, the match starts with both picks',
      (WidgetTester tester) async {
    phone(tester);
    final _FakeNet net = _FakeNet();
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(home: Scaffold(backgroundColor: Colors.black, body: BermudaView(launch: _launch(net))))));
    await tester.pump(const Duration(milliseconds: 100));
    // before the log is replayed: the same lobby, disabled, "connecting"
    expect(find.text('در حال اتصال به بازی…'), findsOneWidget);
    net.onDone!();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey<String>('setup-ready')), findsOneWidget);
    // the opponent's pick arrives while this phone is still choosing: no match yet
    net.deliver(1, <String, dynamic>{'a': 'setup', 'team': 'club9', 'form': 4, 'field': 0, 'ball': 0});
    await tester.pump(const Duration(milliseconds: 300));
    expect(engineOf(tester), isNull);
    expect(find.text('حریف آماده است ✓'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('setup-ready')));
    await pumpFor(tester, 1);
    final Map<String, dynamic> mine = net.sent.firstWhere((Map<String, dynamic> d) => d['a'] == 'setup');
    expect(mine['for'], isNull);
    final BmEngine e = engineOf(tester)!;
    expect(e.sel, <String>[mine['team'] as String, 'club9']);
    expect(e.form[1], 4);
    expect(e.form[0], mine['form']);
    await close(tester);
  });

  testWidgets('online: an idle player still sends a pick, and a silent opponent gets a default so it never hangs',
      (WidgetTester tester) async {
    final _FakeNet net = await open(tester, seat: 1);
    await pumpFor(tester, 31); // the lobby countdown (30 s) sends the shown pick by itself
    expect(net.sent.where((Map<String, dynamic> d) => d['a'] == 'setup' && d['for'] == null).length, 1);
    expect(engineOf(tester), isNull);
    // ANIX PRO watchdog: 45 s after the picks opened the silent side gets a default setup logged for it; once the
    // log confirms it (send -> ok) it counts on this phone too, so the match starts instead of hanging.
    await pumpFor(tester, 15);
    final Map<String, dynamic> fill = net.sent.firstWhere((Map<String, dynamic> d) => d['for'] == 0);
    expect(fill['team'], 'club0');
    expect(fill[kNetFloat], isTrue);
    await tester.pump(const Duration(milliseconds: 300));
    expect(engineOf(tester)!.sel[0], 'club0');
    // a late real setup of that side changes nothing (first per side in the log wins on both phones)
    net.deliver(0, <String, dynamic>{'a': 'setup', 'team': 'club5', 'form': 2, 'field': 0, 'ball': 0});
    await tester.pump(const Duration(milliseconds: 300));
    expect(engineOf(tester)!.sel[0], 'club0');
    await close(tester);
  });

  testWidgets('online replay: a match whose setups are logged restarts straight into play', (WidgetTester tester) async {
    phone(tester);
    final _FakeNet net = _FakeNet();
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(home: Scaffold(body: BermudaView(launch: _launch(net))))));
    await tester.pump(const Duration(milliseconds: 100));
    net.deliver(0, <String, dynamic>{'a': 'setup', 'team': 'club3', 'form': 1, 'field': 0, 'ball': 0}, replay: true);
    net.deliver(1, <String, dynamic>{'a': 'setup', 'team': 'club4', 'form': 2, 'field': 0, 'ball': 0}, replay: true);
    net.onDone!();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey<String>('setup-ready')), findsNothing);
    expect(engineOf(tester)!.sel, <String>['club3', 'club4']);
    await close(tester);
  });

  testWidgets('room match logged before v4 (play moves, no setups) still starts from its room prefs',
      (WidgetTester tester) async {
    phone(tester);
    final _FakeNet net = _FakeNet(settings: <String, dynamic>{
      'room_prefs': <String, dynamic>{
        '0': <String, dynamic>{'team': 'club6', 'form': 3},
        '1': <String, dynamic>{'team': 'club7', 'form': 5},
      },
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(home: Scaffold(body: BermudaView(launch: _launch(net))))));
    await tester.pump(const Duration(milliseconds: 100));
    net.deliver(0, <String, dynamic>{'a': 'form', 'side': 0, 'form': 3}, replay: true);
    net.onDone!();
    await tester.pump(const Duration(milliseconds: 300));
    expect(engineOf(tester)!.sel, <String>['club6', 'club7']);
    await close(tester);
  });

  testWidgets('room match (v4): the room pick is the starting pick in the lobby', (WidgetTester tester) async {
    final _FakeNet net = await open(tester, settings: <String, dynamic>{
      'room_prefs': <String, dynamic>{
        '0': <String, dynamic>{'team': 'nx_core', 'form': 3},
        '1': <String, dynamic>{'team': 'club7', 'form': 5},
      },
    });
    expect(find.byKey(const ValueKey<String>('setup-ready')), findsOneWidget);
    expect(net.sent, isEmpty);
    await tester.tap(find.byKey(const ValueKey<String>('setup-ready')));
    await pumpFor(tester, 1);
    final Map<String, dynamic> mine = net.sent.firstWhere((Map<String, dynamic> d) => d['a'] == 'setup');
    expect(mine['team'], 'nx_core');
    expect(mine['form'], 3);
    await close(tester);
  });
}
