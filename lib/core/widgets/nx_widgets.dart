import 'dart:math';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../assets/app_assets.dart';
import '../profile/profile_service.dart';
import '../settings/app_settings.dart';
import '../theme/nx_theme.dart';
import '../ui2/luxe.dart';
import '../ui2/nx2_widgets.dart';
import '../ui2/oracle_mascot.dart';

import '../ui2/anix_kit.dart';
import '../../worlds/hub/hub_search.dart';
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

/// ===================== ONE PAGE SHELL =====================
/// Every non-game screen of ANIX PRO is drawn by [NxPageShell]: the Station Luxe
/// backdrop of the home page, one top bar ([NxTopBar]), one bottom dock, one safe-area
/// policy and one page transition. Pages only supply their body.
///
/// Before this, each world built its own `Scaffold` + `AppBar`/`Nx2TopBar` + background
/// combination, so the arcade, rooms, tournaments, settings and profile could drift apart
/// (different bar height, different wallet visibility, different backdrop art, some pages
/// even dropped the safe area). Anything that needs a page now goes through here.
/// ==========================================================
class NxPageShell extends StatelessWidget {
  const NxPageShell({
    super.key,
    required this.title,
    required this.body,
    this.accent,
    this.actions,
    this.leading,
    this.bottomNavigationBar,
    this.dock,
    this.sections,
    this.sectionIndex = 0,
    this.onSectionSelect,
    this.floatingActionButton,
    this.showWallet = true,
    this.search = true,
    this.showBack = true,
    this.scene,
    this.backdrop = true,
    this.safeArea = true,
    this.resizeToAvoidBottomInset,
    this.backgroundColor,
    this.trailing,
  });

  /// Page title (already localised by the caller, usually with `context.tx`).
  final String title;
  final Widget body;

  /// World tint used for the bar's hairline glow. Defaults to the theme accent.
  final Color? accent;
  final List<Widget>? actions;

  /// Replaces the default back/home button when set.
  final Widget? leading;

  /// When set (or when [dock]/[sections] is set) the Luxe dock is attached to the bottom.
  final Widget? bottomNavigationBar;

  /// App-level dock tab.
  final Nx2Tab? dock;

  /// In-page sections (sub-tabs of one screen, e.g. NOVA's Feed/Explore/Reels). They are drawn
  /// by [NxDockBar] on the same geometry as the app dock, so sub-tabs never look like a second
  /// design language.
  final List<NxDockSection>? sections;
  final int sectionIndex;
  final ValueChanged<int>? onSectionSelect;
  final Widget? floatingActionButton;

  /// Coins + gems pills on the right of the bar.
  final bool showWallet;

  /// Global search button on the right of the bar (`search`, not `showSearch`, which would
  /// shadow Material's `showSearch()` inside this widget).
  final bool search;
  final bool showBack;

  /// Backdrop art; defaults to the arcade art for the arcade palette and the social art
  /// for the social worlds, exactly like the home page's luxe hub art.
  final Nx2Scene? scene;

  /// False for pages that paint their own full-bleed art (splash, video, cinematic).
  final bool backdrop;
  final bool safeArea;
  final bool? resizeToAvoidBottomInset;
  final Color? backgroundColor;

  /// Extra widgets appended after [actions] in the bar (right side).
  final List<Widget>? trailing;

  @override
  Widget build(BuildContext context) {
    final Widget? bottom = bottomNavigationBar ??
        (sections != null
            ? NxDockBar(
                sections: sections!,
                index: sectionIndex,
                onSelect: onSectionSelect,
              )
            : (dock != null ? Nx2Dock(current: dock) : null));
    final bool hasBottom = bottom != null;
    final Widget content = safeArea
        ? SafeArea(top: false, bottom: !hasBottom, child: body)
        : body;
    return Scaffold(
      backgroundColor: backgroundColor ?? Nx2.deep,
      extendBody: hasBottom,
      // The body starts *below* the bar. This is the one layout contract of the shell: a page
      // supplies a body and never pads for the bar itself. (Pages used to add kToolbarHeight by
      // hand — which was also wrong, because the bar is 64, not 56.)
      extendBodyBehindAppBar: false,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: NxTopBar(
          title: title,
          accent: accent,
          actions: <Widget>[...?actions, ...?trailing],
          leading: leading,
          showWallet: showWallet,
          search: search,
          showBack: showBack,
        ),
      ),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottom,
      // NxBrandBackground paints the art as a Stack and appends the child last, so the page
      // body is always above the art with a single image decode per screen.
      body: backdrop ? NxBrandBackground(scene: scene, child: content) : content,
    );
  }
}

/// One destination of an in-page [NxDockBar].
class NxDockSection {
  const NxDockSection({required this.icon, required this.label, this.badge = 0, this.activeIcon});
  final IconData icon;
  final IconData? activeIcon;
  final String label;

  /// Red count on the icon (0 hides it).
  final int badge;
}

/// In-page sections bar. Same height, gold chrome, glass and label behaviour as the app dock,
/// so a screen with sub-tabs (NOVA Gallery, Orbit Network) keeps the home page's navigation
/// language instead of dropping a Material [NavigationBar] under a Luxe app bar.
class NxDockBar extends StatelessWidget implements PreferredSizeWidget {
  const NxDockBar({super.key, required this.sections, this.index = 0, this.onSelect});
  final List<NxDockSection> sections;
  final int index;
  final ValueChanged<int>? onSelect;

  @override
  Size get preferredSize => const Size.fromHeight(66);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 66,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xF20F0E0B), Color(0xFA07080C)],
        ),
        border: Border(top: BorderSide(color: Color(0x33D9B872))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: <Widget>[
            for (int i = 0; i < sections.length; i++)
              Expanded(
                child: Nx2Pressable(
                  onTap: onSelect == null ? null : () => onSelect!(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Badge(
                        isLabelVisible: sections[i].badge > 0,
                        backgroundColor: Nx2.danger,
                        label: Text('${sections[i].badge}', style: const TextStyle(fontSize: 9)),
                        child: Icon(
                          i == index ? (sections[i].activeIcon ?? sections[i].icon) : sections[i].icon,
                          size: 22,
                          color: i == index ? Luxe.gold : Luxe.mute,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        sections[i].label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: i == index ? FontWeight.w900 : FontWeight.w600,
                          color: i == index ? Luxe.gold2 : Luxe.mute,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The single top bar of the application: ornate frame buttons (identical geometry on
/// every screen), title plate, global search and the wallet. Mirrors the home page's HUD.
class NxTopBar extends ConsumerWidget implements PreferredSizeWidget {
  const NxTopBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.accent,
    this.showWallet = true,
    this.search = true,
    this.showBack = true,
  });

  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final Color? accent;
  final bool showWallet;
  final bool search;
  final bool showBack;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ProfileService p = ref.watch(profileProvider);
    final Color tint = accent ?? NxThemeColors.of(context).accent;
    final bool canPop = Navigator.of(context).canPop();
    final bool rtl = Directionality.of(context) == TextDirection.rtl;
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: 64,
        child: Row(children: <Widget>[
          const SizedBox(width: 8),
          if (leading != null)
            leading!
          else if (showBack)
            NxBarButton(
              icon: canPop
                  ? (rtl ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded)
                  : Icons.home_rounded,
              tooltip: canPop
                  ? context.tx('بازگشت', 'Back')
                  : context.tx('خانه', 'Home'),
              tint: tint,
              onTap: () {
                if (canPop) {
                  Navigator.of(context).maybePop();
                } else {
                  context.go('/hub');
                }
              },
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Nx2.title.copyWith(fontSize: 17, shadows: <Shadow>[
                Shadow(color: tint.withValues(alpha: 0.4), blurRadius: 12),
              ]),
            ),
          ),
          if (search)
            NxBarButton(
              icon: Icons.search_rounded,
              tooltip: context.tx('جستجوی سراسری', 'Open global search'),
              tint: tint,
              onTap: () => showSearch<void>(
                context: context,
                delegate: HubSearchDelegate(
                  isFa: Localizations.localeOf(context).languageCode == 'fa',
                ),
              ),
            ),
          ...?actions,
          if (showWallet) ...<Widget>[
            const SizedBox(width: 2),
            Nx2Stat(value: '${p.coins}', onTap: () => context.push('/world/nexora_exchange')),
            const SizedBox(width: 4),
            Nx2GemStat(gems: p.gems, onTap: () => context.push('/world/nexora_exchange')),
          ],
          const SizedBox(width: 10),
        ]),
      ),
    );
  }
}

/// Square frame button used by [NxTopBar] and by page headers (arcade HUD, room header…).
class NxBarButton extends StatelessWidget {
  const NxBarButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.tint,
    this.size = 44,
    this.color,
  });
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final Color? tint;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final Color c = tint ?? NxThemeColors.of(context).accent;
    final Widget button = Nx2Pressable(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: Nx2FramePainter(
              cut: 12,
              glow: 0.22,
              border: LinearGradient(colors: <Color>[c, Color.lerp(c, Nx2.gold, 0.5) ?? c]),
            ),
            child: Icon(icon, color: color ?? Nx2.text, size: size * 0.5),
          ),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// App surfaces backdrop (NX2: the owner's cosmic castle art, darkened for contrast).
class NxBrandBackground extends StatelessWidget {
  const NxBrandBackground({super.key, this.child, this.room = false, this.scene});
  final Widget? child;
  final bool room;
  final Nx2Scene? scene;

  @override
  Widget build(BuildContext context) => Nx2Background(room: room, scene: scene, child: child);
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
    // One surface style app-wide: the home page's rounded Luxe glass (gold hairline,
    // blurred warm charcoal), not the chamfered neon frame. Pages that ask for a border
    // colour keep their tint — the tint only changes the hairline, never the geometry.
    final Widget panel = LuxeCard(
      padding: padding,
      radius: math.max(NxRadius.md, math.min(radius, LuxeRadius.lg)),
      borderColor: borderColor,
      tint: tint,
      blur: blur ? 14 : 0,
      child: child,
    );
    if (onTap == null) return panel;
    return Nx2Pressable(onTap: onTap!, child: panel);
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
    final Color pillColor = color ?? Nx2.cyan;
    return CustomPaint(
      painter: Nx2FramePainter(
        cut: 7,
        glow: 0,
        strokeWidth: 1.1,
        fill: LinearGradient(colors: <Color>[
          pillColor.withValues(alpha: 0.22),
          const Color(0xE614130F),
        ]),
        border: LinearGradient(colors: <Color>[
          pillColor,
          pillColor.withValues(alpha: 0.5),
        ]),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: pillColor),
            const SizedBox(width: 4)
          ],
          Text(label,
              style: TextStyle(
                  color: Color.lerp(pillColor, Colors.white, 0.35),
                  fontWeight: FontWeight.w800,
                  fontSize: 12)),
        ]),
      ),
    );
  }
}

/// XP progress bar.
class XpBar extends ConsumerWidget {
  const XpBar({super.key, this.height = 10});
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(profileProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Text('${context.tx('سطح', 'Level')} ${p.level}',
            style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(width: 8),
        Text(context.tx(p.rankTitleFa, p.rankTitleEn),
            style: const TextStyle(color: NxColors.textDim, fontSize: 12)),
        const Spacer(),
        Text('${p.xpIntoLevel}/${ProfileService.xpForLevel(p.level)} XP',
            style: const TextStyle(color: NxColors.textDim, fontSize: 12)),
      ]),
      const SizedBox(height: 6),
      Nx2Progress(value: p.levelProgress, height: height),
    ]);
  }
}

/// Standard world page scaffold (NX2 top bar, cosmic backdrop, optional bottom dock).
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
    this.dock,
    this.sections,
    this.sectionIndex = 0,
    this.onSectionSelect,
    this.room = false,
    this.scene,
  });
  final String title;
  final WorldPalette palette;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool showWallet;

  /// When set, the NX2 bottom dock is shown with this tab highlighted.
  final Nx2Tab? dock;

  /// In-page sub-tabs of this screen (NOVA's Feed/Explore/Reels, Orbit's Chats/Calls/Contacts).
  /// Forwarded to [NxPageShell], which draws them with [NxDockBar] on the app dock's own
  /// geometry — one navigation language instead of a second bar style per page.
  final List<NxDockSection>? sections;
  final int sectionIndex;
  final ValueChanged<int>? onSectionSelect;
  final bool room;

  /// Scene art; by default arcade pages get the ANIX arcade art and social pages the social art.
  final Nx2Scene? scene;

  Nx2Scene? get _scene {
    if (scene != null) return scene;
    if (identical(palette, WorldPalette.arcade)) return Nx2Scene.arcade;
    if (identical(palette, WorldPalette.social) ||
        identical(palette, WorldPalette.nova) ||
        identical(palette, WorldPalette.orbit)) {
      return Nx2Scene.social;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => NxPageShell(
        title: title,
        accent: palette.primary,
        body: body,
        actions: actions,
        leading: null,
        bottomNavigationBar: bottomNavigationBar,
        dock: dock,
        sections: sections,
        sectionIndex: sectionIndex,
        onSectionSelect: onSectionSelect,
        floatingActionButton: floatingActionButton,
        showWallet: showWallet,
        scene: room ? Nx2Scene.room : _scene,
      );
}

/// ORACLE mascot (NX2 animated robot). Legacy pose names map to moods.
class OracleAvatar extends StatelessWidget {
  const OracleAvatar({super.key, this.pose = 'idle', this.size = 90});
  final String pose;
  final double size;

  @override
  Widget build(BuildContext context) => OracleMascot(
      mood: oracleMoodFromLegacy(pose), size: size, interactive: true);
}

/// Shows level-up / achievement celebration (short, skippable).
Future<void> showAwardOutcome(BuildContext context, AwardOutcome o) async {
  if (!o.levelUp && o.unlocked.isEmpty) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AnixDialog(
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
                  color: NxColors.champagne)),
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
