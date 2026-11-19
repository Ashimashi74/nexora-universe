import 'dart:math' as math;
import 'package:flutter/painting.dart';

/// Screen placement of the Bomb Arena board.
///
/// The board is [cols] x [rows] square tiles. The tile size is the largest that fits between the HUD (below the
/// status bar / notch and the host's exit button) and the touch controls (above the gesture bar), with a frame
/// margin on every side, and it is snapped to whole physical pixels so tile edges never blur or drift. The board
/// therefore keeps the same 13:11 aspect on every phone and tablet; only its scale changes. Everything the game
/// draws in tile units (tiles, players, bombs, fire) and every hitbox uses this one transform.
class BombLayout {
  const BombLayout({
    required this.size,
    required this.padding,
    required this.dpr,
    required this.tile,
    required this.origin,
    required this.cols,
    required this.rows,
    required this.hudTop,
    required this.safeTop,
    required this.controlsTop,
  });

  /// Gap between the safe-area top and the HUD row (keeps the host's 56 px exit button clear).
  static const double hudOffset = 62;
  static const double hudHeight = 30;

  /// Height of the touch-control band above the bottom safe inset (joystick, bomb and trap buttons, stats).
  static const double controlsHeight = 176;
  static const double sideMargin = 8;

  /// Frame drawn around the board, in tiles.
  static const double frame = 0.25;

  final Size size;
  final EdgeInsets padding;
  final double dpr;

  /// Tile edge in logical pixels (a whole number of physical pixels).
  final double tile;

  /// Top-left of tile (0, 0) in logical pixels (on the physical pixel grid).
  final Offset origin;
  final int cols, rows;
  final double hudTop;

  /// Top of the area the board may use (below the HUD).
  final double safeTop;

  /// Top of the touch-control band; the board never reaches below it.
  final double controlsTop;

  static BombLayout compute(Size size, EdgeInsets padding, double dpr, {int cols = 13, int rows = 11}) {
    final double px = dpr > 0 ? dpr : 1;
    final double hudTop = padding.top + hudOffset;
    final double top = hudTop + hudHeight + 8;
    final double controlsTop = size.height - padding.bottom - controlsHeight;
    final double left = padding.left + sideMargin, right = size.width - padding.right - sideMargin;
    final double availW = math.max(0, right - left);
    final double availH = math.max(0, controlsTop - 8 - top);
    double tile = math.min(availW / (cols + 2 * frame), availH / (rows + 2 * frame));
    tile = math.max(1 / px, (tile * px).floorToDouble() / px);
    final double bw = tile * cols, bh = tile * rows;
    double ox = left + (availW - bw) / 2;
    double oy = top + (availH - bh) / 2;
    ox = (ox * px).roundToDouble() / px;
    oy = (oy * px).roundToDouble() / px;
    return BombLayout(
      size: size,
      padding: padding,
      dpr: px,
      tile: tile,
      origin: Offset(ox, oy),
      cols: cols,
      rows: rows,
      hudTop: hudTop,
      safeTop: top,
      controlsTop: controlsTop,
    );
  }

  /// The playfield (tiles only).
  Rect get board => Rect.fromLTWH(origin.dx, origin.dy, tile * cols, tile * rows);

  /// The playfield plus its frame.
  Rect get framed => board.inflate(tile * frame);

  /// Tile-space point → screen.
  Offset toScreen(double x, double y) => Offset(origin.dx + x * tile, origin.dy + y * tile);

  /// Screen point → tile-space point.
  Offset toTiles(Offset p) => Offset((p.dx - origin.dx) / tile, (p.dy - origin.dy) / tile);

  /// Screen rect of tile (x, y).
  Rect tileRect(int x, int y) => Rect.fromLTWH(origin.dx + x * tile, origin.dy + y * tile, tile, tile);
}
