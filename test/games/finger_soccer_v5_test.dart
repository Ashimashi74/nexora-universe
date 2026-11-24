import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/storage/local_store.dart';
import 'package:nexora/games/core/game_contract.dart';
import 'package:nexora/games/finger_soccer/core/bm_engine.dart';
import 'package:nexora/games/finger_soccer/ui/bm_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// v5 (owner request 2026-11-20): online picks on one shared countdown (team 15 s, formation 15 s; an early picker
/// waits, everyone enters together) and team-game results (2v2 / 3v3: every seat of a side gets the side's result,
/// a leaver loses).
class _FakeNet implements NetLink {
  _FakeNet({this.seat = 0, this.seats = 2, Map<String, dynamic>? settings}) : _settings = settings ?? <String, dynamic>{};
  final int seat, seats;
  final Set<int> forfeited = <int>{};
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
  int get seatCount => seats;
  @override
  int get seed => 7;
  @override
  Map<String, dynamic> get settings => _settings;
  @override
  List<String> get names => const <String>['Ali', 'Sara', 'Reza', 'Mina', 'Omid', 'Lida'].sublist(0, seats);
  @override
  Set<int> get connectedSeats => <int>{for (int s = 0; s < seats; s++) if (!forfeited.contains(s)) s};
  @override
  Set<int> get forfeitedSeats => forfeited;
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

GameLaunch _launch(NetLink net, {void Function(GameResult r)? onFinish}) => GameLaunch(
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

  Future<_FakeNet> open(WidgetTester tester,
      {int seat = 0, int seats = 2, void Function(GameResult r)? onFinish}) async {
    phone(tester);
    final _FakeNet net = _FakeNet(seat: seat, seats: seats);
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(
                backgroundColor: Colors.black, body: BermudaView(launch: _launch(net, onFinish: onFinish))))));
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

  Iterable<Map<String, dynamic>> sentOf(_FakeNet n, String a) => n.sent.where((Map<String, dynamic> d) => d['a'] == a);

  // 2026-11-24: the online pre-match is the app's black-gold lobby (BermudaView._setupScreen) with one shared
  // 30 s countdown; the reference-style FsOnlinePick screens are gone.
  group('online lobby countdown', () {
    testWidgets('READY sends the pick and waits; the opponent\'s pick starts the match for everyone',
        (WidgetTester tester) async {
      final _FakeNet net = await open(tester);
      expect(find.byKey(const ValueKey<String>('setup-ready')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('online-opp-status')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('setup-ready')));
      await pumpFor(tester, 1);
      expect(sentOf(net, 'setup').length, 1);
      expect(engineOf(tester), isNull);
      expect(find.byKey(const ValueKey<String>('online-wait')), findsOneWidget);
      net.deliver(1, _setup('club9', 4));
      await tester.pump(const Duration(milliseconds: 300));
      expect(engineOf(tester)!.sel, <String>[sentOf(net, 'setup').first['team'] as String, 'club9']);
      await close(tester);
    });

    testWidgets('team pick replayed from the log (older app) is not a play move (no legacy room start)',
        (WidgetTester tester) async {
      final _FakeNet net = await open(tester, seat: 1);
      net.deliver(0, <String, dynamic>{'a': 'tpick', 'team': 'club3'}, replay: true);
      await tester.pump(const Duration(milliseconds: 300));
      expect(engineOf(tester), isNull);
      expect(find.byKey(const ValueKey<String>('setup-ready')), findsOneWidget);
      await close(tester);
    });

    testWidgets('idle phones: the 30 s countdown sends the shown pick, then a silent side is filled in',
        (WidgetTester tester) async {
      final _FakeNet net = await open(tester, seat: 1);
      await pumpFor(tester, 29);
      expect(sentOf(net, 'setup'), isEmpty);
      await pumpFor(tester, 2); // countdown over: the pick on screen goes out
      expect(sentOf(net, 'setup').where((Map<String, dynamic> d) => d['for'] == null).length, 1);
      expect(engineOf(tester), isNull);
      await pumpFor(tester, 15); // watchdog (45 s) logs a default for the silent side
      expect(net.sent.where((Map<String, dynamic> d) => d['for'] == 0), isNotEmpty);
      await tester.pump(const Duration(milliseconds: 300));
      expect(engineOf(tester), isNotNull);
      await close(tester);
    });
  });

  test('team games: a seat that left has its turns played by the next teammate still in the match', () {
    final BmEngine e = BmEngine(_NoHooks(), rng: math.Random(1));
    e.perSide = 3;
    e.sideTurns[0] = 2; // side 0's shooter index 1 -> seat 2
    expect(e.shooterSeat(0), 2);
    expect(e.controllerSeat(0), 2);
    e.seatGone = (int s) => s == 2;
    expect(e.shooterSeat(0), 2); // rotation unchanged (replays agree)
    expect(e.controllerSeat(0), 4);
    e.seatGone = (int s) => s == 2 || s == 4;
    expect(e.controllerSeat(0), 0);
    e.perSide = 1;
    expect(e.controllerSeat(1), 1);
  });

  group('team games (2v2 / 3v3) results', () {
    Future<GameResult> playToEnd(WidgetTester tester, int seat, int seats, List<int> global,
        {Set<int> left = const <int>{}, bool forfeit = false}) async {
      GameResult? got;
      final _FakeNet net = await open(tester, seat: seat, seats: seats, onFinish: (GameResult r) => got = r);
      net.forfeited.addAll(left);
      net.deliver(0, _setup('club3', 1));
      net.deliver(1, _setup('club4', 2));
      await tester.pump(const Duration(milliseconds: 300));
      final BmEngine e = engineOf(tester)!;
      expect(e.perSide, seats ~/ 2);
      e.score = <int>[global[e.ct(0)], global[e.ct(1)]];
      e.end();
      await pumpFor(tester, 2.5);
      await close(tester);
      return got!;
    }

    for (final int seats in <int>[4, 6]) {
      testWidgets('$seats players: every seat of a side gets the side\'s result', (WidgetTester tester) async {
        final List<int> win0 = <int>[for (int s = 0; s < seats; s += 2) s];
        for (int seat = 0; seat < seats; seat++) {
          final GameResult r = await playToEnd(tester, seat, seats, <int>[3, 1]);
          expect(r.winnerSeats, win0, reason: 'seat $seat');
          expect(r.outcome, seat.isEven ? GameOutcome.win : GameOutcome.loss, reason: 'seat $seat');
          expect(r.score, seat.isEven ? 3 : 1, reason: 'seat $seat');
          expect(r.opponentScore, seat.isEven ? 1 : 3, reason: 'seat $seat');
          // per-seat scores for the server (seat i's own side's goals), not just [side 0, side 1]
          expect(r.scores, <int>[for (int s = 0; s < seats; s++) s.isEven ? 3 : 1], reason: 'seat $seat');
        }
      });
    }

    testWidgets('4 players, draw: nobody wins', (WidgetTester tester) async {
      for (int seat = 0; seat < 4; seat++) {
        final GameResult r = await playToEnd(tester, seat, 4, <int>[2, 2]);
        expect(r.winnerSeats, isEmpty);
        expect(r.outcome, GameOutcome.draw);
      }
    });

    testWidgets('4 players, a player left: the leaver is never a winner, the others keep their side\'s result',
        (WidgetTester tester) async {
      for (int seat = 0; seat < 4; seat++) {
        if (seat == 2) continue; // the leaver's phone is gone
        final GameResult r = await playToEnd(tester, seat, 4, <int>[3, 1], left: <int>{2});
        expect(r.winnerSeats, <int>[0], reason: 'seat $seat');
        expect(r.outcome, seat.isEven ? GameOutcome.win : GameOutcome.loss, reason: 'seat $seat');
      }
    });
  });
}

class _NoHooks implements BmHooks {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
