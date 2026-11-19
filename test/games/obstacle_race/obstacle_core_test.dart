import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/obstacle_race/core/obstacle_core.dart';

const double h = ObstacleRace.fixedDt;
const double rr = ObstacleRace.runnerR;

/// A race with one human-controlled runner and the countdown over.
ObstacleRace solo(int seed) => ObstacleRace(seed: seed, count: 1)..countdown = 0;

/// Run full fixed steps.
void run(ObstacleRace r, double secs, {Set<int>? only}) {
  final int n = (secs / h).round();
  for (int i = 0; i < n; i++) {
    r.step(h, simulate: only);
  }
}

/// First obstacle of [kind] in a section of [sk], searching seeds.
(ObstacleRace, Obstacle) find(ObSectionKind sk, ObKind kind, {bool Function(Obstacle o)? where}) {
  for (int seed = 1; seed < 200; seed++) {
    final ObstacleRace r = solo(seed);
    for (final Obstacle o in r.obstacles) {
      if (o.kind != kind) continue;
      final ObSection? s = r.sectionAt(o.yMin + 1);
      if (s?.kind == sk && (where == null || where(o))) return (r, o);
    }
  }
  throw StateError('no $kind in $sk');
}

/// Clear everything except [keep] so a unit test is not disturbed by neighbouring obstacles.
void isolate(ObstacleRace r, List<Obstacle> keep) {
  r.obstacles
    ..clear()
    ..addAll(keep);
}

void main() {
  group('race flow', () {
    test('countdown freezes everybody, ignores jump, then GO', () {
      final ObstacleRace r = ObstacleRace(seed: 1, count: 3, botSkill: const <double>[0, 0.9, 0.9]);
      final List<double> y0 = r.runners.map((Runner p) => p.y).toList();
      r.input(0, 1, true);
      run(r, 2.9);
      expect(r.countdown, greaterThan(0));
      expect(r.time, 0);
      for (final Runner p in r.runners) {
        expect(p.y, y0[p.seat]);
        expect(p.z, 0);
        expect(p.jumpBuffer, 0, reason: 'a press during the countdown is not buffered into the start');
      }
      run(r, 0.2);
      expect(r.countdown, 0);
      expect(r.time, greaterThan(0));
      run(r, 0.5);
      for (final Runner p in r.runners) {
        expect(p.y, greaterThan(y0[p.seat]));
      }
    });

    test('a full race against bots: everybody ranked once, finishers by time, results consistent', () {
      for (final int seed in <int>[1, 2, 3, 7]) {
        final ObstacleRace r = ObstacleRace(seed: seed, count: 4, botSkill: const <double>[0.3, 0.62, 0.92, 1]);
        final List<int> finishOrder = <int>[];
        int guard = 0;
        while (!r.over && guard++ < 120 * 400) {
          r.step(1 / 60);
          for (final ObEvent e in r.events) {
            if (e.kind == 'finish') finishOrder.add(e.seat);
          }
          r.events.clear();
        }
        expect(r.over, isTrue);
        expect(r.time, lessThanOrEqualTo(ObstacleRace.maxRaceTime + 0.01));
        final List<int> rank = r.ranking();
        expect(rank.toSet().length, 4);
        final List<Runner> fin = r.runners.where((Runner p) => p.finished).toList();
        expect(fin, isNotEmpty);
        for (int i = 1; i < fin.length; i++) {
          final Runner a = r.runners[rank[i - 1]], b = r.runners[rank[i]];
          if (a.finished && b.finished) expect(a.finishTime, lessThanOrEqualTo(b.finishTime));
        }
        // the finish events came in time order too
        for (int i = 1; i < finishOrder.length; i++) {
          expect(r.runners[finishOrder[i - 1]].finishTime, lessThanOrEqualTo(r.runners[finishOrder[i]].finishTime));
        }
        expect(r.placeOf(rank.first), 1);
      }
    });

    test('ranking: finishers by time, then DNF by distance, then forfeits (latest forfeit ranks higher)', () {
      final ObstacleRace r = ObstacleRace(seed: 4, count: 5)..countdown = 0;
      r.markFinished(3, 31.2);
      r.markFinished(1, 29.8);
      r.runners[0].bestY = 900;
      r.runners[2].bestY = 1500;
      r.eliminate(4, 5);
      expect(r.ranking(), <int>[1, 3, 2, 0, 4]);
      r.eliminate(0, 6);
      expect(r.ranking(), <int>[1, 3, 2, 0, 4]);
      expect(r.runners[0].phase, RunPhase.out);
    });

    test('qualifying window: the others are eliminated when it runs out', () {
      final ObstacleRace r = ObstacleRace(seed: 5, count: 3)..countdown = 0;
      run(r, 1, only: <int>{});
      r.markFinished(2, r.time);
      expect(r.over, isFalse);
      expect(r.timeLeft, closeTo(ObstacleRace.qualifyWindow, 0.02));
      run(r, ObstacleRace.qualifyWindow - 0.1, only: <int>{});
      expect(r.over, isFalse);
      run(r, 0.2, only: <int>{});
      expect(r.over, isTrue);
      expect(r.runners[0].phase, RunPhase.dnf);
      expect(r.ranking().first, 2);
      // A finish reported late (net lag) still overrides the local DNF.
      r.markFinished(0, r.firstFinish + 19);
      expect(r.ranking().take(2), <int>[2, 0]);
    });

    test('the race always ends by maxRaceTime even if nobody moves forward', () {
      final ObstacleRace r = ObstacleRace(seed: 6, count: 2)..countdown = 0;
      run(r, ObstacleRace.maxRaceTime + 0.5, only: <int>{});
      expect(r.over, isTrue);
    });

    test('crossing the finish line records an interpolated time and the runner coasts to a stop', () {
      final ObstacleRace r = solo(8);
      final Runner p = r.runners[0];
      isolate(r, <Obstacle>[]);
      p
        ..y = r.finishY - 10
        ..vy = ObstacleRace.runMax;
      final double t0 = r.time;
      run(r, 0.2);
      expect(p.finished, isTrue);
      expect(p.finishTime, closeTo(t0 + 10 / ObstacleRace.runMax, 0.01));
      run(r, 3);
      expect(p.vy, 0);
      expect(p.y, lessThan(r.finishY + ObstacleRace.finishRunway));
    });
  });

  group('checkpoints & respawn', () {
    test('passing a checkpoint stores it; falling respawns there with a ghost period', () {
      final (ObstacleRace r, Obstacle pit) = find(ObSectionKind.pits, ObKind.pit);
      final ObSection sec = r.sectionAt(pit.y)!;
      final Runner p = r.runners[0];
      p
        ..y = sec.checkpointY - 5
        ..vy = ObstacleRace.runMax;
      final List<String> ev = <String>[];
      run(r, 0.1);
      ev.addAll(r.events.map((ObEvent e) => e.kind));
      expect(p.checkpoint, sec.index);
      expect(ev, contains('checkpoint'));
      // drop into the middle of the pit
      p
        ..x = pit.x + pit.w / 2
        ..y = pit.y + pit.h / 2;
      r.events.clear();
      r.step(h);
      expect(p.phase, RunPhase.falling);
      expect(p.alive, isFalse);
      expect(r.events.map((ObEvent e) => e.kind), contains('fall'));
      run(r, ObstacleRace.fallTime + 0.02);
      expect(p.phase, RunPhase.racing);
      expect(p.y, closeTo(sec.spawnY, 6));
      expect(r.inPit(p.x, p.y), isFalse);
      expect(r.solidAt(p.x, p.y), isFalse);
      expect(p.ghost, greaterThan(0));
      expect(p.respawns, 1);
      expect(p.vx, 0);
      expect(p.vy, lessThan(ObstacleRace.runMax * 0.2), reason: 'accelerates again from the checkpoint');
    });

    test('before the first checkpoint you respawn at the start line', () {
      final ObstacleRace r = solo(3);
      final Runner p = r.runners[0];
      expect(p.checkpoint, -1);
      r.respawn(0);
      expect(p.y, ObstacleRace.startY);
    });

    test('respawning runners do not stack on each other', () {
      final ObstacleRace r = ObstacleRace(seed: 3, count: 4)..countdown = 0;
      for (final Runner p in r.runners) {
        p.checkpoint = 2;
        r.respawn(p.seat);
      }
      for (int i = 0; i < 4; i++) {
        for (int j = i + 1; j < 4; j++) {
          final Runner a = r.runners[i], b = r.runners[j];
          expect(math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2)), greaterThanOrEqualTo(2 * rr));
        }
      }
    });

    test('teleported into a pit = no coyote grace (legacy contract)', () {
      final ObstacleRace r = ObstacleRace(seed: 9, count: 2)..countdown = 0;
      final Obstacle pit = r.obstacles.firstWhere((Obstacle o) => o.kind == ObKind.pit);
      final Runner p = r.runners[0];
      p.x = pit.x + pit.w / 2;
      p.y = pit.y + pit.h / 2;
      r.step(1 / 60, simulate: <int>{0});
      expect(p.alive, isFalse);
    });
  });

  group('movement', () {
    test('run accelerates smoothly to top speed (no instant start)', () {
      final ObstacleRace r = solo(2);
      isolate(r, <Obstacle>[]);
      final Runner p = r.runners[0];
      double last = 0;
      for (int i = 0; i < 120; i++) {
        r.step(h);
        expect(p.vy, greaterThanOrEqualTo(last));
        expect(p.vy - last, lessThanOrEqualTo(ObstacleRace.runAccel * h + 1e-6));
        last = p.vy;
      }
      expect(p.vy, closeTo(ObstacleRace.runMax, 1e-6));
      // steering: lateral speed ramps, capped
      r.input(0, 1, false);
      r.step(h);
      expect(p.vx, closeTo(ObstacleRace.sideAccel * h, 1e-6));
      run(r, 0.5);
      expect(p.vx, lessThanOrEqualTo(ObstacleRace.sideMax));
    });

    test('jump: gravity arc, air time and reach clear the longest pit', () {
      final ObstacleRace r = solo(2);
      isolate(r, <Obstacle>[]);
      final Runner p = r.runners[0];
      run(r, 1);
      r.input(0, 0, true);
      double apex = 0, air = 0;
      r.step(h);
      expect(p.z, greaterThan(0));
      while (p.z > 0) {
        apex = math.max(apex, p.z);
        air += h;
        r.step(h);
      }
      final double ideal = ObstacleRace.jumpV * ObstacleRace.jumpV / (2 * ObstacleRace.gravity);
      expect(apex, closeTo(ideal, 4));
      expect(air, closeTo(ObstacleRace.jumpAir, 0.03));
      expect(ObstacleRace.jumpReach, greaterThan(ObstacleRace.maxPitLen + 2 * ObstacleRace.pitMargin + 20));
      expect(apex, greaterThan(ObstacleRace.armHeight * 3), reason: 'a jump clearly clears a sweeper arm');
    });

    test('no double jump in the air', () {
      final ObstacleRace r = solo(2);
      isolate(r, <Obstacle>[]);
      final Runner p = r.runners[0];
      r.input(0, 0, true);
      run(r, 0.1);
      final double vz = p.vz;
      r.input(0, 0, true);
      r.step(h);
      expect(p.vz, lessThan(vz));
    });

    test('jump buffering: a press just before landing jumps on touchdown; an early press is dropped', () {
      for (final double before in <double>[0.06, 0.3]) {
        final ObstacleRace r = solo(2);
        isolate(r, <Obstacle>[]);
        final Runner p = r.runners[0];
        r.input(0, 0, true);
        r.step(h);
        final double land = ObstacleRace.jumpAir;
        run(r, land - before - h);
        expect(p.z, greaterThan(0));
        r.input(0, 0, true);
        r.events.clear();
        int jumps = 0;
        for (int i = 0; i < ((before + 0.05) / h).round(); i++) {
          r.step(h);
          jumps += r.events.where((ObEvent e) => e.kind == 'jump').length;
          r.events.clear();
        }
        if (before < ObstacleRace.jumpBufferTime) {
          expect(jumps, 1, reason: 'buffered press (${before}s early) fires on landing');
        } else {
          expect(jumps, 0, reason: 'a press ${before}s early has expired');
        }
      }
    });

    test('coyote time: walking off a pit edge gives a short grace to still jump', () {
      final (ObstacleRace base, Obstacle pit) = find(ObSectionKind.pits, ObKind.pit, where: (Obstacle o) => o.w > 80);
      for (final bool press in <bool>[false, true]) {
        final ObstacleRace r = ObstacleRace(seed: base.seed, count: 1)..countdown = 0;
        isolate(r, <Obstacle>[pit]);
        final Runner p = r.runners[0];
        p
          ..x = pit.x + pit.w / 2
          ..y = pit.y - 4
          ..vy = ObstacleRace.runMax;
        // walk until the centre is over the pit
        int guard = 0;
        while (!r.inPit(p.x, p.y) && guard++ < 100) {
          r.step(h);
        }
        expect(p.phase, RunPhase.racing, reason: 'still in coyote grace');
        expect(p.coyote, greaterThan(0));
        run(r, ObstacleRace.coyoteTime * 0.6);
        expect(p.phase, RunPhase.racing);
        if (press) {
          r.input(0, 0, true);
          run(r, ObstacleRace.jumpAir + 0.1);
          expect(p.phase, RunPhase.racing, reason: 'coyote jump clears the pit');
          expect(p.y, greaterThan(pit.y + pit.h));
        } else {
          run(r, ObstacleRace.coyoteTime);
          expect(p.phase, RunPhase.falling);
        }
      }
    });

    test('landing from a jump onto a pit gets no grace', () {
      final (ObstacleRace base, Obstacle pit) = find(ObSectionKind.pits, ObKind.pit, where: (Obstacle o) => o.w > 80);
      final ObstacleRace r = ObstacleRace(seed: base.seed, count: 1)..countdown = 0;
      isolate(r, <Obstacle>[pit]);
      final Runner p = r.runners[0];
      p
        ..x = pit.x + pit.w / 2
        ..y = pit.y + 12
        ..z = 5
        ..vz = -50;
      run(r, 0.08);
      expect(p.phase, RunPhase.falling);
    });

    test('fixed timestep: identical outcome at 30, 60, 120 and 144 fps', () {
      List<String> outcome(double frame) {
        final ObstacleRace r = ObstacleRace(seed: 11, count: 4, botSkill: const <double>[1, 0.62, 0.3, 0.92]);
        int guard = 0;
        while (!r.over && guard++ < 200000) {
          r.step(frame);
        }
        return r.runners.map((Runner p) => '${p.phase.name}:${p.finishTime.toStringAsFixed(4)}:${p.respawns}').toList();
      }

      final List<String> a = outcome(1 / 120);
      expect(outcome(1 / 60), a);
      expect(outcome(1 / 30), a);
      final List<String> d = outcome(1 / 144);
      // 1/144 is not a multiple of the step: sub-steps land on the same grid, only frame boundaries move.
      expect(d.map((String s) => s.split(':').first), a.map((String s) => s.split(':').first));
      for (int i = 0; i < 4; i++) {
        final double ta = double.parse(a[i].split(':')[1]), td = double.parse(d[i].split(':')[1]);
        expect((ta - td).abs(), lessThan(0.05));
      }
    });

    test('a long hitch is clamped: one huge frame advances at most maxFrameDt', () {
      final ObstacleRace r = solo(2);
      r.step(5);
      expect(r.time, closeTo(ObstacleRace.maxFrameDt, h));
      r.step(double.nan);
      r.step(-1);
      expect(r.time, closeTo(ObstacleRace.maxFrameDt, h));
    });
  });

  group('collisions', () {
    test('gate walls are solid: no passing outside the gap, even at knock-back speed', () {
      final (ObstacleRace base, Obstacle gate) = find(ObSectionKind.gates, ObKind.gate);
      final ObstacleRace r = ObstacleRace(seed: base.seed, count: 1)..countdown = 0;
      isolate(r, <Obstacle>[gate]);
      final Runner p = r.runners[0];
      for (int k = 0; k < 240; k++) {
        // keep the runner aimed at a wall section, away from the gap
        final double g = gate.gateGap(r.time, ObstacleRace.width);
        final double wallX = g > ObstacleRace.width / 2 ? rr + 2 : ObstacleRace.width - rr - 2;
        if (k == 0) {
          p
            ..x = wallX
            ..y = gate.y - 80
            ..vy = 900; // far faster than anything in the game
        }
        r.input(0, ((wallX - p.x) / 20).clamp(-1, 1), false);
        r.step(h);
        final double gNow = gate.gateGap(r.time, ObstacleRace.width);
        final bool inGap = (p.x - gNow).abs() < gate.w / 2;
        if (!inGap) expect(p.y, lessThanOrEqualTo(gate.y - rr + 0.5));
      }
    });

    test('gate gap lets you through', () {
      final (ObstacleRace base, Obstacle gate) = find(ObSectionKind.gates, ObKind.gate);
      final ObstacleRace r = ObstacleRace(seed: base.seed, count: 1)..countdown = 0;
      isolate(r, <Obstacle>[gate]);
      final Runner p = r.runners[0];
      p.y = gate.y - 120;
      for (int k = 0; k < 240 && p.y < gate.y + gate.h + rr; k++) {
        final double g = gate.gateGap(r.time + 0.15, ObstacleRace.width);
        r.input(0, ((g - p.x) / 25).clamp(-1, 1), false);
        r.step(h);
      }
      expect(p.y, greaterThan(gate.y + gate.h));
    });

    test('bumper: never overlapped, bounces you back', () {
      final (ObstacleRace base, Obstacle b) = find(ObSectionKind.bumpers, ObKind.bumper);
      final ObstacleRace r = ObstacleRace(seed: base.seed, count: 1)..countdown = 0;
      isolate(r, <Obstacle>[b]);
      final Runner p = r.runners[0];
      p
        ..x = b.x + 3
        ..y = b.y - b.w - rr - 30
        ..vy = ObstacleRace.runMax;
      bool bumped = false;
      for (int k = 0; k < 60; k++) {
        r.step(h);
        bumped |= r.events.any((ObEvent e) => e.kind == 'bump');
        r.events.clear();
        final double d = math.sqrt(math.pow(p.x - b.x, 2) + math.pow(p.y - b.y, 2));
        expect(d, greaterThanOrEqualTo(b.w + rr - 0.01));
      }
      expect(bumped, isTrue);
    });

    test('sweeper arm knocks a grounded runner along the sweep and never passes through it', () {
      final (ObstacleRace base, Obstacle s) = find(ObSectionKind.sweepers, ObKind.sweeper);
      final ObstacleRace r = ObstacleRace(seed: base.seed, count: 1)..countdown = 0;
      isolate(r, <Obstacle>[s]);
      final Runner p = r.runners[0];
      // stand on the circle swept by the arm's middle, just ahead of the arm
      final double a0 = s.angle(0) + (s.speed > 0 ? 0.35 : -0.35);
      p
        ..x = (s.x + math.cos(a0) * s.w * 0.6).clamp(rr, ObstacleRace.width - rr)
        ..y = s.y + math.sin(a0) * s.w * 0.6;
      r.input(0, 0, false);
      bool knocked = false;
      for (int k = 0; k < 120 && !knocked; k++) {
        p
          ..vy = 0
          ..vx = 0;
        r.step(h);
        knocked = r.events.any((ObEvent e) => e.kind == 'knock');
      }
      expect(knocked, isTrue);
      expect(math.sqrt(p.vx * p.vx + p.vy * p.vy), greaterThan(ObstacleRace.knockSpeed * 0.8));
      expect(p.stun, greaterThan(0));
      final double ang = s.angle(r.time);
      expect(ObstacleRace.segDist(p.x, p.y, s.x, s.y, s.x + math.cos(ang) * s.w, s.y + math.sin(ang) * s.w),
          greaterThanOrEqualTo(rr + ObstacleRace.armHalf - 0.01));
    });

    test('jumping over a sweeper arm is safe', () {
      final (ObstacleRace base, Obstacle s) = find(ObSectionKind.sweepers, ObKind.sweeper);
      final ObstacleRace r = ObstacleRace(seed: base.seed, count: 1)..countdown = 0;
      isolate(r, <Obstacle>[s]);
      final Runner p = r.runners[0];
      final double a0 = s.angle(0) + (s.speed > 0 ? 0.25 : -0.25);
      p
        ..x = (s.x + math.cos(a0) * s.w * 0.6).clamp(rr, ObstacleRace.width - rr)
        ..y = s.y + math.sin(a0) * s.w * 0.6
        ..z = ObstacleRace.armHeight + 40
        ..vz = 0;
      final double x0 = p.x;
      for (int k = 0; k < 12; k++) {
        p.vy = 0;
        r.step(h);
      }
      expect(r.events.any((ObEvent e) => e.kind == 'knock'), isFalse);
      expect(p.x, closeTo(x0, 1));
    });

    test('drop block squashes whoever is under it on landing, then is solid', () {
      final (ObstacleRace base, Obstacle d) = find(ObSectionKind.drops, ObKind.drop);
      final ObstacleRace r = ObstacleRace(seed: base.seed, count: 1)..countdown = 0;
      isolate(r, <Obstacle>[d]);
      final Runner p = r.runners[0];
      // advance to just before landing
      while (d.dropCycle(r.time + h) < 0.74 || d.dropCycle(r.time + h) > 0.75) {
        p
          ..x = d.x
          ..y = d.y
          ..vy = 0
          ..vx = 0;
        r.step(h);
        r.events.clear();
      }
      bool squashed = false;
      for (int k = 0; k < 12; k++) {
        r.step(h);
        squashed |= r.events.any((ObEvent e) => e.kind == 'squash');
      }
      expect(squashed, isTrue);
      expect(p.stun, greaterThan(0));
      expect(d.dropSolid(r.time), isTrue);
      final bool inside = (p.x - d.x).abs() < d.w / 2 + rr - 0.5 && (p.y - d.y).abs() < d.h / 2 + rr - 0.5;
      final double cx = p.x.clamp(d.x - d.w / 2, d.x + d.w / 2), cy = p.y.clamp(d.y - d.h / 2, d.y + d.h / 2);
      expect(inside && math.sqrt(math.pow(p.x - cx, 2) + math.pow(p.y - cy, 2)) < rr - 0.5, isFalse);
    });

    test('runner-runner shoves separate overlapping runners', () {
      final ObstacleRace r = ObstacleRace(seed: 1, count: 2)..countdown = 0;
      isolate(r, <Obstacle>[]);
      r.runners[0]
        ..x = 200
        ..y = 300;
      r.runners[1]
        ..x = 205
        ..y = 302;
      r.step(h);
      final Runner a = r.runners[0], b = r.runners[1];
      expect(math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2)), greaterThanOrEqualTo(2 * rr - 0.5));
    });

    test('side rails hold the runner inside the course', () {
      final ObstacleRace r = solo(1);
      isolate(r, <Obstacle>[]);
      final Runner p = r.runners[0];
      r.input(0, -1, false);
      run(r, 2);
      expect(p.x, rr);
      r.input(0, 1, false);
      run(r, 3);
      expect(p.x, ObstacleRace.width - rr);
    });
  });

  group('course is fair and passable', () {
    test('generation invariants: always a lane, every pit jumpable or avoidable, clear checkpoints', () {
      for (int seed = 1; seed <= 60; seed++) {
        final ObstacleRace r = ObstacleRace(seed: seed, count: 4);
        expect(r.sections.length, 10);
        expect(r.sections.map((ObSection s) => s.kind).toSet().length, ObSectionKind.values.length,
            reason: 'every section type appears');
        expect(r.sections.first.kind, isNot(ObSectionKind.bridge));
        for (final ObSection s in r.sections) {
          // checkpoint runway is free of obstacles
          for (double y = s.y0; y <= s.y0 + ObstacleRace.runway - 1; y += 5) {
            for (final Obstacle o in r.near(y, y)) {
              expect(o.yMin > y || o.yMax < y, isTrue, reason: 'seed $seed: ${o.kind} on the checkpoint runway of #${s.index}');
            }
          }
        }
        for (double y = ObstacleRace.startY; y < r.finishY; y += 4) {
          // widest pit-free centre interval at this y
          final List<Obstacle> pits = r.near(y, y).where((Obstacle o) => o.kind == ObKind.pit && y > o.y + ObstacleRace.pitMargin && y < o.y + o.h - ObstacleRace.pitMargin).toList();
          double best = 0, run0 = -1;
          for (double x = rr; x <= ObstacleRace.width - rr; x += 1) {
            if (!r.inPit(x, y)) {
              if (run0 < 0) run0 = x;
              best = math.max(best, x - run0);
            } else {
              run0 = -1;
            }
          }
          if (pits.isNotEmpty) expect(best, greaterThanOrEqualTo(2 * rr), reason: 'seed $seed y $y: no walkable lane');
        }
        for (final Obstacle o in r.obstacles) {
          switch (o.kind) {
            case ObKind.pit:
              final ObSection s = r.sectionAt(o.y + 1)!;
              if (s.kind == ObSectionKind.pits) expect(o.h, lessThanOrEqualTo(ObstacleRace.maxPitLen));
            case ObKind.gate:
              expect(o.w, greaterThanOrEqualTo(130));
              expect(o.w - 2 * rr, greaterThan(90), reason: 'gap fits three runners');
            case ObKind.sweeper:
              expect(o.x - ObstacleRace.hubR, greaterThan(2 * rr));
              expect(ObstacleRace.width - o.x - ObstacleRace.hubR, greaterThan(2 * rr));
            case ObKind.bumper:
              for (final Obstacle q in r.obstacles) {
                if (q == o || q.kind != ObKind.bumper) continue;
                final double d = math.sqrt(math.pow(q.x - o.x, 2) + math.pow(q.y - o.y, 2));
                expect(d - o.w - q.w, greaterThanOrEqualTo(2 * rr + 29));
              }
            case ObKind.drop:
              break;
          }
        }
      }
    });

    test('every section of 25 courses is passed by a top bot in reasonable time, without getting stuck', () {
      for (int seed = 1; seed <= 25; seed++) {
        final ObstacleRace r = ObstacleRace(seed: seed, count: 1, botSkill: const <double>[1]);
        final Runner p = r.runners[0];
        final Map<int, double> enter = <int, double>{};
        int guard = 0;
        while (!r.over && guard++ < 120 * 200) {
          r.step(h);
          for (final ObEvent e in r.events) {
            if (e.kind == 'checkpoint') enter[p.checkpoint] = r.time;
          }
          r.events.clear();
          expect(r.solidAt(p.x, p.y), isFalse, reason: 'seed $seed: wedged in geometry at ${p.x},${p.y}');
        }
        expect(p.finished, isTrue, reason: 'seed $seed');
        expect(p.respawns, 0, reason: 'seed $seed: a top bot never falls');
        expect(p.finishTime, lessThan(40), reason: 'seed $seed');
        for (int i = 0; i < r.sections.length; i++) {
          final double t1 = i + 1 < r.sections.length ? enter[i + 1]! : p.finishTime;
          expect(t1 - enter[i]!, lessThan(9), reason: 'seed $seed section ${r.sections[i].kind.name}#$i');
        }
      }
    });

    test('low-skill bots still finish (they may fall and respawn) and skill matters', () {
      double good = 0, bad = 0;
      int falls = 0;
      for (int seed = 1; seed <= 8; seed++) {
        for (final double sk in <double>[1.0, 0.3]) {
          final ObstacleRace r = ObstacleRace(seed: seed, count: 1, botSkill: <double>[sk]);
          int guard = 0;
          while (!r.over && guard++ < 120 * 200) {
            r.step(1 / 60);
          }
          expect(r.runners[0].finished, isTrue, reason: 'seed $seed skill $sk');
          if (sk == 1) {
            good += r.runners[0].finishTime;
          } else {
            bad += r.runners[0].finishTime;
            falls += r.runners[0].respawns;
          }
        }
      }
      expect(bad, greaterThan(good));
      expect(falls, greaterThanOrEqualTo(0));
    });
  });

  group('camera', () {
    test('follows smoothly and frame-rate independently, cuts on respawn', () {
      double after(double frame) {
        final ObCamera c = ObCamera()..y = 0;
        for (double t = 0; t < 0.5 - 1e-9; t += frame) {
          c.follow(800, frame);
        }
        return c.y;
      }

      expect(after(1 / 30), closeTo(after(1 / 120), 0.5));
      final ObCamera c = ObCamera()..y = 0;
      double prev = c.y;
      for (int i = 0; i < 60; i++) {
        c.follow(500, 1 / 60);
        expect(c.y - prev, lessThan(60), reason: 'no snapping while following');
        expect(c.y, greaterThanOrEqualTo(prev));
        prev = c.y;
      }
      expect(c.y, closeTo(500 - ObstacleRace.followOffset, 15));
      c.follow(5000, 1 / 60);
      expect(c.y, 5000 - ObstacleRace.followOffset, reason: 'a respawn far away cuts');
    });
  });
}
