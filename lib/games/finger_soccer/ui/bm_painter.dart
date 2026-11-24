// Rendering of game.js build()/draw()/sprite()/aim()/drawTrail()/drawParts(), same world coordinates.
// ignore_for_file: non_constant_identifier_names
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/bm_data.dart';
import '../core/bm_engine.dart';
import 'bm_ball.dart';
import 'bm_trails.dart';

/// Every sprite is drawn so its measured rim lands exactly on the physics radius (see kBmDiscArtFill /
/// kBmBallArtFill and tool/build_fs_v9_assets.py): what the player sees is what collides.
double bmDiscSpriteHalf(BmBody b) => b.r / kBmDiscArtFill;
double bmBallSpriteHalf(BmBody b) => b.r / kBmBallArtFill;

/// v7 GIF ball playback: the animation runs while the ball moves (speed above [kBmGifBallMinSpeed], world units/s).
const double kBmGifBallMinSpeed = 4;
bool bmGifBallPlays(double speed) => speed > kBmGifBallMinSpeed;

/// Frame of a GIF ball after [ms] of playback: GIF order, [frameMs] per frame, looping.
int bmGifFrame(double ms, int frameMs, int frames) => frames <= 0 ? 0 : (ms / frameMs).floor() % frames;

class BmImages {
  ui.Image? field, goal, ball;
  // Animated sprite-sheet ball (kBmAnimBalls): frames advance with distance rolled + a slow idle spin.
  ui.Image? ballSheet;
  int ballFrames = 0;
  int ballFrameMs = 120;
  /// v7 GIF balls (BmAnimBall.gifTimed): frames follow the GIF's own order and timing while the ball moves.
  bool ballTimed = false;
  double animMs = 0;
  double animPhase = 0, animX = double.nan, animY = double.nan, animT = 0;
  final List<ui.Image?> team = <ui.Image?>[null, null];
  BmBallRenderer? ballR;
  // cached background (blurred cover + faded field), keyed by size/field
  ui.Image? bg;
  Size bgSize = Size.zero;
  int bgField = -1;
  double bgDpr = 1;

  void dispose() {
    field?.dispose();
    goal?.dispose();
    ball?.dispose();
    team[0]?.dispose();
    team[1]?.dispose();
    bg?.dispose();
    ballR?.dispose();
    ballSheet?.dispose();
    ballSheet = null;
    ballFrames = 0;
    ballTimed = false;
    animMs = 0;
    field = goal = ball = bg = null;
    team[0] = team[1] = null;
    ballR = null;
  }
}

/// Screen mapping of game.js build(): world -> screen = world * s + (ox, oy).
class BmView {
  /// Breathing room below the top scoreboard. The match HUD is painted above
  /// the field, so the complete world (including the top goal) must move down
  /// as one unit instead of moving only the goal artwork.
  static const double topHudClearance = 20;
  /// v12 (bigger pitch): the pitch fills 98% of the width (was .94) and the rail margin beside it is [sideMargin]
  /// world units (was 56 * FS), so the playfield is as large as the phone allows.
  static const double matchWidthFraction = 0.98;
  static const double matchHeightFraction = 0.99;
  static const double sideMargin = 24 * FS;
  double s = 1, ox = 0, oy = 0;
  Size size = Size.zero;

  /// Screen space taken by the scoreboard/status bar above and the gesture bar below (logical px).
  /// The world is centred in what is left; [topHudClearance] stays the minimum gap under the HUD.
  double insetTop = 0, insetBottom = 0;

  void layout(BmEngine e, Size sz) {
    size = sz;
    final BmFieldS f = e.field;
    final double W = sz.width, fullH = sz.height;
    if (f.fullArt) {
      // v9: the pitch art is the whole scene (goals, nets and the side score displays drawn in): fit all of it into
      // the space between the top bar and the bottom strip, so no control ever sits on the playfield.
      final double top = insetTop;
      final double H = fullH - top - insetBottom;
      if (W < 50 || H < 50) return;
      s = math.min(W / f.W, H / f.H);
      ox = (W - f.W * s) / 2;
      oy = top + (H - f.H * s) / 2;
      return;
    }
    final double top = math.max(insetTop, topHudClearance);
    final double H = fullH - top - insetBottom;
    if (W < 50 || H < 50) return;
    final double worldWidth = f.R - f.L + sideMargin;
    final double worldHeight = (f.B - f.T) + 2 * e.goalVisualDepth + 20;
    s = math.min(W * matchWidthFraction / worldWidth, H * matchHeightFraction / worldHeight);
    ox = W / 2 - e.CX * s;
    // Keep the scoreboard clear of the top goal while preserving the same
    // world-to-screen mapping for rendering and pointer input.
    oy = top + H / 2 - e.CY * s;
  }

  /// The pitch art's rectangle on screen (logical px).
  Rect artRect(BmEngine e) => Rect.fromLTWH(ox, oy, e.field.W * s, e.field.H * s);

  Offset toWorld(Offset p) => Offset((p.dx - ox) / s, (p.dy - oy) / s);
}

/// v12: the pitch's four round corner cushions in world coordinates: for each corner, the square [RC] x [RC] between
/// the two rails minus the quarter circle of radius [BmEngine.RC] the bodies roll on (BmEngine.walls). [arcsOnly]
/// returns just the four arcs (for the bevel line).
Path bmCornerCushionPath(BmEngine e, {bool arcsOnly = false}) {
  final double rc = e.RC;
  final Path out = Path();
  for (final List<double> c in <List<double>>[
    <double>[e.Fl, e.Ft, 1, 1],
    <double>[e.Fr, e.Ft, -1, 1],
    <double>[e.Fl, e.Fb, 1, -1],
    <double>[e.Fr, e.Fb, -1, -1],
  ]) {
    final double x0 = c[0], y0 = c[1], sx = c[2], sy = c[3];
    final double cx = x0 + sx * rc, cy = y0 + sy * rc;
    if (arcsOnly) {
      out
        ..moveTo(cx, y0)
        ..arcToPoint(Offset(x0, cy), radius: Radius.circular(rc), clockwise: sx * sy < 0);
    } else {
      out
        ..moveTo(x0, y0)
        ..lineTo(cx, y0)
        ..arcToPoint(Offset(x0, cy), radius: Radius.circular(rc), clockwise: sx * sy < 0)
        ..close();
    }
  }
  return out;
}

/// v12: draws the corner cushions: a dark rail fill with a soft champagne bevel along the arc the bodies roll on.
void bmPaintCornerCushions(Canvas c, BmEngine e) {
  if (e.RC <= 0) return;
  c.drawPath(bmCornerCushionPath(e), Paint()..color = const Color(0xB30A0B12));
  final Path arcs = bmCornerCushionPath(e, arcsOnly: true);
  c.drawPath(
      arcs,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..color = const Color(0x80D9B872));
  c.drawPath(
      arcs,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xDDF6E7BD));
}

Color _rgba(int r, int g, int b, double a) => Color.fromRGBO(r, g, b, a.clamp(0.0, 1.0).toDouble());

// ---------------------------------------------------------------- reference aim + turn ring (measured 2026-11-20)
// Measured on the owner's reference recording in disc radii (disc r ~18.5 px there): pull circle up to ~4.8 r, arrow
// from the ring edge (1.3 r) to ~3.1 r at a light pull and ~4.0 r at full pull, head 0.8 r long and 0.9 r wide,
// white dots 13 / 11 / 10 px (0.70 / 0.60 / 0.54 r) at 2.55 r + 1.85 r steps toward the finger.

/// Pull fraction 0..1 of a drag of [l] world units (the engine's own power: [LMAX] is a full shot).
double bmAimPower(double l) => math.min(l, LMAX) / LMAX;
double bmAimCircleRadius(double r, double p) => r * (1.3 + 3.5 * p);
double bmAimArrowTip(double r, double p) => r * (2.4 + 1.6 * p);
/// Disc water ribbon length in disc radii (reference ~3.4 diameters).
const double kBmDiscTrailLen = 6.8;
const List<double> kBmAimDotR = <double>[.70, .60, .54, .50, .47];
/// Dots shown for a drag of [l]: one per 1.85 r of finger travel past the first, 1..5.
int bmAimDots(double l, double r) => ((l / r + 1.2 - 2.55) / 1.85).floor().clamp(0, 4).toInt() + 1;

/// Rings show on the side whose turn it is, while it aims and while its shot rolls.
bool bmRingVisible(BmEngine e) => !e.menuOpen && e.bodies.isNotEmpty && (e.phase == 'aim' || e.phase == 'move');
/// Green on the local player's discs, gold on the opponent's (reference: the recorder's side is green whether it
/// plays from the top or the bottom).
bool bmRingMine(BmEngine e) => e.turn == 0;
const Color kBmRingGreen = Color(0xFF2FD13C), kBmRingGold = Color(0xFFF4B81E);

/// A turn ring: a 0.22 r band just outside the disc rim with a dark rim line and a light inner edge, no pulse.
void bmPaintTurnRing(Canvas c, Offset o, double r, bool mine) {
  final Color main = mine ? kBmRingGreen : kBmRingGold;
  final Color edge = mine ? const Color(0xFF0B5E14) : const Color(0xFF7A4A00);
  final Color hi = mine ? const Color(0xFFA6FF9C) : const Color(0xFFFFE58A);
  final double rc = r * 1.11, w = r * .22;
  c.drawCircle(o, rc, Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = w + r * .08
    ..color = edge.withValues(alpha: .85));
  c.drawCircle(o, rc, Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..color = main);
  c.drawCircle(o, rc - w * .3, Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = w * .28
    ..color = hi.withValues(alpha: .7));
}

// ---------------------------------------------------------------- 3D pieces (ANIX PRO, render only)
/// Height of a puck's visible side wall in disc radii. The top face stays on the collider; the wall hangs below it,
/// as if seen from a camera slightly in front of the table. Pieces never lift, land or shake.
const double kBmPuckWall = .15;

/// Soft contact shadow under a piece that sits on the felt: a tight dark core at the rim and a wider ambient
/// falloff, both at a fixed small offset away from the top-left light.
void bmPaintContactShadow(Canvas c, Offset o, double r, bool ball) {
  final Offset core = o + Offset(r * .10, r * (ball ? .22 : .26));
  final double w = r * (ball ? 1.02 : 1.12);
  c.drawOval(
      Rect.fromCenter(center: core, width: w * 2, height: w * 1.86),
      Paint()
        ..shader = ui.Gradient.radial(core, w, <Color>[_rgba(0, 0, 0, .58), _rgba(0, 0, 0, .42), _rgba(0, 0, 0, 0)],
            <double>[0, .72, 1]));
  final Offset amb = o + Offset(r * .22, r * .42);
  final double aw = r * 1.55;
  c.drawCircle(
      amb,
      aw,
      Paint()
        ..shader = ui.Gradient.radial(amb, aw, <Color>[_rgba(0, 0, 0, .22), _rgba(0, 0, 0, 0)], <double>[.35, 1]));
}

final Map<double, Path> _wallPaths = <double, Path>{};

/// The crescent of the side wall (wall height [h] below a face of radius [r]), cached per size.
Path _puckWallPath(double r, double h) => _wallPaths.putIfAbsent(r * 1000 + h, () {
      final Path cyl = Path()
        ..addOval(Rect.fromCircle(center: Offset(0, h), radius: r))
        ..addRect(Rect.fromLTRB(-r, 0, r, h));
      return Path.combine(PathOperation.difference, cyl, Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: r)));
    });

/// Side lighting on the wall: lit on the light side, falling to shadow on the far side, with a thin bright edge
/// where the wall meets the felt.
void bmPaintPuckWallLight(Canvas c, double r, double h) {
  final Path p = _puckWallPath(r, h);
  c.drawPath(
      p,
      Paint()
        ..shader = ui.Gradient.linear(Offset(-r, 0), Offset(r, 0),
            <Color>[_rgba(255, 255, 255, .20), _rgba(255, 255, 255, .02), _rgba(0, 0, 0, .38)], <double>[0, .45, 1]));
  c.drawArc(Rect.fromCircle(center: Offset(0, h), radius: r - .6), .35, math.pi - .7, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * .035
        ..color = _rgba(0, 0, 0, .5));
}

/// Bevel ring and glossy rim on a puck's top face (unrotated: the light does not turn with the disc).
void bmPaintPuckBevel(Canvas c, double r) {
  final Rect rc = Rect.fromCircle(center: Offset.zero, radius: r * .955);
  c.drawCircle(
      Offset.zero,
      r * .955,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * .09
        ..shader = ui.Gradient.linear(Offset(-r * .7, -r * .7), Offset(r * .7, r * .7),
            <Color>[_rgba(255, 255, 255, .55), _rgba(255, 255, 255, .08), _rgba(0, 0, 0, .42)], <double>[0, .5, 1]));
  // glossy specular arc on the lit rim
  c.drawArc(rc, math.pi * 1.06, math.pi * .42, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = r * .05
        ..color = _rgba(255, 255, 255, .78));
  // soft sheen across the face
  final Offset g = Offset(-r * .34, -r * .40);
  c.drawCircle(
      Offset.zero,
      r * .9,
      Paint()..shader = ui.Gradient.radial(g, r * .95, <Color>[_rgba(255, 255, 255, .16), _rgba(255, 255, 255, 0)]));
}

/// Ball shading: darker toward the far rim and a small specular highlight (fixed top-left light).
void bmPaintBallGloss(Canvas c, Offset o, double r) {
  c.drawCircle(
      o,
      r,
      Paint()
        ..shader = ui.Gradient.radial(o + Offset(-r * .3, -r * .35), r * 1.35,
            <Color>[_rgba(0, 0, 0, 0), _rgba(0, 0, 0, 0), _rgba(0, 0, 0, .34)], <double>[0, .55, 1]));
  final Offset h = o + Offset(-r * .36, -r * .42);
  c.drawCircle(h, r * .34, Paint()..shader = ui.Gradient.radial(h, r * .34, <Color>[_rgba(255, 255, 255, .72), _rgba(255, 255, 255, 0)]));
}

// ---------------------------------------------------------------- v9 score displays
/// Segments lit for each digit, in the order a b c d e f g (top, top-right, bottom-right, bottom, bottom-left,
/// top-left, middle).
const List<int> kBmSegMasks = <int>[0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F];

/// A glowing seven-segment digit filling [r]: unlit segments faintly visible, lit ones in [c] with a soft glow.
void bmPaintSevenSeg(Canvas canvas, Rect r, int digit, Color c) {
  final int m = kBmSegMasks[digit.clamp(0, 9).toInt()];
  final double w = r.width, h = r.height, t = math.min(w, h) * .17, g = t * .18;
  final double l = r.left, tp = r.top, mid = r.top + h / 2;
  final List<Rect> seg = <Rect>[
    Rect.fromLTWH(l + t * .6 + g, tp, w - t * 1.2 - 2 * g, t), // a
    Rect.fromLTWH(l + w - t, tp + t * .6 + g, t, h / 2 - t * .9 - 2 * g), // b
    Rect.fromLTWH(l + w - t, mid + t * .3 + g, t, h / 2 - t * .9 - 2 * g), // c
    Rect.fromLTWH(l + t * .6 + g, tp + h - t, w - t * 1.2 - 2 * g, t), // d
    Rect.fromLTWH(l, mid + t * .3 + g, t, h / 2 - t * .9 - 2 * g), // e
    Rect.fromLTWH(l, tp + t * .6 + g, t, h / 2 - t * .9 - 2 * g), // f
    Rect.fromLTWH(l + t * .6 + g, mid - t / 2, w - t * 1.2 - 2 * g, t), // g
  ];
  final Paint off = Paint()..color = c.withValues(alpha: .10);
  final Paint glow = Paint()
    ..color = c.withValues(alpha: .55)
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, t * .9);
  final Paint on = Paint()..color = c;
  final Paint core = Paint()..color = Color.lerp(c, const Color(0xFFFFFFFF), .45)!;
  for (int i = 0; i < 7; i++) {
    final RRect rr = RRect.fromRectAndRadius(seg[i], Radius.circular(t / 2));
    if ((m >> i) & 1 == 0) {
      canvas.drawRRect(rr, off);
      continue;
    }
    canvas.drawRRect(rr, glow);
    canvas.drawRRect(rr, on);
    canvas.drawRRect(rr.deflate(t * .28), core);
  }
}

class BmPainter extends CustomPainter {
  BmPainter(this.e, this.im, this.view, this.now, this.dpr, this.fancy, {required Listenable repaint, this.debugColliders = false})
      : super(repaint: repaint);

  /// Draws every collider (walls, rounded corners, goal mouths, posts, back nets, disc and ball circles) over the
  /// art. Used by test_render/finger_soccer_colliders_test.dart to check the physics against each field's drawing.
  final bool debugColliders;

  final BmEngine e;
  final BmImages im;
  final BmView view;
  final double Function() now; // ms
  final double dpr;
  final bool fancy;

  /// Render-only per-disc trail history (v13).
  final BmDiscTrails discTrails = BmDiscTrails();

  @override
  void paint(Canvas canvas, Size size) {
    paintBackground(canvas, size);
    if (e.bodies.isEmpty) return;
    paintUnder(canvas);
    paintDiscs(canvas);
    paintBall(canvas);
    paintOver(canvas);
    paintScore(canvas);
  }

  // The phases below are the same frame split into layers, so the Flame scene (fs_flame.dart) can draw each layer as
  // its own component while CustomPaint users (render tests) still get the whole frame from paint().

  /// Layout + blurred surround + the pitch art.
  void paintBackground(Canvas canvas, Size size) {
    view.layout(e, size);
    _bg(canvas, size);
  }

  void _world(Canvas canvas) {
    canvas.save();
    canvas.translate(view.ox, view.oy);
    canvas.scale(view.s);
  }

  /// Motion trails, contact shadows, the pull circle and the turn rings (everything under the pieces).
  void paintUnder(Canvas canvas) {
    if (e.bodies.isEmpty) return;
    final double t = now();
    // ANIX PRO: no camera shake (owner request) and never a draw from the simulation RNG here: painting must not
    // consume e.rnd, or the bot / online stream would depend on the frame rate.
    _world(canvas);
    // Reference motion marks: a grey tapered streak behind the rolling ball, a blue water ribbon behind each
    // sliding disc (both under the pieces).
    _drawTrail(canvas, t);
    // v13: each sliding disc leaves a coloured, fading glow streak in its side's trail colours (bm_trails.dart),
    // sampled from where the disc is drawn on the paint clock: render only, never part of physics or sync.
    discTrails.sample(e, drawPos, t);
    discTrails.paint(canvas, e, drawPos, t, glow: fancy);
    // Soft contact shadows, drawn where the piece is DRAWN (interpolated + post-goal glide), so nothing dark is left
    // on the kickoff slots while the pieces glide home after a goal. Pieces never leave the ground: fixed offset.
    final bool over0 = e.phase == 'over';
    if (!over0) {
      for (final BmBody b in e.bodies) {
        bmPaintContactShadow(canvas, drawPos(b), b.r, b == e.ball);
      }
    }
    // Pull circle of the aim (translucent, under the pieces like the reference).
    _aimUnder(canvas);
    // Turn rings: every disc of the side whose turn it is, for the whole turn (aim and while the shot rolls).
    if (bmRingVisible(e) && e.phase != 'over') {
      for (final BmBody b in e.bodies) {
        if (b != e.ball && b.team == e.turn) {
          bmPaintTurnRing(canvas, drawPos(b), b.r, bmRingMine(e));
        }
      }
    }
    canvas.restore();
  }

  /// Every disc (team badges as 3D pucks). v6: at the final whistle the pieces leave the pitch.
  void paintDiscs(Canvas canvas) {
    if (e.bodies.isEmpty || e.phase == 'over') return;
    final double t = now();
    _world(canvas);
    for (final BmBody b in e.bodies) {
      if (b != e.ball) _sprite(canvas, b, t);
    }
    canvas.restore();
  }

  /// The match ball.
  void paintBall(Canvas canvas) {
    final BmBody? b = e.ball;
    if (b == null || e.phase == 'over') return;
    _world(canvas);
    _sprite(canvas, b, now());
    canvas.restore();
  }

  /// Separate goal sprites (pitches without built-in goals), the debug colliders and the aim arrow.
  void paintOver(Canvas canvas) {
    if (e.bodies.isEmpty) return;
    final double t = now();
    _world(canvas);
    // goals (drawn over the ball: the net covers it). The sprite's post bottoms sit exactly on the goal line and its
    // posts on the engine's post colliders (BmEngine.geo builds the colliders from this same placement).
    final ui.Image? gi = im.goal;
    if (gi != null && e.GGw > 0) {
      for (final BmGoal g in e.GOALS) {
        final double gx = e.GGx + math.sin(t / 25) * 8 * e.shake[g.team];
        final double top = g.d < 0 ? g.y - e.GGh * e.GGleg : g.y - e.GGh * (1 - e.GGleg);
        final Rect dst = Rect.fromLTWH(gx, top, e.GGw, e.GGh);
        final Rect src = Rect.fromLTWH(0, 0, gi.width.toDouble(), gi.height.toDouble());
        final Paint p = Paint()..filterQuality = FilterQuality.medium;
        if (g.d > 0) {
          canvas.save();
          canvas.translate(0, top * 2 + e.GGh);
          canvas.scale(1, -1);
          canvas.drawImageRect(gi, src, dst, p);
          canvas.restore();
        } else {
          canvas.drawImageRect(gi, src, dst, p);
        }
      }
    }
    if (debugColliders) _colliders(canvas);
    // Impact sparks, rings and the full-screen flash are removed by design.
    _aimOver(canvas);
    canvas.restore();
  }

  /// v9: the live score on the pitch art's two side displays (left = the bottom side, right = the top side),
  /// two seven-segment digits each, stacked tens over ones like the printed "00" they replace.
  void paintScore(Canvas canvas) {
    final BmScoreDisplay? d = e.field.score;
    if (d == null) return;
    final double k = e.field.W / d.artW; // art px -> world (across)
    final double ky = k * BmFieldS.stretchY; // art px -> world (along the stretched length)
    _world(canvas);
    for (int side = 0; side < 2; side++) {
      final int v = e.score[side].clamp(0, 99).toInt();
      final double cx = (side == 0 ? d.leftCx : d.rightCx) * k;
      final Color c = side == 0 ? e.field.scoreLeft : e.field.scoreRight;
      final Rect tens = Rect.fromCenter(center: Offset(cx, d.tensCy * ky), width: d.digitW * k, height: d.digitH * ky);
      final Rect ones = Rect.fromCenter(center: Offset(cx, d.onesCy * ky), width: d.digitW * k, height: d.digitH * ky);
      final Rect panel = tens.expandToInclude(ones).inflate(3.5 * k);
      canvas.drawRRect(
        RRect.fromRectAndRadius(panel, Radius.circular(3 * k)),
        Paint()..color = const Color(0xDD07111C),
      );
      bmPaintSevenSeg(canvas, tens, v ~/ 10, c);
      bmPaintSevenSeg(canvas, ones, v % 10, c);
    }
    canvas.restore();
  }

  // ------------------------------------------------------------ background (build())
  void _bg(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF03060D));
    final ui.Image? fi = im.field;
    if (fi == null) return;
    if (im.bg == null || im.bgSize != size || im.bgField != e.setFld || im.bgDpr != dpr) {
      im.bg?.dispose();
      final double d = dpr;
      final ui.PictureRecorder rec = ui.PictureRecorder();
      final Canvas b = Canvas(rec);
      b.scale(d);
      final BmFieldS f = e.field;
      final double W = size.width, H = size.height;
      b.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF03060D));
      final Rect src = Rect.fromLTWH(0, 0, fi.width.toDouble(), fi.height.toDouble());
      final double c = math.max(W / f.W, H / f.H);
      b.saveLayer(Offset.zero & size, Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 8 / d * 1.0, sigmaY: 8 / d * 1.0));
      b.drawImageRect(fi, src, Rect.fromLTWH((W - f.W * c) / 2, (H - f.H * c) / 2, f.W * c, f.H * c),
          Paint()..filterQuality = FilterQuality.low);
      b.restore();
      b.drawRect(Offset.zero & size, Paint()..color = _rgba(0, 0, 0, .5));
      final Rect fr = Rect.fromLTWH(view.ox, view.oy, f.W * view.s, f.H * view.s);
      b.saveLayer(Offset.zero & size, Paint());
      b.drawImageRect(fi, src, fr, Paint()..filterQuality = FilterQuality.high);
      b.drawRect(
          Offset.zero & size,
          Paint()
            ..blendMode = BlendMode.dstIn
            ..shader = ui.Gradient.linear(Offset(0, fr.top), Offset(0, fr.bottom), const <Color>[
              Color(0x00000000),
              Color(0xFF000000),
              Color(0xFF000000),
              Color(0x00000000)
            ], const <double>[0, .012, .988, 1]));
      b.drawRect(
          Offset.zero & size,
          Paint()
            ..blendMode = BlendMode.dstIn
            ..shader = ui.Gradient.linear(Offset(fr.left, 0), Offset(fr.right, 0), const <Color>[
              Color(0x00000000),
              Color(0xFF000000),
              Color(0xFF000000),
              Color(0x00000000)
            ], const <double>[0, .012, .988, 1]));
      b.restore();
      // v12: the round corner cushions the bodies roll round (BmEngine.walls, kBmCornerR), baked into the cached
      // background so they cost nothing per frame.
      // v13 (owner request 2026-11-24): the corner cushions are no longer drawn (no curved white lines in the
      // corners). The round-corner PHYSICS is unchanged (BmEngine.walls / RC); only the paint is gone.
      final ui.Picture pic = rec.endRecording();
      im.bg = pic.toImageSync(math.max(1, (size.width * d).round()), math.max(1, (size.height * d).round()));
      pic.dispose();
      im.bgSize = size;
      im.bgField = e.setFld;
      im.bgDpr = dpr;
    }
    final ui.Image bg = im.bg!;
    canvas.drawImageRect(bg, Rect.fromLTWH(0, 0, bg.width.toDouble(), bg.height.toDouble()), Offset.zero & size, Paint());
  }

  // ------------------------------------------------------------ sprite()
  void _sprite(Canvas canvas, BmBody b, double t) {
    final bool isBall = b == e.ball;
    final double renderRadius = b.r;
    final ui.Image? sp = isBall ? (im.ballSheet ?? im.ball) : im.team[b.team == 0 ? 0 : 1];
    if (sp == null) {
      canvas.drawCircle(Offset(b.x, b.y), renderRadius, Paint()..color = isBall ? Colors.white : (b.team != 0 ? const Color(0xFFFF5B5B) : const Color(0xFF3B9BFF)));
      return;
    }
    final double half = isBall ? bmBallSpriteHalf(b) : bmDiscSpriteHalf(b);
    final Rect src = Rect.fromLTWH(0, 0, sp.width.toDouble(), sp.height.toDouble());
    final Rect dst = Rect.fromLTWH(-half, -half, half * 2, half * 2);
    canvas.save();
    // v6: post-goal glide back to the kickoff slots (render only, BmEngine.glideK).
    final Offset dp = drawPos(b);
    final double bx = dp.dx, by = dp.dy;
    final double drawY = by;
    final double ang = e.renderAng(b);
    if (isBall) {
      final double sv = math.sqrt(b.vx * b.vx + b.vy * b.vy);
      final BmBallRenderer? br = im.ballR;
      if (br != null && br.ready) br.update(b.R, b.rv);
      // (contact shadow: bmPaintContactShadow, drawn with every piece's shadow before the sprites)
      // The reference ball stays round while it rolls: no speed stretch, only the 3D roll below.
      canvas.translate(bx, by);
      final ui.Image? sheet = im.ballSheet;
      final ui.Image? rendered = br?.image;
      if (sheet != null && im.ballFrames > 0 && im.ballTimed) {
        // v7 GIF ball: exactly the GIF's frames in the GIF's order at its own frame time (e.g. 90 ms) while the ball
        // moves; at rest it holds the frame it stopped on. No extra rotation (no travel direction, no b.ang): the
        // GIF's own spin is the only rotation, about the ball centre (every frame was re-centred at build time).
        final double dt = im.animT > 0 ? (t - im.animT).clamp(0, 250).toDouble() : 0;
        if (bmGifBallPlays(sv)) im.animMs += dt;
        im.animT = t;
        final int fi = bmGifFrame(im.animMs, im.ballFrameMs, im.ballFrames);
        final double fw = sheet.width / im.ballFrames;
        canvas.drawImageRect(sheet, Rect.fromLTWH(fi * fw, 0, fw, sheet.height.toDouble()), dst,
            Paint()..filterQuality = FilterQuality.medium);
      } else if (sheet != null && im.ballFrames > 0) {
        // distance-driven roll (one frame per ~0.45 radius) + idle spin at a quarter of the GIF speed
        if (!im.animX.isNaN) {
          final double dx = bx - im.animX, dy = by - im.animY;
          im.animPhase += math.sqrt(dx * dx + dy * dy) / (b.r * .45);
        }
        if (im.animT > 0) im.animPhase += (t - im.animT).clamp(0, 100) / (im.ballFrameMs * 4);
        im.animX = bx;
        im.animY = by;
        im.animT = t;
        final int fi = im.animPhase.floor() % im.ballFrames;
        final double fw = sheet.width / im.ballFrames;
        // v5: the ball's own spin (b.ang, from glancing hits / walls) turns the sprite on top of the roll direction.
        canvas.rotate((sv > 40 ? math.atan2(b.vy, b.vx) + math.pi / 2 : 0) + ang);
        canvas.drawImageRect(sheet, Rect.fromLTWH(fi * fw, 0, fw, sheet.height.toDouble()), dst,
            Paint()..filterQuality = FilterQuality.medium);
      } else if (rendered != null) {
        // v6: the rolled sphere and the classic art fill their square, so they are drawn at the collider radius.
        canvas.drawImageRect(rendered, Rect.fromLTWH(0, 0, rendered.width.toDouble(), rendered.height.toDouble()),
            Rect.fromCircle(center: Offset.zero, radius: b.r), Paint()..filterQuality = FilterQuality.medium);
      } else {
        canvas.rotate(ang);
        canvas.drawImageRect(sp, src, Rect.fromCircle(center: Offset.zero, radius: b.r), Paint()..filterQuality = FilterQuality.medium);
      }
      canvas.restore();
      // Sphere shading + a fixed specular highlight (light from the top left), drawn unrotated over the art.
      bmPaintBallGloss(canvas, Offset(bx, by), b.r);
      return;
    }
    // No idle bobbing: the sprite stays exactly on its collider.
    // v5 (owner request 2026-11-20): the disc turns with its spin (b.ang, picked up from glancing hits and rails), so
    // a struck disc visibly rotates; a small rim notch keeps the turn visible on a crest that looks the same rotated.
    canvas.translate(bx, drawY);
    // 3D puck (ANIX PRO, render only, the piece never lifts): a bevelled side wall below the top face, the top face
    // (the collider, exactly where it is drawn), a lit bevel ring and a glossy rim highlight from a fixed top-left
    // light, then the small white notch that turns with the disc's spin.
    final Paint dark = Paint()
      ..filterQuality = FilterQuality.medium
      ..colorFilter = const ColorFilter.mode(Color.fromRGBO(18, 20, 30, .55), BlendMode.multiply);
    final double wall = renderRadius * kBmPuckWall;
    // The side wall is the crescent under the top face (see _puckWallPath): clip the disc art to that
    // crescent so the wall reads as a clean cylinder edge, not a stack of five full discs (the old
    // per-layer full-disc draw smeared the crest into a blurry blob — the "broken skin" the player saw).
    final Path wallPath = _puckWallPath(renderRadius, wall);
    canvas.save();
    canvas.clipPath(wallPath);
    canvas.translate(0, wall);
    canvas.rotate(ang);
    canvas.drawImageRect(sp, src, dst, dark);
    canvas.restore();
    bmPaintPuckWallLight(canvas, renderRadius, wall);
    canvas.save();
    canvas.rotate(ang);
    canvas.drawImageRect(sp, src, dst, Paint()..filterQuality = FilterQuality.medium);
    canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: renderRadius * .86),
        -math.pi / 2 - .16,
        .32,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = renderRadius * .08
          ..color = const Color(0xBFFFFFFF));
    canvas.restore();
    bmPaintPuckBevel(canvas, renderRadius);
    canvas.restore();
  }

  /// Where [b] is drawn: interpolated between fixed physics steps, plus the post-goal glide home.
  Offset drawPos(BmBody b) {
    final Offset p = e.renderPos(b);
    final double gk = e.glideK;
    return Offset(p.dx + b.gx * gk, p.dy + b.gy * gk);
  }

  // ------------------------------------------------------------ debug collider overlay
  void _colliders(Canvas canvas) {
    final Paint wall = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0xFFFF2D55);
    final Paint post = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0xFF00E5FF);
    final Paint net = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0xFFFFD60A);
    final double rc = e.RC;
    // straight walls (the goal mouths are open between the inner post faces)
    final Path p = Path();
    for (final BmGoal g in e.GOALS) {
      p
        ..moveTo(e.Fl + rc, g.y)
        ..lineTo(g.x1, g.y)
        ..moveTo(g.x2, g.y)
        ..lineTo(e.Fr - rc, g.y);
    }
    p
      ..moveTo(e.Fl, e.Ft + rc)
      ..lineTo(e.Fl, e.Fb - rc)
      ..moveTo(e.Fr, e.Ft + rc)
      ..lineTo(e.Fr, e.Fb - rc);
    canvas.drawPath(p, wall);
    if (rc > 0) {
      canvas.drawArc(Rect.fromCircle(center: Offset(e.Fl + rc, e.Ft + rc), radius: rc), math.pi, math.pi / 2, false, wall);
      canvas.drawArc(Rect.fromCircle(center: Offset(e.Fr - rc, e.Ft + rc), radius: rc), -math.pi / 2, math.pi / 2, false, wall);
      canvas.drawArc(Rect.fromCircle(center: Offset(e.Fl + rc, e.Fb - rc), radius: rc), math.pi / 2, math.pi / 2, false, wall);
      canvas.drawArc(Rect.fromCircle(center: Offset(e.Fr - rc, e.Fb - rc), radius: rc), 0, math.pi / 2, false, wall);
    }
    for (final BmGoal g in e.GOALS) {
      final double back = g.y + g.d * e.DEPTH;
      canvas.drawPath(
          Path()
            ..moveTo(g.x1, g.y)
            ..lineTo(g.x1, back)
            ..lineTo(g.x2, back)
            ..lineTo(g.x2, g.y),
          net);
      canvas.drawCircle(Offset(g.px1, g.y), g.pr, post);
      canvas.drawCircle(Offset(g.px2, g.y), g.pr, post);
    }
    for (final BmBody b in e.bodies) {
      canvas.drawCircle(Offset(b.x, b.y), b.r, b == e.ball ? net : post);
    }
  }

  // ------------------------------------------------------------ motion marks (reference)
  /// Tapered ribbon through [pts] (oldest first) with half widths [hw].
  static Path _ribbon(List<Offset> pts, List<double> hw) {
    final int n = pts.length;
    final List<Offset> l = <Offset>[], r = <Offset>[];
    for (int i = 0; i < n; i++) {
      Offset d = pts[math.min(n - 1, i + 1)] - pts[math.max(0, i - 1)];
      final double len = d.distance;
      d = len < 1e-6 ? const Offset(1, 0) : d / len;
      final Offset nn = Offset(-d.dy, d.dx);
      l.add(pts[i] + nn * hw[i]);
      r.add(pts[i] - nn * hw[i]);
    }
    final Path p = Path()..moveTo(l[0].dx, l[0].dy);
    for (int i = 1; i < n; i++) {
      p.lineTo(l[i].dx, l[i].dy);
    }
    for (int i = n - 1; i >= 0; i--) {
      p.lineTo(r[i].dx, r[i].dy);
    }
    return p..close();
  }

  /// Ball: a light-grey streak, as wide as ~60% of the ball at the ball and tapering to a point over the last
  /// ~0.3 s of its path (the engine's trail points fade at 3/s).
  void _drawTrail(Canvas canvas, double now) {
    final BmBody? bl = e.ball;
    if (bl == null) return;
    final List<Offset> pts = <Offset>[];
    final List<double> al = <double>[];
    for (final BmTrailPt q in e.trail) {
      final Offset o = Offset(q.x, q.y);
      if (pts.isNotEmpty && (o - pts.last).distance < 2) continue;
      pts.add(o);
      al.add(q.a.clamp(0.0, 1.0).toDouble());
    }
    if (pts.isEmpty) return;
    final Offset head = e.renderPos(bl);
    if ((head - pts.last).distance < bl.r * 3) {
      pts.add(head);
      al.add(al.last);
    }
    if (pts.length < 2) return;
    final List<double> hw = <double>[for (final double a in al) BR * .62 * math.pow(a, .7).toDouble()];
    hw[0] = 0;
    canvas.drawPath(
        _ribbon(pts, hw),
        Paint()
          ..shader = ui.Gradient.linear(pts.first, pts.last == pts.first ? pts.first + const Offset(0, 1) : pts.last,
              <Color>[_rgba(205, 205, 205, 0), _rgba(205, 205, 205, .55), _rgba(214, 214, 214, .82)], <double>[0, .45, 1]));
  }

  // ------------------------------------------------------------ aim (reference)
  /// The live pull: the disc, the pull length (world) and the shot direction (unit).
  ({BmBody b, double l, double p, double ux, double uy})? _pull() {
    final BmDrag? d = e.drag;
    if (d == null) return null;
    final double dx = d.sx - d.cx, dy = d.sy - d.cy, l = math.sqrt(dx * dx + dy * dy);
    if (l < 18) return null;
    return (b: d.b, l: l, p: bmAimPower(l), ux: dx / l, uy: dy / l);
  }

  /// Translucent dark pull circle around the disc; it opens with the pull (1.3 -> 4.8 disc radii).
  void _aimUnder(Canvas canvas) {
    final ({BmBody b, double l, double p, double ux, double uy})? a = _pull();
    if (a == null) return;
    canvas.drawCircle(Offset(a.b.x, a.b.y), bmAimCircleRadius(a.b.r, a.p), Paint()..color = _rgba(0, 0, 0, .17));
  }

  /// Red-to-yellow arrow in the shot direction (grows with the pull) and the chain of white dots toward the finger.
  void _aimOver(Canvas canvas) {
    final ({BmBody b, double l, double p, double ux, double uy})? a = _pull();
    if (a == null) return;
    final BmBody b = a.b;
    final double r = b.r, ux = a.ux, uy = a.uy, nx = -uy, ny = ux;
    // dots on the pull side
    final int nd = bmAimDots(a.l, r);
    for (int i = 0; i < nd; i++) {
      final double dd = r * (2.55 + 1.85 * i), rad = r * kBmAimDotR[i];
      final Offset c = Offset(b.x - ux * dd, b.y - uy * dd);
      canvas.drawCircle(c, rad, Paint()..color = const Color(0xE61C1C1C));
      canvas.drawCircle(
          c,
          rad - r * .09,
          Paint()
            ..shader = ui.Gradient.radial(c + Offset(-rad * .25, -rad * .3), rad, const <Color>[Color(0xFFFFFFFF), Color(0xFFD6D6D6)]));
    }
    // arrow
    final double base = r * 1.3, tip = bmAimArrowTip(r, a.p), neck = tip - r * .82;
    final double sw0 = r * .10, sw1 = r * .17, hw = r * .46;
    Offset at(double d, double w) => Offset(b.x + ux * d + nx * w, b.y + uy * d + ny * w);
    final Path arrow = Path()
      ..moveTo(at(base, sw0).dx, at(base, sw0).dy)
      ..lineTo(at(neck, sw1).dx, at(neck, sw1).dy)
      ..lineTo(at(neck, hw).dx, at(neck, hw).dy)
      ..lineTo(at(tip, 0).dx, at(tip, 0).dy)
      ..lineTo(at(neck, -hw).dx, at(neck, -hw).dy)
      ..lineTo(at(neck, -sw1).dx, at(neck, -sw1).dy)
      ..lineTo(at(base, -sw0).dx, at(base, -sw0).dy)
      ..close();
    canvas.drawPath(
        arrow,
        Paint()
          ..shader = ui.Gradient.linear(at(base, 0), at(tip, 0), const <Color>[
            Color(0xFFFFEE55),
            Color(0xFFFFB020),
            Color(0xFFF04A1E),
            Color(0xFFD82A1A),
          ], <double>[0, .42, .74, 1]));
    canvas.drawPath(
        arrow,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = r * .045
          ..color = const Color(0x8C5A140A));
  }

  @override
  bool shouldRepaint(covariant BmPainter oldDelegate) => true;
}
