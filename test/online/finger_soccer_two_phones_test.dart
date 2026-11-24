// ANIX PRO P0: two phones, one server. A room match must leave the team / formation screens on both phones (also on
// the old turn-gated server function and when one phone never picks), and both phones must show the same match.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/online/match_link.dart';
import 'package:nexora/core/storage/local_store.dart';
import 'package:nexora/games/core/game_contract.dart';
import 'package:nexora/games/finger_soccer/core/bm_engine.dart';
import 'package:nexora/games/finger_soccer/ui/bm_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_match_server.dart';

GameLaunch _launch(NetLink net) => GameLaunch(
      gameId: 'finger_soccer',
      mode: GameMode.online,
      difficulty: BotDifficulty.normal,
      playerName: 'P${net.mySeat}',
      isFa: true,
      fancyEffects: false,
      reducedMotion: true,
      soundOn: false,
      seed: net.seed,
      net: net,
      onFinish: (_) {},
    );

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(<String, Object>{'settings.lang': 'fa', 'settings.sound': false});
    await LocalStore.init();
  });

  Future<void> pumpFor(WidgetTester tester, double seconds) async {
    for (int i = 0; i < seconds * 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<List<SupabaseMatchLink>> openBoth(WidgetTester tester, FakeMatchServer s) async {
    tester.view.physicalSize = const Size(720, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final List<SupabaseMatchLink> links = <SupabaseMatchLink>[fakeLink(s, 0), fakeLink(s, 1)];
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(
                backgroundColor: Colors.black,
                body: Row(children: <Widget>[
                  for (final SupabaseMatchLink l in links)
                    SizedBox(width: 360, height: 800, child: BermudaView(key: ValueKey<int>(l.mySeat), launch: _launch(l))),
                ])))));
    return links;
  }

  BmEngine? engineOf(WidgetTester tester, int seat) {
    final dynamic st = tester.state(find.byKey(ValueKey<int>(seat)));
    return st.matchEngine as BmEngine?;
  }

  Future<void> closeAll(WidgetTester tester, List<SupabaseMatchLink> links) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    for (final SupabaseMatchLink l in links) {
      l.dispose();
    }
  }

  for (final bool legacy in <bool>[false, true]) {
    final String srv = legacy ? 'old turn-gated server' : 'fixed server';

    testWidgets('room match: both phones leave the picks and start the same match ($srv)', (WidgetTester tester) async {
      final FakeMatchServer s = FakeMatchServer(players: <String>['u0', 'u1'], legacyTurnGate: legacy, settings: <String, dynamic>{
        'room_prefs': <String, dynamic>{
          '0': <String, dynamic>{'team': 'club0', 'form': 1},
          '1': <String, dynamic>{'team': 'club1', 'form': 2},
        },
      });
      final List<SupabaseMatchLink> links = await openBoth(tester, s);
      // nobody touches anything: the shared countdowns pick for both phones
      await pumpFor(tester, 40);
      final BmEngine? a = engineOf(tester, 0), b = engineOf(tester, 1);
      expect(a, isNotNull, reason: 'seat 0 is still on the pick / waiting screen');
      expect(b, isNotNull, reason: 'seat 1 is still on the pick / waiting screen');
      expect(find.text('منتظر بقیه‌ی بازیکن‌ها…'), findsNothing);
      expect(s.refused, 0);
      // same match on both phones: same teams / formations per global side, mirrored only on seat 1
      expect(a!.mirror, isFalse);
      expect(b!.mirror, isTrue);
      expect(a.snapshot(), b.snapshot());
      await closeAll(tester, links);
    });
  }

  testWidgets('a phone that never answers cannot hold the other on the waiting screen', (WidgetTester tester) async {
    final FakeMatchServer s = FakeMatchServer(players: <String>['u0', 'u1']);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final SupabaseMatchLink a = fakeLink(s, 0);
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(home: Scaffold(body: BermudaView(key: const ValueKey<int>(0), launch: _launch(a))))));
    await pumpFor(tester, 70);
    expect(engineOf(tester, 0), isNotNull, reason: 'the default setup for the silent side starts the match');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    a.dispose();
  });

  testWidgets('a shot on one phone ends in the same position on the other (mirrored seat included)',
      (WidgetTester tester) async {
    final FakeMatchServer s = FakeMatchServer(players: <String>['u0', 'u1']);
    final List<SupabaseMatchLink> links = await openBoth(tester, s);
    await pumpFor(tester, 40);
    final BmEngine a = engineOf(tester, 0)!, b = engineOf(tester, 1)!;
    await pumpFor(tester, 4);
    for (int shot = 0; shot < 4; shot++) {
      final BmEngine shooter = a.turn == 0 ? a : b;
      expect(shooter.phase, 'aim');
      final BmBody piece = shooter.bodies.firstWhere((BmBody x) => x != shooter.ball && x.team == shooter.turn);
      final BmBody ball = shooter.ball!;
      final double dx = ball.x - piece.x, dy = ball.y - piece.y;
      shooter.launch(piece, dx * 4, dy * 4, false);
      await pumpFor(tester, 9);
      expect(a.snapshot(), b.snapshot(), reason: 'boards differ after shot $shot');
      expect(<int>[a.score[a.ct(0)], a.score[a.ct(1)]], <int>[b.score[b.ct(0)], b.score[b.ct(1)]]);
    }
    await closeAll(tester, links);
  });
}
