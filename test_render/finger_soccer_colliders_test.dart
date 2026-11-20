// Collider audit: renders every finger-soccer field with its real art (field, goal sprite, team discs, ball) and the
// physics colliders drawn on top (BmPainter.debugColliders): walls + rounded corners (red), goal mouths and back nets
// (yellow), posts and disc circles (cyan), ball circle (yellow). A disc is placed touching the ball and the ball is
// placed touching a post, so a correct field shows the sprites touching exactly where the circles touch.
//
//   flutter test test_render/finger_soccer_colliders_test.dart   (PNGs in $SHOTS/colliders/, one per field)
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/finger_soccer/core/bm_data.dart';
import 'package:nexora/games/finger_soccer/core/bm_engine.dart';
import 'package:nexora/games/finger_soccer/ui/bm_painter.dart';

import 'render_util.dart';

class _Hooks implements BmHooks {
  @override
  void sfx(String k, [double v = 1]) {}
  @override
  void tone(String k) {}
  @override
  void vib(List<int> pattern) {}
  @override
  void toast(String text, bool big) {}
  @override
  void goalFx() {}
  @override
  void emit(String event, Map<String, dynamic> data) {}
}

Future<ui.Image> _load(String path, {int? w}) async {
  final ByteData d = await rootBundle.load(path);
  final ui.Codec c = await ui.instantiateImageCodec(d.buffer.asUint8List(), targetWidth: w);
  return (await c.getNextFrame()).image;
}

void main() {
  const String only = String.fromEnvironment('FIELD', defaultValue: '');
  for (int fi = 0; fi < kBmFields.length; fi++) {
    final BmFieldS f = kBmFields[fi];
    if (only.isNotEmpty && only != f.id) continue;
    testWidgets('colliders over the art: ${f.id}', (WidgetTester tester) async {
      phone(tester, w: 420, h: 800, dpr: 2);
      final BmEngine e = BmEngine(_Hooks(), rng: math.Random(1));
      e.startMatch(BmConfig(
          mode: 'local',
          teams: const <String>['club0', 'lux3'],
          form: const <int>[0, 3],
          names: const <String>['A', 'B'],
          field: fi,
          ball: fi % kBmAnimBalls.length));
      // Contact scene: ball touching the top-left post of the top goal; a team-0 disc touching the ball from below.
      final BmGoal g = e.GOALS[0];
      final BmBody ball = e.ball!;
      final double a = math.pi * .35;
      ball
        ..x = g.px1 + math.cos(a) * (g.pr + ball.r)
        ..y = g.y + math.sin(a) * (g.pr + ball.r);
      final BmBody d = e.bodies.firstWhere((BmBody b) => b.team == 0 && b != ball);
      d
        ..x = ball.x + (ball.r + d.r) * .6
        ..y = ball.y + (ball.r + d.r) * .8;
      // a second disc resting in the far corner against both walls
      final BmBody c = e.bodies.lastWhere((BmBody b) => b.team == 1 && b != ball);
      c
        ..x = e.Fr - c.r
        ..y = e.Fb - math.max(e.RC, c.r) - 40;
      final BmImages im = BmImages();
      await tester.runAsync(() async {
        im.field = await _load(f.asset);
        if (!f.builtInGoals) im.goal = await _load('assets/games/bermuda/goals/${f.gs}.webp');
        im.team[0] = await _load(bmTeam('club0').asset, w: 192);
        im.team[1] = await _load(bmTeam('lux3').asset, w: 192);
        im.ballSheet = await _load(kBmAnimBalls[fi % kBmAnimBalls.length]!.sheet);
        im.ballFrames = 16;
      });
      final BmView view = BmView();
      final ValueNotifier<int> rp = ValueNotifier<int>(0);
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: kShotKey,
          child: CustomPaint(
            painter: BmPainter(e, im, view, () => 0, 1, false, repaint: rp, debugColliders: true),
            size: Size.infinite,
          ),
        ),
      ));
      await tester.pump();
      final RenderRepaintBoundary rb = kShotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final ui.Image shot = await rb.toImage(pixelRatio: 2);
        final ByteData? bd = await shot.toByteData(format: ui.ImageByteFormat.png);
        final File out = File('$kShots/colliders/${fi.toString().padLeft(2, '0')}_${f.id}.png');
        out.parent.createSync(recursive: true);
        out.writeAsBytesSync(bd!.buffer.asUint8List());
      });
      expect(view.s, greaterThan(0));
    });
  }
}
