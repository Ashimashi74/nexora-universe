import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/kart_racing/core/kart_core.dart';

/// Runs the countdown off so karts can move.
void _go(KartRace r) {
  while (!r.started) {
    r.step(kFixedDt);
  }
  r.events.clear();
}

/// Places [k] on the track at coordinate [s] (lateral [lat]) heading along the track at [speed].
void _place(KartRace r, Kart k, double s, {double lat = 0, double speed = 0, bool backwards = false}) {
  final V2 d = r.track.dirAt(s);
  k.pos = r.track.centerAt(s) + d.perp * lat;
  k.heading = math.atan2(d.y, d.x) + (backwards ? math.pi : 0);
  k.vel = V2.polar(k.heading, speed);
  k.speed = speed;
}

/// Drives [k] along the centre line (perfect steering) for [seconds].
void _driveAlong(KartRace r, Kart k, double seconds, {double steerLat = 0, bool backwards = false}) {
  final int steps = (seconds / kFixedDt).round();
  for (int i = 0; i < steps; i++) {
    final double ahead = backwards ? -3 : 3;
    final V2 t = r.track.centerAt(k.s + ahead + r.track.n) + r.track.dirAt(k.s + ahead + r.track.n).perp * steerLat;
    final double want = math.atan2(t.y - k.pos.y, t.x - k.pos.x);
    final double diff = wrapAngle(want - k.heading);
    r.input(k.seat, (diff * 3).clamp(-1.0, 1.0), false, false);
    r.step(kFixedDt);
  }
}

void main() {
  group('track', () {
    test('deterministic, closed, uniformly sampled', () {
      final KartTrack a = KartTrack.generate(5), b = KartTrack.generate(5);
      expect(a.n, b.n);
      for (int i = 0; i < a.n; i += 17) {
        expect(a.at(i).x, b.at(i).x);
        expect(a.at(i).y, b.at(i).y);
      }
      for (int i = 0; i < a.n; i++) {
        expect((a.at(i).dist(a.at(i + 1)) - a.spacing).abs() < 1.0, isTrue, reason: 'segment $i');
      }
    });

    for (final int seed in <int>[1, 2, 3, 7, 42, 99, 1234, 20261118]) {
      test('seed $seed: drivable corners, walls never overlap another part, racing line on the asphalt', () {
        final KartTrack t = KartTrack.generate(seed);
        // every corner can be held at a reasonable speed
        expect(KartTrack.minRadius(t.points) > KartTrack.minCornerRadius * 0.85, isTrue);
        // two parts of the track that are far apart along the lap never come within two wall offsets
        final int skip = (t.wallOffset * 4 / t.spacing).ceil();
        for (int i = 0; i < t.n; i += 2) {
          for (int j = i + skip; j < t.n; j += 2) {
            if (t.n - (j - i) < skip) continue;
            expect(t.at(i).dist(t.at(j)) > t.wallOffset * 2, isTrue, reason: '$i-$j');
          }
        }
        final double maxOff = t.width / 2 - KartDims.width / 2;
        for (int i = 0; i < t.n; i++) {
          expect(t.lineOffset(i).abs() <= maxOff, isTrue);
        }
      });
    }

    test('projection matches the drawn centre line and lateral sign', () {
      final KartTrack t = KartTrack.generate(9);
      for (int i = 0; i < t.n; i += 23) {
        final V2 p = t.centerAt(i + 0.5) + t.dirAt(i + 0.5).perp * 40;
        final TrackHit h = t.project(p, i);
        expect((h.dist - 40).abs() < 1.5, isTrue);
        expect(h.lateral > 0, isTrue);
        expect((h.s - (i + 0.5)).abs() < 0.2, isTrue);
        expect(t.project(p).seg, h.seg); // global search agrees with the hinted one
      }
    });
  });

  group('fixed timestep', () {
    test('same race at 30, 60, 144 fps and with hitches is bit-identical', () {
      List<double> run(List<double> frames) {
        final KartRace r = KartRace(seed: 11, racers: 4, botSkill: const <double>[0.9, 0.6, 0.3, 0.9]);
        int f = 0;
        while (r.ticks < 2400) {
          r.step(math.min(frames[f++ % frames.length], (2400 - r.ticks) * kFixedDt));
        }
        expect(r.ticks, 2400);
        return <double>[for (final Kart k in r.karts) ...<double>[k.pos.x, k.pos.y, k.heading, k.raceProgress]];
      }

      final List<double> a = run(<double>[1 / 30]);
      expect(run(<double>[1 / 60]), a);
      expect(run(<double>[1 / 120]), a);
      expect(run(<double>[1 / 40, 1 / 24, 1 / 120, 1 / 60]), a);
    });

    test('a long hitch is clamped (no tunnelling jump)', () {
      final KartRace r = KartRace(seed: 3, racers: 2);
      r.step(5);
      expect(r.time, closeTo(kMaxFrameDt, kFixedDt));
      r.step(-1);
      r.step(double.nan);
      expect(r.time, closeTo(kMaxFrameDt, kFixedDt));
    });

    test('countdown holds karts on the grid, then GO', () {
      final KartRace r = KartRace(seed: 3, racers: 4);
      final List<V2> grid = <V2>[for (final Kart k in r.karts) k.pos];
      for (int i = 0; i < 60; i++) {
        r.input(0, 1, true, true);
        r.step(1 / 30);
      }
      expect(r.started, isFalse);
      for (int i = 0; i < 4; i++) {
        expect(r.karts[i].pos.x, grid[i].x);
      }
      for (int i = 0; i < 40; i++) {
        r.step(1 / 30);
      }
      expect(r.started, isTrue);
      expect(r.raceTime, closeTo(r.time - 3, 1e-9));
      expect(r.karts[0].speed > 0, isTrue); // auto throttle
    });

    test('grid: karts do not overlap and start behind the line', () {
      for (final int n in <int>[2, 3, 4]) {
        final KartRace r = KartRace(seed: 8, racers: n);
        for (int i = 0; i < n; i++) {
          expect(r.karts[i].passed, 0);
          expect(r.karts[i].raceProgress < 0, isTrue);
          for (int j = i + 1; j < n; j++) {
            expect(r.karts[i].pos.dist(r.karts[j].pos) > KartDims.width + 2, isTrue);
          }
          expect(r.track.project(r.karts[i].pos).dist + KartDims.width / 2 < r.track.width / 2, isTrue);
        }
      }
    });
  });

  group('laps and checkpoints', () {
    test('legit laps count, the lap is completed only after every gate in order', () {
      final KartRace r = KartRace(seed: 21, racers: 2, laps: 2);
      _go(r);
      final Kart k = r.karts[0];
      _driveAlong(r, k, 2);
      expect(k.passed, greaterThanOrEqualTo(1)); // crossed the start line
      expect(k.lap, 0);
      int guard = 0;
      while (!k.finished && guard++ < 200) {
        _driveAlong(r, k, 1);
      }
      expect(k.finished, isTrue);
      expect(k.lap, 2);
      expect(k.passed, r.finishPasses);
      final List<int> laps = r.events.where((KartEvent e) => e.kind == 'lap' && e.seat == 0).map((KartEvent e) => e.other).toList();
      expect(laps, <int>[1, 2]);
      expect(r.finishOrder.first, 0);
      expect(k.finishTime > 0 && k.finishTime < r.raceTime + 1e-9, isTrue);
    });

    test('skipping the lap (teleport/cut back to the line) never counts', () {
      final KartRace r = KartRace(seed: 21, racers: 2);
      _go(r);
      final Kart k = r.karts[0];
      _driveAlong(r, k, 2);
      expect(k.passed, 1);
      final double progressBefore = k.raceProgress;
      // cut: jump to just before the finish line and cross it again
      for (int i = 0; i < 6; i++) {
        _place(r, k, r.track.n - 3.0, speed: 300);
        _driveAlong(r, k, 0.6);
        expect(k.lap, 0);
        expect(k.passed, lessThanOrEqualTo(2));
      }
      expect(r.events.where((KartEvent e) => e.kind == 'lap').isEmpty, isTrue);
      expect(k.raceProgress < progressBefore + r.gateGap * 2, isTrue);
    });

    test('cutting across the infield is impossible: the walls hold the kart in the corridor', () {
      final KartRace r = KartRace(seed: 4, racers: 1);
      _go(r);
      final Kart k = r.karts[0];
      // aim straight at the infield at full boost and hold
      _place(r, k, 30, speed: KartRace.maxSpeed);
      final V2 c = r.track.centerAt(30);
      k.heading = math.atan2(-c.y, -c.x);
      k.boost = 5;
      for (int i = 0; i < 600; i++) {
        r.input(0, 0, false, false);
        r.step(kFixedDt);
        final TrackHit h = r.track.project(k.pos, k.idx);
        expect(h.dist <= r.track.wallOffset - KartDims.r + 6, isTrue, reason: 'step $i dist ${h.dist}');
      }
      expect(k.passed, lessThanOrEqualTo(3));
    });

    test('driving backwards over the line un-counts it (no lap farming)', () {
      final KartRace r = KartRace(seed: 6, racers: 1);
      _go(r);
      final Kart k = r.karts[0];
      _driveAlong(r, k, 1.5);
      expect(k.passed, 1);
      _place(r, k, k.s, speed: 150, backwards: true);
      _driveAlong(r, k, 1.5, backwards: true);
      expect(k.passed, 0);
      expect(k.isWrongWay, isTrue);
      _place(r, k, k.s, speed: 100);
      _driveAlong(r, k, 1.5);
      expect(k.passed, 1);
      expect(k.lap, 0);
      expect(k.isWrongWay, isFalse);
    });
  });

  group('ranking', () {
    test('finishers by finishing order, then by race distance', () {
      final KartRace r = KartRace(seed: 2, racers: 4);
      r.karts[0].raceProgress = 100;
      r.karts[1].raceProgress = 300;
      r.karts[2].raceProgress = 200;
      r.karts[3].raceProgress = 50;
      expect(r.standings().map((Kart k) => k.seat).toList(), <int>[1, 2, 0, 3]);
      r.finish(3, 70);
      r.finish(0, 70); // same time, later across the line
      expect(r.standings().map((Kart k) => k.seat).toList(), <int>[3, 0, 1, 2]);
      expect(r.placeOf(1), 3);
      r.finish(3, 99); // idempotent
      expect(r.finishOrder, <int>[3, 0]);
    });

    test('positions during a race follow the real race distance', () {
      final KartRace r = KartRace(seed: 77, racers: 4, botSkill: const <double>[0.3, 0.6, 0.9, 0.6]);
      for (int i = 0; i < 30 * 40; i++) {
        r.step(1 / 30);
        if (i % 30 != 0 || !r.started) continue;
        final List<Kart> st = r.standings();
        for (int j = 1; j < st.length; j++) {
          if (!st[j - 1].finished && !st[j].finished) {
            expect(st[j - 1].raceProgress >= st[j].raceProgress, isTrue);
          }
        }
      }
    });
  });

  group('AI', () {
    for (final List<double> skills in <List<double>>[
      <double>[0.3, 0.3, 0.3, 0.3],
      <double>[0.62, 0.62, 0.62, 0.62],
      <double>[0.92, 0.62, 0.3, 0.92],
    ]) {
      test('bots finish a full 3-lap race $skills', () {
        for (final int seed in <int>[42, 5, 1234]) {
          final KartRace r = KartRace(seed: seed, racers: 4, botSkill: skills);
          int steps = 0;
          while (!r.allFinished && steps < 30 * 240) {
            r.step(1 / 30);
            steps++;
          }
          expect(r.allFinished, isTrue, reason: 'seed $seed');
          expect(r.finishOrder.toSet().length, 4);
          for (final Kart k in r.karts) {
            expect(k.lap, 3);
            expect(k.passed, r.finishPasses);
            expect(k.finishTime, inInclusiveRange(30, 130), reason: 'seed $seed kart ${k.seat}');
          }
          expect(r.standings().first.seat, r.finishOrder.first);
        }
      });
    }

    test('hard bots beat easy bots', () {
      int hardWins = 0;
      for (final int seed in <int>[1, 2, 3, 4, 5, 6]) {
        final KartRace r = KartRace(seed: seed, racers: 2, botSkill: const <double>[0.92, 0.3]);
        while (!r.allFinished && r.time < 300) {
          r.step(1 / 30);
        }
        if (r.finishOrder.first == 0) hardWins++;
      }
      expect(hardWins, greaterThanOrEqualTo(4)); // items can swing a race, the driving decides most
    });

    test('pure driving: higher skill laps faster on every track', () {
      for (final int seed in <int>[1, 2, 3, 4]) {
        final List<double> times = <double>[];
        for (final double sk in <double>[0.3, 0.62, 0.92]) {
          final KartRace r = KartRace(seed: seed, racers: 1, botSkill: <double>[sk]);
          while (!r.allFinished && r.time < 300) {
            r.step(1 / 30);
          }
          times.add(r.karts[0].finishTime);
        }
        expect(times[0] > times[1] && times[1] > times[2] - 0.5, isTrue, reason: 'seed $seed $times');
      }
    });

    test('rubber band is gentle and bounded', () {
      final KartRace r = KartRace(seed: 12, racers: 3, botSkill: const <double>[0, 0.62, 0.62]);
      _go(r);
      r.karts[0].raceProgress = 500;
      r.karts[1].raceProgress = 500 + r.track.n.toDouble(); // a lap ahead
      r.karts[2].raceProgress = 500 - r.track.n.toDouble(); // a lap behind
      r.step(kFixedDt);
      const double base = 0.86 + 0.14 * 0.62;
      expect(r.karts[1].engine, closeTo(base - 0.07, 0.02));
      expect(r.karts[2].engine, closeTo(base + 0.05, 0.02));
      expect(r.karts[0].engine, 1); // humans are never touched
    });

    test('offline end of race: the remaining field is raced to the line for the real order', () {
      final KartRace r = KartRace(seed: 31, racers: 4, botSkill: const <double>[0, 0.3, 0.62, 0.92]);
      r.simulateToEnd();
      expect(r.allFinished, isTrue);
      expect(r.finishOrder.length, 4);
      expect(r.karts[0].lap, 3); // the human seat was driven by the autopilot
    });
  });

  group('movement', () {
    test('acceleration curve, top speed, braking', () {
      final KartRace r = KartRace(seed: 50, racers: 1);
      _go(r);
      final Kart k = r.karts[0];
      _driveAlong(r, k, 0.5);
      final double v05 = k.speed;
      _driveAlong(r, k, 0.5);
      final double v1 = k.speed;
      _driveAlong(r, k, 4);
      expect(v05 > 150 && v05 < 300, isTrue, reason: 'v05 $v05');
      expect(v1 - v05 < v05, isTrue); // falling acceleration
      expect(k.speed, lessThanOrEqualTo(KartRace.maxSpeed + 1));
      expect(k.speed > KartRace.maxSpeed * 0.85, isTrue);
      final V2 p0 = k.pos;
      int steps = 0;
      while (k.speed > 1 && steps < 600) {
        r.input(0, 0, false, false, brake: true);
        r.step(kFixedDt);
        steps++;
      }
      expect(steps * kFixedDt, lessThan(0.7));
      expect(k.pos.dist(p0), lessThan(140));
      expect(k.speed, greaterThanOrEqualTo(-1)); // brake never reverses
    });

    test('steering depends on speed', () {
      double yawRate(double speed) {
        final KartRace r = KartRace(seed: 50, racers: 1);
        _go(r);
        final Kart k = r.karts[0];
        _place(r, k, 10, speed: speed);
        k.steerApplied = 1;
        k.engine = speed / KartRace.maxSpeed; // hold the speed
        final double h0 = k.heading;
        r.input(0, 1, false, false);
        r.step(kFixedDt * 6);
        return wrapAngle(k.heading - h0) / (kFixedDt * 6);
      }

      final double slow = yawRate(20), mid = yawRate(150), fast = yawRate(370);
      expect(slow < mid, isTrue);
      expect(fast < mid, isTrue);
      expect(fast > 0.9, isTrue);
    });

    test('drift slides (low grip), charges and releases a mini-turbo', () {
      final KartRace r = KartRace(seed: 50, racers: 1);
      _go(r);
      final Kart k = r.karts[0];
      // full speed on the left edge of a straight-ish stretch, then drift to the right
      _place(r, k, 10, lat: -(r.track.width / 2 - KartDims.width), speed: 340);
      double maxSlip = 0;
      bool started = false;
      for (int i = 0; i < 84; i++) {
        r.input(0, 1, true, false);
        r.step(kFixedDt);
        started = started || k.drifting;
        maxSlip = math.max(maxSlip, k.slip.abs());
      }
      expect(started, isTrue);
      expect(k.drifting, isTrue);
      expect(k.driftCharge > KartRace.driftLv1, isTrue);
      expect(maxSlip > 0.25, isTrue, reason: 'slip $maxSlip');
      expect(k.speed > 220, isTrue, reason: 'drift keeps speed: ${k.speed}');
      r.events.clear();
      r.input(0, 0, false, false);
      expect(k.drifting, isFalse);
      expect(k.boost > 0, isTrue);
      expect(r.events.any((KartEvent e) => e.kind == 'boost'), isTrue);
    });

    test('grass halves the top speed, curbs do not', () {
      double settle(double lat) {
        final KartRace r = KartRace(seed: 50, racers: 1);
        _go(r);
        final Kart k = r.karts[0];
        _place(r, k, 10, lat: lat, speed: 300);
        _driveAlong(r, k, 2.5, steerLat: lat);
        return k.speed;
      }

      final KartTrack t = KartTrack.generate(50);
      final double road = settle(0);
      final double curb = settle(t.width / 2 + KartTrack.curb - 4);
      final double grass = settle(t.width / 2 + KartTrack.curb + 22);
      expect(curb, closeTo(road, road * 0.12));
      expect(grass < road * 0.62, isTrue, reason: 'road $road grass $grass');
    });
  });

  group('collisions', () {
    test('kart-kart: separated, bounced apart, no sticking or tunnelling', () {
      final KartRace r = KartRace(seed: 60, racers: 2);
      _go(r);
      final Kart a = r.karts[0], b = r.karts[1];
      _place(r, a, 40, speed: 350);
      _place(r, b, 40 + 70 / r.track.spacing, speed: 0);
      b.heading += math.pi; // head-on
      b.vel = V2.polar(b.heading, 350);
      double minD = 1e9;
      for (int i = 0; i < 60; i++) {
        r.step(kFixedDt);
        minD = math.min(minD, a.pos.dist(b.pos));
      }
      expect(minD > KartDims.r * 2 - 4, isTrue, reason: 'min distance $minD'); // no pass-through
      expect(r.events.any((KartEvent e) => e.kind == 'bump'), isTrue);
      final double rel = (b.vel - a.vel).dot((b.pos - a.pos).unit);
      expect(rel >= -1, isTrue); // separating afterwards
    });

    test('side-by-side contact pushes apart without locking', () {
      final KartRace r = KartRace(seed: 60, racers: 2);
      _go(r);
      final Kart a = r.karts[0], b = r.karts[1];
      _place(r, a, 40, lat: -10, speed: 300);
      _place(r, b, 40, lat: 10, speed: 300);
      for (int i = 0; i < 120; i++) {
        r.input(0, 0.2, false, false);
        r.input(1, -0.2, false, false);
        r.step(kFixedDt);
      }
      // capsules never overlap by more than a sliver
      final V2 fa = V2.polar(a.heading), fb = V2.polar(b.heading);
      double minC = 1e9;
      for (final double oa in <double>[KartDims.circleOffset, -KartDims.circleOffset]) {
        for (final double ob in <double>[KartDims.circleOffset, -KartDims.circleOffset]) {
          minC = math.min(minC, (a.pos + fa * oa).dist(b.pos + fb * ob));
        }
      }
      expect(minC > KartDims.r * 2 - 2, isTrue);
      expect(a.speed > 150 && b.speed > 150, isTrue);
    });

    test('walls: glancing hit slides along, head-on hit bounces, never tunnels', () {
      for (final double angle in <double>[0.35, math.pi / 2]) {
        final KartRace r = KartRace(seed: 61, racers: 1);
        _go(r);
        final Kart k = r.karts[0];
        _place(r, k, 60, lat: r.track.wallOffset - 60, speed: 520);
        k.heading += angle; // towards the right-hand wall
        k.vel = V2.polar(k.heading, 520);
        k.boost = 3;
        double maxDist = 0;
        for (int i = 0; i < 90; i++) {
          r.step(kFixedDt);
          maxDist = math.max(maxDist, r.track.project(k.pos, k.idx).dist);
        }
        expect(maxDist <= r.track.wallOffset - KartDims.circleOffset * math.sin(angle) - KartDims.r + 3, isTrue,
            reason: 'angle $angle maxDist $maxDist');
        if (angle < 1) {
          expect(k.vel.len > 250, isTrue, reason: 'slides on: ${k.vel.len}');
        } else {
          expect(r.events.any((KartEvent e) => e.kind == 'wall'), isTrue);
        }
      }
    });
  });

  group('items and props', () {
    test('item box gives an item, pad boosts, turbo raises top speed', () {
      final KartRace r = KartRace(seed: 70, racers: 1);
      _go(r);
      final Kart k = r.karts[0];
      final ItemBox box = r.boxes[1];
      k.pos = box.pos - V2.polar(k.heading, KartDims.length / 2 + KartProps.boxSize / 2 - 2);
      r.step(kFixedDt);
      expect(k.item, isNot(KartItem.none));
      expect(box.active, isFalse);
      final int pad = r.pads.first;
      _place(r, k, pad - 0.5, speed: 200);
      r.step(kFixedDt);
      expect(k.boost > 0, isTrue);
      k.item = KartItem.turbo;
      r.useItem(0);
      _driveAlong(r, k, 1.2);
      expect(k.speed > KartRace.maxSpeed * 1.05, isTrue);
    });

    test('missile homes onto the racer ahead; shield absorbs; oil spares its dropper', () {
      final KartRace r = KartRace(seed: 71, racers: 2, botSkill: const <double>[0, 0]);
      _go(r);
      final Kart a = r.karts[0], b = r.karts[1];
      _place(r, a, 20, speed: 0);
      _place(r, b, 34, speed: 0);
      a.raceProgress = 20;
      b.raceProgress = 34;
      a.item = KartItem.missile;
      r.useItem(0);
      expect(r.missiles.single.target, 1);
      for (int i = 0; i < 240 && r.missiles.isNotEmpty; i++) {
        r.step(kFixedDt);
      }
      expect(r.missiles, isEmpty);
      expect(b.spin > 0 || r.events.any((KartEvent e) => e.kind == 'missile_hit'), isTrue);
      b.shield = 3;
      b.spin = 0;
      r.hit(1);
      expect(b.spin, 0);
      expect(b.shield, 0);
      // oil dropped behind a moving kart does not hit it
      _place(r, a, 60, speed: 250);
      a.item = KartItem.oil;
      r.useItem(0);
      for (int i = 0; i < 60; i++) {
        r.step(kFixedDt);
      }
      expect(a.spin, lessThanOrEqualTo(0));
      expect(r.oils.length, 1);
    });
  });

  group('dimensions', () {
    test('collision capsule is the drawn kart box', () {
      final KartRace r = KartRace(seed: 80, racers: 1);
      final Kart k = r.karts[0];
      k.pos = V2.zero;
      for (final double h in <double>[0, 0.7, math.pi / 2, 2.4]) {
        k.heading = h;
        final V2 f = V2.polar(h), s = f.perp;
        // nose, tail and both sides of the drawn box touch the capsule
        expect(r.touches(k, f * (KartDims.length / 2 - 0.5), 0.1), isTrue);
        expect(r.touches(k, f * -(KartDims.length / 2 - 0.5), 0.1), isTrue);
        expect(r.touches(k, s * (KartDims.width / 2 - 0.5), 0.1), isTrue);
        expect(r.touches(k, s * -(KartDims.width / 2 - 0.5), 0.1), isTrue);
        // just outside the drawn box is outside the capsule
        expect(r.touches(k, f * (KartDims.length / 2 + 1), 0.1), isFalse);
        expect(r.touches(k, s * (KartDims.width / 2 + 1), 0.1), isFalse);
        // the rounded corners leave at most a few units of the drawn box uncovered
        final V2 corner = f * (KartDims.length / 2) + s * (KartDims.width / 2);
        expect(r.touches(k, corner, 8), isTrue);
      }
    });

    test('track and props are in kart proportions', () {
      final KartTrack t = KartTrack.generate(1);
      expect(t.width / KartDims.width, inInclusiveRange(4.5, 6)); // 4-5 karts side by side
      expect(KartDims.length / KartDims.width, inInclusiveRange(1.3, 1.6));
      expect(KartProps.boxSize < KartDims.width, isTrue);
      expect(KartProps.oilW, lessThan(KartDims.length * 1.2));
      expect(KartProps.padWidth(t.width) > KartDims.width * 1.5, isTrue);
      expect(t.runoff > KartDims.length, isTrue);
      final KartRace r = KartRace(seed: 1, racers: 4);
      for (final ItemBox b in r.boxes) {
        expect(t.project(b.pos).dist + KartProps.boxSize / 2 <= t.width / 2, isTrue); // boxes on the asphalt
      }
    });
  });
}
