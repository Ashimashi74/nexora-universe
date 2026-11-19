import 'dart:math' as math;

/// Fixed virtual canvas the court is composed on (9:16 portrait). It is scaled uniformly to the phone, so the court
/// keeps the same aspect and the same framing on every screen ([BasketLayout]).
const double kCanvasW = 360, kCanvasH = 640;

class CanvasPoint {
  const CanvasPoint(this.x, this.y, this.scale);
  final double x, y;

  /// Canvas units per metre at this depth.
  final double scale;
}

/// Pinhole camera behind the shooter, looking straight down the court (+z), level (no pitch).
/// Everything — the court lines, backboard, rim, net and ball — is drawn through [project], and the physics uses
/// the same metres, so what is drawn is exactly what collides.
class BasketCamera {
  BasketCamera._();

  static const double camY = 2.0, camZ = -3.0;
  static const double focal = 780; // canvas units
  static const double cx = kCanvasW / 2;

  /// Horizon height on the canvas: chosen so the bottom of the ball in the shooter's hands (1.25 m high at the
  /// free-throw line, r = 0.1194 m) sits at canvas y = 612.
  static const double cy = 612 + focal * (1.25 - 0.1194 - camY) / (0 - camZ);

  static CanvasPoint project(double x, double y, double z) {
    final double d = math.max(0.05, z - camZ);
    final double s = focal / d;
    return CanvasPoint(cx + x * s, cy - (y - camY) * s, s);
  }

  /// World x at depth [z] that projects to canvas x [px].
  static double unprojectX(double px, double z) => (px - cx) * (z - camZ) / focal;
}

/// Where the canvas sits on the phone. The court is fitted (uniform scale, centred) inside the area left between
/// the HUD (below the status bar / notch and the host's top buttons) and the gesture bar, and inside the side
/// insets, so nothing important is ever behind a system bar or the HUD.
class BasketLayout {
  const BasketLayout(this.scale, this.ox, this.oy, this.areaTop, this.areaBottom);

  /// Space reserved under the status bar for the host buttons row (56 dp) + the score row.
  static const double kHudHeight = 104;
  static const double kBottomGap = 8;

  final double scale, ox, oy;
  final double areaTop, areaBottom;

  double get width => kCanvasW * scale;
  double get height => kCanvasH * scale;

  static BasketLayout fit(double w, double h,
      {double padTop = 0, double padBottom = 0, double padLeft = 0, double padRight = 0}) {
    final double top = padTop + kHudHeight;
    final double bottom = h - padBottom - kBottomGap;
    final double availW = math.max(1, w - padLeft - padRight);
    final double availH = math.max(1, bottom - top);
    final double s = math.min(availW / kCanvasW, availH / kCanvasH);
    return BasketLayout(s, padLeft + (availW - kCanvasW * s) / 2, top + (availH - kCanvasH * s) / 2, top, bottom);
  }

  /// Canvas → screen.
  (double, double) toScreen(double x, double y) => (ox + x * scale, oy + y * scale);

  /// Screen → canvas (swipes).
  (double, double) toCanvas(double x, double y) => ((x - ox) / scale, (y - oy) / scale);
}

// Canvas shapes of the physics bodies: the painter draws exactly these, so drawn = hitbox.
// World constants are passed in so this file stays free of the rules engine.

/// Ball circle on the canvas for a ball of radius [r] metres at (x, y, z).
({double cx, double cy, double r}) ballOnCanvas(double x, double y, double z, double r) {
  final CanvasPoint p = BasketCamera.project(x, y, z);
  return (cx: p.x, cy: p.y, r: r * p.scale);
}

/// Axis-aligned rectangle of a backboard plate (the board plane faces the camera, so it projects to a rectangle).
({double l, double t, double r, double b}) boardOnCanvas(double hoopX, double w, double bottom, double h, double z) {
  final CanvasPoint a = BasketCamera.project(hoopX - w / 2, bottom + h, z);
  final CanvasPoint b = BasketCamera.project(hoopX + w / 2, bottom, z);
  return (l: a.x, t: a.y, r: b.x, b: b.y);
}

/// Horizontal half-width and centre of a horizontal ring of radius [ringR] at height [y], depth [z].
({double cx, double cy, double halfW}) ringOnCanvas(double hoopX, double y, double z, double ringR) {
  final CanvasPoint p = BasketCamera.project(hoopX, y, z);
  // widest projected extent: the ring points at the camera's depth of the centre (cos = ±1)
  return (cx: p.x, cy: p.y, halfW: ringR * p.scale);
}
