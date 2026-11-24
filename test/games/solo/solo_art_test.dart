import 'dart:ui' show PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/arcade_kit/arcade_skin.dart';
import 'package:nexora/games/solo/solo_registry.dart';
import 'package:nexora/games/solo/solo_kit.dart';

/// The solo art layer is the contract every board paints through: if these colours,
/// measurements or primitives drift, a board silently loses contrast or draws off-screen.
/// Every helper is also exercised on degenerate rects, because a board paints one frame at
/// a tiny size before (and while) the shell animates its layout.
void main() {
  group('palette', () {
    test('alpha is clamped so callers cannot overflow a colour', () {
      expect(SoloArt.a(const Color(0xFFFFFFFF), 2).a, 1.0);
      expect(SoloArt.a(const Color(0xFFFFFFFF), -1).a, 0.0);
      expect(SoloArt.a(const Color(0xFFFFFFFF), 0.5).a, closeTo(0.5, 0.01));
    });

    test('lift / sink keep lightness inside 0..1', () {
      final Color white = SoloArt.lift(const Color(0xFFFFFFFF), 0.9);
      final Color black = SoloArt.sink(const Color(0xFF000000), 0.9);
      expect(HSLColor.fromColor(white).lightness, lessThanOrEqualTo(1.0));
      expect(HSLColor.fromColor(black).lightness, greaterThanOrEqualTo(0.0));
    });

    test('mix is a true interpolation at both ends', () {
      const Color a = Color(0xFF102030);
      const Color b = Color(0xFF403020);
      expect(SoloArt.mix(a, b, 0), a);
      expect(SoloArt.mix(a, b, 1), b);
      expect(SoloArt.mix(a, b, 2), b, reason: 'out-of-range t is clamped');
    });

    test('the three semantic tints are distinct from the board accents', () {
      expect(SoloArt.ink, isNot(SoloArt.mute));
      expect(SoloArt.danger, isNot(SoloArt.gold));
      expect(SoloArt.hazard, SoloArt.danger);
    });
  });

  group('metrics', () {
    test('the play band leaves room for the shell HUD and the control deck', () {
      const double height = 800;
      final double band = height - SoloMetrics.hudTop - SoloMetrics.deck;
      expect(band, greaterThan(500), reason: 'a 800px screen must keep a tall playfield');
      expect(SoloMetrics.hudTop, greaterThanOrEqualTo(80), reason: 'the score readout is 40px + chips');
      expect(SoloMetrics.deck, greaterThanOrEqualTo(90), reason: 'two 66px pads + padding');
    });
  });

  group('primitives never throw on degenerate input', () {
    testWidgets('every helper paints on a 1x1 canvas and on a phone canvas', (WidgetTester tester) async {
      final List<Size> sizes = <Size>[const Size(1, 1), const Size(390, 844), const Size(1080, 2400)];
      final ArcadeSkin skin = ArcadeSkin(
        gameId: 'geo_dash',
        bgTop: const Color(0xFF16233F),
        bgBottom: const Color(0xFF04060D),
        accent: const Color(0xFFB8F05A),
        accent2: const Color(0xFFEAFBFF),
        glow: const Color(0xFFB8F05A),
      );
      for (final Size size in sizes) {
        final PictureRecorder rec = PictureRecorder();
        final Canvas canvas = Canvas(rec);
        SoloArt.backdrop(canvas, size, skin: skin, time: 1.5);
        SoloArt.starfield(canvas, size, 2, tint: const Color(0xFFFFFFFF));
        SoloArt.ribbons(canvas, size, 1, const Color(0xFF00FFCC), const Color(0xFF7C4DFF));
        SoloArt.sunset(canvas, size.center(Offset.zero), size.shortestSide * 0.2, const Color(0xFFFFD166),
            const Color(0xFFFF5B62));
        SoloArt.floorGrid(canvas, size, size.height * 0.3, const Color(0xFFB8F05A));
        SoloArt.ridge(canvas, size, size.height * 0.6, const Color(0xFF101A2E));
        SoloArt.skyline(canvas, size, size.height * 0.7, const Color(0xFF0A1020));
        SoloArt.caustics(canvas, size, 1.2, const Color(0xFF37D9FF));
        SoloArt.road(canvas, size, Rect.fromLTRB(20, 40, size.width - 20, size.height - 40), const Color(0xFFB8F05A), 12);
        SoloArt.speedLines(canvas, size, 3, const Color(0xFFFFFFFF));
        SoloArt.panel(canvas, Rect.fromLTWH(4, 4, size.width - 8, size.height * 0.4), const Color(0xFFB8F05A));
        SoloArt.cube(canvas, Rect.fromLTWH(2, 2, size.width - 4, size.height * 0.5), const Color(0xFFB8F05A));
        SoloArt.orb(canvas, size.center(Offset.zero), size.shortestSide * 0.1, const Color(0xFFFFD166), ring: 1);
        SoloArt.spike(canvas, Offset(size.width * 0.5, size.height * 0.9), size.width * 0.1, size.height * 0.2,
            SoloArt.danger);
        SoloArt.diamond(canvas, size.center(Offset.zero), size.shortestSide * 0.06, SoloArt.hazard);
        SoloArt.barrier(canvas, Rect.fromLTWH(10, 10, size.width - 20, size.height * 0.2), SoloArt.gold);
        SoloArt.blade(canvas, <Offset>[Offset.zero, size.center(Offset.zero), Offset(size.width, size.height)],
            const Color(0xFFFFFFFF), const Color(0xFFB8F05A), 4);
        SoloArt.meter(canvas, Rect.fromLTWH(8, 8, size.width - 16, 5), 1.6, const Color(0xFFB8F05A));
        SoloArt.chip(canvas, const Offset(8, 30), '12 m', SoloArt.ink);
        SoloArt.label(canvas, '', Offset.zero);
        SoloArt.score(canvas, '999', size.center(Offset.zero), accent: const Color(0xFFB8F05A));
        SoloArt.bottomScrim(canvas, size);
        SoloArt.frame(canvas, size, const Color(0xFFB8F05A));
        rec.endRecording().dispose();
      }
      expect(tester.takeException(), isNull);
    });

    test('every registered solo game has the metadata the shell needs', () {
      expect(kSoloDefs, isNotEmpty);
      for (final SoloDef d in kSoloDefs) {
        expect(d.id, isNotEmpty);
        expect(d.titleFa, isNotEmpty);
        expect(d.titleEn, isNotEmpty);
        expect(d.hintFa, isNotEmpty);
        expect(d.hintEn, isNotEmpty);
        expect(d.accent.a, 1.0);
        expect(d.accent2.a, 1.0);
        expect(d.titleFa, isNot(d.titleEn));
      }
    });
  });

  group('layout maths', () {
    test('approach factor is frame-rate independent', () {
      // Two half steps must land where one full step does.
      final double once = soloApproach(0.001, 1 / 30);
      final double twice = 1 - (1 - soloApproach(0.001, 1 / 60)) * (1 - soloApproach(0.001, 1 / 60));
      expect(twice, closeTo(once, 1e-9));
      expect(once, inInclusiveRange(0.0, 1.0));
    });

    test('easeOutBack overshoots then settles on exactly 1', () {
      expect(SoloArt.easeOutBack(1), closeTo(1.0, 1e-9));
      expect(SoloArt.easeOutBack(0), closeTo(0.0, 1e-9));
      expect(SoloArt.easeOutBack(0.6), greaterThan(1.0), reason: 'the curve is meant to overshoot');
      expect(SoloArt.easeOutBack(5), closeTo(1.0, 1e-9), reason: 'out-of-range t is clamped');
    });

    test('soloLerp clamps t', () {
      expect(soloLerp(0, 10, -1), 0);
      expect(soloLerp(0, 10, 2), 10);
      expect(soloLerp(0, 10, 0.5), 5);
    });

    test('hash01 is deterministic and inside [0,1)', () {
      for (int i = 0; i < 500; i++) {
        final double v = SoloArt.hash01(i);
        expect(v, inInclusiveRange(0.0, 1.0));
        expect(SoloArt.hash01(i), v);
      }
    });
  });
}
