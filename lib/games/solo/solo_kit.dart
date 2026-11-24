import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../arcade_kit/arcade_shell.dart';

// `SoloRun` is declared in arcade_shell.dart and is the shell's controller; re-exported so
// registry and board files that only need the controller do not import the shell machinery.
export '../arcade_kit/arcade_shell.dart' show SoloRun;
import '../arcade_kit/arcade_skin.dart';
import '../core/game_contract.dart';

/// ===================== SOLO ARCADE KIT =====================
/// Shared plumbing and premium electric-night visual system for the ten solo arcade games.
///
///  * `SoloDef` declares a game (title, hint, accent, board builder) and
///    [buildSoloGame] wraps it in [ArcadeSoloShell] — so the ready card, HUD, medals,
///    daily challenge, personal best and the hand-off to the host are identical for
///    every solo game.
///  * [SoloBoard] is the base class a game's board extends: it owns one ticker, calls
///    [step] with a clamped delta time (never more than 20 ms, so a hitch cannot tunnel
///    objects) and repaints a single CustomPainter instead of rebuilding widgets.
///  * [LuxeBoardPainter] holds the shared drawing helpers (background, glow, frames, text)
///    so no board invents its own palette.
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
    bgTop: const Color(0xFF101B32),
    bgBottom: const Color(0xFF050812),
    accent: def.accent,
    accent2: def.accent2,
    glow: def.accent2,
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

/// Base class of every solo playfield: one ticker, clamped dt, single CustomPainter.
///
/// Subclasses implement [step] (advance the simulation) and [paint] (draw it). The board
/// only runs while the shell reports [SoloRun.playing]; when the run is over the board
/// freezes on its last frame so the result overlay appears over a stable image.
abstract class SoloBoard extends StatefulWidget {
  const SoloBoard({super.key, required this.run});
  final SoloRun run;

  // `StatefulWidget` already declares `State<StatefulWidget> createState()`; every board
  // narrows it to its own `_XBoardState` (a `SoloBoardState<XBoard>`), which is a valid
  // override, so the base class only documents the contract.
}

abstract class SoloBoardState<T extends SoloBoard> extends State<T> with SingleTickerProviderStateMixin {
  late final Ticker ticker;
  final ValueNotifier<int> frame = ValueNotifier<int>(0);
  Duration _last = Duration.zero;

  /// Seconds since the board was created (always advancing, for idle animations).
  double clock = 0;

  /// Starts a fresh run (called by [restart] and available to subclasses).
  void reset();

  /// Advances the simulation. [dt] is clamped to 20 ms.
  void step(double dt);

  /// Paints the current state. [size] is the full play area.
  void paint(Canvas canvas, Size size);

  /// Whether the game is currently simulating (default: only while the run plays).
  bool get simulating => widget.run.playing && !widget.run.over;

  @override
  void initState() {
    super.initState();
    reset();
    ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    double dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt <= 0) return;
    if (dt > 0.02) dt = 0.02;
    clock += dt;
    if (simulating) step(dt);
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
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: frame,
        builder: (BuildContext c, _) => RepaintBoundary(
          child: CustomPaint(painter: _SoloPainter(this), size: Size.infinite),
        ),
      );
}

class _SoloPainter extends CustomPainter {
  _SoloPainter(this.state);
  final SoloBoardState state;

  @override
  void paint(Canvas canvas, Size size) => state.paint(canvas, size);

  @override
  bool shouldRepaint(covariant _SoloPainter old) => true;
}

/// Shared drawing helpers: every solo board uses this palette and these primitives, so
/// the ten games look like one family (and like the rest of ANIX PRO).
class LuxeBoardPainter {
  LuxeBoardPainter._();

  static const Color ink = Color(0xFFF4F8FF);
  static const Color mute = Color(0xFFA7B5CC);
  static const Color gold = Color(0xFF43D9FF); // electric cyan
  static const Color champagne = Color(0xFFEAFBFF);
  static const Color bronze = Color(0xFF806CFF); // ultraviolet

  static void background(Canvas canvas, Size size, Color accent) {
    final Rect rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF101B32), Color(0xFF080D1A), Color(0xFF050812)],
          stops: <double>[0, 0.48, 1],
        ).createShader(rect),
    );
    // Quiet technical grid gives every solo title a deliberate arcade-console stage.
    final double spacing = (size.width / 15).clamp(22, 36).toDouble();
    final Paint grid = stroke(const Color(0xFF8CB6FF).withValues(alpha: 0.055), 0.7);
    for (double x = spacing; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = spacing; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final Offset c = Offset(size.width * 0.5, size.height * 0.24);
    final double r = math.max(size.width, size.height) * 0.82;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(colors: <Color>[accent.withValues(alpha: 0.18), Colors.transparent])
            .createShader(Rect.fromCircle(center: c, radius: r)),
    );
    final Rect vignette = rect;
    canvas.drawRect(
      vignette,
      Paint()
        ..shader = const RadialGradient(
          radius: 0.9,
          colors: <Color>[Colors.transparent, Color(0x99020712)],
          stops: <double>[0.55, 1],
        ).createShader(vignette),
    );
  }

  static Paint stroke(Color c, [double w = 1.2]) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..color = c;

  static Paint fill(Color c) => Paint()..color = c;

  static void glow(Canvas canvas, Offset at, double r, Color c, [double alpha = 0.34]) {
    canvas.drawCircle(
      at,
      r * 2,
      Paint()
        ..shader = RadialGradient(colors: <Color>[c.withValues(alpha: alpha), Colors.transparent])
            .createShader(Rect.fromCircle(center: at, radius: r * 2)),
    );
  }

  static void text(
    Canvas canvas,
    String s,
    Offset centre, {
    Color color = ink,
    double size = 16,
    FontWeight weight = FontWeight.w800,
    TextAlign align = TextAlign.center,
    double maxWidth = 460,
  }) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: weight,
          fontFamily: 'ChakraPetch',
          shadows: <Shadow>[Shadow(color: Colors.black.withValues(alpha: 0.65), blurRadius: 4)],
        ),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    final double dx = align == TextAlign.center ? tp.width / 2 : (align == TextAlign.right ? tp.width : 0);
    tp.paint(canvas, centre - Offset(dx, tp.height / 2));
  }

  static void roundedRect(Canvas canvas, Rect r, double radius, Color fillColor, {Color? border, double borderWidth = 1.2}) {
    final RRect rr = RRect.fromRectAndRadius(r, Radius.circular(radius));
    canvas.drawRRect(rr, fill(fillColor));
    if (border != null) canvas.drawRRect(rr, stroke(border, borderWidth));
  }

  /// Subtle inset frame with short illuminated corner ticks; never competes with gameplay.
  static void frame(Canvas canvas, Size size, Color accent) {
    const double m = 10;
    const double len = 20;
    final Rect r = Rect.fromLTWH(m, m, size.width - 2 * m, size.height - 2 * m);
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(22)),
      stroke(const Color(0xFFB8D4FF).withValues(alpha: 0.12), 0.8),
    );
    final Paint p = stroke(accent.withValues(alpha: 0.78), 1.6);
    for (final Offset c in <Offset>[r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
      final double sx = c.dx == r.left ? 1 : -1;
      final double sy = c.dy == r.top ? 1 : -1;
      canvas.drawLine(c, c + Offset(len * sx, 0), p);
      canvas.drawLine(c, c + Offset(0, len * sy), p);
      canvas.drawCircle(c + Offset(len * sx * .42, len * sy * .42), 2, fill(accent));
    }
  }

  /// Soft edge vignette that keeps the HUD scrollable over busy playfields.
  static void vignette(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          radius: 0.95,
          colors: <Color>[Colors.transparent, Colors.black.withValues(alpha: 0.5)],
        ).createShader(rect),
    );
  }

  static double lerp(double a, double b, double t) => a + (b - a) * t.clamp(0.0, 1.0);

  static double easeOutBack(double t) {
    const double c = 1.70158;
    final double u = t.clamp(0.0, 1.0) - 1;
    return 1 + (c + 1) * u * u * u + c * u * u;
  }

  /// A Luxe-styled button drawn on the canvas (for tap-anywhere "start over" prompts).
  static void pill(Canvas canvas, Rect r, Color accent, String label) {
    roundedRect(canvas, r, r.height / 2, const Color(0xF01C1A14), border: accent.withValues(alpha: 0.6));
    text(canvas, label, r.center, color: champagne, size: 14, weight: FontWeight.w900);
  }
}

/// Square frame button used by solo boards for arrows / actions.
class SoloPad extends StatefulWidget {
  const SoloPad({super.key, required this.icon, required this.onTap, this.onHold, this.onRelease, this.size = 64, this.accent = const Color(0xFF43D9FF)});
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
                borderRadius: BorderRadius.circular(widget.size * 0.28),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _down
                      ? <Color>[widget.accent.withValues(alpha: 0.34), const Color(0xFF111A2D)]
                      : const <Color>[Color(0xE91B2941), Color(0xF0091121)],
                ),
                border: Border.all(color: widget.accent.withValues(alpha: _down ? 0.9 : 0.48), width: 1.3),
                boxShadow: <BoxShadow>[
                  BoxShadow(color: widget.accent.withValues(alpha: _down ? 0.38 : 0.12), blurRadius: 18, spreadRadius: -5),
                ],
              ),
              child: Icon(widget.icon, color: const Color(0xFFEAFBFF), size: widget.size * 0.46),
            ),
          ),
        ),
      );
}
