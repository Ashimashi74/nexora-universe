import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../arcade_kit/arcade_fx.dart';
import '../arcade_kit/arcade_shell.dart' show ArcadeSoloShell, SoloRun;
import '../arcade_kit/arcade_skin.dart';
import '../core/game_contract.dart';
import 'ui/solo_art.dart';

// `SoloRun` is declared in arcade_shell.dart and is the shell's controller; re-exported so
// registry and board files that only need the controller do not import the shell machinery.
export '../arcade_kit/arcade_shell.dart' show SoloRun;

/// Drawing primitives the boards paint with (shaded blocks, spheres, glows, particles).
export '../arcade_kit/arcade_fx.dart'
    show
        ArcadeFx,
        FloatText,
        Particle,
        ParticleKind,
        drawLabel,
        paintBackdrop,
        paintBlock,
        paintGlow,
        paintNeonPath,
        paintPulseRing,
        paintShadow,
        paintSphere,
        paintTrail,
        paintVignette,
        shade;

export 'ui/solo_art.dart';

/// ===================== SOLO ARCADE KIT =====================
/// Shared plumbing and the visual system for the ten solo arcade games.
///
///  * `SoloDef` declares a game (title, hint, accent, board builder) and
///    [buildSoloGame] wraps it in `ArcadeSoloShell` — so the ready card, HUD, medals,
///    daily challenge, personal best and the hand-off to the host are identical for
///    every solo game.
///  * [SoloBoard] is the base class a game's board extends: it owns one ticker, feeds the
///    game a clamped delta time (never more than 20 ms, so a hitch cannot tunnel objects),
///    runs a particle/shake FX system and repaints a single CustomPainter instead of
///    rebuilding widgets. It also tracks the play rect so every board can lay itself out
///    between the shell HUD and the control deck.
///  * [SoloStage] is the shared control deck: glass pads that drive the same input the
///    playfield accepts by touch, so a game is always playable one-handed.
/// ===========================================================

/// How a solo game takes input.
enum SoloControl {
  /// Left/right arrows (puzzle, wall, racer steering).
  dpad,

  /// One large action button (jump, drop, throw).
  tap,

  /// Free dragging (slice, aim).
  drag,
}

/// One solo game: metadata plus the widget that plays it.
class SoloDef {
  const SoloDef({
    required this.id,
    required this.titleFa,
    required this.titleEn,
    required this.hintFa,
    required this.hintEn,
    required this.control,
    required this.board,
    this.accent = const Color(0xFF43D9FF),
    this.accent2 = const Color(0xFFEAFBFF),
  });

  final String id;
  final String titleFa;
  final String titleEn;
  final String hintFa;
  final String hintEn;
  final SoloControl control;
  final Color accent;
  final Color accent2;

  /// Builds the playfield. [run] is the shared shell controller: report score with
  /// `run.add(n)` / `run.set(n)`, end the run with `run.gameOver()`.
  final Widget Function(BuildContext context, SoloRun run) board;
}

/// Registry entry point: asks the shell for the shared frame and hands it the board.
Widget buildSoloGame(SoloDef def, GameLaunch launch) {
  final ArcadeSkin skin = ArcadeSkin(
    gameId: def.id,
    bgTop: SoloArt.mix(const Color(0xFF16233F), def.accent, 0.10),
    bgBottom: const Color(0xFF04060D),
    accent: def.accent,
    accent2: def.accent2,
    glow: def.accent,
  );
  return ArcadeSoloShell(
    launch: launch,
    skin: skin,
    titleFa: def.titleFa,
    titleEn: def.titleEn,
    hintFa: def.hintFa,
    hintEn: def.hintEn,
    builder: def.board,
  );
}

/// Base class of every solo playfield: one ticker, clamped dt, one CustomPainter, one FX system.
///
/// Subclasses implement [step] (advance the simulation) and [paint] (draw it, in the full
/// viewport) and may override [onPointer] for touch input. The board only simulates while the
/// shell reports [SoloRun.playing]; when the run is over it freezes on its last frame so the
/// result overlay appears over a stable image.
abstract class SoloBoard extends StatefulWidget {
  const SoloBoard({super.key, required this.run});
  final SoloRun run;
}

abstract class SoloBoardState<T extends SoloBoard> extends State<T> with SingleTickerProviderStateMixin {
  late final Ticker ticker;

  /// Repaint signal; incremented once per frame (only after the board is laid out).
  final ValueNotifier<int> frame = ValueNotifier<int>(0);
  Duration _last = Duration.zero;

  /// Seconds since the board was created (always advancing, for idle animations).
  double clock = 0;

  /// Particle bursts, screen shake and floating score text.
  late final ArcadeFx fx = ArcadeFx(
    enabled: widget.run.launch.fancyEffects && !widget.run.launch.reducedMotion,
    skin: widget.run.skin,
  );

  /// Last laid-out viewport (0 before the first build).
  Size viewport = Size.zero;

  /// Last pointer position seen, also handed to [onPointer] for `up` / `dragEnd` so a swipe
  /// can be resolved against where the finger actually lifted.
  Offset lastPointer = Offset.zero;

  /// Top safe inset, read on the first build so [playRect] never touches MediaQuery while the
  /// ticker is running (a board may paint before it is laid out).
  double topInset = 0;

  @override
  void initState() {
    super.initState();
    reset();
    ticker = createTicker(_onTick)..start();
  }

  /// Starts a fresh run (called by [restart] and available to subclasses).
  void reset();

  /// Advances the simulation. [dt] is clamped to 20 ms.
  void step(double dt);

  /// Paints the current state. [size] is the full play area.
  void paint(Canvas canvas, Size size);

  /// Touch hook: [at] is the pointer position in viewport coordinates, [kind] is the gesture.
  void onPointer(Offset at, SoloGesture kind) {}

  /// Whether the game is currently simulating (default: only while the run plays).
  bool get simulating => widget.run.playing && !widget.run.over;

  /// Playfield between the shell HUD and the control deck.
  Rect playRect(Size size) => Rect.fromLTRB(
        0,
        SoloMetrics.hudTop + topInset,
        size.width,
        size.height - SoloMetrics.deck,
      );

  /// Bottom deck rect (control area).
  Rect deckRect(Size size) => Rect.fromLTRB(0, size.height - SoloMetrics.deck, size.width, size.height);

  void _onTick(Duration elapsed) {
    double dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt <= 0) return;
    if (dt > 0.02) dt = 0.02;
    clock += dt;
    fx.update(dt);
    if (simulating) step(dt);
    // Only repaint once a size is known: painting with a zero viewport would divide by zero
    // and log a framework error before the first layout.
    if (viewport.isEmpty) return;
    frame.value++;
  }

  void restart() {
    reset();
    setState(() {});
  }

  @override
  void dispose() {
    ticker.dispose();
    frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (BuildContext c, BoxConstraints box) {
          viewport = box.biggest;
          // The shell already keeps its HUD inside the status bar; the board only needs a hair
          // of extra room on notched devices.
          topInset = MediaQuery.paddingOf(context).top * 0.15;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (TapDownDetails d) {
              lastPointer = d.localPosition;
              onPointer(d.localPosition, SoloGesture.down);
            },
            onTapUp: (TapUpDetails d) {
              lastPointer = d.localPosition;
              onPointer(d.localPosition, SoloGesture.up);
            },
            onTapCancel: () => onPointer(lastPointer, SoloGesture.cancel),
            onPanStart: (DragStartDetails d) {
              lastPointer = d.localPosition;
              onPointer(d.localPosition, SoloGesture.dragStart);
            },
            onPanUpdate: (DragUpdateDetails d) {
              lastPointer = d.localPosition;
              onPointer(d.localPosition, SoloGesture.drag);
            },
            onPanEnd: (DragEndDetails d) => onPointer(lastPointer, SoloGesture.dragEnd),
            child: AnimatedBuilder(
              animation: frame,
              builder: (BuildContext c, _) => RepaintBoundary(
                child: CustomPaint(painter: _SoloPainter(this), size: Size.infinite),
              ),
            ),
          );
        },
      );

  /// Paints the FX layer on top of the game (subclasses call this last).
  void paintFx(Canvas canvas, Size size) {
    canvas.save();
    final Offset sh = fx.shakeOffset;
    if (sh != Offset.zero) canvas.translate(sh.dx * 0.5, sh.dy * 0.5);
    fx.paint(canvas);
    canvas.restore();
    fx.paintFlash(canvas, size);
  }

  /// Emits a burst of particles clamped to [rect] so effects never bleed outside the playfield.
  void burst(Rect rect, Offset at, Color color, {int count = 16, double speed = 240, ParticleKind kind = ParticleKind.spark}) {
    if (!rect.contains(at)) return;
    fx.burst(at, color, count: count, speed: speed, kind: kind, life: 0.5, size: 3.4);
  }
}

/// Pointer gesture kinds a board can react to.
enum SoloGesture { down, up, cancel, dragStart, drag, dragEnd }

class _SoloPainter extends CustomPainter {
  _SoloPainter(this.state);
  final SoloBoardState state;

  @override
  void paint(Canvas canvas, Size size) => state.paint(canvas, size);

  @override
  bool shouldRepaint(covariant _SoloPainter old) => true;
}

/// Control deck: a glass panel holding one action button ([SoloStage.action]) and/or a row of
/// directional pads ([SoloStage.left] / [SoloStage.right]). Every game funnels its touch input
/// through the same widgets, so the deck reads as one product across ten games.
class SoloStage extends StatelessWidget {
  const SoloStage({
    super.key,
    required this.accent,
    this.onAction,
    this.onActionDown,
    this.onActionUp,
    this.actionIcon = Icons.arrow_upward_rounded,
    this.actionLabel,
    this.onLeft,
    this.onRight,
    this.leftIcon = Icons.chevron_left_rounded,
    this.rightIcon = Icons.chevron_right_rounded,
    this.extra,
  });

  final Color accent;
  final VoidCallback? onAction;
  final VoidCallback? onActionDown;
  final VoidCallback? onActionUp;
  final IconData actionIcon;
  final String? actionLabel;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final IconData leftIcon;
  final IconData rightIcon;

  /// Optional extra control (e.g. rotate / hard drop).
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final bool hasDpad = onLeft != null || onRight != null;
    return SizedBox(
      height: SoloMetrics.deck,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
        child: Row(
          children: <Widget>[
            if (hasDpad) ...<Widget>[
              SoloPad(icon: leftIcon, onTap: onLeft ?? () {}, accent: accent, size: 66),
              const SizedBox(width: 12),
              SoloPad(icon: rightIcon, onTap: onRight ?? () {}, accent: accent, size: 66),
            ],
            const Spacer(),
            if (extra != null) ...<Widget>[extra!, const SizedBox(width: 12)],
            if (onAction != null)
              _ActionButton(
                accent: accent,
                icon: actionIcon,
                label: actionLabel,
                onTap: onAction!,
                onDown: onActionDown,
                onUp: onActionUp,
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  const _ActionButton({required this.accent, required this.icon, required this.onTap, this.label, this.onDown, this.onUp});
  final Color accent;
  final IconData icon;
  final String? label;
  final VoidCallback onTap;
  final VoidCallback? onDown;
  final VoidCallback? onUp;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final Color accent = widget.accent;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        setState(() => _down = true);
        widget.onDown?.call();
      },
      onTapUp: (_) {
        setState(() => _down = false);
        widget.onUp?.call();
      },
      onTapCancel: () {
        setState(() => _down = false);
        widget.onUp?.call();
      },
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.94 : 1,
        duration: const Duration(milliseconds: 90),
        child: Semantics(
          button: true,
          label: widget.label,
          child: Container(
            height: 72,
            constraints: const BoxConstraints(minWidth: 96),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _down
                    ? <Color>[SoloArt.lift(accent, 0.1), accent]
                    : <Color>[SoloArt.lift(accent, 0.22), SoloArt.sink(accent, 0.18)],
              ),
              border: Border.all(color: SoloArt.a(const Color(0xFFFFFFFF), 0.5), width: 1.2),
              boxShadow: <BoxShadow>[
                BoxShadow(color: SoloArt.a(accent, _down ? 0.55 : 0.32), blurRadius: _down ? 26 : 18, spreadRadius: -2),
                const BoxShadow(color: Color(0x66000000), blurRadius: 12, offset: Offset(0, 6)),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(widget.icon, color: const Color(0xFF06101E), size: 26),
                if (widget.label != null) ...<Widget>[
                  const SizedBox(width: 8),
                  Text(
                    widget.label!,
                    style: const TextStyle(
                      fontFamily: 'ChakraPetch',
                      color: Color(0xFF06101E),
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Square glass frame button used by solo boards for arrows / actions (kept for boards that
/// need a bespoke deck layout).
class SoloPad extends StatefulWidget {
  const SoloPad({
    super.key,
    required this.icon,
    required this.onTap,
    this.onHold,
    this.onRelease,
    this.size = 64,
    this.accent = const Color(0xFF43D9FF),
  });
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onHold;
  final VoidCallback? onRelease;
  final double size;
  final Color accent;

  @override
  State<SoloPad> createState() => _SoloPadState();
}

class _SoloPadState extends State<SoloPad> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          setState(() => _down = true);
          widget.onHold?.call();
        },
        onTapUp: (_) {
          setState(() => _down = false);
          widget.onRelease?.call();
        },
        onTapCancel: () {
          setState(() => _down = false);
          widget.onRelease?.call();
        },
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.92 : 1,
          duration: const Duration(milliseconds: 110),
          child: Semantics(
            button: true,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.size * 0.30),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _down
                      ? <Color>[SoloArt.a(widget.accent, 0.42), const Color(0xFF0C1526)]
                      : const <Color>[Color(0xF0203050), Color(0xF0060C18)],
                ),
                border: Border.all(color: SoloArt.a(widget.accent, _down ? 0.95 : 0.5), width: 1.4),
                boxShadow: <BoxShadow>[
                  BoxShadow(color: SoloArt.a(widget.accent, _down ? 0.45 : 0.14), blurRadius: 20, spreadRadius: -4),
                  const BoxShadow(color: Color(0x66000000), blurRadius: 10, offset: Offset(0, 5)),
                ],
              ),
              child: Icon(widget.icon, color: SoloArt.ink, size: widget.size * 0.46),
            ),
          ),
        ),
      );
}

/// Small centred banner text used for in-run callouts (PERFECT, COMBO, STAGE 2…).
void paintCallout(Canvas canvas, Offset at, String text, Color color, {double scale = 1, double alpha = 1}) {
  if (text.isEmpty || alpha <= 0.01) return;
  canvas.save();
  canvas.translate(at.dx, at.dy);
  canvas.scale(scale);
  SoloArt.label(canvas, text, Offset.zero, size: 22 * scale.clamp(0.8, 1.2), color: SoloArt.ink, glow: color);
  canvas.restore();
}

/// Linear interpolation helper shared by boards (kept here so no board redefines it).
double soloLerp(double a, double b, double t) => a + (b - a) * t.clamp(0.0, 1.0);

/// Frame-rate independent approach factor: `1 - pow(sharpness, dt)`.
double soloApproach(double sharpness, double dt) => 1 - math.pow(sharpness, dt).toDouble();
