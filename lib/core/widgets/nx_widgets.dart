import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../assets/app_assets.dart';
import '../navigation/nexora_menu.dart';
import '../profile/profile_service.dart';
import '../settings/app_settings.dart';
import '../theme/nx_theme.dart';

/// Animated cosmic background used by every world (respects quality + reduced motion).
class NxBackground extends ConsumerStatefulWidget {
  const NxBackground(
      {super.key,
      this.palette = WorldPalette.hub,
      this.child,
      this.stars = true});
  final WorldPalette palette;
  final Widget? child;
  final bool stars;

  @override
  ConsumerState<NxBackground> createState() => _NxBackgroundState();
}

class _NxBackgroundState extends ConsumerState<NxBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 60));
  List<_Star> _stars = const [];
  int _count = -1;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _ensureStars(int count) {
    if (count == _count) return;
    _count = count;
    final r = Random(7);
    _stars = List.generate(
        count,
        (_) => _Star(r.nextDouble(), r.nextDouble(), r.nextDouble() * 1.6 + 0.3,
            r.nextDouble()));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final animate = !s.reducedMotion;
    if (animate && !_c.isAnimating) _c.repeat();
    if (!animate && _c.isAnimating) _c.stop();
    _ensureStars(widget.palette.light ? (s.starCount ~/ 3) : s.starCount);
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: widget.palette.background,
            ),
          ),
        ),
        if (widget.stars)
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, __) => CustomPaint(
                painter: _StarPainter(_stars, _c.value, widget.palette),
              ),
            ),
          ),
        if (widget.child != null) widget.child!,
      ],
    );
  }
}

class _Star {
  const _Star(this.x, this.y, this.size, this.phase);
  final double x, y, size, phase;
}

class _StarPainter extends CustomPainter {
  _StarPainter(this.stars, this.t, this.palette);
  final List<_Star> stars;
  final double t;
  final WorldPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    // nebula glows
    final glow1 = Paint()
      ..shader = RadialGradient(colors: [
        palette.primary.withValues(alpha: 0.18),
        Colors.transparent
      ]).createShader(Rect.fromCircle(
          center: Offset(size.width * 0.15, size.height * 0.25),
          radius: size.width * 0.8));
    canvas.drawRect(Offset.zero & size, glow1);
    final glow2 = Paint()
      ..shader = RadialGradient(colors: [
        palette.secondary.withValues(alpha: 0.16),
        Colors.transparent
      ]).createShader(Rect.fromCircle(
          center: Offset(size.width * 0.9, size.height * 0.75),
          radius: size.width * 0.9));
    canvas.drawRect(Offset.zero & size, glow2);
    final p = Paint();
    final starColor = palette.light ? palette.secondary : Colors.white;
    for (final s in stars) {
      final tw = 0.55 + 0.45 * sin((t * 2 * pi * 6) + s.phase * 6.28);
      final dy = (s.y + t * 0.05 * s.size) % 1.0;
      p.color = starColor.withValues(alpha: (palette.light ? 0.35 : 0.85) * tw);
      canvas.drawCircle(Offset(s.x * size.width, dy * size.height), s.size, p);
    }
  }

  @override
  bool shouldRepaint(covariant _StarPainter old) =>
      old.t != t || old.stars != stars;
}

/// Quiet, premium dark backdrop used by app surfaces (not active game boards).
class NxBrandBackground extends StatelessWidget {
  const NxBrandBackground({super.key, this.child});
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                visual.background,
                visual.backgroundMid,
                visual.background
              ],
            ),
          ),
        ),
        Positioned(
          top: -150,
          right: -100,
          width: 360,
          height: 360,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: <Color>[
                  visual.accent.withValues(alpha: 0.13),
                  Colors.transparent
                ]),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -180,
          left: -120,
          width: 420,
          height: 420,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: <Color>[
                  visual.accentSecondary.withValues(alpha: 0.10),
                  Colors.transparent
                ]),
              ),
            ),
          ),
        ),
        if (child != null) child!,
      ],
    );
  }
}

/// Premium inset panel with a quiet metallic/neon rim, shared by all app worlds.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(NxSpace.md),
    this.radius = NxRadius.lg,
    this.tint,
    this.borderColor,
    this.blur = true,
    this.onTap,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? tint;
  final Color? borderColor;
  final bool blur;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    final Color panelFill = tint ?? visual.surface;
    Widget body = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: visual.premiumPanels && tint == null ? null : panelFill,
        gradient: visual.premiumPanels && tint == null
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[visual.surfaceRaised, visual.surface],
              )
            : null,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: borderColor ??
              visual.border.withValues(alpha: visual.premiumPanels ? 0.48 : 1),
          width: visual.premiumPanels ? 1.1 : 1,
        ),
        boxShadow: visual.premiumPanels
            ? <BoxShadow>[
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 18,
                    offset: const Offset(0, 8)),
                BoxShadow(
                    color: visual.accent.withValues(alpha: 0.055),
                    blurRadius: 16,
                    spreadRadius: 0.5),
              ]
            : null,
      ),
      child: child,
    );
    if (onTap != null) {
      body = Material(
        color: Colors.transparent,
        child: InkWell(
            borderRadius: BorderRadius.circular(radius),
            onTap: onTap,
            child: body),
      );
    }
    if (!blur) {
      return ClipRRect(
          borderRadius: BorderRadius.circular(radius), child: body);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14), child: body),
    );
  }
}

/// Small rounded label.
class NxPill extends StatelessWidget {
  const NxPill({super.key, required this.label, this.icon, this.color});
  final String label;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final Color pillColor = color ?? NxThemeColors.of(context).accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: pillColor.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: pillColor.withValues(alpha: 0.55)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: pillColor),
          const SizedBox(width: 4)
        ],
        Text(label,
            style: TextStyle(
                color: pillColor, fontWeight: FontWeight.w700, fontSize: 12)),
      ]),
    );
  }
}

/// Coins + level chip for app bars.
class WalletChip extends ConsumerWidget {
  const WalletChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(profileProvider);
    final NxThemeColors visual = NxThemeColors.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      NxPill(
          label: '${p.coins}', icon: Icons.toll_rounded, color: NxColors.gold),
      const SizedBox(width: 6),
      NxPill(
          label: 'Lv ${p.level}',
          icon: Icons.bolt_rounded,
          color: visual.accent),
    ]);
  }
}

/// XP progress bar.
class XpBar extends ConsumerWidget {
  const XpBar({super.key, this.height = 10});
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(profileProvider);
    final NxThemeColors visual = NxThemeColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Text('${context.tx('سطح', 'Level')} ${p.level}',
            style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(width: 8),
        Text(context.tx(p.rankTitleFa, p.rankTitleEn),
            style: TextStyle(color: visual.muted, fontSize: 12)),
        const Spacer(),
        Text('${p.xpIntoLevel}/${ProfileService.xpForLevel(p.level)} XP',
            style: TextStyle(color: visual.muted, fontSize: 12)),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: Stack(children: [
          Container(height: height, color: const Color(0x22FFFFFF)),
          FractionallySizedBox(
            widthFactor: p.levelProgress.clamp(0.0, 1.0),
            child: Container(
              height: height,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [visual.accent, visual.accentSecondary]),
              ),
            ),
          ),
        ]),
      ),
    ]);
  }
}

/// Standard world page scaffold with themed background and app bar.
class NxWorldScaffold extends StatelessWidget {
  const NxWorldScaffold({
    super.key,
    required this.title,
    required this.palette,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.showWallet = true,
    this.showSearchButton = true,
  });
  final String title;
  final WorldPalette palette;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool showWallet;
  final bool showSearchButton;

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: visual.background,
      appBar: AppBar(
        foregroundColor: visual.text,
        titleTextStyle: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
            color: visual.text),
        title: Text(title),
        actions: [
          ...?actions,
          if (showSearchButton)
            IconButton(
              tooltip: context.tx('جستجوی سراسری', 'Open global search'),
              onPressed: () => context.push('/search'),
              icon: const Icon(Icons.search_rounded),
            ),
          IconButton(
            tooltip: context.tx('باز کردن منوی بخش‌ها', 'Open section menu'),
            onPressed: () => showNexoraMenu(context),
            icon: const Icon(Icons.apps_rounded),
          ),
          if (showWallet)
            const Padding(
                padding: EdgeInsetsDirectional.only(end: 10),
                child: WalletChip()),
        ],
      ),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      body: NxBrandBackground(
        child: SafeArea(child: body),
      ),
    );
  }
}

/// ORACLE mascot image with gentle float animation.
class OracleAvatar extends ConsumerStatefulWidget {
  const OracleAvatar({super.key, this.pose = 'idle', this.size = 90});
  final String pose;
  final double size;

  @override
  ConsumerState<OracleAvatar> createState() => _OracleAvatarState();
}

class _OracleAvatarState extends ConsumerState<OracleAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2400))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = ref.watch(settingsProvider).reducedMotion;
    final img = Image.asset(
      AppAssets.oraclePose(widget.pose),
      height: widget.size,
      cacheHeight: (widget.size * 2.5).round(),
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) =>
          Icon(Icons.blur_circular, size: widget.size, color: NxColors.violet),
    );
    if (reduced) return img;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) => Transform.translate(
          offset: Offset(0, -6 * Curves.easeInOut.transform(_c.value)),
          child: child),
      child: img,
    );
  }
}

/// Shows level-up / achievement celebration (short, skippable).
Future<void> showAwardOutcome(BuildContext context, AwardOutcome o) async {
  if (!o.levelUp && o.unlocked.isEmpty) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(children: [
        const Icon(Icons.auto_awesome, color: NxColors.gold),
        const SizedBox(width: 8),
        Expanded(
            child: Text(o.levelUp
                ? ctx.tx('ارتقای سطح!', 'Level up!')
                : ctx.tx('دستاورد جدید!', 'New achievement!'))),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        if (o.levelUp)
          Text('${ctx.tx('سطح', 'Level')} ${o.newLevel}',
              style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: NxColors.turquoise)),
        for (final a in o.unlocked)
          ListTile(
            leading: Image.asset(AppAssets.achievement(a.asset),
                width: 44, cacheWidth: 120),
            title: Text(ctx.tx(a.nameFa, a.nameEn)),
            subtitle: Text('${ctx.tx(a.descFa, a.descEn)}  +${a.coinReward}'),
          ),
      ]),
      actions: [
        FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.tx('عالی', 'Great')))
      ],
    ),
  );
}

/// Honest "needs online" notice for features that can't work offline yet.
class OnlineOnlyNotice extends StatelessWidget {
  const OnlineOnlyNotice(
      {super.key, required this.featureFa, required this.featureEn});
  final String featureFa;
  final String featureEn;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      tint: const Color(0x14FFC857),
      borderColor: NxColors.gold.withValues(alpha: 0.5),
      child: Row(children: [
        const Icon(Icons.cloud_off_rounded, color: NxColors.gold),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            context.tx(
                '$featureFa به اتصال آنلاین نیاز دارد و بعد از اتصال سرور فعال می‌شود.',
                '$featureEn needs the online server and turns on once it is connected.'),
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ]),
    );
  }
}
