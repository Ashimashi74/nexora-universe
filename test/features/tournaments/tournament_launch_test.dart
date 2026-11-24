import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tournaments/domain/bracket.dart';
import 'package:nexora/features/tournaments/domain/reminders.dart';

void main() {
  group('best-of range matches the server (1..15)', () {
    test('any 1..15 is kept, everything else falls back to 1', () {
      for (int v = 1; v <= 15; v++) {
        expect(BestOf(early: v, semi: v, finalRound: v).of('early'), v);
      }
      expect(const BestOf(early: 0).of('early'), 1);
      expect(const BestOf(early: 16).of('early'), 1);
      expect(const BestOf(finalRound: 7).of('final'), 7);
    });

    test('Bo7 series: first to four wins; even best-of split goes to the decider', () {
      final Series s = Series(bestOf: 7);
      for (int i = 0; i < 3; i++) {
        expect(s.add(1, 0, 1), SeriesOutcome.more);
      }
      expect(s.add(0, 1, 2), SeriesOutcome.more);
      expect(s.add(1, 0, 1), SeriesOutcome.p1);
      final Series four = Series(bestOf: 4);
      expect(four.add(1, 0, 1), SeriesOutcome.more);
      expect(four.add(1, 0, 1), SeriesOutcome.more);
      expect(four.add(0, 1, 2), SeriesOutcome.more);
      expect(four.add(0, 1, 2), SeriesOutcome.more);
      expect(four.nextIsGolden, isTrue);
      expect(four.add(1, 0, 1), SeriesOutcome.p1);
    });
  });

  test('swiss match count includes the bye row of an odd field', () {
    expect(BracketGen.matchCount(TFormat.swiss, 8, swissRoundsCfg: 3), 12);
    expect(BracketGen.matchCount(TFormat.swiss, 7, swissRoundsCfg: 3), 12);
  });

  group('disqualification after the draw', () {
    test('single elimination: a disqualified player never advances and the bracket still finishes', () {
      for (int n = 2; n <= 33; n++) {
        for (final int dq in <int>{1, 2, n}) {
          final Bracket b = BracketGen.singleElim(n, thirdPlace: n >= 4);
          // byes are decided at the draw, before anybody can be disqualified
          final Set<String> before = <String>{for (final BMatch m in b.matches) if (m.isFinal) m.id};
          b.disqualify(dq);
          b.simulate((BMatch m, int a, int c) => a < c ? a : c);
          expect(b.finished, isTrue, reason: 'n=$n dq=$dq');
          expect(b.champion, isNot(dq));
          for (final BMatch m in b.matches) {
            if (before.contains(m.id)) continue;
            expect(m.winner == dq, isFalse, reason: 'n=$n dq=$dq ${m.id}');
          }
        }
      }
    });

    test('double elimination: disqualified mid-way, every later match is a walkover', () {
      for (int n = 3; n <= 20; n++) {
        final Bracket b = BracketGen.doubleElim(n);
        // play the first round, then disqualify the top seed
        for (final BMatch m in b.playable.where((BMatch x) => x.bracket == 'W' && x.round == 1).toList()) {
          b.complete(m.id, m.p1! < m.p2! ? m.p1 : m.p2, m.p1! < m.p2! ? m.p2 : m.p1);
        }
        final Set<String> before = <String>{for (final BMatch m in b.matches) if (m.isFinal) m.id};
        b.disqualify(1);
        b.simulate((BMatch m, int a, int c) => a < c ? a : c);
        expect(b.finished, isTrue, reason: 'n=$n');
        expect(b.champion, isNot(1), reason: 'n=$n');
        expect(b.champion, isNotNull, reason: 'n=$n');
        for (final BMatch m in b.matches) {
          if (before.contains(m.id)) continue;
          if (m.status == 'done') expect(m.p1 == 1 || m.p2 == 1, isFalse, reason: 'n=$n ${m.id}');
          if (m.p1 == 1 || m.p2 == 1) expect(m.winner == 1, isFalse, reason: 'n=$n ${m.id}');
        }
      }
    });

    test('disqualified one after the other: the later match is a walkover too', () {
      final Bracket b = BracketGen.singleElim(8);
      b.disqualify(1);
      b.disqualify(8); // 8 got the walkover against 1, then is disqualified as well
      expect(b[BMatch.matchId('W', 1, 0)]!.winner, 8);
      b.simulate((BMatch m, int a, int c) => a < c ? a : c);
      expect(b.finished, isTrue);
      expect(b[BMatch.matchId('W', 2, 0)]!.status, 'walkover');
      expect(b.champion, 2);
    });

    test('two disqualified players seated in one match: nobody advances, the next opponent gets a bye', () {
      final Bracket b = Bracket()
        ..add(BMatch(bracket: 'W', round: 1, idx: 0)
          ..winTo = 'W2-0'
          ..winSlot = 1)
        ..add(BMatch(bracket: 'W', round: 1, idx: 1)
          ..winTo = 'W2-0'
          ..winSlot = 2)
        ..add(BMatch(bracket: 'W', round: 2, idx: 0));
      b.removed.addAll(<int>{1, 4});
      b.put('W1-0', 1, 1);
      b.put('W1-0', 2, 4);
      expect(b['W1-0']!.status, 'walkover');
      expect(b['W1-0']!.winner, isNull);
      b.put('W1-1', 1, 2);
      b.put('W1-1', 2, 3);
      b.simulate((BMatch m, int a, int c) => a < c ? a : c);
      expect(b['W2-0']!.status, 'bye');
      expect(b.champion, 2);
    });
  });

  group('device reminders', () {
    final DateTime now = DateTime.utc(2026, 12, 1, 12);
    TRemTournament t(String id, String status, {int inMin = 60, bool checkin = false}) =>
        TRemTournament(id: id, status: status, startAt: now.add(Duration(minutes: inMin)), checkin: checkin);

    test('only tournaments I am in, before they start, 10 minutes early', () {
      final List<TReminder> plan = ReminderPlanner.plan(
        nowUtc: now,
        tournaments: <TRemTournament>[
          t('a', 'registering'),
          t('b', 'live'),
          t('c', 'cancelled'),
          t('d', 'closed', inMin: 5),
          t('e', 'registering'),
          t('f', 'closed', checkin: true),
          t('g', 'closed'),
        ],
        myStatus: <String, String>{
          'a': 'approved',
          'b': 'approved',
          'c': 'approved',
          'd': 'approved',
          'e': 'withdrawn',
          'f': 'waitlist',
          'g': 'waitlist',
        },
        myMatches: const <TRemMatch>[],
      );
      expect(plan.map((TReminder r) => r.key).toSet(), <String>{'soon:a', 'soon:f'});
      expect(plan.firstWhere((TReminder r) => r.key == 'soon:a').at, now.add(const Duration(minutes: 50)));
      expect(plan.firstWhere((TReminder r) => r.key == 'soon:f').kind, 'checkin');
    });

    test('match reminders only for scheduled matches of running tournaments', () {
      final List<TReminder> plan = ReminderPlanner.plan(
        nowUtc: now,
        tournaments: <TRemTournament>[t('x', 'live'), t('y', 'cancelled')],
        myStatus: const <String, String>{},
        myMatches: <TRemMatch>[
          TRemMatch(id: 'm1', tournamentId: 'x', status: 'scheduled', scheduledAt: now.add(const Duration(minutes: 30))),
          TRemMatch(id: 'm2', tournamentId: 'x', status: 'ready_check', scheduledAt: now.add(const Duration(minutes: 30))),
          TRemMatch(id: 'm3', tournamentId: 'y', status: 'scheduled', scheduledAt: now.add(const Duration(minutes: 30))),
          TRemMatch(id: 'm4', tournamentId: 'x', status: 'scheduled', scheduledAt: now.add(const Duration(minutes: 5))),
        ],
      );
      expect(plan.map((TReminder r) => r.key).toList(), <String>['msoon:m1']);
    });

    test('stale reminders are cancelled, other apps\' notifications are left alone', () {
      final List<TReminder> plan = <TReminder>[
        TReminder(key: 'soon:a', at: now, tournamentId: 'a', kind: 'start'),
      ];
      final int keep = ReminderPlanner.idFor('soon:a');
      final int gone = ReminderPlanner.idFor('soon:old');
      final Set<int> stale = ReminderPlanner.stale(<int, String?>{
        keep: '/tournaments/a',
        gone: '/tournaments/old',
        42: '/chat/1',
        43: null,
      }, plan);
      expect(stale, <int>{gone});
    });

    test('notification ids are stable and in the Android range', () {
      expect(ReminderPlanner.idFor('msoon:abc'), ReminderPlanner.idFor('msoon:abc'));
      expect(ReminderPlanner.idFor('msoon:abc'), isNot(ReminderPlanner.idFor('msoon:abd')));
      for (final String k in <String>['a', 'soon:1', 'msoon:${'x' * 80}']) {
        final int id = ReminderPlanner.idFor(k);
        expect(id >= 0 && id <= 0x3fffffff, isTrue);
      }
    });
  });
}
