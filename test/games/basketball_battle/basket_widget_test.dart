import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/basketball_battle/basketball_battle_entry.dart';
import 'package:nexora/games/basketball_battle/core/basket_core.dart';
import 'package:nexora/games/basketball_battle/ui/basket_game.dart';
import 'package:nexora/games/core/game_contract.dart';

GameLaunch _launch(List<GameResult> results, {int players = 2, BotDifficulty d = BotDifficulty.normal}) => GameLaunch(
      gameId: 'basketball_battle',
      mode: GameMode.vsBot,
      difficulty: d,
      playerName: 'Tester',
      isFa: false,
      fancyEffects: false,
      reducedMotion: true,
      soundOn: false,
      seed: 7,
      playerCount: players,
      onFinish: results.add,
    );

/// Phone sizes (logical) with their status-bar / notch and gesture-bar insets.
const List<(String, Size, EdgeInsets)> kScreens = <(String, Size, EdgeInsets)>[
  ('360x640', Size(360, 640), EdgeInsets.only(top: 24)),
  ('393x873', Size(393, 873), EdgeInsets.only(top: 47, bottom: 34)),
  ('412x915', Size(412, 915), EdgeInsets.only(top: 32, bottom: 24)),
  ('800x1280 tablet', Size(800, 1280), EdgeInsets.only(top: 24, bottom: 20)),
];

Future<void> _pumpGame(WidgetTester tester, Size size, EdgeInsets pad, GameLaunch l) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  tester.view.padding = FakeViewPadding(top: pad.top * 2, bottom: pad.bottom * 2);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: buildBasketballBattleGame(l))));
}

Future<void> _run(WidgetTester tester, Duration total) async {
  const Duration frame = Duration(milliseconds: 50);
  for (int n = total.inMilliseconds ~/ 50; n > 0; n--) {
    await tester.pump(frame);
  }
}

void main() {
  group('layout and hitboxes', () {
    for (final (String name, Size size, EdgeInsets pad) in kScreens) {
      test('$name: same 9:16 court, inside the safe area and below the HUD', () {
        final BasketLayout lay =
            BasketLayout.fit(size.width, size.height, padTop: pad.top, padBottom: pad.bottom);
        expect(lay.width / lay.height, closeTo(kCanvasW / kCanvasH, 1e-9));
        expect(lay.oy, greaterThanOrEqualTo(pad.top + BasketLayout.kHudHeight - 1e-9));
        expect(lay.oy + lay.height, lessThanOrEqualTo(size.height - pad.bottom + 1e-9));
        expect(lay.ox, greaterThanOrEqualTo(0));
        expect(lay.ox + lay.width, lessThanOrEqualTo(size.width + 1e-9));
        // it fills one dimension of the safe area
        final bool fillsW = (lay.width - size.width).abs() < 1e-6;
        final bool fillsH = (lay.height - (lay.areaBottom - lay.areaTop)).abs() < 1e-6;
        expect(fillsW || fillsH, isTrue);
        // screen proportions: ball vs ring at the rim's depth are the real ones on every phone
        final ({double cx, double cy, double r}) b = ballOnCanvas(0, kRimHeight, kRimZ, kBallR);
        final ({double cx, double cy, double halfW}) ring = ringOnCanvas(0, kRimHeight, kRimZ, kRimInnerR);
        expect((b.r * lay.scale) / (ring.halfW * lay.scale), closeTo(kBallR / kRimInnerR, 1e-9));
        // swipe round trip screen <-> canvas
        final (double sx, double sy) = lay.toScreen(120, 300);
        final (double cx, double cy) = lay.toCanvas(sx, sy);
        expect(cx, closeTo(120, 1e-9));
        expect(cy, closeTo(300, 1e-9));
      });
    }

    test('the drawn backboard is the physics plate', () {
      for (final double hx in <double>[-kSlideAmp, 0, 0.37]) {
        final ({double l, double t, double r, double b}) q =
            boardOnCanvas(hx, kBoardW, kBoardBottom, kBoardH, kBoardZ);
        final CanvasPoint tl = BasketCamera.project(hx - kBoardW / 2, kBoardBottom + kBoardH, kBoardZ);
        final CanvasPoint br = BasketCamera.project(hx + kBoardW / 2, kBoardBottom, kBoardZ);
        expect(q.l, tl.x);
        expect(q.t, tl.y);
        expect(q.r, br.x);
        expect(q.b, br.y);
        // a ball touching the board face is drawn overlapping the board rectangle
        final ({double cx, double cy, double r}) ball = ballOnCanvas(hx, 3.4, kBoardZ - kBallR, kBallR);
        expect(ball.cx, inInclusiveRange(q.l, q.r));
        expect(ball.cy, inInclusiveRange(q.t, q.b));
      }
    });

    test('clock reads m:ss', () {
      expect(basketClock(60), '1:00');
      expect(basketClock(59.2), '1:00');
      expect(basketClock(9.01), '0:10');
      expect(basketClock(0), '0:00');
    });

    test('result: a full tie for first is a draw, otherwise win/loss', () {
      final GameLaunch l = _launch(<GameResult>[]);
      final GameResult draw = basketResult(l, <int, BasketLine>{0: const BasketLine(10, 4, 8), 1: const BasketLine(10, 4, 8)});
      expect(draw.outcome, GameOutcome.draw);
      expect(draw.winnerSeats, isEmpty);
      final GameResult win = basketResult(l, <int, BasketLine>{0: const BasketLine(10, 4, 6), 1: const BasketLine(10, 4, 8)});
      expect(win.outcome, GameOutcome.win);
      expect(win.winnerSeats, <int>[0]);
      final GameResult loss = basketResult(l, <int, BasketLine>{0: const BasketLine(3, 1, 8), 1: const BasketLine(10, 4, 8)});
      expect(loss.outcome, GameOutcome.loss);
      expect(loss.winnerSeats, <int>[1]);
    });
  });

  for (final (String name, Size size, EdgeInsets pad) in kScreens) {
    testWidgets('$name: HUD clear of the court, swipe shoots, no overflow', (WidgetTester tester) async {
      final List<GameResult> results = <GameResult>[];
      await _pumpGame(tester, size, pad, _launch(results, players: 4));
      await _run(tester, const Duration(milliseconds: 4200)); // countdown + a second of play
      expect(find.text('1:00'), findsNothing, reason: 'the clock is running');
      final BasketLayout lay = BasketLayout.fit(size.width, size.height, padTop: pad.top, padBottom: pad.bottom);
      final Rect clock = tester.getRect(find.byKey(const ValueKey<String>('bb-clock')));
      expect(clock.top, greaterThanOrEqualTo(pad.top + 56), reason: 'below the host buttons');
      expect(clock.bottom, lessThanOrEqualTo(lay.oy + 1));
      expect(clock.right, lessThanOrEqualTo(size.width));
      for (int s = 0; s < 4; s++) {
        final Rect pill = tester.getRect(find.byKey(ValueKey<String>('bb-seat-$s')));
        expect(pill.bottom, lessThanOrEqualTo(lay.oy + 1));
      }
      expect(find.text('Swipe up towards the hoop'), findsOneWidget);
      // swipe from the ball straight up towards the rim
      final ({double cx, double cy, double r}) ball = ballOnCanvas(0, kReleaseY, kReleaseZ, kBallR);
      final (double bx, double by) = lay.toScreen(ball.cx, ball.cy);
      await tester.timedDragFrom(Offset(bx, by), Offset(0, -260 * lay.scale), const Duration(milliseconds: 180));
      await _run(tester, const Duration(milliseconds: 300));
      expect(find.text('Swipe up towards the hoop'), findsNothing, reason: 'the swipe threw the ball');
      await _run(tester, const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a whole match against bots ends and reports exactly one result', (WidgetTester tester) async {
    final List<GameResult> results = <GameResult>[];
    await _pumpGame(tester, const Size(393, 873), const EdgeInsets.only(top: 47, bottom: 34), _launch(results, players: 3));
    await _run(tester, const Duration(seconds: 70));
    expect(results, hasLength(1));
    final GameResult r = results.single;
    expect(r.scores, hasLength(3));
    expect(r.outcome, isNot(GameOutcome.win), reason: 'a player who never shoots cannot win against shooting bots');
    expect(r.durationMs, 60000);
    await _run(tester, const Duration(seconds: 3));
    expect(results, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
