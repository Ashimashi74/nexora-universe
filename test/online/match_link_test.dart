// ANIX PRO P0: the online move log. Two real SupabaseMatchLink instances on one in-memory server.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/online/match_link.dart';
import 'package:nexora/games/core/net_link.dart';

import 'fake_match_server.dart';

Future<void> _settle([int ms = 600]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  for (final bool legacy in <bool>[false, true]) {
    final String srv = legacy ? 'old turn-gated nx_push_move' : 'fixed nx_push_move';

    test('both phones post their pre-match picks at once and both see both ($srv)', () async {
      final FakeMatchServer s = FakeMatchServer(players: <String>['u0', 'u1'], legacyTurnGate: legacy)
        ..latency = const Duration(milliseconds: 30);
      final SupabaseMatchLink a = fakeLink(s, 0), b = fakeLink(s, 1);
      final List<NetMove> ga = <NetMove>[], gb = <NetMove>[];
      int resyncs = 0;
      a.resyncRequests.addListener(() => resyncs++);
      b.resyncRequests.addListener(() => resyncs++);
      a.listen(ga.add);
      b.listen(gb.add);
      await _settle(200);
      // the same instant on both phones: both race for seq 1, then 2
      final List<bool> ok = await Future.wait(<Future<bool>>[
        a.send(<String, dynamic>{'a': 'tpick', 'team': 'club0', kNetFloat: true}),
        b.send(<String, dynamic>{'a': 'tpick', 'team': 'club1', kNetFloat: true}),
        a.send(<String, dynamic>{'a': 'setup', 'team': 'club0', 'form': 2, kNetFloat: true}),
        b.send(<String, dynamic>{'a': 'setup', 'team': 'club1', 'form': 4, kNetFloat: true}),
      ]);
      await _settle();
      expect(ok, everyElement(isTrue));
      expect(resyncs, 0, reason: 'order-independent picks never force a rebuild');
      expect(s.rows.length, 4);
      expect(s.refused, 0);
      // each phone got exactly the other's two moves, in log order, with the real kind restored
      expect(ga.map((NetMove m) => m.data['team']).toList(), <String>['club1', 'club1']);
      expect(gb.map((NetMove m) => m.data['team']).toList(), <String>['club0', 'club0']);
      expect(<String>{...ga.map((NetMove m) => m.kind), ...gb.map((NetMove m) => m.kind)}, <String>{'move'});
      a.dispose();
      b.dispose();
    });

    test('a shot, the shooter\'s settled snapshot and a goal all reach the other phone ($srv)', () async {
      final FakeMatchServer s = FakeMatchServer(players: <String>['u0', 'u1'], legacyTurnGate: legacy);
      final SupabaseMatchLink a = fakeLink(s, 0), b = fakeLink(s, 1);
      final List<NetMove> gb = <NetMove>[];
      int resyncs = 0;
      a.resyncRequests.addListener(() => resyncs++);
      a.listen((_) {});
      b.listen(gb.add);
      await _settle(200);
      expect(await a.send(<String, dynamic>{'a': 'shot', 'cid': 3, 'vx': 1.5, 'vy': -2.0}), isTrue);
      expect(await a.send(<String, dynamic>{'a': 'settled', 'snap': <String, dynamic>{'tn': 1}}), isTrue);
      expect(await a.send(<String, dynamic>{'a': 'goal', 'team': 0}), isTrue);
      expect(await a.send(<String, dynamic>{'a': 'timeout', 'seat': 1}, kind: 'timeout'), isTrue);
      await _settle();
      expect(resyncs, 0);
      expect(gb.map((NetMove m) => m.data['a']).toList(), <String>['shot', 'settled', 'goal', 'timeout']);
      expect(gb.last.kind, 'timeout');
      expect(gb.last.isTimeout, isTrue);
      expect(gb.first.data.containsKey('_k'), isFalse);
      a.dispose();
      b.dispose();
    });
  }

  test('a late joiner replays the whole log, wrapped rows decoded', () async {
    final FakeMatchServer s = FakeMatchServer(players: <String>['u0', 'u1'], legacyTurnGate: true);
    final SupabaseMatchLink a = fakeLink(s, 0);
    a.listen((_) {});
    await a.send(<String, dynamic>{'a': 'setup', 'team': 'club0', kNetFloat: true});
    await a.send(<String, dynamic>{'a': 'shot', 'cid': 1});
    final SupabaseMatchLink b = fakeLink(s, 1);
    final List<NetMove> gb = <NetMove>[];
    final Completer<void> done = Completer<void>();
    b.listen(gb.add, onReplayDone: done.complete);
    await done.future;
    expect(gb.map((NetMove m) => '${m.kind}:${m.data['a']}:${m.replay}').toList(),
        <String>['move:setup:true', 'move:shot:true']);
    a.dispose();
    b.dispose();
  });
}
