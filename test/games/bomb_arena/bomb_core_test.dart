import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/bomb_arena/core/bomb_core.dart';

/// Arena with every crate removed and the start countdown skipped.
BombArena openArena({int count = 2}) {
  final BombArena a = BombArena(seed: 1, count: count)..countdown = 0;
  for (int y = 0; y < BombArena.h; y++) {
    for (int x = 0; x < BombArena.w; x++) {
      if (!BombArena.isFixedWall(x, y)) a.grid[y][x] = '.';
    }
  }
  a.powerups.clear();
  return a;
}

void put(BPlayer p, int x, int y) {
  p
    ..x = x + 0.5
    ..y = y + 0.5;
}

Set<String> fire(BombArena a) => a.flames.map((Flame f) => '${f.tx},${f.ty}').toSet();

/// Steps until [done] or [seconds] of round time pass.
void runUntil(BombArena a, bool Function() done, {double seconds = 10}) {
  final int max = (seconds * 60).ceil();
  for (int i = 0; i < max && !done(); i++) {
    a.fixedStep();
  }
}

/// True when the player's box overlaps no wall, crate or bomb it may not stand on.
bool boxClear(BombArena a, BPlayer p) {
  for (int y = 0; y < BombArena.h; y++) {
    for (int x = 0; x < BombArena.w; x++) {
      if (BombArena.overlaps(p, x, y) && a.solid(x, y, forSeat: p.seat)) return false;
    }
  }
  return true;
}

void main() {
  group('blast', () {
    test('reaches exactly its range and stops at walls', () {
      final BombArena a = openArena();
      put(a.players[1], 11, 9);
      a.bombs.add(Bomb(0, 3, 1, 3));
      put(a.players[0], 7, 7);
      runUntil(a, () => a.bombs.isEmpty);
      // (3,0) is the border, (2,2)/(4,2) pillars do not block the column x = 3
      expect(fire(a), <String>{'3,1', '2,1', '1,1', '4,1', '5,1', '6,1', '3,2', '3,3', '3,4'});
    });

    test('a pillar blocks the ray behind it', () {
      final BombArena a = openArena();
      put(a.players[0], 7, 7);
      put(a.players[1], 11, 9);
      a.bombs.add(Bomb(0, 2, 1, 4));
      runUntil(a, () => a.bombs.isEmpty);
      expect(fire(a).where((String s) => s.startsWith('2,')).toSet(), <String>{'2,1'}, reason: '(2,2) is a pillar');
    });

    test('crates stop the ray, burn, and shield the crate behind them', () {
      final BombArena a = openArena();
      put(a.players[0], 7, 7);
      put(a.players[1], 11, 9);
      a.grid[1][3] = 'c';
      a.grid[1][4] = 'c';
      a.bombs.add(Bomb(0, 1, 1, 5));
      runUntil(a, () => a.bombs.isEmpty);
      expect(a.grid[1][3], '.');
      expect(a.grid[1][4], 'c');
      expect(fire(a).contains('3,1'), isTrue);
      expect(fire(a).contains('4,1'), isFalse);
    });

    test('a crate broken by two blasts in the same step still stops the second ray', () {
      final BombArena a = openArena();
      put(a.players[0], 9, 9);
      put(a.players[1], 11, 9);
      a.grid[3][3] = 'c';
      a.bombs
        ..add(Bomb(0, 3, 1, 2))
        ..add(Bomb(0, 1, 3, 4));
      runUntil(a, () => a.bombs.isEmpty);
      expect(a.grid[3][3], '.');
      expect(fire(a).contains('4,3'), isFalse);
      expect(fire(a).contains('5,3'), isFalse);
    });

    test('fire burns power-ups and traps on its path', () {
      final BombArena a = openArena();
      put(a.players[0], 9, 9);
      put(a.players[1], 11, 9);
      a.powerups[a.key(2, 1)] = Pu.speed;
      a.traps.add(Trap(1, 1, 2));
      a.bombs.add(Bomb(0, 1, 1, 2));
      runUntil(a, () => a.bombs.isEmpty);
      expect(a.powerups, isEmpty);
      expect(a.traps, isEmpty);
    });

    test('fire lasts flameLife and anyone walking into it is knocked out', () {
      final BombArena a = openArena();
      put(a.players[0], 9, 9);
      put(a.players[1], 5, 3);
      a.bombs.add(Bomb(0, 1, 3, 3));
      runUntil(a, () => a.bombs.isEmpty);
      expect(a.players[1].alive, isTrue);
      a.input(1, -1, 0); // walk left into the burning tile (4,3)
      runUntil(a, () => !a.players[1].alive, seconds: BombArena.flameLife);
      expect(a.players[1].alive, isFalse);
      expect(a.players[1].killedBy, 0);
      expect(a.players[0].kills, 1);
      runUntil(a, () => a.flames.isEmpty, seconds: 2);
      expect(a.flames, isEmpty);
    });
  });

  group('chain reactions', () {
    test('a bomb in the blast goes off in the same step and extends the fire', () {
      final BombArena a = openArena();
      put(a.players[0], 11, 9);
      put(a.players[1], 11, 7);
      a.bombs
        ..add(Bomb(0, 1, 1, 2))
        ..add(Bomb(1, 3, 1, 3, fuse: 30));
      int steps = 0;
      runUntil(a, () {
        steps++;
        return a.bombs.length < 2;
      });
      expect(a.bombs, isEmpty, reason: 'both bombs explode in the same step');
      expect(fire(a).containsAll(<String>['6,1', '3,4']), isTrue);
      expect(a.flames.firstWhere((Flame f) => f.tx == 6 && f.ty == 1).owner, 1);
      expect(steps, lessThanOrEqualTo((BombArena.fuseTime * 60).ceil() + 2));
    });

    test('a long chain resolves at once and the blast stops at the next bomb', () {
      final BombArena a = openArena();
      put(a.players[0], 11, 9);
      put(a.players[1], 11, 7);
      a.bombs
        ..add(Bomb(0, 1, 5, 2))
        ..add(Bomb(1, 3, 5, 2, fuse: 30))
        ..add(Bomb(1, 5, 5, 2, fuse: 30))
        ..add(Bomb(0, 7, 5, 2, fuse: 30));
      runUntil(a, () => a.bombs.length < 4);
      expect(a.bombs, isEmpty);
      expect(fire(a).contains('9,5'), isTrue);
      expect(fire(a).contains('10,5'), isFalse);
    });

    test('a bomb dropped into lingering fire goes off immediately', () {
      final BombArena a = openArena();
      put(a.players[0], 11, 9);
      put(a.players[1], 11, 7);
      a.bombs.add(Bomb(0, 1, 1, 3));
      runUntil(a, () => a.bombs.isEmpty);
      a.bombs.add(Bomb(1, 3, 1, 1, fuse: 30));
      a.fixedStep();
      expect(a.bombs, isEmpty);
    });

    test('the bot danger map shortens chained fuses', () {
      final BombArena a = openArena();
      a.bombs
        ..add(Bomb(0, 1, 1, 2, fuse: 0.5))
        ..add(Bomb(1, 3, 1, 3, fuse: 2.0));
      final BDanger d = a.dangerMap();
      expect(d.start[a.key(6, 1)], closeTo(0.5, 1e-9));
      expect(d.start[a.key(3, 4)], closeTo(0.5, 1e-9));
      expect(d.start[a.key(7, 7)], double.infinity);
    });
  });

  group('power-ups', () {
    void walkOnto(BombArena a, Pu pu) {
      put(a.players[0], 1, 1);
      put(a.players[1], 11, 9);
      a.powerups[a.key(2, 1)] = pu;
      a.input(0, 1, 0);
      runUntil(a, () => !a.powerups.containsKey(a.key(2, 1)), seconds: 2);
      a.input(0, 0, 0);
    }

    test('range adds one tile of fire', () {
      final BombArena a = openArena();
      walkOnto(a, Pu.range);
      expect(a.players[0].range, BombArena.startRange + 1);
      put(a.players[0], 5, 5);
      expect(a.placeBomb(0), isTrue);
      put(a.players[0], 9, 9);
      runUntil(a, () => a.bombs.isEmpty);
      expect(fire(a).contains('8,5'), isTrue);
      expect(fire(a).contains('9,5'), isFalse);
    });

    test('extra bomb allows one more bomb at a time', () {
      final BombArena a = openArena();
      walkOnto(a, Pu.bomb);
      expect(a.players[0].maxBombs, 2);
      put(a.players[0], 5, 5);
      expect(a.placeBomb(0), isTrue);
      expect(a.placeBomb(0), isFalse, reason: 'one bomb per tile');
      put(a.players[0], 7, 7);
      expect(a.placeBomb(0), isTrue);
      put(a.players[0], 9, 9);
      expect(a.placeBomb(0), isFalse, reason: 'cap reached');
    });

    test('speed makes the player cover more ground per second, capped', () {
      double distanceIn(BombArena a, double secs) {
        put(a.players[0], 1, 3);
        a.input(0, 1, 0);
        final double x0 = a.players[0].x;
        runUntil(a, () => false, seconds: secs);
        a.input(0, 0, 0);
        return a.players[0].x - x0;
      }

      final BombArena a = openArena();
      put(a.players[1], 11, 9);
      final double before = distanceIn(a, 0.5);
      expect(before, closeTo(BombArena.baseSpeed * 0.5, 0.02));
      walkOnto(a, Pu.speed);
      final double after = distanceIn(a, 0.5);
      expect(after, closeTo((BombArena.baseSpeed + BombArena.speedStep) * 0.5, 0.02));
      for (int i = 0; i < 12; i++) {
        walkOnto(a, Pu.speed);
      }
      expect(a.players[0].speed, BombArena.maxSpeed);
    });

    test('a trap stuns opponents (not its owner) and stops them moving and bombing', () {
      final BombArena a = openArena();
      walkOnto(a, Pu.trap);
      expect(a.players[0].traps, 1);
      put(a.players[0], 3, 3);
      expect(a.placeTrap(0), isTrue);
      expect(a.players[0].traps, 0);
      a.fixedStep();
      expect(a.players[0].stun, 0, reason: 'own trap is harmless');
      put(a.players[0], 9, 9);
      put(a.players[1], 5, 3);
      a.input(1, -1, 0);
      runUntil(a, () => a.players[1].stun > 0, seconds: 2);
      expect(a.players[1].stun, greaterThan(BombArena.stunTime - 0.05));
      expect(a.traps, isEmpty);
      final double x = a.players[1].x;
      expect(a.placeBomb(1), isFalse);
      runUntil(a, () => false, seconds: 1);
      expect(a.players[1].x, x);
      runUntil(a, () => a.players[1].stun <= 0, seconds: 1);
      runUntil(a, () => false, seconds: 0.3);
      expect(a.players[1].x, lessThan(x));
    });
  });

  group('round end', () {
    test('a simultaneous knock-out is a draw', () {
      final BombArena a = openArena();
      put(a.players[0], 1, 1);
      put(a.players[1], 2, 1);
      a.bombs.add(Bomb(0, 1, 1, 2));
      runUntil(a, () => a.over);
      expect(a.over, isTrue);
      expect(a.draw, isTrue);
      expect(a.winner, -1);
      expect(a.players[0].outStep, a.players[1].outStep);
    });

    test('last player standing wins; suicides are not kills', () {
      final BombArena a = openArena(count: 3);
      put(a.players[0], 1, 1);
      put(a.players[1], 11, 9);
      put(a.players[2], 11, 1);
      a.bombs.add(Bomb(0, 1, 1, 2));
      runUntil(a, () => !a.players[0].alive);
      expect(a.over, isFalse);
      expect(a.players[0].kills, 0);
      expect(a.selfKnockouts, 1);
      a.bombs.add(Bomb(1, 11, 2, 2));
      runUntil(a, () => a.over);
      expect(a.winner, 1);
      expect(a.players[1].kills, 1);
      expect(a.ranking(), <int>[1, 2, 0]);
    });

    test('sudden death fills the arena in a spiral and always ends the round before the timer', () {
      final BombArena a = openArena();
      put(a.players[0], 1, 1);
      put(a.players[1], 6, 5);
      final List<String> kinds = <String>[];
      runUntil(a, () {
        kinds.addAll(a.events.map((BEvent e) => e.kind));
        a.events.clear();
        return a.over;
      }, seconds: BombArena.timeLimit + 1);
      expect(kinds, contains('hurry'));
      expect(a.players[0].killedBy, BombArena.crushed);
      expect(a.players[0].outAt, closeTo(BombArena.suddenDeathAt, 0.02));
      expect(a.winner, 1);
      expect(a.time, lessThan(BombArena.timeLimit));
      expect(BombArena.dropTime(BombArena.dropOrder.length - 1), lessThan(BombArena.timeLimit));
      expect(BombArena.dropOrder.toSet().length, 79);
    });

    test('a block landing beside a player pushes it back into its own tile', () {
      final BombArena a = openArena();
      put(a.players[1], 11, 9);
      final BPlayer p = a.players[0];
      p
        ..x = 4.2
        ..y = 1.5; // centre in (4,1), box over (3,1)
      a.time = BombArena.dropTime(2) - 0.001; // (1,1), (2,1), (3,1) are the first blocks of the spiral
      a.fixedStep();
      expect(a.grid[1][3], '#');
      expect(p.alive, isTrue);
      expect(boxClear(a, p), isTrue);
    });
  });

  group('movement', () {
    test('corner sliding: off-lane input slides onto the open lane, never into walls', () {
      final BombArena a = openArena();
      put(a.players[1], 11, 9);
      final BPlayer p = a.players[0];
      // between rows 2 and 1 in column 1; (2,2) is a pillar, (2,1) is open → slide up and continue right
      p
        ..x = 1.5
        ..y = 2.2;
      a.input(0, 1, 0);
      for (int i = 0; i < 40; i++) {
        a.fixedStep();
        expect(boxClear(a, p), isTrue);
      }
      expect(p.y, 1.5);
      expect(p.x, greaterThan(2.5));
    });

    test('corner sliding snaps to the nearer lane when both are open', () {
      final BombArena a = openArena();
      put(a.players[1], 11, 9);
      final BPlayer p = a.players[0];
      p
        ..x = 3.5
        ..y = 3.3; // rows 3 and 2 overlap; (4,3) open, (4,2) pillar
      a.input(0, 1, 0);
      for (int i = 0; i < 20; i++) {
        a.fixedStep();
        expect(boxClear(a, p), isTrue);
      }
      expect(p.y, 3.5);
      expect(p.x, greaterThan(4.0));
    });

    test('a perpendicular nudge turns into the side corridor when straight ahead is blocked', () {
      final BombArena a = openArena();
      put(a.players[1], 11, 9);
      final BPlayer p = a.players[0];
      put(p, 1, 3);
      a.input(0, -1, 0.6); // pushing into the border wall, a little down
      for (int i = 0; i < 15; i++) {
        a.fixedStep();
        expect(boxClear(a, p), isTrue);
      }
      expect(p.x, 1.5);
      expect(p.y, greaterThan(3.6));
    });

    test('pushing straight into a wall does not move or jitter', () {
      final BombArena a = openArena();
      put(a.players[1], 11, 9);
      final BPlayer p = a.players[0];
      put(p, 1, 1);
      a.input(0, 0, -1);
      runUntil(a, () => false, seconds: 0.5);
      expect(p.x, 1.5);
      expect(p.y, 1.5);
    });

    test('long walks stay inside corridors at every speed', () {
      for (final double sp in <double>[BombArena.baseSpeed, BombArena.maxSpeed]) {
        final BombArena a = openArena();
        put(a.players[1], 11, 9);
        final BPlayer p = a.players[0]..speed = sp;
        final math.Random r = math.Random(7);
        for (int i = 0; i < 60 * 20; i++) {
          if (i % 23 == 0) a.input(0, r.nextDouble() * 2 - 1, r.nextDouble() * 2 - 1);
          a.fixedStep();
          expect(boxClear(a, p), isTrue, reason: 'at ${p.x},${p.y}');
          final bool alignedX = (p.x - p.tx - 0.5).abs() < 1e-6, alignedY = (p.y - p.ty - 0.5).abs() < 1e-6;
          expect(alignedX || alignedY, isTrue, reason: 'always on a lane');
        }
      }
    });

    test('own fresh bomb can be walked off but never back onto; others cannot enter it', () {
      final BombArena a = openArena();
      final BPlayer p = a.players[0], q = a.players[1];
      put(p, 3, 3);
      put(q, 5, 3);
      expect(a.placeBomb(0), isTrue);
      a.input(0, -1, 0);
      runUntil(a, () => p.x <= 2.5, seconds: 1);
      expect(a.bombs.single.passable, isEmpty);
      a.input(0, 1, 0);
      runUntil(a, () => false, seconds: 0.4);
      expect(p.x, closeTo(2.5, 1e-6), reason: 'bomb is solid once left');
      a.input(1, -1, 0);
      runUntil(a, () => false, seconds: 0.4);
      expect(q.x, closeTo(4.5, 1e-6), reason: 'an opponent stops in front of it');
    });

    test('a player overlapping the tile when a bomb is placed may also walk off it', () {
      final BombArena a = openArena();
      final BPlayer p = a.players[0], q = a.players[1];
      put(p, 3, 3);
      q
        ..x = 3.9
        ..y = 3.5; // centre in (3,3) too
      expect(a.placeBomb(0), isTrue);
      expect(a.bombs.single.passable, <int>{0, 1});
      a.input(1, 1, 0);
      runUntil(a, () => q.x >= 4.5, seconds: 1);
      expect(q.x, greaterThanOrEqualTo(4.5));
    });
  });

  group('timing', () {
    test('fixed timestep: frame pacing does not change the simulation', () {
      final BombMatch m1 = BombMatch(seed: 11, count: 4, botSkill: const <double>[0.9, 0.6, 0.6, 0.3]);
      final BombMatch m2 = BombMatch(seed: 11, count: 4, botSkill: const <double>[0.9, 0.6, 0.6, 0.3]);
      int s1 = 0, s2 = 0;
      const int target = 60 * 40;
      while (s1 < target) {
        s1 += m1.step(1 / 30);
      }
      final math.Random r = math.Random(3);
      while (s2 < s1) {
        if (s1 - s2 < 4) {
          m2.fixedStep();
          s2++;
        } else {
          s2 += m2.step(0.004 + r.nextDouble() * 0.04);
        }
      }
      expect(m2.arena.time, m1.arena.time);
      expect(m2.snapshot().toString(), m1.snapshot().toString());
    });

    test('a long hitch is clamped instead of simulated in one go', () {
      final BombArena a = openArena();
      expect(a.step(5), BombArena.maxStepsPerCall);
      expect(a.step(double.nan), 0);
      expect(a.step(-1), 0);
    });
  });

  group('match', () {
    test('first to two round wins takes the match; rounds reset the arena', () {
      final BombMatch m = BombMatch(seed: 3, count: 2);
      final List<String> kinds = <String>[];
      void play() {
        m.arena.countdown = 0;
        m.arena.eliminate(1);
        for (int i = 0; i < 60 * 4 && !m.over && m.intermission <= 0; i++) {
          m.fixedStep();
        }
        while (m.intermission > 0) {
          m.fixedStep();
        }
        kinds.addAll(m.events.map((BEvent e) => e.kind));
        m.events.clear();
      }

      play();
      expect(m.wins, <int>[1, 0]);
      expect(m.round, 2);
      expect(m.over, isFalse);
      expect(m.arena.players.every((BPlayer p) => p.alive), isTrue);
      play();
      expect(m.over, isTrue);
      expect(m.winner, 0);
      expect(m.isDraw, isFalse);
      expect(m.ranking().first, 0);
      expect(kinds, containsAll(<String>['roundEnd', 'round', 'match']));
    });

    test('a drawn round awards nobody; leaders tied at the last round draw the match', () {
      final BombMatch m = BombMatch(seed: 3, count: 2, maxRounds: 1);
      final BombArena a = m.arena..countdown = 0;
      for (int y = 0; y < BombArena.h; y++) {
        for (int x = 0; x < BombArena.w; x++) {
          if (!BombArena.isFixedWall(x, y)) a.grid[y][x] = '.';
        }
      }
      put(a.players[0], 1, 1);
      put(a.players[1], 2, 1);
      a.bombs.add(Bomb(0, 1, 1, 2));
      for (int i = 0; i < 60 * 4 && !m.over; i++) {
        m.fixedStep();
      }
      expect(m.roundWinners, <int>[-1]);
      expect(m.wins, <int>[0, 0]);
      expect(m.over, isTrue);
      expect(m.isDraw, isTrue);
      expect(m.leaders, <int>[0, 1]);
    });

    test('snapshot round-trip keeps round, wins and arena', () {
      final BombMatch host = BombMatch(seed: 9, count: 3, botSkill: const <double>[0.6, 0.6, 0.6]);
      for (int i = 0; i < 60 * 30; i++) {
        host.fixedStep();
      }
      host.wins[2] = 1;
      final BombMatch client = BombMatch(seed: 9, count: 3);
      client.applySnapshot(host.snapshot());
      expect(client.round, host.round);
      expect(client.wins, host.wins);
      expect(client.arena.grid.map((List<String> r) => r.join()).join(), host.arena.grid.map((List<String> r) => r.join()).join());
      for (int i = 0; i < 3; i++) {
        expect(client.arena.players[i].x, closeTo(host.arena.players[i].x, 1e-3));
        expect(client.arena.players[i].speed, closeTo(host.arena.players[i].speed, 1e-2));
      }
      expect(client.arena.bombs.length, host.arena.bombs.length);
    });
  });

  group('bots', () {
    test('bot matches finish with a result and bots never blow themselves up on their own', () {
      int deaths = 0, own = 0, pure = 0, matches = 0;
      for (int seed = 1; seed <= 8; seed++) {
        for (final int n in <int>[2, 3, 4]) {
          final List<double> sk = <double>[for (int i = 0; i < n; i++) <double>[0.3, 0.62, 0.92][(seed + i) % 3]];
          final BombMatch m = BombMatch(seed: seed * 31, count: n, botSkill: sk);
          final Map<int, double> enemyBombAt = <int, double>{}, stunAt = <int, double>{};
          int guard = 0;
          while (!m.over && guard++ < 60 * 130 * m.maxRounds + 60 * 30) {
            m.fixedStep();
            final double t = m.arena.time;
            for (final BEvent e in m.events) {
              if (e.kind == 'round') {
                enemyBombAt.clear();
                stunAt.clear();
              }
              if (e.kind == 'place') {
                for (int s = 0; s < n; s++) {
                  if (s != e.seat) enemyBombAt[s] = t;
                }
              }
              if (e.kind == 'stun') stunAt[e.seat] = t;
              if (e.kind == 'out') {
                final BPlayer p = m.arena.players[e.seat];
                deaths++;
                if (p.killedBy == p.seat) {
                  own++;
                  // own fire with no opponent bomb around and no stun: a real suicide
                  if (t - (enemyBombAt[p.seat] ?? -99) > 3 && t - (stunAt[p.seat] ?? -99) > 3) pure++;
                }
              }
            }
            m.events.clear();
          }
          matches++;
          expect(m.over, isTrue, reason: 'seed $seed n $n');
          expect(m.roundWinners.length, inInclusiveRange(1, m.maxRounds));
          expect(m.isDraw || m.wins[m.winner] >= m.winsNeeded || m.roundWinners.length == m.maxRounds, isTrue);
        }
      }
      expect(matches, 24);
      expect(pure, 0, reason: 'no bot dies to its own bomb unless an opponent cornered it');
      expect(own, lessThan(deaths * 0.25));
    });

    test('bots hunt an idle human down (or it gets crushed) — every round ends', () {
      final BombMatch m = BombMatch(seed: 77, count: 4, botSkill: const <double>[0, 0.62, 0.62, 0.92]);
      int guard = 0, humanOut = 0;
      while (!m.over && guard++ < 60 * 130 * m.maxRounds) {
        m.fixedStep();
        humanOut += m.events.where((BEvent e) => e.kind == 'out' && e.seat == 0).length;
        m.events.clear();
      }
      expect(m.over, isTrue);
      expect(humanOut, greaterThanOrEqualTo(m.roundWinners.where((int w) => w != 0).length));
    });

    test('bots blast crates and collect power-ups', () {
      final BombArena a = BombArena(seed: 5, count: 4, botSkill: const <double>[0.9, 0.9, 0.9, 0.9]);
      final int crates0 = a.grid.expand((List<String> r) => r).where((String c) => c == 'c').length;
      int pickups = 0, places = 0;
      for (int i = 0; i < 60 * 45 && !a.over; i++) {
        a.fixedStep();
        pickups += a.events.where((BEvent e) => e.kind == 'pickup').length;
        places += a.events.where((BEvent e) => e.kind == 'place').length;
        a.events.clear();
      }
      final int crates1 = a.grid.expand((List<String> r) => r).where((String c) => c == 'c').length;
      expect(places, greaterThan(10));
      expect(crates1, lessThan(crates0 ~/ 2));
      expect(pickups, greaterThan(0));
    });
  });
}
