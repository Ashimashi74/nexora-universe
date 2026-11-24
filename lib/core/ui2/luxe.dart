import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'nexora_station_scene.dart';

/// ANIX PRO "Station Luxe" design tokens and primitives (black / gold, glass, 3D cards).
/// Native Flutter rebuild of the NEXORA Station Luxe HTML reference — no WebView.
class Luxe {
  Luxe._();

  static const Color bg = Color(0xFF07080C);
  static const Color ink = Color(0xFFF4EAD2);
  static const Color mute = Color(0x99F4EAD2);
  static const Color gold = Color(0xFFD9B872);
  static const Color gold2 = Color(0xFFF6E7BD);
  static const Color gold3 = Color(0xFF8A6A2C);
  static const Color line = Color(0x33D9B872);
  static const Color panel = Color(0xFF14130F);

  static const LinearGradient goldGrad =
      LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: <Color>[gold2, gold]);
  static const LinearGradient glass = LinearGradient(
      begin: Alignment(-0.6, -1),
      end: Alignment(0.6, 1),
      colors: <Color>[Color(0x13FFFFFF), Color(0x04FFFFFF)]);
  static const Curve ease = Cubic(.22, .8, .2, 1);

  static const String hubBg = 'assets/luxe/hub.webp';
  static const String splash = 'assets/luxe/splash.webp';
  static String icon(String n) => 'assets/luxe/icons/$n.webp';

  /// Latin small-caps label (the reference uses Cormorant Garamond; ChakraPetch is bundled).
  static const TextStyle latin =
      TextStyle(fontFamily: 'ChakraPetch', letterSpacing: 2.2, fontWeight: FontWeight.w600, color: gold, fontSize: 11);

  static bool reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

/// Frosted glass surface with a hairline gold border.
class LuxeGlass extends StatelessWidget {
  const LuxeGlass({
    super.key,
    required this.child,
    this.radius = 26,
    this.padding = EdgeInsets.zero,
    this.blur = 14,
    this.color,
    this.glow,
  });
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double blur;
  final Color? color;
  final Color? glow;

  @override
  Widget build(BuildContext context) {
    final BorderRadius r = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: glow == null
            ? const <BoxShadow>[]
            : <BoxShadow>[BoxShadow(color: glow!.withValues(alpha: 0.35), blurRadius: 28, spreadRadius: -8)],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: r,
              color: color,
              gradient: color == null ? Luxe.glass : null,
              border: Border.all(color: Luxe.line),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Pressable with a soft scale, used by every Luxe card and button.
class LuxePress extends StatefulWidget {
  const LuxePress({super.key, required this.child, this.onTap, this.semantics});
  final Widget child;
  final VoidCallback? onTap;
  final String? semantics;

  @override
  State<LuxePress> createState() => _LuxePressState();
}

class _LuxePressState extends State<LuxePress> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semantics,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.97 : 1,
          duration: const Duration(milliseconds: 160),
          curve: Luxe.ease,
          child: widget.child,
        ),
      ),
    );
  }
}

/// The ambient hub scene: warm radial light, the station art and the dark vignette.
/// When [stationScene] is true the static hub art is replaced by the live native orbital-station
/// painter ([NexoraStationScene]) — the §6.2 signature visual, with reduced-motion/quality fallbacks.
class LuxeScene extends StatelessWidget {
  const LuxeScene(
      {super.key, required this.child, this.artOpacity = 0.6, this.tint, this.stationScene = false});
  final Widget child;
  final double artOpacity;
  final Color? tint;
  final bool stationScene;

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: <Widget>[
      const DecoratedBox(
        decoration: BoxDecoration(
          color: Luxe.bg,
          gradient: RadialGradient(
            center: Alignment(0, -1.15),
            radius: 1.2,
            colors: <Color>[Color(0xFF22201A), Luxe.bg],
          ),
        ),
      ),
      if (stationScene)
        Opacity(
          opacity: artOpacity,
          child: const NexoraStationScene(),
        )
      else
        Opacity(
          opacity: artOpacity,
          child: Image.asset(Luxe.hubBg,
              fit: BoxFit.cover, cacheWidth: 900, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
        ),
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const <double>[0, 0.4, 1],
            colors: <Color>[
              const Color(0x9907080C),
              (tint ?? const Color(0x2607080C)).withValues(alpha: tint == null ? 0.15 : 0.22),
              const Color(0xEB07080C),
            ],
          ),
        ),
      ),
      const RepaintBoundary(child: LuxeDust()),
      child,
    ]);
  }
}

/// Slow drifting gold dust. One ticker, ~40 particles, paused off-screen (TickerMode)
/// and disabled entirely when the system asks for reduced motion.
class LuxeDust extends StatefulWidget {
  const LuxeDust({super.key, this.count = 40});
  final int count;

  @override
  State<LuxeDust> createState() => _LuxeDustState();
}

class _LuxeDustState extends State<LuxeDust> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 40));
  late final List<_Mote> _motes = List<_Mote>.generate(widget.count, (int i) => _Mote(math.Random(i * 7919 + 13)));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Luxe.reduceMotion(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(child: CustomPaint(painter: _DustPainter(_c, _motes), size: Size.infinite));
}

class _Mote {
  _Mote(math.Random r)
      : x = r.nextDouble(),
        y = r.nextDouble(),
        size = 0.6 + r.nextDouble() * 1.6,
        speed = 0.3 + r.nextDouble() * 0.9,
        phase = r.nextDouble() * math.pi * 2,
        alpha = 0.15 + r.nextDouble() * 0.45;
  final double x, y, size, speed, phase, alpha;
}

class _DustPainter extends CustomPainter {
  _DustPainter(this.t, this.motes) : super(repaint: t);
  final Animation<double> t;
  final List<_Mote> motes;
  final Paint _p = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);

  @override
  void paint(Canvas canvas, Size size) {
    final double v = t.value;
    for (final _Mote m in motes) {
      final double y = (m.y - v * m.speed) % 1.0;
      final double x = m.x + math.sin(v * math.pi * 2 * m.speed + m.phase) * 0.02;
      final double tw = 0.6 + 0.4 * math.sin(v * math.pi * 8 * m.speed + m.phase);
      _p.color = Luxe.gold2.withValues(alpha: m.alpha * tw);
      canvas.drawCircle(Offset(x * size.width, y * size.height), m.size, _p);
    }
  }

  @override
  bool shouldRepaint(_DustPainter old) => false;
}

/// Gold pill chip (wallet values, counters).
class LuxeChip extends StatelessWidget {
  const LuxeChip({super.key, required this.child, this.onTap, this.semantics});
  final Widget child;
  final VoidCallback? onTap;
  final String? semantics;

  @override
  Widget build(BuildContext context) => LuxePress(
        onTap: onTap,
        semantics: semantics,
        child: LuxeGlass(
          radius: 99,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: DefaultTextStyle.merge(
            style: const TextStyle(fontSize: 12, color: Luxe.ink, fontWeight: FontWeight.w600),
            child: child,
          ),
        ),
      );
}

/// Coin and gem glyphs drawn in gold (same shapes as the reference SVGs).
class LuxeCoin extends StatelessWidget {
  const LuxeCoin({super.key, this.size = 15});
  final double size;
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _CoinPainter());
}

class _CoinPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final Offset o = s.center(Offset.zero);
    final double r = s.width / 2;
    c.drawCircle(o, r * .8, Paint()..color = Luxe.gold);
    c.drawCircle(o, r * .8, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * .1
      ..color = Luxe.gold2);
    c.drawCircle(o, r * .48, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * .1
      ..color = Luxe.gold3);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class LuxeGem extends StatelessWidget {
  const LuxeGem({super.key, this.size = 15});
  final double size;
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _GemPainter());
}

class _GemPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final double w = s.width, h = s.height;
    final Path p = Path()
      ..moveTo(w * .5, h * .92)
      ..lineTo(w * .1, h * .38)
      ..lineTo(w * .27, h * .12)
      ..lineTo(w * .73, h * .12)
      ..lineTo(w * .9, h * .38)
      ..close();
    c.drawPath(p, Paint()..color = Luxe.gold2);
    c.drawPath(p, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * .05
      ..color = Luxe.gold);
    c.drawLine(Offset(w * .1, h * .38), Offset(w * .9, h * .38), Paint()
      ..strokeWidth = w * .04
      ..color = Luxe.gold3);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Thin XP / progress bar in gold.
class LuxeBar extends StatelessWidget {
  const LuxeBar({super.key, required this.value, this.height = 6});
  final double value;
  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: SizedBox(
          height: height,
          child: Stack(fit: StackFit.expand, children: <Widget>[
            const ColoredBox(color: Color(0x1FF6E7BD)),
            FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: value.clamp(0.0, 1.0),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                    gradient: LinearGradient(colors: <Color>[Luxe.gold3, Luxe.gold, Luxe.gold2])),
              ),
            ),
          ]),
        ),
      );
}

/// Bottom sheet chrome used across ANIX PRO (grab handle, dark gold panel).
Future<T?> showLuxeSheet<T>(BuildContext context, {required WidgetBuilder builder}) {
  return showModalBottomSheet<T>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x8C030306),
    builder: (BuildContext ctx) => Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.paddingOf(ctx).bottom + 22),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: <Color>[Color(0xFF14130F), Color(0xFF0A0A0D)]),
        border: Border(top: BorderSide(color: Luxe.line)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(color: const Color(0x40F6E7BD), borderRadius: BorderRadius.circular(4))),
        Flexible(child: builder(ctx)),
      ]),
    ),
  );
}

/// One wide glass option row in a Luxe sheet.
class LuxeOption extends StatelessWidget {
  const LuxeOption({super.key, required this.label, this.icon, this.onTap, this.trailing});
  final String label;
  final String? icon;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 9),
        child: LuxePress(
          onTap: onTap,
          semantics: label,
          child: LuxeGlass(
            radius: 20,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: <Widget>[
              if (icon != null)
                Image.asset(Luxe.icon(icon!), width: 32, height: 32, cacheWidth: 96,
                    errorBuilder: (_, __, ___) => const SizedBox(width: 32)),
              if (icon != null) const SizedBox(width: 12),
              Expanded(child: Text(label, style: const TextStyle(fontSize: 14, color: Luxe.ink))),
              if (trailing != null) trailing!,
            ]),
          ),
        ),
      );
}

// =====================================================================================
// SHARED COMPONENTS
// Every secondary screen (rooms, lobbies, settings, tournaments, profiles, dialogs,
// sheets, empty/loading states) is built from these, so the Station Luxe identity of
// the home page carries through the whole app instead of each page inventing its own
// buttons, panels and colours.
// =====================================================================================

/// Spacing / radius / motion scale of the Station Luxe system (8-pt based).
class LuxeSpace {
  LuxeSpace._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
}

class LuxeRadius {
  LuxeRadius._();
  static const double sm = 12;
  static const double md = 18;
  static const double lg = 26;
  static const double pill = 99;
}

/// Frosted gold-hairline card: the standard surface for content, list rows and tiles.
class LuxeCard extends StatelessWidget {
  const LuxeCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(LuxeSpace.md),
    this.radius = LuxeRadius.lg,
    this.onTap,
    this.semantics,
    this.glow,
    this.tint,
    this.borderColor,
    this.blur = 12,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final String? semantics;
  final Color? glow;
  final Color? tint;
  final Color? borderColor;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final BorderRadius r = BorderRadius.circular(radius);
    final Widget panel = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        border: Border.all(color: borderColor ?? (glow ?? Luxe.gold).withValues(alpha: 0.28)),
        gradient: tint == null
            ? const LinearGradient(
                begin: Alignment(-0.6, -1),
                end: Alignment(0.6, 1),
                colors: <Color>[Color(0x14FFFFFF), Color(0x05FFFFFF)])
            : LinearGradient(colors: <Color>[tint!.withValues(alpha: 0.18), const Color(0x0AFFFFFF)]),
        boxShadow: <BoxShadow>[
          BoxShadow(color: (glow ?? Luxe.gold).withValues(alpha: 0.10), blurRadius: 22, spreadRadius: -10),
        ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    if (onTap == null) return panel;
    return LuxePress(onTap: onTap, semantics: semantics, child: panel);
  }
}

enum LuxeButtonKind {
  /// Gold gradient, dark ink — one per screen.
  primary,

  /// Gold hairline on glass — secondary actions.
  ghost,

  /// Destructive action.
  danger,
}

/// The app button: same geometry, typography and press animation everywhere.
class LuxeButton extends StatelessWidget {
  const LuxeButton({
    super.key,
    required this.label,
    this.onTap,
    this.icon,
    this.kind = LuxeButtonKind.primary,
    this.height = 52,
    this.fontSize = 14,
    this.loading = false,
    this.expand = true,
    this.uppercase = true,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final LuxeButtonKind kind;
  final double height;
  final double fontSize;
  final bool loading;
  final bool expand;
  final bool uppercase;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null && !loading;
    final Color fg = switch (kind) {
      LuxeButtonKind.primary => const Color(0xFF14120C),
      LuxeButtonKind.ghost => Luxe.ink,
      LuxeButtonKind.danger => const Color(0xFFFFE9EC),
    };
    final Gradient? fill = switch (kind) {
      LuxeButtonKind.primary => enabled
          ? Luxe.goldGrad
          : const LinearGradient(colors: <Color>[Color(0x4DF6E7BD), Color(0x33D9B872)]),
      LuxeButtonKind.ghost => null,
      LuxeButtonKind.danger => const LinearGradient(colors: <Color>[Color(0xFFB3313F), Color(0xFF7A1F2A)]),
    };
    final Border? border = switch (kind) {
      LuxeButtonKind.primary => null,
      LuxeButtonKind.ghost => Border.all(color: enabled ? Luxe.line : const Color(0x1AFFFFFF)),
      LuxeButtonKind.danger => Border.all(color: const Color(0x66FF8A9A)),
    };
    final Widget content = loading
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF14120C)),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: fontSize + 6, color: fg),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  uppercase ? label.toUpperCase() : label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'ChakraPetch',
                    fontSize: fontSize,
                    fontWeight: FontWeight.w700,
                    letterSpacing: uppercase ? 1.1 : 0.2,
                    color: fg,
                  ),
                ),
              ),
            ],
          );
    final Widget body = Container(
      height: height,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        gradient: fill,
        borderRadius: BorderRadius.circular(height / 2),
        border: border,
      ),
      child: content,
    );
    final Widget sized = expand ? SizedBox(width: double.infinity, child: body) : body;
    if (!enabled) return Opacity(opacity: 0.62, child: sized);
    return LuxePress(onTap: loading ? null : onTap, semantics: label, child: sized);
  }
}

/// Round glass icon button (back, close, share…).
class LuxeIconButton extends StatelessWidget {
  const LuxeIconButton({super.key, required this.icon, this.onTap, this.tooltip, this.size = 42, this.color});

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final Widget button = LuxePress(
      onTap: onTap,
      semantics: tooltip,
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0x0FFFFFFF),
            border: Border.all(color: Luxe.line),
          ),
          child: Icon(icon, size: size * 0.45, color: color ?? Luxe.ink),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// Small-caps section label, with an optional trailing action.
class LuxeSection extends StatelessWidget {
  const LuxeSection({super.key, required this.title, this.trailing, this.top = LuxeSpace.lg});

  final String title;
  final Widget? trailing;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: top, bottom: LuxeSpace.sm),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                title.toUpperCase(),
                style: const TextStyle(
                  fontFamily: 'ChakraPetch',
                  letterSpacing: 2.0,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  color: Luxe.gold,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

/// Gold pill with an icon — counts, states, tags.
class LuxeStat extends StatelessWidget {
  const LuxeStat({super.key, required this.label, this.icon, this.color, this.onTap});

  final String label;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color c = color ?? Luxe.gold;
    return LuxePress(
      onTap: onTap,
      semantics: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(LuxeRadius.pill),
          color: c.withValues(alpha: 0.12),
          border: Border.all(color: c.withValues(alpha: 0.42)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          if (icon != null) ...<Widget>[Icon(icon, size: 13, color: c), const SizedBox(width: 5)],
          Text(label,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color.lerp(c, Luxe.ink, 0.45))),
        ]),
      ),
    );
  }
}

/// Standard list row: avatar/icon, title, subtitle, trailing widget.
class LuxeListRow extends StatelessWidget {
  const LuxeListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.selected = false,
    this.tint,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;
  final Color? tint;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: LuxeSpace.sm),
        child: LuxeCard(
          radius: LuxeRadius.md,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          onTap: onTap,
          semantics: title,
          glow: selected ? (tint ?? Luxe.gold) : null,
          borderColor: selected ? (tint ?? Luxe.gold).withValues(alpha: 0.7) : null,
          child: Row(children: <Widget>[
            if (leading != null) ...<Widget>[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Luxe.ink)),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: Luxe.mute, height: 1.35)),
                  ),
              ]),
            ),
            if (trailing != null) ...<Widget>[const SizedBox(width: 10), trailing!],
          ]),
        ),
      );
}

/// Hairline divider.
class LuxeDivider extends StatelessWidget {
  const LuxeDivider({super.key, this.vertical = LuxeSpace.md});
  final double vertical;
  @override
  Widget build(BuildContext context) =>
      Padding(padding: EdgeInsets.symmetric(vertical: vertical), child: const Divider(height: 1, color: Luxe.line));
}

/// Empty state used by lists, rooms, lobbies and record tabs.
class LuxeEmpty extends StatelessWidget {
  const LuxeEmpty({super.key, required this.title, this.message, this.icon = Icons.auto_awesome_outlined, this.action});

  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => LuxeCard(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Luxe.line),
              gradient: RadialGradient(colors: <Color>[Luxe.gold.withValues(alpha: 0.18), Colors.transparent]),
            ),
            child: Icon(icon, color: Luxe.gold, size: 24),
          ),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Luxe.ink)),
          if (message != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(message!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, height: 1.5, color: Luxe.mute)),
          ],
          if (action != null) ...<Widget>[const SizedBox(height: 14), action!],
        ]),
      );
}

/// Gold loading state with a label, used instead of a bare spinner.
class LuxeLoading extends StatelessWidget {
  const LuxeLoading({super.key, this.label, this.height = 120});
  final String? label;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2, color: Luxe.gold),
            ),
            if (label != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(label!, style: const TextStyle(fontSize: 12, color: Luxe.mute)),
            ],
          ]),
        ),
      );
}

/// Page header for secondary screens that do not use the NX2 top bar: back/close on the
/// start edge, gold title, small-caps latin subtitle.
class LuxeHeader extends StatelessWidget {
  const LuxeHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.trailing = const <Widget>[],
    this.showBack = true,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget> trailing;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(LuxeSpace.md, LuxeSpace.sm, LuxeSpace.md, LuxeSpace.sm),
      child: Row(children: <Widget>[
        if (showBack) ...<Widget>[
          LuxeIconButton(
            icon: Directionality.of(context) == TextDirection.rtl ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded,
            tooltip: 'Back',
            onTap: onBack ?? () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: <Widget>[
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Luxe.ink, letterSpacing: 0.4)),
            if (subtitle != null && subtitle!.isNotEmpty) Text(subtitle!, style: Luxe.latin),
          ]),
        ),
        ...trailing,
      ]),
    );
  }
}

/// Gold-bordered dialog: the single dialog chrome for confirmations, prompts and info.
Future<T?> showLuxeDialog<T>(BuildContext context, {required Widget child}) {
  return showDialog<T>(
    context: context,
    barrierColor: const Color(0x99030306),
    builder: (BuildContext ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(LuxeRadius.lg),
            gradient: const LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: <Color>[Color(0xFF16140F), Color(0xFF0A0A0D)]),
            border: Border.all(color: Luxe.line),
            boxShadow: <BoxShadow>[BoxShadow(color: Luxe.gold.withValues(alpha: 0.12), blurRadius: 34, spreadRadius: -12)],
          ),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: child,
        ),
      ),
    ),
  );
}

/// Yes/no dialog in the app's own chrome. Returns true when confirmed.
Future<bool?> showLuxeConfirm(
  BuildContext context, {
  required String title,
  String? message,
  String confirm = 'OK',
  String? cancel,
  bool danger = false,
}) {
  return showLuxeDialog<bool>(
    context,
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Text(title, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: Luxe.ink)),
      if (message != null) ...<Widget>[
        const SizedBox(height: 8),
        Text(message, style: const TextStyle(fontSize: 12.5, height: 1.55, color: Luxe.mute)),
      ],
      const SizedBox(height: 18),
      Row(children: <Widget>[
        Expanded(
          child: LuxeButton(
            label: cancel ?? (Localizations.localeOf(context).languageCode == 'fa' ? 'انصراف' : 'Cancel'),
            kind: LuxeButtonKind.ghost,
            height: 46,
            expand: true,
            onTap: () => Navigator.of(context).pop(false),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: LuxeButton(
            label: confirm,
            kind: danger ? LuxeButtonKind.danger : LuxeButtonKind.primary,
            height: 46,
            expand: true,
            onTap: () => Navigator.of(context).pop(true),
          ),
        ),
      ]),
    ]),
  );
}

/// Single-field prompt (room name, message, reason) in the app's own chrome.
Future<String?> showLuxePrompt(
  BuildContext context, {
  required String title,
  String? message,
  String? hint,
  String confirm = 'OK',
  int maxLength = 60,
  String? initial,
}) {
  final TextEditingController controller = TextEditingController(text: initial);
  return showLuxeDialog<String>(
    context,
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Text(title, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: Luxe.ink)),
      if (message != null) ...<Widget>[
        const SizedBox(height: 6),
        Text(message, style: const TextStyle(fontSize: 12, color: Luxe.mute)),
      ],
      const SizedBox(height: 12),
      TextField(
        controller: controller,
        autofocus: true,
        maxLength: maxLength,
        style: const TextStyle(color: Luxe.ink, fontSize: 14),
        decoration: InputDecoration(hintText: hint, counterStyle: const TextStyle(fontSize: 10, color: Luxe.mute)),
        onSubmitted: (String v) => Navigator.of(context).pop(v.trim()),
      ),
      const SizedBox(height: 6),
      Row(children: <Widget>[
        Expanded(
          child: LuxeButton(
            label: Localizations.localeOf(context).languageCode == 'fa' ? 'انصراف' : 'Cancel',
            kind: LuxeButtonKind.ghost,
            height: 46,
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: LuxeButton(
            label: confirm,
            height: 46,
            onTap: () => Navigator.of(context).pop(controller.text.trim()),
          ),
        ),
      ]),
    ]),
  );
}

/// Themed snackbar: gold hairline panel above the dock, never a Material default.
///
/// The one feedback surface of the app — every screen reports through this instead of
/// building its own [SnackBar], so a message looks the same in a room, a shop, a tournament
/// wizard and a game. [actionLabel]/[onAction] add the gold text shortcut the Material
/// `SnackBarAction` used to provide; [duration] defaults to 3 s (call invitations ask for more).
void luxeToast(
  BuildContext context,
  String message, {
  bool error = false,
  IconData? icon,
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 3),
}) {
  final ScaffoldMessengerState? m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  luxeToastState(m, message,
      error: error, icon: icon, actionLabel: actionLabel, onAction: onAction, duration: duration);
}

/// The same themed snackbar for callers that hold the root messenger but no [BuildContext]
/// (the call / invite / announcement / tournament watchers run off a global key).
void luxeToastState(
  ScaffoldMessengerState m,
  String message, {
  bool error = false,
  IconData? icon,
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 3),
}) {
  final Color accent = error ? const Color(0xFFFF5A7A) : Luxe.gold;
  final bool hasAction = actionLabel != null && onAction != null;
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: EdgeInsets.zero,
      duration: duration,
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(LuxeRadius.md),
          gradient: const LinearGradient(colors: <Color>[Color(0xFF16140F), Color(0xFF0A0A0D)]),
          border: Border.all(color: accent.withValues(alpha: 0.5)),
        ),
        child: Row(children: <Widget>[
          Icon(icon ?? (error ? Icons.error_outline_rounded : Icons.auto_awesome),
              size: 17, color: error ? const Color(0xFFFF8A9A) : Luxe.gold),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: TextStyle(fontSize: 12.5, height: 1.35, color: error ? const Color(0xFFFFD9DF) : Luxe.ink)),
          ),
          if (hasAction) ...<Widget>[
            const SizedBox(width: 10),
            LuxePress(
              onTap: onAction,
              semantics: actionLabel,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(actionLabel.toUpperCase(),
                    maxLines: 1,
                    style: const TextStyle(
                        fontFamily: 'ChakraPetch',
                        fontSize: 11.5,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w700,
                        color: Luxe.gold2)),
              ),
            ),
          ],
        ]),
      ),
    ));
}
