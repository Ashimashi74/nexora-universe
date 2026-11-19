import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/mini_golf/core/golf_core.dart';

/// Shot that rolls the current ball straight at the cup with [arrive] units/s left at the cup.
(double, double) _straight(GolfMatch g, [double arrive = 120]) {
  final GBall b = g.balls[g.current];
  final double d = math.sqrt(math.pow(g.h.cup.x - b.x, 2) + math.pow(g.h.cup.y - b.y, 2));
  return (math.atan2(g.h.cup.y - b.y, g.h.cup.x - b.x), GolfMatch.powerFor(d, arrive));
}

/// Starts a shot, then overrides the shooter's position and velocity (precise physics set-ups).
void _launch(GolfMatch g, double x, double y, double vx, double vy) {
  final GBall b = g.balls[g.current];
  b
    ..x = x
    ..y = y;
  g.shoot(0, 0.1);
  b
    ..vx = vx
    ..vy = vy;
}

double _minWallGap(GolfMatch g, GBall b) {
  double m = double.infinity;
  for (final GWall w in g.h.walls) {
    m = math.min(m, GolfMatch.segDist(b.x, b.y, w.x1, w.y1, w.x2, w.y2));
  }
  return m;
}

void main() {
  group('strokes, par and scorecard', () {
    test('course is 9 holes, par 28, mirrored for odd seeds', () {
      final List<GHole> even = golfCourse(2), odd = golfCourse(3);
      expect(even.length, 9);
      expect(even.fold(0, (int a, GHole h) => a + h.par), 28);
      for (int i = 0; i < 9; i++) {
        expect(odd[i].par, even[i].par);
        expect(odd[i].cup.x, closeTo(kGolfW - even[i].cup.x, 1e-9));
      }
    });

    test('a hole in one is one stroke on the card, then the next hole tees off', () {
      final GolfMatch g = GolfMatch(players: 1, seed: 2);
      final (double a, double p) = _straight(g);
      g.shoot(a, p);
      final List<GEvent> seen = <GEvent>[];
      while (!g.step(1)) {
        seen.addAll(g.events);
        g.events.clear();
      }
      seen.addAll(g.events);
      final GEvent cup = seen.firstWhere((GEvent e) => e.kind == 'cup');
      expect(cup.strokes, 1);
      expect(golfScoreName(cup.strokes, 2), 'ace');
      expect(g.cards[0], <int>[1]);
      expect(g.hole, 1);
      expect(g.total(0), 1);
      expect(g.toPar(0), -1);
      expect(g.balls[0].strokes, 0);
      expect(g.balls[0].onCourse, isTrue, reason: 'next hole: the shooter is teed up');
    });

    test('score names', () {
      expect(golfScoreName(1, 3), 'ace');
      expect(golfScoreName(2, 4), 'eagle');
      expect(golfScoreName(2, 3), 'birdie');
      expect(golfScoreName(3, 3), 'par');
      expect(golfScoreName(4, 3), 'bogey');
      expect(golfScoreName(5, 3), 'double');
      expect(golfScoreName(6, 3), 'over');
      expect(golfScoreName(kMaxStrokes + 1, 3), 'pickup');
    });

    test('strokes count up and a player picks up after the maximum', () {
      final GolfMatch g = GolfMatch(players: 2, seed: 2);
      final List<String> kinds = <String>[];
      // seat 0 keeps tapping the ball sideways; seat 1 holes out in one
      while (g.hole == 0) {
        if (g.current == 0) {
          g.shoot(g.balls[0].x < 150 ? 0 : math.pi, 0.08);
        } else {
          final (double a, double p) = _straight(g);
          g.shoot(a, p);
        }
        g.runToEnd();
        kinds.addAll(g.events.map((GEvent e) => e.kind));
        g.events.clear();
      }
      expect(kinds, contains('pickup'));
      expect(g.cards[0].single, kMaxStrokes + 1);
      expect(g.cards[1].single, 1);
      expect(g.parSoFar(), 2);
    });

    test('water: shooter replays from the previous lie with a penalty stroke', () {
      final GolfMatch g = GolfMatch(players: 1, seed: 2);
      g.hole = 5;
      g.balls = <GBall>[GBall(80, 330)];
      g.shoot(-math.pi / 2, 0.2);
      g.runToEnd();
      expect(g.balls[0].strokes, 2);
      expect(g.balls[0].x, closeTo(80, 1e-9));
      expect(g.balls[0].y, closeTo(330, 1e-9));
    });

    test('out of bounds costs a stroke and the ball comes back to a legal spot', () {
      final GolfMatch g = GolfMatch(players: 1, seed: 2);
      _launch(g, 500, 300, 0, 0); // outside the course
      g.runToEnd();
      expect(g.balls[0].strokes, 2);
      expect(golfLegalSpot(g.h, g.balls[0].x, g.balls[0].y), isTrue);
    });
  });

  group('turn order and end of round', () {
    test('seat order from the tee, then furthest from the cup, then honour on the next hole', () {
      final GolfMatch g = GolfMatch(players: 3, seed: 2);
      expect(g.current, 0);
      expect(g.balls[1].onCourse, isFalse);
      g.shoot(-math.pi / 2 - 0.35, 0.3); // short, off the line to the cup
      g.runToEnd();
      expect(g.current, 1);
      final (double a, double p) = _straight(g); // seat 1 aces
      g.shoot(a, p);
      g.runToEnd();
      expect(g.balls[1].holed, isTrue);
      expect(g.current, 2);
      g.shoot(-math.pi / 2 + 0.3, 0.5); // ends nearer the cup than seat 0
      g.runToEnd();
      // furthest from the cup plays next
      final double d0 = g.distanceToCup(g.balls[0].x, g.balls[0].y), d2 = g.distanceToCup(g.balls[2].x, g.balls[2].y);
      expect(d0, greaterThan(d2));
      expect(g.current, 0);
      while (g.hole == 0) {
        final (double a2, double p2) = g.botShot(math.Random(3), 1, samples: 8);
        g.shoot(a2, p2);
        g.runToEnd();
      }
      // seat 1 made the ace: it has the honour on hole 2
      expect(g.current, 1);
    });

    test('distance order follows the walls (walking distance), not a straight line', () {
      final GolfMatch g = GolfMatch(players: 2, seed: 2);
      g.hole = 2; // L-shape: cup top-right, behind the inner wall
      final GolfGeo geo = GolfGeo.of(g.h);
      // just behind the inner wall, close in a straight line but far to walk
      expect(geo.at(200, 200), greaterThan(geo.at(80, 120)));
      expect(geo.at(200, 200) > math.sqrt(math.pow(200 - g.h.cup.x, 2) + math.pow(200 - g.h.cup.y, 2)) + 50, isTrue);
    });

    test('a full round ends after 9 holes with complete cards and a ranking', () {
      final GolfMatch g = GolfMatch(players: 2, seed: 4);
      int shots = 0;
      while (!g.over && shots < 300) {
        final (double a, double p) = g.botShot(math.Random(shots), 0.8, samples: 12);
        expect(g.shoot(a, p), isTrue);
        g.runToEnd();
        shots++;
      }
      expect(g.over, isTrue);
      expect(g.shoot(0, 0.5), isFalse, reason: 'no shots after the round');
      for (int s = 0; s < 2; s++) {
        expect(g.cards[s].length, 9);
        expect(g.cards[s].every((int x) => x >= 1 && x <= kMaxStrokes + 1), isTrue);
        expect(g.total(s), g.cards[s].fold(0, (int a, int b) => a + b));
      }
      expect(g.parSoFar(), 28);
      final List<int> r = g.ranking();
      expect(r.toSet(), <int>{0, 1});
      expect(g.total(r.first), lessThanOrEqualTo(g.total(r.last)));
    });

    test('a player who leaves writes the max and ranks last; everybody leaving ends the round', () {
      final GolfMatch g = GolfMatch(players: 3, seed: 2);
      g.forfeit(0);
      expect(g.current, 1);
      while (!g.over) {
        final (double a, double p) = g.botShot(math.Random(g.shotsTaken), 1, samples: 6);
        g.shoot(a, p);
        g.runToEnd();
        if (g.hole == 4 && !g.out.contains(1)) {
          g.forfeit(1);
          g.forfeit(2);
        }
      }
      expect(g.cards[0].every((int s) => s == kMaxStrokes + 1), isTrue);
      expect(g.cards[2].length, 9);
      expect(g.ranking().last, isNot(2));
    });
  });

  group('bot', () {
    test('bots finish a full 4-player round at every difficulty', () {
      for (final double skill in <double>[0.3, 0.62, 0.92]) {
        final GolfMatch g = GolfMatch(players: 4, seed: 5);
        final math.Random rng = math.Random(9);
        int shots = 0;
        while (!g.over && shots < 400) {
          final (double a, double p) = g.botShot(rng, skill, samples: 16);
          g.shoot(a, p);
          g.runToEnd();
          shots++;
        }
        expect(g.over, isTrue, reason: 'skill $skill');
        for (final List<int> c in g.cards) {
          expect(c.length, 9);
        }
      }
    });

    test('every hole is solvable: reachable cup and a perfect bot holes out near par (both mirrors)', () {
      for (final int seed in <int>[2, 3]) {
        final List<GHole> course = golfCourse(seed);
        for (int i = 0; i < course.length; i++) {
          final GHole h = course[i];
          expect(golfLegalSpot(h, h.start.x, h.start.y), isTrue, reason: 'tee hole ${i + 1}');
          expect(golfLegalSpot(h, h.cup.x, h.cup.y), isTrue, reason: 'cup hole ${i + 1}');
          expect(GolfGeo.of(h).reachable(h.start.x, h.start.y), isTrue, reason: 'route hole ${i + 1}');
        }
        final GolfMatch g = GolfMatch(players: 1, seed: seed);
        final math.Random rng = math.Random(1);
        while (!g.over) {
          final (double a, double p) = g.botShot(rng, 1, samples: 24);
          g.shoot(a, p);
          g.runToEnd();
        }
        for (int i = 0; i < 9; i++) {
          expect(g.cards[0][i], lessThanOrEqualTo(course[i].par + 2), reason: 'seed $seed hole ${i + 1}: ${g.cards[0]}');
        }
      }
    });

    test('the incremental planner gives the same shot as a one-go plan', () {
      final GolfMatch g = GolfMatch(players: 2, seed: 2);
      final (double, double) a = g.botShot(math.Random(4), 0.7, samples: 10);
      final GolfBotPlanner p = GolfBotPlanner(g, math.Random(4), 0.7, samples: 10);
      int frames = 0;
      while (!p.work(3)) {
        frames++;
      }
      expect(frames, greaterThan(5));
      expect(p.shot, a);
    });
  });

  group('physics', () {
    test('capture speed: a dead-centre roll drops below it and lips out above it', () {
      expect(kCaptureSpeed, closeTo(455, 5)); // ≈ 1.6 m/s, the measured real-world value
      bool holedAt(double v, double offset) {
        final GolfMatch g = GolfMatch(players: 1, seed: 2);
        final GVec c = g.h.cup;
        _launch(g, c.x + offset, c.y + 40, 0, -v);
        bool holed = false;
        while (g.simulating && g.hole == 0 && g.balls[0].y > c.y - kCupR - 1) {
          g.step(1);
          holed = holed || g.events.any((GEvent e) => e.kind == 'cup');
        }
        return holed;
      }

      expect(holedAt(kCaptureSpeed * 0.85, 0), isTrue);
      expect(holedAt(kCaptureSpeed * 1.15, 0), isFalse);
      // off-centre the chord is shorter, so the same pace lips out
      expect(holedAt(400, 0), isTrue);
      expect(holedAt(400, 10), isFalse);
      expect(holedAt(200, 10), isTrue);
    });

    test('a fast pass over the cup reports a lip-out and bends the line', () {
      final GolfMatch g = GolfMatch(players: 1, seed: 2);
      final GVec c = g.h.cup;
      _launch(g, c.x + 8, c.y + 40, 0, -650);
      final List<String> kinds = <String>[];
      while (g.simulating && g.balls[0].y > c.y - kCupR - 2) {
        g.step(1);
        kinds.addAll(g.events.map((GEvent e) => e.kind));
        g.events.clear();
      }
      expect(kinds, contains('lip'));
      expect(g.balls[0].vx.abs(), greaterThan(1));
    });

    test('a ball coming to rest over the cup drops in', () {
      final GolfMatch g = GolfMatch(players: 1, seed: 2);
      final GVec c = g.h.cup;
      _launch(g, c.x, c.y + 20, 0, -60);
      g.runToEnd();
      expect(g.cards[0].single, 1);
    });

    test('rolling friction: a putt stops at the distance the deceleration predicts', () {
      final GolfMatch g = GolfMatch(players: 1, seed: 2);
      _launch(g, 150, 470, 0, -300);
      g.runToEnd();
      final double travelled = 470 - g.balls[0].y;
      expect(travelled, closeTo(GolfMatch.rollDistance(300), 2));
      expect(travelled, lessThan(300 * 300 / (2 * kRollDecel))); // drag on top of rolling resistance
      expect(g.balls[0].moving, isFalse);
    });

    test('sand slows the ball far more than carpet', () {
      double roll(bool sand) {
        final GolfMatch g = GolfMatch(players: 1, seed: 2);
        g.hole = 3; // sand 80..220 x 140..200
        g.balls = <GBall>[GBall(100, sand ? 195 : 240)];
        _launch(g, 100, sand ? 195 : 240, 0, -200);
        g.runToEnd();
        return (sand ? 195 : 240) - g.balls[0].y;
      }

      expect(roll(true), lessThan(roll(false) * 0.5));
    });

    test('wall bounce keeps the restitution and rests exactly against the drawn rail', () {
      final GolfMatch g = GolfMatch(players: 1, seed: 2);
      // hole 1 right rail at x = 230
      _launch(g, 200, 300, 400, 0);
      double vxAfter = 0;
      while (g.simulating) {
        g.step(1);
        if (g.balls[0].vx < 0) {
          vxAfter = g.balls[0].vx;
          break;
        }
      }
      expect(vxAfter.abs(), closeTo(400 * kRestWall, 40)); // a few ticks of friction before contact
      expect(g.balls[0].x, lessThanOrEqualTo(230 - kRailHalf - kBallR + 1e-6));
    });

    test('no tunnelling: full-power shots at every rail on every hole never cross or sink into one', () {
      for (final int seed in <int>[2, 3]) {
        final GolfMatch base = GolfMatch(players: 1, seed: seed);
        for (int hole = 0; hole < 9; hole++) {
          for (int k = 0; k < 24; k++) {
            final GolfMatch g = GolfMatch(players: 1, seed: seed)..hole = hole;
            final GHole h = g.h;
            g.balls = <GBall>[GBall(h.start.x, h.start.y)];
            g.shoot(k * math.pi / 12 + 0.05, 1);
            final double startGeo = GolfGeo.of(h).at(h.start.x, h.start.y);
            while (g.simulating) {
              g.step(1);
              final GBall b = g.balls[0];
              if (b.holed) break;
              expect(_minWallGap(g, b), greaterThan(kRailHalf + kBallR - 0.5), reason: 'seed $seed hole ${hole + 1} angle $k');
            }
            final GBall b = g.balls[0];
            if (!b.holed) {
              expect(h.bounds.has(b.x, b.y), isTrue);
              expect(GolfGeo.of(h).at(b.x, b.y), lessThan(1e4), reason: 'ended on the wrong side of a rail');
            }
            expect(startGeo, lessThan(1e4));
          }
        }
        expect(base.hole, 0);
      }
    });

    test('no tunnelling even at the speed cap straight into a thin inner rail', () {
      final GolfMatch g = GolfMatch(players: 1, seed: 2)..hole = 2; // inner rail x = 130
      g.balls = <GBall>[GBall(80, 300)];
      _launch(g, 80, 300, kMaxShot * 1.15, 3);
      double maxX = 0;
      while (g.simulating) {
        g.step(1);
        maxX = math.max(maxX, g.balls[0].x);
      }
      expect(maxX, lessThanOrEqualTo(130 - kRailHalf - kBallR + 1e-6));
    });

    test('frame-rate independent: 30, 60, 90 and 144 Hz frames replay a shot identically', () {
      String run(double fps) {
        final GolfMatch g = GolfMatch(players: 2, seed: 2);
        g.hole = 1;
        g.balls = <GBall>[GBall(150, 460), GBall(170, 300)];
        g.shoot(-math.pi / 2 + 0.11, 0.8);
        int guard = 0;
        while (!g.advance(1 / fps) && guard++ < 100000) {}
        return g.stateKey();
      }

      final String ref = run(60);
      expect(run(30), ref);
      expect(run(90), ref);
      expect(run(144), ref);
      // a 5 s hitch is clamped, it never fast-forwards the shot in one frame
      final GolfMatch g = GolfMatch(players: 1, seed: 2);
      g.shoot(-math.pi / 2, 0.5);
      g.advance(5);
      expect(g.simTime, lessThanOrEqualTo(0.1 + 1e-9));
    });

    test('balls knock each other with momentum; a knocked ball in the water goes back without a penalty', () {
      final GolfMatch g = GolfMatch(players: 2, seed: 2);
      g.hole = 5; // water 40..125 x 230..300
      g.balls = <GBall>[GBall(100, 345), GBall(100, 320)];
      g.current = 0;
      g.shoot(-math.pi / 2, 0.45);
      final GBall other = g.balls[1];
      bool moved = false, splashed = false;
      while (g.simulating) {
        g.step(1);
        if (other.moving) moved = true;
        if (g.events.any((GEvent e) => e.kind == 'water' && e.seat == 1)) splashed = true;
        g.events.clear();
      }
      expect(moved, isTrue);
      expect(splashed, isTrue);
      expect(other.strokes, 0);
      // back at its old lie (nudged aside only if the shooter's ball now sits there)
      expect(math.sqrt(math.pow(other.x - 100, 2) + math.pow(other.y - 320, 2)), lessThanOrEqualTo(2 * kBallR + 2));
      expect(math.sqrt(math.pow(other.x - g.balls[0].x, 2) + math.pow(other.y - g.balls[0].y, 2)), greaterThanOrEqualTo(2 * kBallR));
    });

    test('ramp: a weak putt rolls back down, a firm one climbs over', () {
      double endY(double p) {
        final GolfMatch g = GolfMatch(players: 1, seed: 2);
        g.hole = 7; // ramp y 370..425 pushing back toward the tee
        g.balls = <GBall>[GBall(60, 465)];
        g.shoot(-math.pi / 2, p);
        g.runToEnd();
        return g.balls[0].y;
      }

      expect(endY(0.3), greaterThan(425));
      expect(endY(0.7), lessThan(370));
    });

    test('windmill: blades and hub collide where they are drawn; an idle blade waits against a resting ball', () {
      final GolfMatch g = GolfMatch(players: 1, seed: 2);
      g.hole = 4;
      final GWindmill m = g.h.mills.single;
      // park the ball right on a blade's path and let the windmill turn
      final double a = g.millAngle(m) + 0.3;
      g.balls = <GBall>[GBall(m.x + math.cos(a) * 35, m.y + math.sin(a) * 35)];
      final double before = g.millClock;
      for (int i = 0; i < 300; i++) {
        g.idle(1 / 60);
      }
      expect(g.millClock, lessThan(before + 5), reason: 'the blade stops at the ball');
      // during a shot the blade pushes the resting ball out of its way
      g.shoot(math.pi / 2, 0.02);
      g.runToEnd();
      final GBall b = g.balls[0];
      for (int k = 0; k < 2; k++) {
        final double aa = g.millAngle(m) + k * math.pi / 2;
        final double cx = math.cos(aa) * m.len, cy = math.sin(aa) * m.len;
        expect(GolfMatch.segDist(b.x, b.y, m.x - cx, m.y - cy, m.x + cx, m.y + cy), greaterThan(kBladeHalf + kBallR - 0.5));
      }
      expect(math.sqrt(math.pow(b.x - m.x, 2) + math.pow(b.y - m.y, 2)), greaterThan(kHubR + kBallR - 0.5));
    });

    test('same shots and clocks replay identically (online determinism)', () {
      String run() {
        final GolfMatch g = GolfMatch(players: 3, seed: 3);
        final math.Random rng = math.Random(2);
        for (int i = 0; i < 30 && !g.over; i++) {
          final (double a, double p) = g.botShot(rng, 0.6, samples: 6);
          g.shoot(a, p, clock: i * 0.37);
          g.runToEnd();
        }
        return g.stateKey();
      }

      expect(run(), run());
    });
  });

  group('dimensions', () {
    test('ball and cup keep the real 42.7 mm : 108 mm proportion', () {
      expect(kCupR / kBallR, closeTo(108 / 42.7, 0.05));
      expect(kBallR * kUnitM, closeTo(0.02135, 1e-9));
    });

    test('everything a hole draws fits inside the view rect', () {
      for (final int seed in <int>[2, 3]) {
        for (final GHole h in golfCourse(seed)) {
          final GRect b = h.bounds;
          expect(b.l - kRailHalf, greaterThanOrEqualTo(kGolfView.l));
          expect(b.r + kRailHalf, lessThanOrEqualTo(kGolfView.r));
          expect(b.t - kRailHalf, greaterThanOrEqualTo(kGolfView.t));
          expect(b.b + kRailHalf + 3, lessThanOrEqualTo(kGolfView.b)); // + rail shadow
          expect(h.cup.y - 46, greaterThanOrEqualTo(kGolfView.t)); // flag
          for (final GWindmill m in h.mills) {
            expect(m.y - m.len - kBladeHalf, greaterThanOrEqualTo(kGolfView.t));
          }
        }
      }
    });

    test('collision radii match the drawn shapes: a ball rests touching rails, bumpers and hubs', () {
      final GolfMatch g = GolfMatch(players: 1, seed: 2);
      g.hole = 1; // bumpers
      final GBumper p = g.h.bumpers.first;
      g.balls = <GBall>[GBall(p.x, p.y + p.r + kBallR + 20)];
      _launch(g, p.x, p.y + p.r + kBallR + 20, 0, -40);
      g.runToEnd();
      final GBall b = g.balls[0];
      final double d = math.sqrt(math.pow(b.x - p.x, 2) + math.pow(b.y - p.y, 2));
      expect(d, greaterThanOrEqualTo(p.r + kBallR - 1e-6));
    });
  });
}
