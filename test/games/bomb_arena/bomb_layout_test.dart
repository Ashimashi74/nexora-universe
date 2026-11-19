import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/arcade_kit/arcade_controls.dart';
import 'package:nexora/games/arcade_kit/arcade_joystick.dart';
import 'package:nexora/games/bomb_arena/bomb_arena_entry.dart';
import 'package:nexora/games/bomb_arena/core/bomb_core.dart';
import 'package:nexora/games/bomb_arena/ui/bomb_game.dart';
import 'package:nexora/games/bomb_arena/ui/bomb_layout.dart';
import 'package:nexora/games/core/game_contract.dart';

class _Screen {
  const _Screen(this.name, this.size, this.dpr, this.pad);
  final String name;
  final Size size;
  final double dpr;
  final EdgeInsets pad; // status bar / notch on top, gesture bar at the bottom
}

const List<_Screen> _screens = <_Screen>[
  _Screen('360x640', Size(360, 640), 2, EdgeInsets.only(top: 24)),
  _Screen('393x873', Size(393, 873), 2.75, EdgeInsets.only(top: 47, bottom: 34)),
  _Screen('412x915', Size(412, 915), 2.625, EdgeInsets.only(top: 32, bottom: 24)),
  _Screen('800x1280 tablet', Size(800, 1280), 2, EdgeInsets.only(top: 24, bottom: 16)),
];

bool onPixelGrid(double v, double dpr) => ((v * dpr) - (v * dpr).roundToDouble()).abs() < 1e-6;

void main() {
  group('layout', () {
    for (final _Screen s in _screens) {
      test('${s.name}: board fits the safe area, keeps 13:11 and sits on the pixel grid', () {
        final BombLayout l = BombLayout.compute(s.size, s.pad, s.dpr, cols: BombArena.w, rows: BombArena.h);
        final Rect b = l.board, f = l.framed;
        expect(b.width / b.height, closeTo(BombArena.w / BombArena.h, 1e-9));
        expect(onPixelGrid(l.tile, s.dpr), isTrue, reason: 'tile ${l.tile}');
        expect(onPixelGrid(l.origin.dx, s.dpr) && onPixelGrid(l.origin.dy, s.dpr), isTrue);
        // inside the safe area, below the HUD and the host exit button, above the controls
        expect(f.left, greaterThanOrEqualTo(s.pad.left));
        expect(f.right, lessThanOrEqualTo(s.size.width - s.pad.right));
        expect(l.hudTop, greaterThanOrEqualTo(s.pad.top + 56));
        expect(f.top, greaterThanOrEqualTo(l.hudTop + BombLayout.hudHeight - 1e-9));
        expect(f.bottom, lessThanOrEqualTo(l.controlsTop + 1e-9));
        expect(l.controlsTop, lessThanOrEqualTo(s.size.height - s.pad.bottom - BombLayout.controlsHeight + 1e-9));
        // big enough to play, and as big as the limiting side allows (within one physical pixel per tile)
        expect(l.tile, greaterThanOrEqualTo(24));
        final double maxW = (s.size.width - s.pad.horizontal - 2 * BombLayout.sideMargin) / (BombArena.w + 2 * BombLayout.frame);
        final double maxH = (l.controlsTop - 8 - (l.hudTop + BombLayout.hudHeight + 8)) / (BombArena.h + 2 * BombLayout.frame);
        expect(l.tile, greaterThan((maxW < maxH ? maxW : maxH) - 1 / s.dpr - 1e-9));
        // tiles tile the board exactly, and tile space maps back and forth without drift
        for (int x = 0; x < BombArena.w - 1; x++) {
          expect(l.tileRect(x, 3).right, closeTo(l.tileRect(x + 1, 3).left, 1e-9));
          expect(onPixelGrid(l.tileRect(x, 3).right, s.dpr), isTrue, reason: 'every tile edge on a physical pixel');
        }
        for (int y = 0; y < BombArena.h; y++) {
          expect(onPixelGrid(l.tileRect(0, y).top, s.dpr), isTrue);
        }
        expect((l.tileRect(BombArena.w - 1, BombArena.h - 1).bottomRight - b.bottomRight).distance, lessThan(1e-9));
        final Offset p = l.toScreen(6.5, 5.5);
        expect((l.toTiles(p) - const Offset(6.5, 5.5)).distance, lessThan(1e-9));
        expect(l.board.center.dx, closeTo((s.pad.left + s.size.width - s.pad.right) / 2, 1 / s.dpr));
      });
    }
  });

  group('widget', () {
    for (final _Screen s in _screens) {
      testWidgets('${s.name}: plays against bots without errors, nothing overlaps the board', (WidgetTester tester) async {
        tester.view.physicalSize = s.size * s.dpr;
        tester.view.devicePixelRatio = s.dpr;
        tester.view.padding = FakeViewPadding(top: s.pad.top * s.dpr, bottom: s.pad.bottom * s.dpr);
        tester.view.viewPadding = FakeViewPadding(top: s.pad.top * s.dpr, bottom: s.pad.bottom * s.dpr);
        addTearDown(tester.view.reset);
        final List<GameResult> results = <GameResult>[];
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: buildBombArenaGame(GameLaunch(
              gameId: 'bomb_arena',
              mode: GameMode.vsBot,
              difficulty: BotDifficulty.normal,
              playerName: 'Tester',
              isFa: false,
              fancyEffects: true,
              reducedMotion: false,
              soundOn: false,
              playerCount: 4,
              seed: 3,
              onFinish: results.add,
            )),
          ),
        ));
        for (int i = 0; i < 60 * 6; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(tester.takeException(), isNull);
        final dynamic state = tester.state(find.byType(BombGame));
        final BombLayout l = (state as dynamic).debugLayout as BombLayout;
        expect(l.size, s.size);
        expect(l.padding.top, closeTo(s.pad.top, 1e-6));
        final Rect board = l.framed;
        // controls live below the board, HUD above it
        for (final Element e in find.byType(ArcadePadButton).evaluate()) {
          final Rect r = tester.getRect(find.byWidget(e.widget));
          expect(r.top, greaterThanOrEqualTo(board.bottom - 1e-6), reason: 'button $r vs board $board');
          expect(r.bottom, lessThanOrEqualTo(s.size.height - s.pad.bottom + 1e-6));
        }
        final Rect stick = tester.getRect(find.byType(ArcadeJoystick));
        expect(stick.top, greaterThanOrEqualTo(board.bottom - 1e-6));
        final Rect timer = tester.getRect(find.textContaining('R1'));
        expect(timer.bottom, lessThanOrEqualTo(board.top + 1e-6));
        expect(timer.top, greaterThanOrEqualTo(s.pad.top + 56));
      });
    }

    test('drawn match reports a draw with no winners', () {
      final BombMatch m = BombMatch(seed: 3, count: 2, maxRounds: 1)..over = true;
      final GameResult r = bombResult(
          GameLaunch(
            gameId: 'bomb_arena',
            mode: GameMode.vsBot,
            difficulty: BotDifficulty.normal,
            playerName: 'T',
            isFa: false,
            fancyEffects: false,
            reducedMotion: true,
            soundOn: false,
            onFinish: (_) {},
          ),
          m);
      expect(m.isDraw, isTrue);
      expect(r.outcome, GameOutcome.draw);
      expect(r.winnerSeats, isEmpty);
      m.wins[0] = 2;
      final GameResult w = bombResult(
          GameLaunch(
            gameId: 'bomb_arena',
            mode: GameMode.vsBot,
            difficulty: BotDifficulty.normal,
            playerName: 'T',
            isFa: false,
            fancyEffects: false,
            reducedMotion: true,
            soundOn: false,
            onFinish: (_) {},
          ),
          m);
      expect(w.outcome, GameOutcome.win);
      expect(w.winnerSeats, <int>[0]);
    });
  });
}
