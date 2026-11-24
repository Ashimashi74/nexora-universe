// Online multiplayer v7: authority election, absence limits, refused-move recovery and the quick-match lobby loop.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/online/match_link.dart';
import 'package:nexora/core/online/quick_match_state.dart';
import 'package:nexora/games/core/net_link.dart';

import 'fake_match_server.dart';

Future<void> _settle([int ms = 400]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  group('authoritySeat', () {
    test('before presence syncs every seat is assumed connected: only seat 0 is the authority', () {
      for (int me = 0; me < 4; me++) {
        expect(
            authoritySeat(seatCount: 4, mySeat: me, connected: <int>{me}, forfeited: <int>{}, presenceKnown: false), 0);
      }
    });

    test('after presence: the lowest connected, non-forfeited seat', () {
      // seat 0 dropped: seat 1 takes over on every phone that sees it
      expect(authoritySeat(seatCount: 3, mySeat: 1, connected: <int>{1, 2}, forfeited: <int>{}, presenceKnown: true), 1);
      expect(authoritySeat(seatCount: 3, mySeat: 2, connected: <int>{1, 2}, forfeited: <int>{}, presenceKnown: true), 1);
      // seat 0 forfeited, still "connected": skipped
      expect(authoritySeat(seatCount: 3, mySeat: 2, connected: <int>{0, 1, 2}, forfeited: <int>{0}, presenceKnown: true),
          1);
      // forfeits are skipped before presence too
      expect(
          authoritySeat(seatCount: 3, mySeat: 2, connected: <int>{2}, forfeited: <int>{0, 1}, presenceKnown: false), 2);
    });

    test('a phone always counts itself as connected', () {
      expect(authoritySeat(seatCount: 2, mySeat: 1, connected: <int>{}, forfeited: <int>{}, presenceKnown: true), 1);
    });
  });

  test('absence limits: 40 s on turn, 90 s waiting, tournament grace overrides', () {
    expect(absenceLimitSec(onTurn: true), 40);
    expect(absenceLimitSec(onTurn: false), 90);
    expect(absenceLimitSec(onTurn: true, graceSec: 60), 60);
  });

  test('MatchEnd: abandoned and forfeit reasons', () {
    expect(const MatchEnd(winners: <int>[], reason: 'abandoned').isAbandoned, isTrue);
    expect(const MatchEnd(winners: <int>[], reason: 'abandoned').isForfeit, isFalse);
    expect(const MatchEnd(winners: <int>[1], reason: 'forfeit:0').forfeitSeat, 0);
  });

  group('refused moves never leave a phantom row behind (strict seat server)', () {
    test('a move for another seat is refused, the phone resyncs, and the next move lands at the right seq', () async {
      final FakeMatchServer s = FakeMatchServer(players: <String>['u0', 'u1'], strictSeats: true);
      final SupabaseMatchLink a = fakeLink(s, 0), b = fakeLink(s, 1);
      int resyncs = 0;
      a.resyncRequests.addListener(() => resyncs++);
      final List<NetMove> gb = <NetMove>[];
      a.listen((_) {});
      b.listen(gb.add);
      await _settle(150);

      expect(await a.send(<String, dynamic>{'a': 'roll'}), isTrue);
      // an ordinary move posted for the opponent's seat: refused by the server
      expect(await a.send(<String, dynamic>{'a': 'vote', 'v': -1}, asSeat: 1), isFalse);
      expect(resyncs, 1, reason: 'the optimistic row is not in the log: rebuild from the server');
      expect(s.rows.length, 1);

      // the game rebuilds and replays: the phantom move is gone, the next move takes seq 2
      final List<NetMove> replay = <NetMove>[];
      final Completer<void> done = Completer<void>();
      a.listen(replay.add, onReplayDone: done.complete);
      await done.future;
      expect(replay.map((NetMove m) => m.data['a']).toList(), <String>['roll']);
      expect(await a.send(<String, dynamic>{'a': 'play'}), isTrue);
      await _settle();
      expect(s.rows.map((Map<String, dynamic> r) => r['seq']).toList(), <int>[1, 2]);
      expect(gb.map((NetMove m) => m.data['a']).toList(), <String>['roll', 'play']);
      a.dispose();
      b.dispose();
    });

    test('a timeout for another seat (authority) is still accepted', () async {
      final FakeMatchServer s = FakeMatchServer(players: <String>['u0', 'u1', 'u2'], strictSeats: true);
      final SupabaseMatchLink a = fakeLink(s, 0), c = fakeLink(s, 2);
      final List<NetMove> gc = <NetMove>[];
      a.listen((_) {});
      c.listen(gc.add);
      await _settle(150);
      expect(await a.send(<String, dynamic>{'a': 'vote', 'v': -1}, kind: 'timeout', asSeat: 1), isTrue);
      await _settle();
      expect(gc.single.kind, 'timeout');
      expect(gc.single.seat, 1);
      a.dispose();
      c.dispose();
    });

    test('a forfeit for another seat through the move log is refused', () async {
      final FakeMatchServer s = FakeMatchServer(players: <String>['u0', 'u1'], strictSeats: true);
      final SupabaseMatchLink a = fakeLink(s, 0);
      a.listen((_) {});
      await _settle(150);
      expect(await a.send(<String, dynamic>{'a': 'leave', 'seat': 1}, kind: 'forfeit', asSeat: 1), isFalse);
      expect(s.forfeited, isEmpty);
      expect(await a.send(<String, dynamic>{'a': 'leave', 'seat': 0}, kind: 'forfeit'), isTrue);
      expect(s.forfeited, <int>{0});
      a.dispose();
    });
  });

  group('quick-match lobby loop', () {
    LobbyTick tick({
      bool hasRoom = true,
      bool quick = true,
      String? status = 'lobby',
      bool seated = true,
      bool inMatch = false,
      bool busy = false,
      String? matchId,
      String? lastMatchSeen,
    }) =>
        lobbyTick(
            hasRoom: hasRoom,
            quick: quick,
            status: status,
            seated: seated,
            inMatch: inMatch,
            busy: busy,
            matchId: matchId,
            lastMatchSeen: lastMatchSeen);

    test('waiting in a quick lobby keeps matchmaking; a regular room only pings', () {
      expect(tick(), LobbyTick.requeue);
      expect(tick(quick: false), LobbyTick.ping);
    });

    test('a dead quick lobby goes back into the queue', () {
      expect(tick(status: 'closed'), LobbyTick.rejoinQueue);
      expect(tick(seated: false), LobbyTick.rejoinQueue, reason: 'dropped as a silent seat');
      expect(tick(status: 'playing', seated: false, matchId: 'm'), LobbyTick.rejoinQueue,
          reason: 'the match started without us');
      expect(tick(status: 'closed', busy: true), LobbyTick.idle, reason: 'never two matchmaking calls at once');
    });

    test('a regular room never re-queues', () {
      expect(tick(quick: false, status: 'closed'), LobbyTick.idle);
      expect(tick(quick: false, seated: false), LobbyTick.ping);
    });

    test('a running match opens once, and nothing happens while it is on screen', () {
      expect(tick(status: 'playing', matchId: 'm'), LobbyTick.openMatch);
      expect(tick(status: 'playing', matchId: 'm', lastMatchSeen: 'm'), LobbyTick.idle);
      expect(tick(status: 'closed', inMatch: true), LobbyTick.idle);
      expect(tick(hasRoom: false), LobbyTick.idle);
    });
  });
}
