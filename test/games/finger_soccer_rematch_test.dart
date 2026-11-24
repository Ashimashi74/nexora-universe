// v13 online rematch (bm_rematch.dart): state machine, two linked controllers, carry of the picks.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/core/net_link.dart';
import 'package:nexora/games/finger_soccer/ui/bm_rematch.dart';

class _Net extends ChangeNotifier implements NetLink {
  _Net(this.mySeat, {this.matchId = 'm1'});
  @override
  final int mySeat;
  @override
  final String matchId;
  _Net? peer;
  final StreamController<NetLiveMessage> _live = StreamController<NetLiveMessage>.broadcast(sync: true);
  Set<int> connected = <int>{0, 1};
  @override
  int get seatCount => 2;
  @override
  int get seed => 1;
  @override
  Map<String, dynamic> get settings => const <String, dynamic>{};
  @override
  List<String> get names => const <String>['A', 'B'];
  @override
  Set<int> get connectedSeats => connected;
  @override
  Set<int> get forfeitedSeats => const <int>{};
  @override
  bool get isAuthority => mySeat == 0;
  @override
  Listenable get changes => this;
  @override
  bool get replaying => false;
  @override
  void listen(void Function(NetMove move) onMove, {VoidCallback? onReplayDone}) {}
  @override
  Future<bool> send(Map<String, dynamic> data, {String kind = 'move', String? hash, int? asSeat}) async => false;
  @override
  void sendLive(String event, Map<String, dynamic> data) => peer?._live.add(NetLiveMessage(mySeat, event, data));
  @override
  Stream<NetLiveMessage> get live => _live.stream;
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
  void leave(int seat) {
    connected = <int>{...connected}..remove(seat);
    notifyListeners();
  }
}

void main() {
  group('machine', () {
    test('request -> accept starts', () {
      final FsRematchMachine a = FsRematchMachine(mySeat: 0, seatCount: 2);
      final FsRematchMachine b = FsRematchMachine(mySeat: 1, seatCount: 2);
      final Map<String, dynamic> req = a.request(0, 7)!;
      expect(a.phase, FsRematchPhase.waiting);
      b.receive(0, req, 10);
      expect(b.phase, FsRematchPhase.incoming);
      final Map<String, dynamic> acc = b.accept(20)!;
      expect(b.phase, FsRematchPhase.starting);
      a.receive(1, acc, 30);
      expect(a.phase, FsRematchPhase.starting);
    });

    test('no answer within 20 s -> noAnswer, the prompt clears on the other phone', () {
      final FsRematchMachine a = FsRematchMachine(mySeat: 0, seatCount: 2);
      final FsRematchMachine b = FsRematchMachine(mySeat: 1, seatCount: 2);
      b.receive(0, a.request(0, 3)!, 0);
      expect(a.tick(19999), isNull);
      final Map<String, dynamic>? cancel = a.tick(kFsRematchTimeoutMs + 1.0);
      expect(a.phase, FsRematchPhase.noAnswer);
      expect(cancel?['op'], 'cancel');
      b.receive(0, cancel!, kFsRematchTimeoutMs + 2.0);
      expect(b.phase, FsRematchPhase.idle);
      expect(a.canRequest, isTrue);
    });

    test('decline', () {
      final FsRematchMachine a = FsRematchMachine(mySeat: 0, seatCount: 2);
      final FsRematchMachine b = FsRematchMachine(mySeat: 1, seatCount: 2);
      b.receive(0, a.request(0, 5)!, 0);
      a.receive(1, b.decline()!, 1);
      expect(a.phase, FsRematchPhase.declined);
      expect(b.phase, FsRematchPhase.idle);
    });

    test('crossing requests count as both accepting', () {
      final FsRematchMachine a = FsRematchMachine(mySeat: 0, seatCount: 2);
      final FsRematchMachine b = FsRematchMachine(mySeat: 1, seatCount: 2);
      final Map<String, dynamic> ra = a.request(0, 1)!, rb = b.request(0, 2)!;
      a.receive(1, rb, 1);
      b.receive(0, ra, 1);
      expect(a.phase, FsRematchPhase.starting);
      expect(b.phase, FsRematchPhase.starting);
    });

    test('opponent left disables the request; back after a blip', () {
      final FsRematchMachine a = FsRematchMachine(mySeat: 0, seatCount: 2);
      a.presence(<int>{0});
      expect(a.phase, FsRematchPhase.opponentLeft);
      expect(a.canRequest, isFalse);
      expect(a.request(0, 1), isNull);
      a.presence(<int>{0, 1});
      expect(a.phase, FsRematchPhase.idle);
    });

    test('starting ignores the other phone leaving and fails without a match in time', () {
      final FsRematchMachine a = FsRematchMachine(mySeat: 0, seatCount: 2);
      a.request(0, 1);
      a.receive(1, <String, dynamic>{'op': 'acc', 'n': 1}, 0);
      a.presence(<int>{0});
      expect(a.phase, FsRematchPhase.starting);
      a.tick(kFsRematchStartMs + 1.0);
      expect(a.phase, FsRematchPhase.failed);
    });
  });

  group('controller', () {
    test('both accept -> seat 0 creates the match, both phones go to it', () async {
      final _Net n0 = _Net(0), n1 = _Net(1);
      n0.peer = n1;
      n1.peer = n0;
      final List<String> went = <String>[];
      int created = 0;
      final FsRematchController c0 = FsRematchController(
          net: n0, starter: () async => 'm2${created++ > 0 ? 'x' : ''}', roomPoll: () async => null, onGo: went.add);
      final FsRematchController c1 = FsRematchController(
          net: n1, starter: () async => null, roomPoll: () async => null, onGo: went.add);
      c0.request();
      expect(c1.phase, FsRematchPhase.incoming);
      c1.accept();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(went, <String>['m2', 'm2']);
      expect(created, 1);
      c0.dispose();
      c1.dispose();
    });

    test('the end screen is held while a request is open', () async {
      final _Net n0 = _Net(0), n1 = _Net(1);
      n0.peer = n1;
      n1.peer = n0;
      final FsRematchController c0 =
          FsRematchController(net: n0, starter: () async => null, roomPoll: () async => null, onGo: (_) {});
      final FsRematchController c1 =
          FsRematchController(net: n1, starter: () async => null, roomPoll: () async => null, onGo: (_) {});
      bool released = false;
      unawaited(c0.released.then((_) => released = true));
      c0.request();
      c0.tableDone();
      await Future<void>.delayed(Duration.zero);
      expect(released, isFalse);
      c1.decline();
      await Future<void>.delayed(Duration.zero);
      expect(c0.phase, FsRematchPhase.declined);
      expect(released, isTrue);
      c0.dispose();
      c1.dispose();
    });

    test('opponent leaving shows and disables', () {
      final _Net n0 = _Net(0);
      final FsRematchController c0 =
          FsRematchController(net: n0, starter: () async => null, roomPoll: () async => null, onGo: (_) {});
      n0.leave(1);
      expect(c0.phase, FsRematchPhase.opponentLeft);
      c0.dispose();
    });
  });

  group('carry', () {
    tearDown(FsRematchCarry.clear);
    test('picks carry into the next match of the same players only', () {
      FsRematchCarry.put('m1', <String>['A', 'B'], <String, dynamic>{'a': 'setup', 'team': 'realmadrid', 'form': 2});
      expect(FsRematchCarry.take(_Net(0)), isNull); // same match: not a rematch
      expect(FsRematchCarry.take(_Net(0, matchId: 'm2'))?['team'], 'realmadrid');
      expect(FsRematchCarry.take(_Net(0, matchId: 'm2')), isNull); // taken once
    });
  });

  test('tournament games never offer a rematch', () {
    expect(fsRematchAllowed(const <String, dynamic>{'tournament': 't', 'tmatch': 'x'}, roomId: 'r'), isFalse);
    expect(fsRematchAllowed(const <String, dynamic>{}, roomId: null), isFalse);
    expect(fsRematchAllowed(const <String, dynamic>{}, roomId: 'r'), isTrue);
  });
}
