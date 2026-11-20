// Finger soccer v6.1 (owner request 2026-11-20, reference recordings): the in-match score banner (white plates, yellow
// clock, last-minute red pulse, red at the final whistle), the "یک دقیقه تا پایان بازی" toast, and score-table rows
// per player with avatars and match points; offline / bot / online flows end on the table without errors.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/storage/local_store.dart';
import 'package:nexora/games/core/game_contract.dart';
import 'package:nexora/games/finger_soccer/core/bm_engine.dart';
import 'package:nexora/games/finger_soccer/intro/fs_score_table.dart';
import 'package:nexora/games/finger_soccer/ui/bm_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeNet implements NetLink {
  _FakeNet({this.seat = 0, this.seats = 2});
  final int seat, seats;
  final List<Map<String, dynamic>> sent = <Map<String, dynamic>>[];
  final List<String> liveSent = <String>[];
  final StreamController<NetLiveMessage> liveCtl = StreamController<NetLiveMessage>.broadcast();
  void Function(NetMove move)? onMove;
  VoidCallback? onDone;
  int _seq = 0;

  void deliver(int fromSeat, Map<String, dynamic> d) =>
      onMove!(NetMove(seq: ++_seq, seat: fromSeat, kind: 'move', data: d));

  @override
  String get matchId => 'm1';
  @override
  int get mySeat => seat;
  @override
  int get seatCount => seats;
  @override
  int get seed => 7;
  @override
  Map<String, dynamic> get settings => const <String, dynamic>{};
  @override
  List<String> get names => const <String>['Ali', 'Sara', 'Reza', 'Mina', 'Omid', 'Lida'].sublist(0, seats);
  @override
  Set<int> get connectedSeats => <int>{for (int s = 0; s < seats; s++) s};
  @override
  Set<int> get forfeitedSeats => const <int>{};
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
  void sendLive(String event, Map<String, dynamic> data) => liveSent.add(event);
  @override
  Stream<NetLiveMessage> get live => liveCtl.stream;
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

GameLaunch _launch({NetLink? net, GameMode mode = GameMode.online, void Function(GameResult r)? onFinish}) => GameLaunch(
      gameId: 'finger_soccer',
      mode: mode,
      difficulty: BotDifficulty.normal,
      playerName: 'Ali',
      isFa: true,
      fancyEffects: false,
      reducedMotion: true,
      soundOn: false,
      seed: 7,
      net: net,
      onFinish: onFinish ?? (_) {},
    );

Map<String, dynamic> _setup(String team, int form) =>
    <String, dynamic>{'a': 'setup', 'team': team, 'form': form, 'field': 0, 'ball': 0};

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

  Future<void> pumpFor(WidgetTester tester, num seconds) async {
    for (int i = 0; i < (seconds * 4).round(); i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  Widget host(GameLaunch l, {bool autoStart = false}) => ProviderScope(
      child: MaterialApp(
          home: Scaffold(backgroundColor: Colors.black, body: BermudaView(launch: l, autoStart: autoStart))));

  dynamic stateOf(WidgetTester tester) => tester.state(find.byType(BermudaView));

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  test('clock colour: plain until the last minute, pulses there, red once the time is up', () {
    expect(bmClockRed(300, 300), 0);
    expect(bmClockRed(61, 300), 0);
    expect(bmClockRed(60, 300), closeTo(0, 1e-9)); // 01:00 left: yellow
    expect(bmClockRed(58, 300), closeTo(1, 1e-9)); // red
    expect(bmClockRed(56, 300), closeTo(0, 1e-9)); // yellow again
    expect(bmClockRed(0, 300), 1); // final whistle: red
    expect(bmClockRed(0, 0), 0); // no clock (goal-limit matches)
  });

  testWidgets('score banner: scores on the plates, clock in the middle', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: BmScoreBanner(left: '۲', right: '۱', clock: '۰۴:۰۰', red: 1)))));
    expect(find.text('۲'), findsOneWidget);
    expect(find.text('۱'), findsOneWidget);
    expect(find.text('۰۴:۰۰'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bot match: count-up clock, one-minute toast once, red at the end, table rows with avatars',
      (WidgetTester tester) async {
    phone(tester);
    GameResult? got;
    await tester.pumpWidget(host(_launch(mode: GameMode.vsBot, onFinish: (GameResult r) => got = r), autoStart: true));
    await pumpFor(tester, 1);
    final BmEngine e = stateOf(tester).matchEngine as BmEngine;
    expect(find.byType(BmScoreBanner), findsOneWidget);
    expect(find.textContaining(RegExp('^۰۰:۰[۰-۲]\$')), findsOneWidget); // count-up from zero, Persian digits
    expect(find.text('یک دقیقه تا پایان بازی'), findsNothing);
    e.mleft = 60.5;
    await pumpFor(tester, 1);
    expect(find.text('یک دقیقه تا پایان بازی'), findsOneWidget);
    await pumpFor(tester, kBmMinuteToastSeconds + .5);
    expect(find.text('یک دقیقه تا پایان بازی'), findsNothing);
    // the score table: one row per player, the side's goals, avatars (player portrait, bot portrait)
    e.score = <int>[1, 2];
    e.end();
    await pumpFor(tester, 2.5);
    expect(find.text('جدول امتیازات'), findsOneWidget);
    final List<FsScoreRow> rows = stateOf(tester).scoreRows() as List<FsScoreRow>;
    expect(rows.length, 2);
    expect(rows.first.winner, isTrue);
    expect(rows.first.score, 2);
    expect(rows.first.avatar, '04-iron-warden');
    expect(rows.last.score, 1);
    expect(rows.last.avatar, isNotNull);
    expect(got, isNotNull);
    expect(got!.holdMs, kFsScoreTableSeconds * 1000);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('local pass-and-play match runs to its table without errors', (WidgetTester tester) async {
    phone(tester);
    await tester.pumpWidget(host(_launch(mode: GameMode.local), autoStart: true));
    await pumpFor(tester, 1);
    final BmEngine e = stateOf(tester).matchEngine as BmEngine;
    e.score = <int>[2, 2];
    e.mleft = 0;
    await pumpFor(tester, 4);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  for (final int seats in <int>[2, 6]) {
    testWidgets('online $seats players: avatars over the live channel, one row per seat with its side\'s goals',
        (WidgetTester tester) async {
      phone(tester);
      final _FakeNet net = _FakeNet(seat: 1, seats: seats);
      await tester.pumpWidget(host(_launch(net: net)));
      await tester.pump(const Duration(milliseconds: 100));
      net.onDone!();
      await tester.pump(const Duration(milliseconds: 300));
      expect(net.liveSent, contains('fs_av'));
      final int before = net.liveSent.length;
      net.liveCtl.add(const NetLiveMessage(0, 'fs_av', <String, dynamic>{'av': '07-star-fox'}));
      await tester.pump(const Duration(milliseconds: 50));
      expect(net.liveSent.length, before + 1); // answered a new phone once
      net.liveCtl.add(const NetLiveMessage(0, 'fs_av', <String, dynamic>{'av': '07-star-fox'}));
      await tester.pump(const Duration(milliseconds: 50));
      expect(net.liveSent.length, before + 1); // no ping-pong
      net.deliver(0, _setup('club3', 1));
      net.deliver(1, _setup('club4', 2));
      await tester.pump(const Duration(milliseconds: 300));
      final BmEngine e = stateOf(tester).matchEngine as BmEngine;
      e.score = <int>[e.ct(0) == 0 ? 3 : 1, e.ct(1) == 0 ? 3 : 1]; // global side 0 scored 3, side 1 scored 1
      e.end();
      await pumpFor(tester, 2.5);
      final List<FsScoreRow> rows = stateOf(tester).scoreRows() as List<FsScoreRow>;
      expect(rows.length, seats);
      // winner side (global side 0 = seats 0,2,4) first, each row with its side's goals
      expect(rows.first.name, 'Ali');
      expect(rows.first.avatar, '07-star-fox');
      for (int i = 0; i < seats; i++) {
        expect(rows[i].winner, i < seats ~/ 2);
        expect(rows[i].score, i < seats ~/ 2 ? 3 : 1);
      }
      expect(rows.firstWhere((FsScoreRow r) => r.name == 'Sara').avatar, isNotNull); // this phone's own avatar
      expect(find.text('جدول امتیازات'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await close(tester);
      await net.liveCtl.close();
    });
  }
}
