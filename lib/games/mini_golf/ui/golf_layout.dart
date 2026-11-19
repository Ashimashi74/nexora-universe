import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../core/golf_core.dart';

/// Top of the HUD row below the host's exit button (56x56 safe area + margin).
const double kGolfHudTop = 62;

/// Height reserved for the single HUD row (pills are ~32 px tall; the row scales down rather than wrapping).
const double kGolfHudH = 34;

/// Space kept free under the course for the "pull back & release" hint.
const double kGolfHintH = 44;

/// Where the course sits on screen. One uniform scale for x and y, so every phone and tablet shows the same
/// aspect, and the whole [kGolfView] (rails, flag, shadows) stays inside the safe area, clear of the notch, the
/// status bar, the HUD and the gesture bar.
class GolfLayout {
  const GolfLayout(this.scale, this.origin, this.safe);

  /// Screen pixels per course unit.
  final double scale;

  /// Screen position of course point (0, 0).
  final Offset origin;

  /// The rect the course view may use.
  final Rect safe;

  Offset toScreen(double x, double y) => origin + Offset(x, y) * scale;
  Offset toCourse(Offset p) => (p - origin) / scale;

  /// The on-screen rect of [kGolfView].
  Rect get viewRect => Rect.fromPoints(toScreen(kGolfView.l, kGolfView.t), toScreen(kGolfView.r, kGolfView.b));
}

GolfLayout golfLayout(Size size, EdgeInsets pad) {
  final double top = pad.top + kGolfHudTop + kGolfHudH + 8;
  final double bottom = math.max(top + 1, size.height - pad.bottom - kGolfHintH);
  final double left = pad.left + 8, right = math.max(left + 1, size.width - pad.right - 8);
  const double vw = 282.0 - 18.0, vh = 512.0 - 14.0; // kGolfView size
  assert(vw == kGolfView.r - kGolfView.l && vh == kGolfView.b - kGolfView.t);
  final double s = math.max(0.05, math.min((right - left) / vw, (bottom - top) / vh));
  final Offset origin = Offset(
    (left + right) / 2 - (kGolfView.l + vw / 2) * s,
    (top + bottom) / 2 - (kGolfView.t + vh / 2) * s,
  );
  return GolfLayout(s, origin, Rect.fromLTRB(left, top, right, bottom));
}

/// Pull-back distance in course units that gives a full-power putt.
const double kGolfFullPull = 140;

/// Below this power a release cancels the putt.
const double kGolfMinPower = 0.04;

/// Converts a drag (finger start → now, screen px) into (angle, power). The putt goes opposite to the pull; power
/// is linear in pull distance (ball speed), measured in course units so it feels the same on every screen.
(double, double)? golfAim(Offset from, Offset to, double scale) {
  final Offset v = (from - to) / scale;
  final double p = (v.distance / kGolfFullPull).clamp(0.0, 1.0);
  if (p < kGolfMinPower) return null;
  return (math.atan2(v.dy, v.dx), p);
}
