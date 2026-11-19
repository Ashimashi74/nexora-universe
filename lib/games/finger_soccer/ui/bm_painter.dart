// Rendering of game.js build()/draw()/sprite()/aim()/drawTrail()/drawParts(), same world coordinates.
// ignore_for_file: non_constant_identifier_names
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/bm_engine.dart';
import 'bm_ball.dart';

/// Visual-only sizing; BmEngine radii and collision geometry remain unchanged.
// Presentation-only tuning. Physics radii stay unchanged so existing replays,
// snapshots and online peers keep the same deterministic contract.
const double kBmPlayerVisualScale = 0.78;
const double kBmBallVisualScale = 0.78;
const double kBmGoalArtScale = 0.82;

class BmImages {
  ui.Image? field, goal, ball;
  // Animated sprite-sheet ball (kBmAnimBalls): frames advance with distance rolled + a slow idle spin.
  ui.Image? ballSheet;
  int ballFrames = 0;
  int ballFrameMs = 120;
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
  static const double matchHeightFraction = 0.88;
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
    final double worldHeight = (f.B - f.T) + 2 * e.GGh * kBmGoalArtScale + 48;
    s = math.min(W * matchWidthFraction / worldWidth, H * matchHeightFraction / worldHeight);
    ox = W / 2 - e.CX * s;
    // Keep the scoreboard clear of the top goal while preserving the same
    // world-to-screen mapping for rendering and pointer input.
    oy = top + H / 2 - e.CY * s;
  }

  Offset toWorld(Offset p) => Offset((p.dx - ox) / s, (p.dy - oy) / s);
}

Color _rgba(int r, int g, int b, double a) => Color.fromRGBO(r, g, b, a.clamp(0.0, 1.0).toDouble());

class BmPainter extends CustomPainter {
  BmPainter(this.e, this.im, this.view, this.now, this.dpr, this.fancy, {required Listenable repaint}) : super(repaint: repaint);

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
    // Keep only the restrained ground/wind trace; no neon projectile effects.
    _drawTrail(canvas, t);
    if (e.phase == 'aim' && !e.menuOpen) {
      final double k = .5 + .5 * math.sin(t / 260);
      final List<int> c = e.turn != 0 ? <int>[255, 110, 110] : <int>[80, 170, 255];
      for (final BmBody b in e.bodies) {
        if (b.team == e.turn) {
          final double visualRadius = b.r * kBmPlayerVisualScale;
          canvas.drawCircle(Offset(b.x, b.y), visualRadius + 11,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 13
                ..color = _rgba(c[0], c[1], c[2], .12 + .14 * k));
          canvas.drawCircle(Offset(b.x, b.y), visualRadius + 11,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 4
                ..color = _rgba(c[0], c[1], c[2], .5 + .5 * k));
        }
      }
    }
    // Player-piece trails are intentionally disabled; only the ball leaves a trace.
    // soft shadows (SPR.shadow)
    for (final BmBody b in e.bodies) {
      final double visualRadius = b == e.ball ? b.r * kBmBallVisualScale : b.r * kBmPlayerVisualScale;
      final double w = visualRadius * 2.6;
      final Offset c = Offset(b.x + 5, b.y + 11);
      canvas.drawCircle(
          c,
          w / 2,
          Paint()
            ..shader = ui.Gradient.radial(c, w / 2, <Color>[_rgba(0, 0, 0, .6), _rgba(0, 0, 0, .6), _rgba(0, 0, 0, 0)],
                <double>[0, .18, 1]));
    }
    for (final BmBody b in e.bodies) {
      if (b != e.ball) _sprite(canvas, b, t);
    }
    if (e.ball != null) _sprite(canvas, e.ball!, t);
    // goals (drawn over the ball: the net covers it)
    final ui.Image? gi = im.goal;
    if (gi != null) {
      for (final BmGoal g in e.GOALS) {
        final double drawWidth = e.GGw * kBmGoalArtScale;
        final double drawHeight = e.GGh * kBmGoalArtScale;
        final double gx = e.GGx + (e.GGw - drawWidth) / 2 + math.sin(t / 25) * 8 * e.shake[g.team];
        final double gy = g.d < 0 ? g.y - drawHeight - 2 : g.y + 2;
        final Rect dst = Rect.fromLTWH(gx, gy, drawWidth, drawHeight);
        final Rect src = Rect.fromLTWH(0, 0, gi.width.toDouble(), gi.height.toDouble());
        final Paint p = Paint()..filterQuality = FilterQuality.medium;
        if (g.d > 0) {
          canvas.save();
          canvas.translate(0, gy * 2 + drawHeight);
          canvas.scale(1, -1);
          canvas.drawImageRect(gi, src, dst, p);
          canvas.restore();
        } else {
          canvas.drawImageRect(gi, src, dst, p);
        }
      }
    }
    // Impact sparks, rings and the full-screen flash are removed by design.
    _aim(canvas, t);
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
            ], const <double>[0, .07, .93, 1]));
      b.drawRect(
          Offset.zero & size,
          Paint()
            ..blendMode = BlendMode.dstIn
            ..shader = ui.Gradient.linear(Offset(fr.left, 0), Offset(fr.right, 0), const <Color>[
              Color(0x00000000),
              Color(0xFF000000),
              Color(0xFF000000),
              Color(0x00000000)
            ], const <double>[0, .04, .96, 1]));
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
    final double renderRadius = isBall ? b.r * kBmBallVisualScale : b.r * kBmPlayerVisualScale;
    final ui.Image? sp = isBall ? im.ball : im.team[b.team == 0 ? 0 : 1];
    if (sp == null) {
      canvas.drawCircle(Offset(b.x, b.y), renderRadius, Paint()..color = isBall ? Colors.white : (b.team != 0 ? const Color(0xFFFF5B5B) : const Color(0xFF3B9BFF)));
      return;
    }
    final Rect src = Rect.fromLTWH(0, 0, sp.width.toDouble(), sp.height.toDouble());
    final Rect dst = Rect.fromLTWH(-renderRadius, -renderRadius, renderRadius * 2, renderRadius * 2);
    canvas.save();
    double drawY = b.y;
    if (isBall) {
      final double sv = math.sqrt(b.vx * b.vx + b.vy * b.vy), fast = math.min(1.0, sv / (1700 * K));
      final BmBallRenderer? br = im.ballR;
      if (br != null && br.ready) br.update(b.R, b.rv);
      final double so = b.r * (.55 + .25 * fast);
      canvas.drawOval(Rect.fromCenter(center: Offset(b.x + so * .35, b.y + so), width: b.r * .86 * 2, height: b.r * .34 * 2),
          Paint()..color = _rgba(8, 14, 24, .42 * .8));
      canvas.translate(b.x, b.y);
      if (sv > 40) {
        final double a = math.atan2(b.vy, b.vx), st = math.min(.16, fast * .12) + b.sq * .12, sq = b.sq * .1;
        canvas.rotate(a);
        canvas.scale(1 + st - sq, 1 - st * .55 + sq);
        canvas.rotate(-a);
      }
      final ui.Image? sheet = im.ballSheet;
      final ui.Image? rendered = br?.image;
      if (sheet != null && im.ballFrames > 0) {
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
        if (sv > 40) canvas.rotate(math.atan2(b.vy, b.vx) + math.pi / 2);
        canvas.drawImageRect(sheet, Rect.fromLTWH(fi * fw, 0, fw, sheet.height.toDouble()), dst,
            Paint()..filterQuality = FilterQuality.medium);
      } else if (rendered != null) {
        canvas.drawImageRect(rendered, Rect.fromLTWH(0, 0, rendered.width.toDouble(), rendered.height.toDouble()), dst,
            Paint()..filterQuality = FilterQuality.medium);
      } else {
        canvas.rotate(b.ang);
        canvas.drawImageRect(sp, src, dst, Paint()..filterQuality = FilterQuality.medium);
      }
      canvas.restore();
      return;
    }
    final double ph = b.cid * 1.7;
    drawY += math.sin(t / 1000 * 1.6 + ph) * 1.6 * (b.vx != 0 || b.vy != 0 ? 0 : 1);
    canvas.translate(b.x, drawY);
    final double sv = math.sqrt(b.vx * b.vx + b.vy * b.vy);
    if (sv > 60 || b.sq > .02) {
      final double a = math.atan2(b.vy, b.vx), st = math.min(.1, sv / (1800 * K) * .1) + b.sq * .1, sq = b.sq * .14;
      canvas.rotate(a);
      canvas.scale(1 + st - sq, 1 - st * .6 + sq);
      canvas.rotate(-a);
    }
    final Paint dark = Paint()
      ..filterQuality = FilterQuality.medium
      ..colorFilter = const ColorFilter.mode(Color.fromRGBO(6, 8, 24, .66), BlendMode.srcATop);
    for (int k = 4; k >= 1; k--) {
      canvas.drawImageRect(sp, src, dst.shift(Offset(0, renderRadius * .052 * k)), dark);
    }
    canvas.drawImageRect(sp, src, dst, Paint()..filterQuality = FilterQuality.medium);
    canvas.restore();
  }

  // ------------------------------------------------------------ drawTrail()
  void _drawTrail(Canvas canvas, double now) {
    final List<BmTrailPt> trail = e.trail;
    final int n = trail.length;
    if (n < 2) return;
    const double bw = BR;
    List<double> nrm(int i) {
      final BmTrailPt p = trail[math.max(0, i - 1)], q = trail[math.min(n - 1, i)];
      final double dx = q.x - p.x, dy = q.y - p.y;
      double l = math.sqrt(dx * dx + dy * dy);
      if (l == 0) l = 1;
      return <double>[-dy / l, dx / l];
    }

    // A low-contrast ground mark sits below the neon trail. It follows the
    // ball's actual path, fades with the stored trail alpha, and reads like a
    // speed/skid trace on the pitch instead of a floating laser effect.
    for (int i = 1; i < n; i++) {
      final BmTrailPt p = trail[i - 1], q = trail[i];
      final double f = q.a.clamp(0.0, 1.0).toDouble();
      final List<double> nn = nrm(i);
      final double offset = bw * 0.42;
      final Paint mark = Paint()
        ..blendMode = BlendMode.multiply
        ..strokeCap = StrokeCap.round
        ..strokeWidth = bw * (0.70 + f * 0.85)
        ..color = _rgba(16, 28, 12, 0.10 + f * 0.16);
      canvas.drawLine(Offset(p.x + nn[0] * offset, p.y + nn[1] * offset),
          Offset(q.x + nn[0] * offset, q.y + nn[1] * offset), mark);
      canvas.drawLine(Offset(p.x - nn[0] * offset, p.y - nn[1] * offset),
          Offset(q.x - nn[0] * offset, q.y - nn[1] * offset), mark);
    }

    // Only the low-alpha multiply trace is drawn; the neon/fire/sparkle trail variants were removed.
  }

  // ------------------------------------------------------------ aim()
  void _aim(Canvas canvas, double now) {
    final BmDrag? d = e.drag;
    if (d == null) return;
    final BmBody b = d.b;
    final double dx = d.sx - d.cx, dy = d.sy - d.cy, l = math.sqrt(dx * dx + dy * dy);
    if (l < 18) return;
    final double p = math.min(l, LMAX) / LMAX, ux = dx / l, uy = dy / l;
    double t = 1200;
    for (final BmBody o in e.bodies) {
      if (o == b) continue;
      final double R = b.r + o.r, qx = o.x - b.x, qy = o.y - b.y, u = qx * ux + qy * uy;
      if (u <= 0) continue;
      final double D = u * u - (qx * qx + qy * qy - R * R);
      if (D >= 0) {
        final double h = u - math.sqrt(D);
        if (h > 0 && h < t) t = h;
      }
    }
    if (ux < 0) t = math.min(t, (e.Fl + b.r - b.x) / ux);
    if (ux > 0) t = math.min(t, (e.Fr - b.r - b.x) / ux);
    if (uy < 0) t = math.min(t, (e.Ft + b.r - b.y) / uy);
    if (uy > 0) t = math.min(t, (e.Fb - b.r - b.y) / uy);
    t = math.max(t, 0);
    final double hue = 135 - 135 * p;
    final Color col = Color(bmHslColor(hue, .95, .58)), col2 = Color(bmHslColor((hue + 35) % 360, 1, .76));
    final double sx = b.x + ux * b.r, sy = b.y + uy * b.r, ex = b.x + ux * t, ey = b.y + uy * t;
    final List<int> tm = b.team != 0 ? <int>[255, 110, 110] : <int>[90, 175, 255];
    // drag band (dashed)
    final Offset p0 = Offset(d.sx, d.sy), pc = Offset(d.cx, d.cy);
    _dashed(canvas, p0, pc, 2, 9,
        Paint()
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = _rgba(tm[0], tm[1], tm[2], .35));
    canvas.drawCircle(pc, 9 + p * 4, Paint()..color = _rgba(tm[0], tm[1], tm[2], .55));
    canvas.drawCircle(
        pc,
        9 + p * 4,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white);
    // prediction line
    final Offset s0 = Offset(sx, sy), e0 = Offset(ex, ey);
    final ui.Gradient g = ui.Gradient.linear(s0, e0 == s0 ? s0 + const Offset(0, 1) : e0, <Color>[col, _rgba(255, 255, 255, .2)]);
    _gline(canvas, s0, e0, g, 16, .16);
    _gline(canvas, s0, e0, g, 3, .85);
    // moving chevrons
    const double step = 44;
    final double off = (now / 12) % step;
    for (double dd = b.r + 14 + off; dd < t - b.r * .5; dd += step) {
      final double x = b.x + ux * dd, y = b.y + uy * dd, a = math.max(0, 1 - dd / t * .75);
      final Path ch = Path()
        ..moveTo(x - uy * 9 - ux * 8, y + ux * 9 - uy * 8)
        ..lineTo(x + ux * 5, y + uy * 5)
        ..lineTo(x + uy * 9 - ux * 8, y - ux * 9 - uy * 8);
      canvas.drawPath(
          ch,
          Paint()
            ..blendMode = BlendMode.plus
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = 4
            ..color = col2.withValues(alpha: a.clamp(0.0, 1.0).toDouble()));
    }
    // wall bounce preview
    {
      double rx = ux, ry = uy;
      bool hit = false;
      const double eps = 2;
      if (ex <= e.Fl + b.r + eps && ux < 0) {
        rx = -ux;
        hit = true;
      } else if (ex >= e.Fr - b.r - eps && ux > 0) {
        rx = -ux;
        hit = true;
      } else if (ey <= e.Ft + b.r + eps && uy < 0) {
        ry = -uy;
        hit = true;
      } else if (ey >= e.Fb - b.r - eps && uy > 0) {
        ry = -uy;
        hit = true;
      }
      if (hit) {
        final Offset a = Offset(ex, ey), z = Offset(ex + rx * 170, ey + ry * 170);
        _dashed(
            canvas,
            a,
            z,
            8,
            10,
            Paint()
              ..blendMode = BlendMode.plus
              ..strokeWidth = 3
              ..strokeCap = StrokeCap.round
              ..shader = ui.Gradient.linear(a, z, <Color>[_rgba(255, 255, 255, .55), _rgba(255, 255, 255, 0)]),
            phase: (now / 30) % 18);
      }
    }
    // impact point: pulsing ring + sight ticks
    {
      final double pu = .5 + .5 * math.sin(now / 140), R = b.r * (1 + .12 * pu);
      canvas.drawCircle(
          e0,
          R,
          Paint()
            ..blendMode = BlendMode.plus
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.5
            ..color = col2.withValues(alpha: .9));
      for (int k = 0; k < 4; k++) {
        final double a = k * 1.5708 + now / 700, ca = math.cos(a), sa = math.sin(a);
        canvas.drawLine(
            Offset(ex + ca * (R + 4), ey + sa * (R + 4)),
            Offset(ex + ca * (R + 13), ey + sa * (R + 13)),
            Paint()
              ..blendMode = BlendMode.plus
              ..strokeWidth = 2.5
              ..strokeCap = StrokeCap.round
              ..color = col2.withValues(alpha: (.5 + .4 * pu).clamp(0.0, 1.0).toDouble()));
      }
      canvas.drawCircle(
          e0,
          R * .55,
          Paint()
            ..blendMode = BlendMode.plus
            ..color = col.withValues(alpha: .25));
    }
    // power ring: 30 segments
    {
      const int N = 30;
      final double r1 = b.r + 20;
      for (int k = 0; k < N; k++) {
        final double a0 = -1.5708 + k / N * 6.2832 + .03;
        final bool lit = k / N < p;
        canvas.drawArc(
            Rect.fromCircle(center: Offset(b.x, b.y), radius: r1),
            a0,
            6.2832 / N - .07,
            false,
            Paint()
              ..blendMode = BlendMode.plus
              ..style = PaintingStyle.stroke
              ..strokeWidth = 4
              ..color = lit ? Color(bmHslColor(135 - 135 * (k / N), .95, .58)) : _rgba(255, 255, 255, .18));
      }
    }
    // main neon arrow
    {
      final double base = b.r + 30, Lh = 34 + p * 92, hl = 24 + p * 16, sw = 3.5 + p * 5, hw = 14 + p * 9;
      final double tipx = b.x + ux * (base + Lh), tipy = b.y + uy * (base + Lh), nx = -uy, ny = ux;
      final double bx = b.x + ux * base, by = b.y + uy * base, jx = b.x + ux * (base + Lh - hl), jy = b.y + uy * (base + Lh - hl);
      final Path arrow = Path()
        ..moveTo(bx + nx * sw * .3, by + ny * sw * .3)
        ..lineTo(jx + nx * sw, jy + ny * sw)
        ..lineTo(jx + nx * hw, jy + ny * hw)
        ..lineTo(tipx, tipy)
        ..lineTo(jx - nx * hw, jy - ny * hw)
        ..lineTo(jx - nx * sw, jy - ny * sw)
        ..lineTo(bx - nx * sw * .3, by - ny * sw * .3)
        ..close();
      final ui.Gradient fg = ui.Gradient.linear(Offset(bx, by), Offset(tipx, tipy), <Color>[_rgba(255, 255, 255, .15), col, Colors.white], <double>[0, .55, 1]);
      canvas.drawPath(
          arrow,
          Paint()
            ..blendMode = BlendMode.plus
            ..color = col
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 11));
      canvas.drawPath(
          arrow,
          Paint()
            ..blendMode = BlendMode.plus
            ..shader = fg);
      canvas.drawPath(
          arrow,
          Paint()
            ..blendMode = BlendMode.plus
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8
            ..color = _rgba(255, 255, 255, .9));
      final int nCh = 1 + (p > .35 ? 1 : 0) + (p > .7 ? 1 : 0);
      for (int k = 1; k <= nCh; k++) {
        final double dd = base - k * 13, x = b.x + ux * dd, y = b.y + uy * dd;
        final Path ch = Path()
          ..moveTo(x - uy * (10 + p * 5) - ux * 7, y + ux * (10 + p * 5) - uy * 7)
          ..lineTo(x + ux * 2, y + uy * 2)
          ..lineTo(x + uy * (10 + p * 5) - ux * 7, y - ux * (10 + p * 5) - uy * 7);
        canvas.drawPath(
            ch,
            Paint()
              ..blendMode = BlendMode.plus
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3.5
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round
              ..color = col2.withValues(alpha: .75 / k));
      }
      // power percent
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: '${(p * 100).round()}%',
          style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
              shadows: <Shadow>[Shadow(color: col, blurRadius: 10)]),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final double tx = b.x - ux * (b.r + 44), ty = b.y - uy * (b.r + 44) - (uy > .5 ? -4 : 0);
      tp.paint(canvas, Offset(tx - tp.width / 2, ty - tp.height / 2));
    }
  }

  void _gline(Canvas canvas, Offset a, Offset b, ui.Gradient g, double w, double alpha) {
    canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
    canvas.drawLine(
        a,
        b,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = g
          ..strokeCap = StrokeCap.round
          ..strokeWidth = w);
    canvas.restore();
  }

  void _dashed(Canvas canvas, Offset a, Offset b, double on, double off, Paint p, {double phase = 0}) {
    final Offset d = b - a;
    final double len = d.distance;
    if (len <= 0) return;
    final Offset u = d / len;
    double pos = -phase;
    while (pos < len) {
      final double s0 = math.max(0, pos), s1 = math.min(len, pos + on);
      if (s1 > s0) canvas.drawLine(a + u * s0, a + u * s1, p);
      pos += on + off;
    }
  }

  @override
  bool shouldRepaint(covariant BmPainter oldDelegate) => true;
}
