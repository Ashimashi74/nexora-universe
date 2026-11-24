// Finger soccer v9: the match scene runs on the Flame engine.
//
// FsFlameGame owns the match loop and the playfield: Flame's game loop calls [FsFlameGame.update] every frame, which
// advances the deterministic engine (BmEngine.frame through the view's tick, unchanged: the same fixed physics steps
// and the same online move log), and each layer of the playfield is its own Flame component, drawn in priority order:
// pitch art, under-layer (trails, shadows, aim circle, turn rings), discs, ball, over-layer (goal sprites, aim arrow)
// and the live score on the art's two side displays. Touch input on the playfield arrives through Flame's drag events
// ([FsPitchInput]) and is mapped to world coordinates with the same BmView transform the layers draw with.
//
// The Flutter widget around the GameWidget only keeps what is not the playfield: the top bar (clock, menu, formation
// button), the bottom strip and the menus / score table.
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';

import '../core/bm_engine.dart';
import 'bm_painter.dart';

/// Pointer callbacks in world units (BmEngine.pointerDown / pointerMove / pointerUp / pointerCancel).
class FsPointerSink {
  const FsPointerSink({required this.down, required this.move, required this.up, required this.cancel});
  final void Function(double x, double y) down, move;
  final void Function() up, cancel;
}

class FsFlameGame extends FlameGame {
  FsFlameGame({required this.painter, required this.onFrame, required this.pointer});

  /// The shared renderer: every layer component draws one of its phases.
  final BmPainter painter;

  /// Advances the match by `dt` seconds (the view's tick: engine frame, clocks, net waiters, end of match).
  final void Function(double dt) onFrame;
  final FsPointerSink pointer;

  BmEngine get engine => painter.e;
  BmView get view => painter.view;

  /// Frames this game has advanced (tests).
  int frames = 0;

  @override
  ui.Color backgroundColor() => const ui.Color(0xFF03060D);

  @override
  Future<void> onLoad() async {
    await addAll(<Component>[
      FsPitchLayer(painter)..priority = 0,
      FsUnderLayer(painter)..priority = 1,
      FsDiscsLayer(painter)..priority = 2,
      FsBallLayer(painter)..priority = 3,
      FsOverLayer(painter)..priority = 4,
      FsScoreLayer(painter)..priority = 5,
      FsPitchInput(this)..priority = 6,
    ]);
  }

  @override
  void update(double dt) {
    // Flame hands us real frame time; the engine's own fixed-step accumulator (and kBmSimRate) turns it into
    // identical physics steps on every phone. A long hitch is clamped like the old ticker path (BmEngine.frame).
    //
    // Flame's GameWidget also calls update(0) from inside its LayoutBuilder whenever the canvas is resized (first
    // layout, rotation, keyboard). No time has passed then, and advancing from there would notify the view's frame
    // listeners in the middle of a build ("setState() called during build"), so a zero-length frame is skipped.
    if (dt > 0) {
      onFrame(dt);
      frames++;
    }
    super.update(dt);
  }
}

/// Base of every playfield layer: covers the whole game canvas and paints one phase of [BmPainter].
abstract class FsLayer extends Component with HasGameReference<FsFlameGame> {
  FsLayer(this.painter);
  final BmPainter painter;

  Size get canvasSize => Size(game.size.x, game.size.y);
}

/// The pitch art (with the blurred surround). Also lays the view out for this frame's canvas size.
class FsPitchLayer extends FsLayer {
  FsPitchLayer(super.painter);
  @override
  void render(ui.Canvas canvas) => painter.paintBackground(canvas, canvasSize);
}

/// Motion trails, contact shadows, the pull circle and the turn rings.
class FsUnderLayer extends FsLayer {
  FsUnderLayer(super.painter);
  @override
  void render(ui.Canvas canvas) => painter.paintUnder(canvas);
}

/// The ten discs (team badges as 3D pucks).
class FsDiscsLayer extends FsLayer {
  FsDiscsLayer(super.painter);
  @override
  void render(ui.Canvas canvas) => painter.paintDiscs(canvas);
}

/// The match ball (rolled by the 3D ball renderer).
class FsBallLayer extends FsLayer {
  FsBallLayer(super.painter);
  @override
  void render(ui.Canvas canvas) => painter.paintBall(canvas);
}

/// Goal sprites of pitches without built-in goals, the aim arrow and the debug colliders.
class FsOverLayer extends FsLayer {
  FsOverLayer(super.painter);
  @override
  void render(ui.Canvas canvas) => painter.paintOver(canvas);
}

/// The live score on the pitch art's side displays (seven-segment digits, blue = bottom side).
class FsScoreLayer extends FsLayer {
  FsScoreLayer(super.painter);
  @override
  void render(ui.Canvas canvas) => painter.paintScore(canvas);
}

/// Touch on the playfield: one finger at a time drives the engine's aim (pull back and release to shoot).
class FsPitchInput extends PositionComponent with DragCallbacks {
  FsPitchInput(this.g);
  final FsFlameGame g;
  int? _pointer;

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    this.size = size;
  }

  @override
  bool containsLocalPoint(Vector2 point) => true;

  ui.Offset _world(Vector2 p) => g.view.toWorld(ui.Offset(p.x, p.y));

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (_pointer != null) return;
    _pointer = event.pointerId;
    final ui.Offset w = _world(event.canvasPosition);
    g.pointer.down(w.dx, w.dy);
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (event.pointerId != _pointer) return;
    final ui.Offset w = _world(event.canvasEndPosition);
    g.pointer.move(w.dx, w.dy);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (event.pointerId != _pointer) return;
    _pointer = null;
    g.pointer.up();
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    if (event.pointerId == _pointer) {
      _pointer = null;
      g.pointer.cancel();
    }
    super.onDragCancel(event);
  }
}
