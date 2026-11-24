import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../audio/sfx_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../profile/profile_service.dart';
import '../settings/app_settings.dart';
import 'anix_kit.dart';
import 'nx2_assets.dart';
import '../../worlds/oracle_core/persona/oracle_tour.dart';
import '../../worlds/hub/hub_search.dart';

/// NX2 colour tokens, re-based on the ANIX PRO Station Luxe palette (deep black, gold, champagne).
class Nx2 {
  Nx2._();
  static const Color deep = Color(0xFF07080C);
  static const Color night = Color(0xFF11100C);
  static const Color plum = Color(0xFF1C1912);
  static const Color violet = Color(0xFF8A6A2C);
  static const Color magenta = Color(0xFFD9B872);
  static const Color cyan = Color(0xFFF6E7BD);
  static const Color gold = Color(0xFFD9B872);
  static const Color goldDeep = Color(0xFF8A6A2C);
  static const Color text = Color(0xFFF4EAD2);
  static const Color muted = Color(0xFFB9AE95);
  static const Color success = Color(0xFF4BE3A0);
  static const Color danger = Color(0xFFFF5A7A);

  /// Frame border gradient. Historic name kept (it is the NX2 frame token used by panels, pills and the dock);
  /// the palette is the Station Luxe gold of the home page, not the old neon violet.
  static const LinearGradient neon =
      LinearGradient(colors: <Color>[Color(0xFFF6E7BD), gold, goldDeep]);
  static const LinearGradient goldGrad =
      LinearGradient(colors: <Color>[Color(0xFFF6E7BD), gold, goldDeep]);

  static const TextStyle title = TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w900,
      letterSpacing: 0.8,
      color: text,
      shadows: <Shadow>[Shadow(color: Color(0x66D9B872), blurRadius: 12)]);
  static const TextStyle label =
      TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: text);
}

/// Scene art behind a page: the ANIX world hub / social / arcade backgrounds, or the NX2 castle/room.
enum Nx2Scene { castle, room, hub, social, arcade, voiceStage, trophyHall, panorama }

/// The cosmic castle backdrop (main), the room backdrop or an ANIX scene background, darkened for contrast.
class Nx2Background extends StatelessWidget {
  const Nx2Background(
      {super.key, this.child, this.room = false, this.dim = 0.45, this.scene});
  final Widget? child;
  final bool room;
  final double dim;

  /// Overrides [room] when set.
  final Nx2Scene? scene;

  String get _asset => switch (scene ?? (room ? Nx2Scene.room : Nx2Scene.castle)) {
        Nx2Scene.castle => Nx2Assets.bgBgMain,
        Nx2Scene.room => Nx2Assets.bgBgRoom,
        Nx2Scene.hub => AnixAssets.bgWorldHub,
        Nx2Scene.social => AnixAssets.bgSocial,
        Nx2Scene.arcade => AnixAssets.bgArcade,
        Nx2Scene.voiceStage => AnixAssets.sceneVoiceStage,
        Nx2Scene.trophyHall => AnixAssets.sceneTrophyHall,
        Nx2Scene.panorama => AnixAssets.sceneHubPanorama,
      };

  @override
  Widget build(BuildContext context) {
    final Size s = MediaQuery.sizeOf(context);
    final int cw = (math.min(s.width, 600) * 2).round();
    return Stack(fit: StackFit.expand, children: <Widget>[
      const ColoredBox(color: Nx2.deep),
      Image.asset(_asset,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          cacheWidth: cw,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => const SizedBox.shrink()),
      IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Nx2.deep.withValues(alpha: dim * 0.6),
                Nx2.deep.withValues(alpha: dim),
                Nx2.deep.withValues(alpha: math.min(1, dim + 0.25)),
              ],
              stops: const <double>[0, 0.55, 1],
            ),
          ),
        ),
      ),
      if (child != null) child!,
    ]);
  }
}

/// Chamfered neon frame painter shared by panels, pills and the dock.
class Nx2FramePainter extends CustomPainter {
  Nx2FramePainter({
    required this.cut,
    this.fill,
    this.border = Nx2.neon,
    this.strokeWidth = 1.4,
    this.glow = 0.35,
    this.gems = false,
  });
  final double cut;
  final Gradient? fill;
  final Gradient border;
  final double strokeWidth;
  final double glow;
  final bool gems;

  static Path chamfer(Rect r, double c) {
    final double k = math.min(c, math.min(r.width, r.height) / 2);
    return Path()
      ..moveTo(r.left + k, r.top)
      ..lineTo(r.right - k, r.top)
      ..lineTo(r.right, r.top + k)
      ..lineTo(r.right, r.bottom - k)
      ..lineTo(r.right - k, r.bottom)
      ..lineTo(r.left + k, r.bottom)
      ..lineTo(r.left, r.bottom - k)
      ..lineTo(r.left, r.top + k)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Rect r = (Offset.zero & size).deflate(strokeWidth / 2);
    final Path p = chamfer(r, cut);
    if (glow > 0) {
      canvas.drawPath(
          p,
          Paint()
            ..color = Nx2.gold.withValues(alpha: glow * 0.55)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7));
    }
    canvas.drawPath(
        p,
        Paint()
          ..shader = (fill ??
                  const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[Color(0xE61C1912), Color(0xEB0A0A0D)],
                  ))
              .createShader(r));
    // inner sheen
    canvas.save();
    canvas.clipPath(p);
    canvas.drawRect(
        Rect.fromLTWH(r.left, r.top, r.width, r.height * 0.45),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Colors.white.withValues(alpha: 0.07),
              Colors.white.withValues(alpha: 0)
            ],
          ).createShader(r));
    canvas.restore();
    canvas.drawPath(
        p,
        Paint()
          ..shader = border.createShader(r)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth);
    if (gems) {
      final Paint g = Paint()..shader = Nx2.neon.createShader(r);
      for (final Offset o in <Offset>[
        Offset(r.center.dx, r.top),
        Offset(r.center.dx, r.bottom)
      ]) {
        final Path d = Path()
          ..moveTo(o.dx, o.dy - 5)
          ..lineTo(o.dx + 5, o.dy)
          ..lineTo(o.dx, o.dy + 5)
          ..lineTo(o.dx - 5, o.dy)
          ..close();
        canvas.drawPath(d, g);
      }
    }
  }

  @override
  bool shouldRepaint(covariant Nx2FramePainter old) =>
      old.cut != cut ||
      old.fill != fill ||
      old.border != border ||
      old.glow != glow ||
      old.gems != gems;
}

/// Glass panel in the NX2 style (chamfered neon frame).
class Nx2Panel extends StatelessWidget {
  const Nx2Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
    this.cut = 14,
    this.gold = false,
    this.tint,
    this.borderColor,
    this.glow = 0.35,
    this.gems = false,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double cut;
  final bool gold;
  final Color? tint;
  final Color? borderColor;
  final double glow;
  final bool gems;

  @override
  Widget build(BuildContext context) {
    final Gradient border = borderColor != null
        ? LinearGradient(colors: <Color>[
            borderColor!,
            Color.lerp(borderColor!, Nx2.magenta, 0.4) ?? borderColor!
          ])
        : (gold ? Nx2.goldGrad : Nx2.neon);
    final Gradient? fill = tint == null
        ? (gold
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[Color(0xE63A2C14), Color(0xEB0F0D09)])
            : null)
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color.alphaBlend(tint!, const Color(0xE61C1912)),
              Color.alphaBlend(tint!, const Color(0xEB0A0A0D)),
            ],
          );
    Widget body = CustomPaint(
      painter: Nx2FramePainter(
          cut: cut, fill: fill, border: border, glow: glow, gems: gems),
      child: Padding(padding: padding, child: child),
    );
    if (onTap != null) {
      body = _Pressable(onTap: onTap!, child: body);
    }
    return body;
  }
}

/// Scale-down-on-press with a light haptic.
///
/// A null [onTap] means "disabled": the child is painted as-is, with no gesture
/// detector, no press animation and no tick sound — the same contract as
/// [Nx2Button.onTap] and Material's `onPressed`, so callers never have to invent
/// an empty callback (which would still swallow taps and play the tick).
class _Pressable extends StatefulWidget {
  const _Pressable({required this.onTap, required this.child});
  final VoidCallback? onTap;
  final Widget child;
  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    final VoidCallback? onTap = widget.onTap;
    if (onTap == null) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: () {
        HapticFeedback.selectionClick();
        NxSfx.instance.play('tick', gain: 0.6);
        onTap();
      },
      child: AnimatedScale(
        scale: _down ? 0.96 : 1,
        duration: const Duration(milliseconds: 110),
        child: widget.child,
      ),
    );
  }
}

/// Public wrapper of the press animation for art tiles.
class Nx2Pressable extends StatelessWidget {
  const Nx2Pressable({super.key, required this.onTap, required this.child});
  final VoidCallback? onTap;
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      _Pressable(onTap: onTap, child: child);
}

enum Nx2ButtonKind { pink, violet, cyan }

/// App button: the ANIX pack button family (pink = primary, violet = secondary, cyan = ghost).
class Nx2Button extends StatelessWidget {
  const Nx2Button({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.kind = Nx2ButtonKind.violet,
    this.height = 52,
    this.fontSize = 16,
    this.loading = false,
  });
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Nx2ButtonKind kind;
  final double height;
  final double fontSize;
  final bool loading;

  @override
  Widget build(BuildContext context) => AnixButton(
        label: label,
        onTap: onTap,
        icon: icon,
        loading: loading,
        height: height,
        fontSize: fontSize,
        style: switch (kind) {
          Nx2ButtonKind.pink => AnixButtonStyle.primary,
          Nx2ButtonKind.violet => AnixButtonStyle.secondary,
          Nx2ButtonKind.cyan => AnixButtonStyle.ghost,
        },
      );
}

/// Neon XP/progress bar in a chamfered track.
class Nx2Progress extends StatelessWidget {
  const Nx2Progress(
      {super.key, required this.value, this.height = 9, this.gold = false});
  final double value;
  final double height;
  final bool gold;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _BarPainter(value.clamp(0.0, 1.0), gold),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.v, this.gold);
  final double v;
  final bool gold;
  @override
  void paint(Canvas canvas, Size size) {
    final Rect r = Offset.zero & size;
    final double c = size.height / 2;
    final Path track = Nx2FramePainter.chamfer(r, c);
    canvas.drawPath(track, Paint()..color = const Color(0xCC11100C));
    canvas.drawPath(
        track,
        Paint()
          ..color = Nx2.goldDeep.withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
    if (v <= 0) return;
    final Rect f = Rect.fromLTWH(r.left + 1.5, r.top + 1.5,
        math.max(c * 2, (r.width - 3) * v), r.height - 3);
    final Path fill = Nx2FramePainter.chamfer(f, c - 1.5);
    canvas.drawPath(
        fill,
        Paint()
          ..shader = (gold
                  ? Nx2.goldGrad
                  : const LinearGradient(
                      colors: <Color>[Nx2.goldDeep, Nx2.cyan]))
              .createShader(f));
    canvas.drawPath(
        fill,
        Paint()
          ..color = (gold ? Nx2.gold : Nx2.cyan).withValues(alpha: 0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) =>
      old.v != v || old.gold != gold;
}

/// Coin / level pill in the HUD.
/// Gem colour (الماس) used by every gem balance / price.
const Color kGemColor = Color(0xFF3BD0FF);

/// Gem balance pill (same frame as the coin pill, diamond icon, cyan).
class Nx2GemStat extends StatelessWidget {
  const Nx2GemStat({super.key, required this.gems, this.onTap});
  final int gems;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) =>
      Nx2Stat(value: '$gems', icon: Icons.diamond_rounded, color: kGemColor, onTap: onTap);
}

class Nx2Stat extends StatelessWidget {
  const Nx2Stat(
      {super.key,
      required this.value,
      this.icon = Icons.toll_rounded,
      this.color = Nx2.gold,
      this.onTap,
      this.wiggle});
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  /// When it ticks, the pill gives a little shake (Oracle pokes the coins).
  final Listenable? wiggle;

  @override
  Widget build(BuildContext context) {
    final Widget pill = CustomPaint(
      painter: Nx2FramePainter(
          cut: 9,
          glow: 0.2,
          border: LinearGradient(colors: <Color>[
            color,
            Color.lerp(color, Nx2.magenta, 0.5) ?? color
          ]),
          fill: const LinearGradient(
              colors: <Color>[Color(0xF0180B40), Color(0xF00B0522)])),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 5, 10, 5),
        child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: <Color>[
                Color.lerp(color, Colors.white, 0.45) ?? color,
                color,
              ]),
              boxShadow: <BoxShadow>[
                BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8)
              ],
            ),
            child: Icon(icon, size: 13, color: const Color(0xFF2A1700)),
          ),
          const SizedBox(width: 6),
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.w900, fontSize: 13, color: Nx2.text)),
        ]),
      ),
    );
    Widget w = pill;
    if (wiggle != null) {
      w = _Wiggle(listenable: wiggle!, child: pill);
    }
    if (onTap != null) w = _Pressable(onTap: onTap!, child: w);
    return w;
  }
}

class _Wiggle extends StatefulWidget {
  const _Wiggle({required this.listenable, required this.child});
  final Listenable listenable;
  final Widget child;
  @override
  State<_Wiggle> createState() => _WiggleState();
}

class _WiggleState extends State<_Wiggle> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600));
  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_go);
  }

  void _go() {
    if (mounted) _c.forward(from: 0);
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_go);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, Widget? child) {
        final double t = _c.value;
        final double a = math.sin(t * math.pi * 6) * (1 - t) * 0.18;
        return Transform.rotate(
            angle: a,
            child: Transform.scale(
                scale: 1 + 0.12 * math.sin(t * math.pi), child: child));
      },
      child: widget.child,
    );
  }
}

/// Section header: neon bar + title + optional action.
class Nx2SectionHeader extends StatelessWidget {
  const Nx2SectionHeader(
      {super.key, required this.title, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(children: <Widget>[
      Container(
        width: 4,
        height: 18,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Nx2.cyan, Nx2.magenta]),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 15,
                letterSpacing: 0.6,
                color: Nx2.text)),
      ),
      if (action != null)
        GestureDetector(
          onTap: onAction,
          child: Text(action!,
              style: const TextStyle(
                  color: Nx2.cyan, fontWeight: FontWeight.w800, fontSize: 12)),
        ),
    ]);
  }
}

/// Destinations of the bottom dock (+ home/profile, reached from the drawer and the top bar).
enum Nx2Tab { home, social, oracle, games, shop, tournaments, rewards, profile }

String nx2TabPath(Nx2Tab t) => switch (t) {
      Nx2Tab.home => '/hub',
      Nx2Tab.social => '/social',
      Nx2Tab.oracle => '/oracle',
      Nx2Tab.games => '/rooms',
      Nx2Tab.shop => '/world/nexora_exchange',
      Nx2Tab.tournaments => '/tournaments',
      Nx2Tab.rewards => '/rewards',
      Nx2Tab.profile => '/world/personal_orbit',
    };

/// Goes to a dock destination: Home is the root; other tabs replace each other on top of it.
void nx2GoTab(BuildContext context, Nx2Tab tab, Nx2Tab? current) {
  if (tab == current) return;
  final String path = nx2TabPath(tab);
  if (tab == Nx2Tab.home) {
    context.go(path);
  } else if (current == null || current == Nx2Tab.home) {
    context.push(path);
  } else {
    context.pushReplacement(path);
  }
}

/// Bottom dock: three balanced destinations on each side of the raised GAME action.
/// Keeping six equal cells prevents long labels from colliding on narrow phones.
class Nx2Dock extends StatelessWidget {
  const Nx2Dock({super.key, required this.current});
  final Nx2Tab? current;

  static const Color _gold = Color(0xFFD9B872);
  static const Color _gold2 = Color(0xFFF6E7BD);
  static const Color _mute = Color(0x99F4EAD2);

  bool get _moreOn => const <Nx2Tab>{Nx2Tab.shop, Nx2Tab.rewards, Nx2Tab.profile, Nx2Tab.oracle}.contains(current);

  void _more(BuildContext context) {
    final List<(Nx2Tab?, String, String, String, String?)> rows = <(Nx2Tab?, String, String, String, String?)>[
      (Nx2Tab.shop, 'r4c1', 'فروشگاه', 'Shop', null),
      (Nx2Tab.rewards, 'r3c6', 'جایزه‌ها و ماموریت‌ها', 'Rewards & missions', null),
      (Nx2Tab.profile, 'r4c4', 'پروفایل', 'Profile', null),
      (Nx2Tab.oracle, 'r5c2', 'هوش مصنوعی اوراکل', 'ORACLE AI', null),
      (null, 'r3c5', 'رویدادها', 'Events', '/station/events'),
      (null, 'r2c6', 'رده‌بندی', 'Leaderboard', '/leaderboard'),
      (null, 'r4c2', 'تنظیمات', 'Settings', '/settings'),
    ];
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x8C030306),
      builder: (BuildContext ctx) => Container(
        padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.paddingOf(ctx).bottom + 18),
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: <Color>[Color(0xFF14130F), Color(0xFF0A0A0D)]),
          border: Border(top: BorderSide(color: Color(0x33D9B872))),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(color: const Color(0x40F6E7BD), borderRadius: BorderRadius.circular(4))),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.95,
            children: <Widget>[
              for (final (Nx2Tab?, String, String, String, String?) r in rows)
                _Pressable(
                  onTap: () {
                    Navigator.of(ctx).pop();
                    if (r.$1 != null) {
                      nx2GoTab(context, r.$1!, current);
                    } else {
                      context.push(r.$5!);
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: const LinearGradient(
                          begin: Alignment(-0.6, -1),
                          end: Alignment(0.6, 1),
                          colors: <Color>[Color(0x13FFFFFF), Color(0x04FFFFFF)]),
                      border: Border.all(color: r.$1 == current && current != null ? _gold : const Color(0x33D9B872)),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
                      Expanded(
                        child: Image.asset('assets/luxe/icons/${r.$2}.webp',
                            cacheWidth: 180, errorBuilder: (_, __, ___) => const SizedBox()),
                      ),
                      const SizedBox(height: 4),
                      Text(context.tx(r.$3, r.$4),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, color: Color(0xFFF4EAD2))),
                    ]),
                  ),
                ),
            ],
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double bottom = MediaQuery.paddingOf(context).bottom;

    Widget cell({required String id, required bool on, required String fa, required String en, String? icon,
        IconData? glyph, required VoidCallback onTap}) {
      return Expanded(
        child: OracleTourTarget(
          id: id,
          child: _Pressable(
            onTap: onTap,
            child: Semantics(
              selected: on,
              button: true,
              label: context.tx(fa, en),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 450),
                curve: const Cubic(.22, .8, .2, 1),
                padding: const EdgeInsets.symmetric(vertical: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: on
                      ? const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[Color(0x33D9B872), Color(0x08D9B872)])
                      : null,
                  border: Border.all(color: on ? const Color(0x40D9B872) : Colors.transparent),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: icon != null
                        ? DecoratedBox(
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: on
                                    ? const <BoxShadow>[BoxShadow(color: Color(0x88D9B872), blurRadius: 12)]
                                    : const <BoxShadow>[]),
                            child: Image.asset('assets/luxe/icons/$icon.webp',
                                cacheWidth: 96, errorBuilder: (_, __, ___) => Icon(glyph, color: on ? _gold2 : _mute)),
                          )
                        : Icon(glyph, size: 24, color: on ? _gold2 : _mute),
                  ),
                  const SizedBox(height: 2),
                  SizedBox(
                    height: 14,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(context.tx(fa, en),
                          maxLines: 1,
                          style: TextStyle(fontSize: 10, color: on ? _gold2 : _mute, fontWeight: FontWeight.w500)),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
    }

    const double center = 72;
    final bool gameOn = current == Nx2Tab.games;
    return OracleTourTarget(
      id: 'dock',
      child: SizedBox(
        height: 74 + bottom + 26,
        child: Stack(clipBehavior: Clip.none, children: <Widget>[
          Positioned(
            left: 14,
            right: 14,
            bottom: bottom + 10,
            height: 70,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: const Color(0x8C0E0E12),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: const Color(0x33D9B872)),
                  ),
                  child: Row(children: <Widget>[
                    cell(
                        id: 'dock.home',
                        on: current == Nx2Tab.home,
                        fa: 'خانه',
                        en: 'Home',
                        glyph: Icons.home_rounded,
                        onTap: () => nx2GoTab(context, Nx2Tab.home, current)),
                    cell(
                        id: 'dock.social',
                        on: current == Nx2Tab.social,
                        fa: 'چت',
                        en: 'Chat',
                        icon: 'r3c3',
                        glyph: Icons.chat_bubble_rounded,
                        onTap: () => nx2GoTab(context, Nx2Tab.social, current)),
                    const SizedBox(width: center),
                    cell(
                        id: 'dock.tournaments',
                        on: current == Nx2Tab.tournaments,
                        fa: 'تورنمنت',
                        en: 'Cups',
                        icon: 'r2c5',
                        glyph: Icons.emoji_events_rounded,
                        onTap: () => nx2GoTab(context, Nx2Tab.tournaments, current)),
                    cell(
                        id: 'dock.more',
                        on: _moreOn,
                        fa: 'بیشتر',
                        en: 'More',
                        icon: 'r4c1',
                        glyph: Icons.apps_rounded,
                        onTap: () => _more(context)),
                  ]),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: bottom + 26,
            left: 0,
            right: 0,
            child: Center(
              child: OracleTourTarget(
                id: 'dock.games',
                child: _Pressable(
                  onTap: () => nx2GoTab(context, Nx2Tab.games, current),
                  child: Semantics(
                    button: true,
                    label: context.tx('بازی‌ها', 'GAMES'),
                    child: Container(
                      width: center,
                      height: center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const RadialGradient(
                            center: Alignment(-0.3, -0.4),
                            colors: <Color>[Color(0xFF2A2418), Color(0xFF0B0A08)]),
                        border: Border.all(color: _gold, width: 1.4),
                        boxShadow: <BoxShadow>[
                          BoxShadow(color: _gold.withValues(alpha: gameOn ? 0.75 : 0.45), blurRadius: gameOn ? 26 : 18),
                          const BoxShadow(color: Colors.black, blurRadius: 20, offset: Offset(0, 10)),
                        ],
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
                        Image.asset('assets/luxe/icons/r4c5.webp',
                            width: 38,
                            height: 38,
                            cacheWidth: 120,
                            errorBuilder: (_, __, ___) => const Icon(Icons.sports_esports_rounded, color: _gold2)),
                        Text(context.tx('بازی', 'GAME'),
                            style: const TextStyle(
                                fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: _gold2)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Top bar for world pages: ornate back button, title plate and wallet.
class Nx2TopBar extends ConsumerWidget implements PreferredSizeWidget {
  const Nx2TopBar(
      {super.key, required this.title, this.actions, this.showWallet = true});
  final String title;
  final List<Widget>? actions;
  final bool showWallet;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ProfileService p = ref.watch(profileProvider);
    final bool canPop = Navigator.of(context).canPop();
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: 64,
        child: Row(children: <Widget>[
          const SizedBox(width: 6),
          if (canPop)
            _RoundIcon(
              icon: Directionality.of(context) == TextDirection.rtl
                  ? Icons.arrow_forward_rounded
                  : Icons.arrow_back_rounded,
              tooltip: context.tx('بازگشت', 'Back'),
              onTap: () => Navigator.of(context).maybePop(),
            )
          else
            _RoundIcon(
                icon: Icons.home_rounded,
                tooltip: context.tx('خانه', 'Home'),
                onTap: () => context.go('/hub')),
          const SizedBox(width: 6),
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Nx2.title.copyWith(fontSize: 17)),
          ),
          _RoundIcon(
            icon: Icons.search_rounded,
            tooltip: context.tx('جستجوی سراسری', 'Open global search'),
            onTap: () => showSearch<void>(
              context: context,
              delegate: HubSearchDelegate(
                isFa: Localizations.localeOf(context).languageCode == 'fa',
              ),
            ),
          ),
          ...?actions,
          if (showWallet) ...<Widget>[
            const SizedBox(width: 4),
            Nx2Stat(value: '${p.coins}'),
            const SizedBox(width: 4),
            Nx2GemStat(gems: p.gems),
          ],
          const SizedBox(width: 10),
        ]),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon(
      {required this.icon, required this.onTap, required this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: _Pressable(
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: CustomPaint(
            painter: Nx2FramePainter(cut: 12, glow: 0.3),
            child: Icon(icon, color: Nx2.text, size: 22),
          ),
        ),
      ),
    );
  }
}

/// Neon segmented tabs bound to the nearest DefaultTabController.
class Nx2SegmentTabs extends StatelessWidget {
  const Nx2SegmentTabs({super.key, required this.labels});
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xCC14130F),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Nx2.cyan.withValues(alpha: 0.45)),
      ),
      child: TabBar(
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(colors: <Color>[Color(0xFFF6E7BD), Color(0xFFD9B872)]),
        ),
        labelColor: const Color(0xFF14120C),
        unselectedLabelColor: Nx2.muted,
        labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
        tabs: <Widget>[for (final String l in labels) Tab(height: 36, text: l)],
      ),
    );
  }
}
