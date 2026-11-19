import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../core/kart_core.dart';

/// Screen layout for the kart race, computed from the screen size and the system insets (notch, status bar,
/// gesture bar). Everything the player must see lives inside the safe rect; the world is drawn with one uniform
/// zoom chosen so that a fixed reference view of the world ([viewW] x [viewH] world units) always fits the safe
/// area, which keeps karts, the track and the props in the same proportions on every phone and tablet.
class KartLayout {
  KartLayout._(this.size, this.safe, this.zoomBase, this.focal, this.exitButton, this.hudLeft, this.minimap,
      this.steerLeft, this.steerRight, this.itemButton, this.driftButton, this.control);

  /// Reference view of the world that is always visible (world units).
  static const double viewW = 560, viewH = 960;

  /// Host exit button (top-start corner) – keep it free.
  static const double exitSize = 56;

  /// Approximate height of the place + lap pills block.
  static const double hudBlockH = 96, hudBlockW = 120;

  factory KartLayout.compute(Size size, EdgeInsets pad) {
    final Rect safe = Rect.fromLTRB(pad.left, pad.top, size.width - pad.right, size.height - pad.bottom);
    final double ctl = (math.min(safe.width, safe.height * 0.5625) / 393).clamp(0.82, 1.3);
    final double steer = 78 * ctl, item = 62 * ctl, drift = 86 * ctl, gap = 14 * ctl;
    final double margin = 14;
    final double bottom = safe.bottom - 18;
    final Rect steerLeft = Rect.fromLTWH(safe.left + margin, bottom - steer, steer, steer);
    final Rect steerRight = Rect.fromLTWH(steerLeft.right + gap, bottom - steer, steer, steer);
    final Rect driftB = Rect.fromLTWH(safe.right - margin - drift, bottom - drift, drift, drift);
    final Rect itemB = Rect.fromLTWH(safe.right - margin - item, driftB.top - 12 * ctl - item, item, item);
    final Rect exit = Rect.fromLTWH(safe.left, safe.top, exitSize, exitSize);
    final double hudTop = safe.top + exitSize + 8;
    final Rect hudLeft = Rect.fromLTWH(safe.left + 12, hudTop, hudBlockW, hudBlockH);
    final Rect minimap = Rect.fromLTWH(safe.right - 12 - 112, hudTop, 112, 84);
    final double playTop = hudLeft.bottom;
    final double playBottom = math.min(steerLeft.top, itemB.top);
    final double zoom = math.min(safe.width / viewW, (safe.height) / viewH);
    // Chase camera: the player's kart sits in the lower part of the play area (more road visible ahead),
    // always above the control row and below the HUD, with its whole rotated footprint on screen.
    final double kr = KartDims.halfDiagonal * zoom * 1.25;
    final double fy = (playTop + (playBottom - playTop) * 0.72).clamp(playTop + kr, steerLeft.top - kr - 8);
    final Offset focal = Offset(safe.center.dx, fy);
    return KartLayout._(size, safe, zoom, focal, exit, hudLeft, minimap, steerLeft, steerRight, itemB, driftB, ctl);
  }

  final Size size;
  final Rect safe;

  /// World → screen scale at rest (the camera zooms out slightly with speed, never by more than [minZoomFactor]).
  final double zoomBase;
  static const double minZoomFactor = 0.88;
  final Offset focal;
  final Rect exitButton, hudLeft, minimap, steerLeft, steerRight, itemButton, driftButton;

  /// Control scale factor.
  final double control;

  List<Rect> get controls => <Rect>[steerLeft, steerRight, itemButton, driftButton];
  List<Rect> get hud => <Rect>[hudLeft, minimap];

  /// Screen-space box guaranteed to contain the player's kart at any heading (at rest zoom).
  Rect get kartScreenBox => Rect.fromCircle(center: focal, radius: KartDims.halfDiagonal * zoomBase);

  /// The drawn kart size on screen at rest zoom.
  Size get kartScreenSize => Size(KartDims.length * zoomBase, KartDims.width * zoomBase);
}
