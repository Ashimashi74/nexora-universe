import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/profile/profile_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/ui2/luxe.dart';
import '../../core/ui2/nx2_widgets.dart';
import '../../core/widgets/nx_widgets.dart';
import 'luxe_worlds.dart';

/// Opens a Station item: a real route, or a real in-app action.
Future<void> luxeOpen(BuildContext context, WidgetRef ref, LuxeItem it) async {
  if (it.action == 'daily') {
    await luxeClaimDaily(context, ref);
    return;
  }
  final String? r = it.route;
  if (r != null) context.push(r);
}

/// Claims today's reward through ProfileService (server-synced award path).
Future<void> luxeClaimDaily(BuildContext context, WidgetRef ref) async {
  final ProfileService p = ref.read(profileProvider);
  final AwardOutcome? o = p.claimDaily();
  if (!context.mounted) return;
  if (o == null) {
    luxeToast(
        context,
        context.tx('جایزه‌ی امروز را گرفته‌ای. فردا برگرد!', 'Already claimed today. Come back tomorrow!'),
    );
    return;
  }
  await showAwardOutcome(context, o);
}

/// A Station world: glyph header, gold tabs and a grid of glass tiles (Station Luxe "world" view).
class LuxeStationPage extends ConsumerStatefulWidget {
  const LuxeStationPage({super.key, required this.k});
  final String k;

  @override
  ConsumerState<LuxeStationPage> createState() => _LuxeStationPageState();
}

class _LuxeStationPageState extends ConsumerState<LuxeStationPage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final LuxeWorld? w = luxeWorld(widget.k);
    if (w == null) {
      return Scaffold(
        backgroundColor: Luxe.bg,
        body: Center(
          child: Text(context.tx('این بخش پیدا نشد', 'Section not found'), style: const TextStyle(color: Luxe.ink)),
        ),
      );
    }
    final List<LuxeItem> items = w.items.where((LuxeItem i) => i.tab == _tab).toList();
    final List<String> tabs = context.isFa ? w.tabsFa : w.tabsEn;
    return Scaffold(
      backgroundColor: Luxe.bg,
      extendBody: true,
      bottomNavigationBar: Nx2Dock(current: _dockTab(w.k)),
      body: LuxeScene(
        // Live orbital-station ambient behind each world station (subtle, tinted to the world).
        stationScene: true,
        artOpacity: 0.3,
        tint: w.color,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
              Row(children: <Widget>[
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: w.color.withValues(alpha: 0.45)),
                    gradient: RadialGradient(
                        center: const Alignment(-0.3, -0.4),
                        colors: <Color>[w.color.withValues(alpha: 0.3), Colors.transparent]),
                  ),
                  padding: const EdgeInsets.all(6),
                  child: Image.asset(Luxe.icon(w.icon), cacheWidth: 140, errorBuilder: (_, __, ___) => const SizedBox()),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Text(w.fa, style: const TextStyle(fontSize: 21, color: Luxe.ink)),
                    Text(w.en, style: Luxe.latin),
                  ]),
                ),
                LuxePress(
                  semantics: context.tx('بازگشت', 'Back'),
                  onTap: () => context.canPop() ? context.pop() : context.go('/hub'),
                  child: const LuxeGlass(
                    radius: 99,
                    padding: EdgeInsets.all(11),
                    child: Icon(Icons.close_rounded, size: 18, color: Luxe.ink),
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              if (tabs.length > 1)
                SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: tabs.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (BuildContext ctx, int i) {
                      final bool on = i == _tab;
                      return LuxePress(
                        onTap: () => setState(() => _tab = i),
                        semantics: tabs[i],
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 380),
                          curve: Luxe.ease,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(99),
                            gradient: on ? Luxe.goldGrad : null,
                            border: Border.all(color: on ? Colors.transparent : Luxe.line),
                            boxShadow: on
                                ? const <BoxShadow>[BoxShadow(color: Color(0x88D9B872), blurRadius: 22, spreadRadius: -4)]
                                : const <BoxShadow>[],
                          ),
                          child: Text(tabs[i],
                              style: TextStyle(fontSize: 13, color: on ? const Color(0xFF1A1408) : Luxe.mute)),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 14),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text(context.tx('چیزی اینجا نیست', 'Nothing here yet'),
                            style: const TextStyle(color: Luxe.mute)))
                    : GridView.builder(
                        padding: const EdgeInsets.only(bottom: 150, top: 2),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2, mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: 0.86),
                        itemCount: items.length,
                        itemBuilder: (BuildContext ctx, int i) => _Tile(item: items[i], color: w.color),
                      ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Nx2Tab? _dockTab(String k) => switch (k) {
        'games' => Nx2Tab.games,
        'chat' => Nx2Tab.social,
        'tournaments' => Nx2Tab.tournaments,
        'shop' => Nx2Tab.shop,
        'profile' => Nx2Tab.profile,
        'oracle' => Nx2Tab.oracle,
        'rewards' || 'events' => Nx2Tab.rewards,
        _ => null,
      };
}

class _Tile extends ConsumerWidget {
  const _Tile({required this.item, required this.color});
  final LuxeItem item;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String title = context.tx(item.fa, item.en);
    return LuxePress(
      semantics: title,
      onTap: () => luxeOpen(context, ref, item),
      child: LuxeGlass(
        radius: 26,
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: <BoxShadow>[BoxShadow(color: color.withValues(alpha: 0.28), blurRadius: 30, spreadRadius: -8)],
              ),
              child: Image.asset(item.image ?? Luxe.icon(item.icon ?? 'r4c5'),
                  fit: BoxFit.contain, cacheWidth: 260, errorBuilder: (_, __, ___) => const SizedBox()),
            ),
          ),
          const SizedBox(height: 8),
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14.5, color: Luxe.ink, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List<Widget>.generate(4, (int i) {
              final bool on = i < item.rarity;
              return Container(
                width: 5,
                height: 5,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on ? color : const Color(0x33F6E7BD),
                  boxShadow: on ? <BoxShadow>[BoxShadow(color: color, blurRadius: 6)] : null,
                ),
              );
            }),
          ),
        ]),
      ),
    );
  }
}
