import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/core/game_contract.dart';
import 'package:nexora/games/kart_racing/core/kart_core.dart';
import 'package:nexora/games/kart_racing/kart_racing_entry.dart';
import 'package:nexora/games/kart_racing/ui/kart_layout.dart';

/// Screen sizes (logical px) with realistic system insets: status bar / notch on top, gesture bar at the bottom.
const List<(Size, EdgeInsets)> kScreens = <(Size, EdgeInsets)>[
  (Size(360, 640), EdgeInsets.only(top: 24)),
  (Size(393, 873), EdgeInsets.only(top: 47, bottom: 34)),
  (Size(412, 915), EdgeInsets.only(top: 32, bottom: 24)),
  (Size(800, 1280), EdgeInsets.only(top: 24, bottom: 20)),
];

bool _inside(Rect outer, Rect r) =>
    r.left >= outer.left - 0.01 && r.top >= outer.top - 0.01 && r.right <= outer.right + 0.01 && r.bottom <= outer.bottom + 0.01;

void main() {
  group('layout', () {
    for (final (Size size, EdgeInsets pad) in kScreens) {
      test('${size.width.toInt()}x${size.height.toInt()}: everything in the safe area, nothing overlaps', () {
        final KartLayout l = KartLayout.compute(size, pad);
        expect(l.safe, Rect.fromLTRB(pad.left, pad.top, size.width - pad.right, size.height - pad.bottom));
        final List<Rect> ui = <Rect>[...l.hud, ...l.controls];
        for (final Rect r in ui) {
          expect(_inside(l.safe, r), isTrue, reason: '$r');
          expect(r.overlaps(l.exitButton), isFalse, reason: 'host exit button covered by $r');
        }
        for (int i = 0; i < ui.length; i++) {
          for (int j = i + 1; j < ui.length; j++) {
            expect(ui[i].overlaps(ui[j]), isFalse, reason: '${ui[i]} vs ${ui[j]}');
          }
        }
        // the player's kart (any heading) is fully visible, clear of the HUD and the controls
        final Rect kart = l.kartScreenBox;
        expect(_inside(l.safe, kart), isTrue);
        for (final Rect r in ui) {
          expect(kart.overlaps(r), isFalse, reason: 'kart $kart vs $r');
        }
        // the reference view of the world always fits: same framing on every screen
        expect(KartLayout.viewW * l.zoomBase <= l.safe.width + 0.01, isTrue);
        expect(KartLayout.viewH * l.zoomBase <= l.safe.height + 0.01, isTrue);
        // enough road ahead of the kart to react (world units, at the most zoomed-out speed)
        final double ahead = (l.focal.dy - l.safe.top) / (l.zoomBase * KartLayout.minZoomFactor);
        expect(ahead > 420, isTrue, reason: 'road ahead $ahead');
        // buttons stay comfortably tappable
        for (final Rect r in l.controls) {
          expect(r.width >= 48, isTrue);
          expect(r.width, closeTo(r.height, 1e-6));
        }
      });
    }

    test('kart and track keep the same proportions and on-screen size on every phone', () {
      final List<double> shares = <double>[];
      for (final (Size size, EdgeInsets pad) in kScreens) {
        final KartLayout l = KartLayout.compute(size, pad);
        final KartTrack t = KartTrack.generate(1);
        final Size ks = l.kartScreenSize;
        // uniform scale: the drawn kart keeps its aspect and its ratio to the track width
        expect(ks.width / ks.height, closeTo(KartDims.length / KartDims.width, 1e-9));
        expect(ks.width / (t.width * l.zoomBase), closeTo(KartDims.length / t.width, 1e-9));
        shares.add(ks.width / l.safe.width);
        expect(ks.width >= 28, isTrue, reason: 'kart readable: ${ks.width}px');
      }
      // phones: the kart takes the same share of the screen width
      for (int i = 1; i < 3; i++) {
        expect(shares[i], closeTo(shares[0], 0.002));
      }
      // tablet: never smaller on screen than on a phone, never twice as big relative to the width
      expect(shares[3] > shares[0] * 0.75, isTrue);
    });
  });

  group('widget', () {
    for (final (Size size, EdgeInsets pad) in kScreens) {
      testWidgets('${size.width.toInt()}x${size.height.toInt()}: countdown and racing render without errors',
          (WidgetTester tester) async {
        tester.view.physicalSize = size * 2;
        tester.view.devicePixelRatio = 2;
        tester.view.padding = FakeViewPadding(top: pad.top * 2, bottom: pad.bottom * 2);
        addTearDown(tester.view.reset);
        final List<GameResult> results = <GameResult>[];
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: buildKartRacingGame(GameLaunch(
              gameId: 'kart_racing',
              mode: GameMode.vsBot,
              difficulty: BotDifficulty.normal,
              playerName: 'Tester',
              isFa: false,
              fancyEffects: false,
              reducedMotion: true,
              soundOn: false,
              playerCount: 4,
              seed: 3,
              onFinish: results.add,
            )),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 16));
        expect(find.text('3'), findsOneWidget); // countdown banner
        // countdown + a few seconds of racing, steering right part of the time
        for (int i = 0; i < 60 * 6; i++) {
          if (i == 250) {
            await tester.startGesture(tester.getCenter(find.byIcon(Icons.arrow_forward_rounded)));
          }
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(tester.takeException(), isNull);
        expect(find.textContaining('LAP 1/3'), findsOneWidget);
        // the controls sit in the safe area
        final Rect drift = tester.getRect(find.text('DRIFT'));
        expect(drift.bottom <= size.height - pad.bottom, isTrue);
        expect(results, isEmpty);
      });
    }
  });
}
