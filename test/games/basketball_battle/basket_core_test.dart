import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/basketball_battle/core/basket_core.dart';

/// A fresh court with the clock running and the ball on a known spot.
BasketCourt court({double spot = 0, int seed = 3}) {
  final BasketCourt c = BasketCourt(seed: seed, countdown: 0);
  c.restX = spot;
  c.x = spot;
  return c;
}

/// Shoots at lateral [tx] with a swipe [dl] canvas units longer than the perfect one; returns the points scored and
/// every event the shot produced.
(int, List<String>) shoot(BasketCourt c, {double tx = 0, double dl = 0}) {
  final int before = c.score;
  final (double sx, double sy) = c.swipeFor(tx, swipeSpeed(swipeLengthFor(idealSpeed(c.restX, tx)) + dl));
  expect(c.throwBall(sx, sy), isTrue);
  final List<String> ev = <String>[];
  for (int i = 0; i < 600 && c.flying; i++) {
    c.step(1 / 60);
    ev.addAll(c.events.map((BEvent e) => e.kind));
    c.events.clear();
  }
  expect(c.flying, isFalse, reason: 'every shot is decided');
  return (c.score - before, ev);
}

/// Where to aim so the ball drops through a (possibly sliding) hoop.
double lead(BasketCourt c) {
  final double v = idealSpeed(c.restX, c.hoopX);
  return c.predictHoopX(flightTime(c.restX, c.hoopX, v));
}

/// Waits until the next ball is in the shooter's hands.
void nextBall(BasketCourt c) {
  for (int i = 0; i < 600 && !c.ready && !c.over; i++) {
    c.step(1 / 60);
  }
  c.events.clear();
}

void main() {
  group('regulation dimensions', () {
    test('ball, ring, backboard and distances are real-world sizes', () {
      expect(kRimHeight, 3.05);
      expect(kRimInnerR * 2, closeTo(0.457, 0.001)); // 18 in ring
      expect(kBallR * 2 * math.pi, closeTo(0.75, 0.01)); // size 7 circumference
      expect(kBallR / kRimInnerR, closeTo(0.522, 0.005)); // the ball nearly half the ring
      expect(kBoardW, 1.83);
      expect(kBoardH, 1.07);
      expect(kBoardBottom + kBoardH, closeTo(3.97, 0.001));
      expect(kBoardZ - kReleaseZ, closeTo(4.6, 0.01)); // free-throw line is 15 ft from the board
      expect(kBoardZ - kRimZ - kRimInnerR, closeTo(0.1524, 1e-9)); // 6 in from board to ring
    });

    test('the camera draws the ball and the ring in true proportion at the same depth', () {
      final ({double cx, double cy, double r}) b = ballOnCanvas(0, kRimHeight, kRimZ, kBallR);
      final ({double cx, double cy, double halfW}) ring = ringOnCanvas(0, kRimHeight, kRimZ, kRimInnerR);
      expect(b.r / ring.halfW, closeTo(kBallR / kRimInnerR, 1e-9));
      final ({double l, double t, double r, double b}) bd = boardOnCanvas(0, kBoardW, kBoardBottom, kBoardH, kBoardZ);
      expect((bd.r - bd.l) / (bd.b - bd.t), closeTo(kBoardW / kBoardH, 1e-9));
      // nearer things look bigger: the ball in the hands is larger than the ball at the rim
      expect(ballOnCanvas(0, kReleaseY, kReleaseZ, kBallR).r, greaterThan(b.r));
    });

    test('the whole scene stays inside the 360x640 canvas', () {
      for (final double spot in <double>[-kRestHalfRange, kRestHalfRange]) {
        final ({double cx, double cy, double r}) b = ballOnCanvas(spot, kReleaseY, kReleaseZ, kBallR);
        expect(b.cx - b.r, greaterThanOrEqualTo(0));
        expect(b.cx + b.r, lessThanOrEqualTo(kCanvasW));
        expect(b.cy + b.r, closeTo(612, 0.01));
      }
      for (final double hx in <double>[-kSlideAmp, kSlideAmp]) {
        final ({double l, double t, double r, double b}) bd = boardOnCanvas(hx, kBoardW, kBoardBottom, kBoardH, kBoardZ);
        expect(bd.l, greaterThanOrEqualTo(0));
        expect(bd.r, lessThanOrEqualTo(kCanvasW));
        expect(bd.t, greaterThan(0));
      }
      // even the hardest possible swipe keeps the ball's arc on the canvas
      final BasketCourt c = court();
      c.throwBall(0, -kSwipeMax);
      double top = 1e9;
      while (c.flying) {
        c.step(1 / 120);
        final ({double cx, double cy, double r}) b = ballOnCanvas(c.x, c.y, c.z, kBallR);
        top = math.min(top, b.cy - b.r);
      }
      expect(top, greaterThan(0));
    });

    test('swipe aim is the exact inverse of swipeFor', () {
      final BasketCourt c = court(spot: 0.3);
      for (final double tx in <double>[-0.5, -0.1, 0, 0.2, 0.55]) {
        final (double sx, double sy) = c.swipeFor(tx, 8.3);
        expect(BasketCourt.aimFromSwipe(0.3, sx, sy), closeTo(tx, 1e-9));
        expect(swipeSpeed(math.sqrt(sx * sx + sy * sy)), closeTo(8.3, 1e-9));
      }
    });
  });

  group('rules and scoring', () {
    test('a perfect shot is a swish worth 3', () {
      final BasketCourt c = court();
      final (int pts, List<String> ev) = shoot(c);
      expect(pts, 3);
      expect(ev, contains('swish'));
      expect(ev, isNot(contains('rim')));
      expect(c.streak, 1);
      expect(c.made, 1);
      expect(c.shots, 1);
      expect(c.swishes, 1);
    });

    test('a make off the rim is worth 2, a bank shot off the board is worth 2', () {
      bool rimIn = false, bank = false;
      for (double dl = -40; dl <= 60 && !(rimIn && bank); dl += 2) {
        final BasketCourt c = court();
        final (int pts, List<String> ev) = shoot(c, dl: dl);
        if (pts > 0 && ev.contains('rim')) {
          expect(pts, 2);
          rimIn = true;
        }
        if (pts > 0 && ev.contains('board')) {
          expect(pts, 2);
          bank = true;
        }
        if (pts > 0 && !ev.contains('rim') && !ev.contains('board')) expect(pts, 3);
      }
      expect(rimIn, isTrue, reason: 'some shot rattles in off the rim');
      expect(bank, isTrue, reason: 'some shot banks in off the backboard');
    });

    test('an airball is a miss and resets the streak', () {
      final BasketCourt c = court();
      c.streak = 2;
      final (int pts, List<String> ev) = shoot(c, dl: -200);
      expect(pts, 0);
      expect(ev, contains('miss'));
      expect(c.streak, 0);
      expect(c.made, 0);
      expect(c.shots, 1);
    });

    test('three in a row sets you on fire: the next makes score double until a miss', () {
      final BasketCourt c = court();
      final List<String> all = <String>[];
      for (int i = 0; i < 3; i++) {
        final BasketCourt cc = c;
        cc
          ..restX = 0
          ..x = 0;
        final (int pts, List<String> ev) = shoot(cc, tx: cc.hoopX);
        expect(pts, 3, reason: 'not doubled before the fire starts');
        all.addAll(ev);
        nextBall(cc);
      }
      expect(all.where((String e) => e == 'fire').length, 1);
      expect(c.onFire, isTrue);
      c
        ..restX = 0
        ..x = 0;
      expect(shoot(c, tx: c.hoopX).$1, 6, reason: 'a swish on fire scores double');
      nextBall(c);
      c
        ..restX = 0
        ..x = 0;
      final (int miss, List<String> ev) = shoot(c, dl: -200);
      expect(miss, 0);
      expect(ev, containsAll(<String>['miss', 'fireout']));
      expect(c.onFire, isFalse);
      nextBall(c);
      c
        ..restX = 0
        ..x = 0;
      expect(shoot(c, tx: lead(c)).$1, 3, reason: 'back to normal after the miss');
      expect(c.score, 3 * 3 + 6 + 3);
    });

    test('a ball pushed up through the net and falling back is not a basket', () {
      final BasketCourt c = court();
      c
        ..phase = BallPhase.flying
        ..x = 0
        ..z = kRimZ
        ..y = kRimHeight - 0.4
        ..vx = 0
        ..vz = 0
        ..vy = 4.5;
      for (int i = 0; i < 600 && c.flying; i++) {
        c.step(1 / 60);
      }
      expect(c.score, 0);
      expect(c.streak, 0);
    });

    test('weak or downward swipes are ignored; no throw while the ball is in the air', () {
      final BasketCourt c = court();
      expect(c.throwBall(0, -5), isFalse);
      expect(c.throwBall(30, 200), isFalse);
      expect(c.throwBall(0, -260), isTrue);
      expect(c.throwBall(0, -260), isFalse);
      expect(c.shots, 1);
    });

    test('no shooting during the countdown; the clock starts at GO', () {
      final BasketCourt c = BasketCourt(seed: 1);
      expect(c.throwBall(0, -260), isFalse);
      c.step(1.0); // a long hitch is clamped (0.1 s), it never skips the countdown
      expect(c.time, 0);
      expect(c.countdown, closeTo(2.9, 1e-6));
      for (int i = 0; i < 200; i++) {
        c.step(1 / 60);
      }
      expect(c.countdown, 0);
      expect(c.time, greaterThan(0));
      expect(c.throwBall(0, -260), isTrue);
    });

    test('the hoop stays still below 12 points, then slides smoothly inside its track', () {
      final BasketCourt c = court();
      for (int i = 0; i < 240; i++) {
        c.step(1 / 60);
      }
      expect(c.hoopX, 0);
      c.score = 12;
      double prev = c.hoopX, maxJump = 0, minX = 0, maxX = 0;
      for (int i = 0; i < 600; i++) {
        c.step(1 / 60);
        maxJump = math.max(maxJump, (c.hoopX - prev).abs());
        prev = c.hoopX;
        minX = math.min(minX, c.hoopX);
        maxX = math.max(maxX, c.hoopX);
      }
      expect(maxX, greaterThan(0.3));
      expect(minX, lessThan(-0.3));
      expect(maxX, lessThanOrEqualTo(kSlideAmp + 1e-9));
      expect(maxJump, lessThanOrEqualTo(c.hoopSpeed / 60 + 1e-6));
      final double slow = c.hoopSpeed;
      c.score = 40;
      expect(c.hoopSpeed, greaterThan(slow));
    });

    test('a shot released before the horn still counts (buzzer beater)', () {
      final BasketCourt c = court();
      c.time = 59.9;
      final (double sx, double sy) = c.swipeFor(0, idealSpeed(0, 0));
      expect(c.throwBall(sx, sy), isTrue);
      c.step(0.2);
      expect(c.timeUp, isTrue);
      expect(c.over, isFalse, reason: 'the last ball is still in the air');
      for (int i = 0; i < 300 && !c.over; i++) {
        c.step(1 / 60);
      }
      expect(c.over, isTrue);
      expect(c.score, 3);
      expect(c.throwBall(0, -260), isFalse);
    });

    test('the clock ends the round at exactly 60 s', () {
      final BasketCourt c = court();
      for (int i = 0; i < 61 * 60; i++) {
        c.step(1 / 60);
      }
      expect(c.time, 60);
      expect(c.left, 0);
      expect(c.over, isTrue);
      expect(c.throwBall(0, -300), isFalse);
    });
  });

  group('physics', () {
    test('frame-rate independent: identical match at 30, 60, 144 fps and with jittery frames', () {
      // every run simulates exactly the same span (70 s, half a step of slack against float drift)
      String run(double Function(int) dt) {
        final BasketBot b = BasketBot(seed: 4, skill: 0.62, countdown: 3);
        const double total = 70 + kStep / 2;
        double t = 0;
        for (int i = 0; t < total; i++) {
          final double d = math.min(dt(i), total - t);
          b.step(d);
          t += d;
        }
        final BasketCourt c = b.court;
        expect(b.over, isTrue);
        return '${b.score} ${b.made}/${b.shots} ${c.x.toStringAsFixed(9)} ${c.y.toStringAsFixed(9)} ${c.z.toStringAsFixed(9)}';
      }

      final math.Random r = math.Random(5);
      final String ref = run((_) => 1 / 60);
      expect(run((_) => 1 / 30), ref);
      expect(run((_) => 1 / 144), ref);
      expect(run((_) => 0.004 + r.nextDouble() * 0.046), ref);
    });

    test('no tunnelling: the hardest shot at the board never passes through it', () {
      for (final double tx in <double>[0, 0.5, -0.7]) {
        final BasketCourt c = court();
        c.throwBall(c.swipeFor(tx, swipeSpeed(kSwipeMax)).$1, c.swipeFor(tx, swipeSpeed(kSwipeMax)).$2);
        bool hitBoard = false;
        while (c.flying) {
          final double pz = c.z;
          c.step(1 / 240);
          if (c.events.any((BEvent e) => e.kind == 'board')) hitBoard = true;
          c.events.clear();
          if (pz < kBoardZ && c.z >= kBoardZ) {
            final bool onBoard =
                c.y > kBoardBottom && c.y < kBoardBottom + kBoardH && (c.x - c.hoopX).abs() < kBoardW / 2;
            expect(onBoard, isFalse, reason: 'the ball may only pass the board plane around it');
          }
        }
        expect(hitBoard, isTrue);
      }
    });

    test('the ball bounces off the floor with a basketball\'s restitution', () {
      final BasketCourt c = court();
      c
        ..phase = BallPhase.flying
        ..y = 2
        ..vy = 0;
      double before = 0, after = 0;
      for (int i = 0; i < 480 && after == 0; i++) {
        final double v = c.vy;
        c.step(1 / 240);
        if (v < 0 && c.vy > 0) {
          before = v;
          after = c.vy;
        }
      }
      expect(before, lessThan(-5)); // ~6 m/s after a 1.9 m drop
      expect(after / -before, closeTo(kFloorE, 0.02));
      expect(c.phase, BallPhase.dead, reason: 'touching the floor decides the shot');
      expect(c.streak, 0);
    });

    test('the net slows a made ball', () {
      final BasketCourt c = court();
      final (double sx, double sy) = c.swipeFor(0, idealSpeed(0, 0));
      c.throwBall(sx, sy);
      double vyIn = 0;
      bool sawNet = false;
      while (c.flying) {
        final double before = c.vy;
        c.step(1 / 240);
        if (c.inNet && !sawNet) {
          sawNet = true;
          vyIn = before;
        }
        if (sawNet && c.y < kRimHeight - kNetLen) {
          expect(c.vy.abs(), lessThan(vyIn.abs()));
          break;
        }
      }
      expect(sawNet, isTrue);
    });
  });

  group('bot and match', () {
    test('the bot really shoots: its points come from balls that went in', () {
      final BasketBot b = BasketBot(seed: 2, skill: 0.62);
      int total = 0;
      for (int i = 0; i < 70 * 60; i++) {
        total += b.step(1 / 60);
      }
      expect(b.over, isTrue);
      expect(b.shots, greaterThan(10));
      expect(b.made, greaterThan(0));
      expect(b.made, lessThan(b.shots));
      expect(total, b.score);
      expect(b.score, greaterThanOrEqualTo(b.made * 2));
      expect(b.score, lessThanOrEqualTo(b.made * 6));
    });

    test('harder bots score more on average and stay beatable', () {
      double avg(double skill) {
        int sum = 0;
        for (int s = 1; s <= 6; s++) {
          final BasketBot b = BasketBot(seed: s, skill: skill);
          for (int i = 0; i < 70 * 60; i++) {
            b.step(1 / 60);
          }
          sum += b.score;
        }
        return sum / 6;
      }

      final double easy = avg(0.3), normal = avg(0.62), hard = avg(0.92);
      expect(normal, greaterThan(easy));
      expect(hard, greaterThan(normal));
      expect(hard, lessThan(120));
    });

    test('a full match against three bots ends with every court finished and a ranking', () {
      final BasketMatch m = BasketMatch(seed: 11, botSkills: <double>[0.3, 0.62, 0.92]);
      final BasketCourt me = m.me;
      int myShots = 0;
      for (int i = 0; i < 80 * 60 && !m.over; i++) {
        if (me.ready && me.clockRunning && myShots < 12) {
          final double tx = lead(me);
          final (double sx, double sy) = me.swipeFor(tx, idealSpeed(me.restX, tx));
          if (me.throwBall(sx, sy)) myShots++;
        }
        m.step(1 / 60);
      }
      expect(m.over, isTrue);
      expect(me.shots, 12);
      expect(me.made, greaterThan(8));
      for (final BasketBot b in m.bots) {
        expect(b.over, isTrue);
        expect(b.shots, greaterThan(8));
      }
      final ({List<int> order, List<int> top}) r = rankBasket(m.lines);
      expect(r.order.toSet(), <int>{0, 1, 2, 3});
      for (int i = 1; i < r.order.length; i++) {
        expect(m.lines[r.order[i - 1]]!.score, greaterThanOrEqualTo(m.lines[r.order[i]]!.score));
      }
    });

    test('ranking: points, then accuracy; a full tie at the top is shared; forfeits go last', () {
      final ({List<int> order, List<int> top}) a = rankBasket(<int, BasketLine>{
        0: const BasketLine(20, 8, 16),
        1: const BasketLine(20, 8, 12),
        2: const BasketLine(25, 9, 20),
      });
      expect(a.order, <int>[2, 1, 0]);
      expect(a.top, <int>[2]);
      final ({List<int> order, List<int> top}) b = rankBasket(<int, BasketLine>{
        0: const BasketLine(18, 7, 14),
        1: const BasketLine(18, 7, 14),
        2: const BasketLine(4, 2, 10),
      });
      expect(b.top, <int>[0, 1]);
      final ({List<int> order, List<int> top}) c = rankBasket(<int, BasketLine>{
        0: const BasketLine(5, 2, 9),
        1: const BasketLine(40, 15, 20),
      }, forfeited: <int>{1});
      expect(c.order, <int>[0, 1]);
      expect(c.top, <int>[0]);
    });
  });
}
