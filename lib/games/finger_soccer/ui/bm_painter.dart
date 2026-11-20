// Rendering of game.js build()/draw()/sprite()/aim()/drawTrail()/drawParts(), same world coordinates.
// ignore_for_file: non_constant_identifier_names
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/bm_data.dart';
import '../core/bm_engine.dart';
import 'bm_ball.dart';

/// Every sprite is drawn so its measured rim lands exactly on the physics radius (see kBmDiscArtFill /
/// kBmBallArtFill and tool/build_fs_assets.py): what the player sees is what collides.
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
  static const double matchWidthFraction = 0.94;
  static const double matchHeightFraction = 0.98; // pitch fills the phone width like the reference
  double s = 1, ox = 0, oy = 0;
  Size size = Size.zero;

  /// Screen space taken by the scoreboard/status bar above and the gesture bar below (logical px).
  /// The world is centred in what is left; [topHudClearance] stays the minimum gap under the HUD.
  double insetTop = 0, insetBottom = 0;

  void layout(BmEngine e, Size sz) {
    size = sz;
    final BmFieldS f = e.field;
    final double W = sz.width, fullH = sz.height;
    final double top = math.max(insetTop, topHudClearance);
    final double H = fullH - top - insetBottom;
    if (W < 50 || H < 50) return;
    final double worldWidth = f.R - f.L + 56 * FS;
    final double worldHeight = (f.B - f.T) + 2 * e.goalVisualDepth + 20;
    s = math.min(W * matchWidthFraction / worldWidth, H * matchHeightFraction / worldHeight);
    ox = W / 2 - e.CX * s;
    // Keep the scoreboard clear of the top goal while preserving the same
    // world-to-screen mapping for rendering and pointer input.
    oy = top + H / 2 - e.CY * s;
  }

  Offset toWorld(Offset p) => Offset((p.dx - ox) / s, (p.dy - oy) / s);
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

  @override
  void paint(Canvas canvas, Size size) {
    view.layout(e, size);
    _bg(canvas, size);
    if (e.bodies.isEmpty) return;
    final double t = now();
    final double s = view.s;
    final math.Random r = e.rnd;
    final double cs = e.cam * e.cam * 9, cx = fancy ? (r.nextDouble() - .5) * cs : 0, cy = fancy ? (r.nextDouble() - .5) * cs : 0;
    canvas.save();
    canvas.translate(view.ox + cx * s, view.oy + cy * s);
    canvas.scale(s);
    // Reference motion marks: a grey tapered streak behind the rolling ball, a blue water ribbon behind each
    // sliding disc (both under the pieces).
    _drawTrail(canvas, t);
    _discTrails(canvas, t);
    // soft shadows (SPR.shadow)
    for (final BmBody b in e.bodies) {
      final double visualRadius = b.r;
      final double w = visualRadius * 2.6;
      final Offset c = Offset(b.x + 5, b.y + 11);
      canvas.drawCircle(
          c,
          w / 2,
          Paint()
            ..shader = ui.Gradient.radial(c, w / 2, <Color>[_rgba(0, 0, 0, .6), _rgba(0, 0, 0, .6), _rgba(0, 0, 0, 0)],
                <double>[0, .18, 1]));
    }
    // Pull circle of the aim (translucent, under the pieces like the reference).
    _aimUnder(canvas);
    // Turn rings: every disc of the side whose turn it is, for the whole turn (aim and while the shot rolls).
    if (bmRingVisible(e) && e.phase != 'over') {
      for (final BmBody b in e.bodies) {
        if (b != e.ball && b.team == e.turn) {
          bmPaintTurnRing(canvas, Offset(b.x + b.gx * e.glideK, b.y + b.gy * e.glideK), b.r, bmRingMine(e));
        }
      }
    }
    // v6 (reference): at the final whistle the pieces leave the pitch (the score table follows).
    final bool over = e.phase == 'over';
    for (final BmBody b in e.bodies) {
      if (b != e.ball && !over) _sprite(canvas, b, t);
    }
    if (e.ball != null && !over) _sprite(canvas, e.ball!, t);
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
    final double gk = e.glideK;
    final double bx = b.x + b.gx * gk, by = b.y + b.gy * gk;
    final double drawY = by;
    if (isBall) {
      final double sv = math.sqrt(b.vx * b.vx + b.vy * b.vy), fast = math.min(1.0, sv / (1700 * K));
      final BmBallRenderer? br = im.ballR;
      if (br != null && br.ready) br.update(b.R, b.rv);
      final double so = b.r * (.55 + .25 * fast);
      canvas.drawOval(Rect.fromCenter(center: Offset(bx + so * .35, by + so), width: b.r * .86 * 2, height: b.r * .34 * 2),
          Paint()..color = _rgba(8, 14, 24, .42 * .8));
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
          final double dx = b.x - im.animX, dy = b.y - im.animY;
          im.animPhase += math.sqrt(dx * dx + dy * dy) / (b.r * .45);
        }
        if (im.animT > 0) im.animPhase += (t - im.animT).clamp(0, 100) / (im.ballFrameMs * 4);
        im.animX = b.x;
        im.animY = b.y;
        im.animT = t;
        final int fi = im.animPhase.floor() % im.ballFrames;
        final double fw = sheet.width / im.ballFrames;
        // v5: the ball's own spin (b.ang, from glancing hits / walls) turns the sprite on top of the roll direction.
        canvas.rotate((sv > 40 ? math.atan2(b.vy, b.vx) + math.pi / 2 : 0) + b.ang);
        canvas.drawImageRect(sheet, Rect.fromLTWH(fi * fw, 0, fw, sheet.height.toDouble()), dst,
            Paint()..filterQuality = FilterQuality.medium);
      } else if (rendered != null) {
        // v6: the rolled sphere and the classic art fill their square, so they are drawn at the collider radius.
        canvas.drawImageRect(rendered, Rect.fromLTWH(0, 0, rendered.width.toDouble(), rendered.height.toDouble()),
            Rect.fromCircle(center: Offset.zero, radius: b.r), Paint()..filterQuality = FilterQuality.medium);
      } else {
        canvas.rotate(b.ang);
        canvas.drawImageRect(sp, src, Rect.fromCircle(center: Offset.zero, radius: b.r), Paint()..filterQuality = FilterQuality.medium);
      }
      canvas.restore();
      return;
    }
    // No idle bobbing: the sprite stays exactly on its collider.
    // v5 (owner request 2026-11-20): the disc turns with its spin (b.ang, picked up from glancing hits and rails), so
    // a struck disc visibly rotates; a small rim notch keeps the turn visible on a crest that looks the same rotated.
    canvas.translate(bx, drawY);
    final Paint dark = Paint()
      ..filterQuality = FilterQuality.medium
      ..colorFilter = const ColorFilter.mode(Color.fromRGBO(6, 8, 24, .66), BlendMode.srcATop);
    // Thin coin edge (3 px-ish) so the top face - the collider - stays where it is drawn.
    for (int k = 3; k >= 1; k--) {
      canvas.save();
      canvas.translate(0, renderRadius * .03 * k);
      canvas.rotate(b.ang);
      canvas.drawImageRect(sp, src, dst, dark);
      canvas.restore();
    }
    canvas.rotate(b.ang);
    canvas.drawImageRect(sp, src, dst, Paint()..filterQuality = FilterQuality.medium);
    canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: renderRadius * .86),
        -math.pi / 2 - .2,
        .4,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = renderRadius * .1
          ..color = const Color(0xD9FFFFFF));
    canvas.restore();
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
    final Offset head = Offset(bl.x, bl.y);
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

  /// Discs: the reference's blue water ribbon (cyan head, royal-blue body, violet edge, white glints) with
  /// droplets flung off its sides. It keeps its width for most of its length and tapers sharply at the tail, and
  /// covers the last ~3.4 disc diameters of the slide (BmBody.tr, trimmed by path length).
  void _discTrails(Canvas canvas, double now) {
    for (final BmBody b in e.bodies) {
      if (b == e.ball || b.tr.isEmpty) continue;
      final List<Offset> raw = <Offset>[];
      for (final BmTrailPt q in b.tr) {
        final Offset o = Offset(q.x, q.y);
        if (raw.isEmpty || (o - raw.last).distance >= 2) raw.add(o);
      }
      final Offset head = Offset(b.x, b.y);
      if ((head - raw.last).distance >= 2) raw.add(head);
      // keep the newest kBmDiscTrailLen * r of path
      final double maxLen = b.r * kBmDiscTrailLen;
      final List<Offset> pts = <Offset>[raw.last];
      double acc = 0;
      for (int i = raw.length - 2; i >= 0 && acc < maxLen; i--) {
        final double sl = (raw[i] - raw[i + 1]).distance;
        if (acc + sl > maxLen) {
          pts.insert(0, raw[i + 1] + (raw[i] - raw[i + 1]) * ((maxLen - acc) / sl));
          acc = maxLen;
        } else {
          pts.insert(0, raw[i]);
          acc += sl;
        }
      }
      final int n = pts.length;
      if (n < 3 || acc < b.r * .8) continue;
      // fraction of the path from the tail (0) to the disc (1)
      final List<double> ft = <double>[0];
      double run = 0;
      for (int i = 1; i < n; i++) {
        run += (pts[i] - pts[i - 1]).distance;
        ft.add(run / acc);
      }
      final double grow = math.min(1, acc / maxLen); // a fresh slide fans out as it lengthens
      final List<double> hw = <double>[
        for (final double f in ft) b.r * .82 * grow * (f < .4 ? math.sin(f / .4 * math.pi / 2) : 1)
      ];
      final Offset a = pts.first, z = pts.last;
      List<Offset> shifted(double k) {
        final List<Offset> o = <Offset>[];
        for (int i = 0; i < n; i++) {
          Offset d = pts[math.min(n - 1, i + 1)] - pts[math.max(0, i - 1)];
          final double len = d.distance;
          d = len < 1e-6 ? const Offset(1, 0) : d / len;
          o.add(pts[i] + Offset(-d.dy, d.dx) * hw[i] * k);
        }
        return o;
      }

      canvas.drawPath(
          _ribbon(pts, hw),
          Paint()
            ..shader = ui.Gradient.linear(a, z, <Color>[
              _rgba(110, 70, 255, .15),
              _rgba(70, 72, 240, .78),
              _rgba(38, 110, 255, .9),
              _rgba(70, 205, 255, .95)
            ], <double>[0, .3, .7, 1]));
      // violet swirl along one edge, cyan-white glint along the other
      canvas.drawPath(
          _ribbon(shifted(.5), <double>[for (final double w in hw) w * .3]),
          Paint()
            ..shader = ui.Gradient.linear(a, z, <Color>[_rgba(170, 90, 255, 0), _rgba(165, 95, 255, .75), _rgba(120, 150, 255, .6)],
                <double>[0, .5, 1]));
      canvas.drawPath(
          _ribbon(shifted(-.3), <double>[for (final double w in hw) w * .28]),
          Paint()
            ..shader = ui.Gradient.linear(a, z, <Color>[_rgba(255, 255, 255, 0), _rgba(190, 245, 255, .7), _rgba(255, 255, 255, .9)],
                <double>[0, .55, 1]));
      // droplets: fixed per trail point (hashed), fading toward the tail
      for (int i = 1; i < n - 1; i++) {
        final Offset d = pts[i + 1] - pts[i - 1];
        final double len = d.distance;
        if (len < 1e-6) continue;
        final Offset nn = Offset(-d.dy / len, d.dx / len), tg = d / len;
        for (int k = 0; k < 3; k++) {
          final int h = ((pts[i].dx * 7.3).round() * 73856093) ^ ((pts[i].dy * 5.1).round() * 19349663) ^ (k * 83492791) ^ b.cid;
          final double u1 = (h & 1023) / 1023, u2 = ((h >> 10) & 1023) / 1023, u3 = ((h >> 20) & 1023) / 1023;
          final double side = u1 < .5 ? -1 : 1, off = b.r * .82 * grow * (.75 + .75 * u2) * side;
          final Offset c = pts[i] + nn * off - tg * b.r * .3 * u3;
          final double al = .9 * ft[i];
          final Color col = u3 < .4 ? _rgba(255, 255, 255, al) : (u3 < .75 ? _rgba(110, 185, 255, al) : _rgba(70, 90, 255, al));
          canvas.drawCircle(c, b.r * (.05 + .09 * u3), Paint()..color = col);
        }
      }
    }
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
