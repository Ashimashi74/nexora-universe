// Finger soccer v13 (owner request 2026-11-24, "افکت مهره‌ها"): a coloured, fading, tapered glow streak behind every
// sliding disc.
//
// RENDER ONLY. The trail is sampled from where each disc is DRAWN (the painter's interpolated position) on the
// painter's own millisecond clock, so it never reads or writes physics state, never draws from the simulation RNG and
// never touches snapshots or the online sync: offline, bot and online phones simply draw what they already show.
//
// Why the old disc ribbon was hardly ever seen: it was built from BmEngine.fx()'s per-FRAME points (BmBody.tr, capped
// at 14 points) and its width grew with the path length. On a 90-120 Hz phone 14 frames are only ~0.1 s of slide,
// i.e. about one disc radius of path, which lies almost entirely under the disc sprite itself, and the length-scaled
// width made the little that stuck out a thin sliver. This trail is time based (the last [kBmTrailLifeMs] of motion
// on every frame rate) with a fixed width, so it shows the same on every phone.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../core/bm_data.dart';
import '../core/bm_engine.dart';

/// How long a trail point lives (ms): the streak fades out within ~0.35 s.
const double kBmTrailLifeMs = 350;

/// Full streak width at the disc, in disc radii (tapers to 0 at the tail).
const double kBmTrailWidth = .6;

/// Below this speed (world units / s, the engine's own disc-trail threshold) a disc adds no new points.
const double kBmTrailMinSpeed = 140 * K;

/// The trail palette of a side (kBmTR): 0 = this phone's side (bottom, blue like its turn ring and score display),
/// 1 = the opponent (top, red). Colours: [0] body, [1] glow, [2] hot core.
BmTrail bmSideTrail(int team) {
  final String k = team == 0 ? 'plasma' : 'blade';
  for (final BmTrail t in kBmTR) {
    if (t.k == k) return t;
  }
  return kBmTR.isEmpty ? const BmTrail('plasma', <int>[0xFF2F8BFF, 0xFF7FC6FF, 0xFFFFFFFF]) : kBmTR[team % kBmTR.length];
}

class BmTrailSample {
  BmTrailSample(this.p, this.t);
  final Offset p;
  final double t; // ms
}

/// Per-disc trail history, owned by the painter. [sample] once per drawn frame, then [paint].
class BmDiscTrails {
  final Map<BmBody, List<BmTrailSample>> _m = <BmBody, List<BmTrailSample>>{};
  double _last = -1;

  /// Trail points currently held for [b] (tests).
  List<BmTrailSample> pointsOf(BmBody b) => _m[b] ?? const <BmTrailSample>[];

  void clear() => _m.clear();

  /// Records where each moving disc is drawn now ([pos]) and drops points older than [kBmTrailLifeMs].
  void sample(BmEngine e, Offset Function(BmBody b) pos, double now) {
    if (now < _last || e.bodies.isEmpty || e.phase == 'over') {
      // clock restarted, no match, or the final whistle: nothing to trail
      _m.clear();
      _last = now;
      return;
    }
    _last = now;
    // bodies are rebuilt on every kickoff reset: forget the old ones
    _m.removeWhere((BmBody b, _) => !e.bodies.contains(b));
    for (final BmBody b in e.bodies) {
      if (b == e.ball) continue;
      final Offset p = pos(b);
      List<BmTrailSample>? l = _m[b];
      // a jump (snapshot, formation change, kickoff) is never smeared into a streak
      if (l != null && l.isNotEmpty && (p - l.last.p).distance > b.r * 4) l.clear();
      final double sp = math.sqrt(b.vx * b.vx + b.vy * b.vy);
      if (sp > kBmTrailMinSpeed) {
        l ??= _m[b] = <BmTrailSample>[];
        if (l.isEmpty || (p - l.last.p).distance >= .5) {
          l.add(BmTrailSample(p, now));
          if (l.length > 96) l.removeAt(0);
        }
      }
      if (l != null) {
        l.removeWhere((BmTrailSample s) => now - s.t > kBmTrailLifeMs);
        if (l.isEmpty) _m.remove(b);
      }
    }
  }

  /// Draws every trail in world coordinates (the caller has applied the world transform). [glow] adds the soft
  /// blurred halo (off with reduced effects).
  void paint(Canvas canvas, BmEngine e, Offset Function(BmBody b) pos, double now, {bool glow = true}) {
    _m.forEach((BmBody b, List<BmTrailSample> l) {
      if (l.isEmpty) return;
      final List<Offset> pts = <Offset>[for (final BmTrailSample s in l) s.p];
      final List<double> f = <double>[for (final BmTrailSample s in l) (1 - (now - s.t) / kBmTrailLifeMs).clamp(0.0, 1.0)];
      // still sliding: the streak runs right up to the disc as drawn this frame
      final Offset head = pos(b);
      if ((head - pts.last).distance >= .5 && (head - pts.last).distance < b.r * 4) {
        pts.add(head);
        f.add(f.last);
      }
      if (pts.length < 2) return;
      double len = 0;
      for (int i = 1; i < pts.length; i++) {
        len += (pts[i] - pts[i - 1]).distance;
      }
      if (len < b.r * .25) return;
      final double hf = f.last; // whole streak fades once the disc stops
      if (hf <= .01) return;
      final double half = b.r * kBmTrailWidth / 2;
      final List<double> hw = <double>[for (final double v in f) half * math.pow(v, .8).toDouble()];
      hw[0] = 0;
      final BmTrail tr = bmSideTrail(b.team);
      final Color c0 = Color(tr.c[0]), c1 = Color(tr.c[1 % tr.c.length]), c2 = Color(tr.c[2 % tr.c.length]);
      final Offset a = pts.first, z = pts.last == pts.first ? pts.first + const Offset(0, 1) : pts.last;
      if (glow) {
        canvas.drawPath(
            bmTrailRibbon(pts, <double>[for (final double w in hw) w * 1.9]),
            Paint()
              ..blendMode = BlendMode.plus
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, b.r * .22)
              ..shader = ui.Gradient.linear(a, z, <Color>[c1.withValues(alpha: 0), c1.withValues(alpha: .45 * hf)]));
      }
      canvas.drawPath(
          bmTrailRibbon(pts, hw),
          Paint()
            ..blendMode = BlendMode.plus
            ..shader = ui.Gradient.linear(a, z, <Color>[
              c0.withValues(alpha: 0),
              c0.withValues(alpha: .55 * hf),
              c1.withValues(alpha: .85 * hf),
            ], <double>[0, .45, 1]));
      canvas.drawPath(
          bmTrailRibbon(pts, <double>[for (final double w in hw) w * .38]),
          Paint()
            ..blendMode = BlendMode.plus
            ..shader = ui.Gradient.linear(a, z, <Color>[c2.withValues(alpha: 0), c2.withValues(alpha: .7 * hf)], <double>[.35, 1]));
    });
  }
}

/// Tapered ribbon through [pts] (oldest first) with half widths [hw].
Path bmTrailRibbon(List<Offset> pts, List<double> hw) {
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
