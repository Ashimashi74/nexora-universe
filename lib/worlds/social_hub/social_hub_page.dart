import 'package:flutter/material.dart';

import '../../core/settings/app_settings.dart';
import '../../core/ui2/luxe.dart';
import '../../core/ui2/nx2_widgets.dart';
import '../nova_gallery/nova_gallery_page.dart';
import '../orbit_network/orbit_network_page.dart';
import '../social_station/social_station_page.dart';

/// CHAT + MEDIA: one social hub with tabs — Feed & stories (Nova Gallery), Messages (Orbit Network),
/// Friends (Social Station). Each tab is the existing Supabase-backed screen.
///
/// The world switcher is the home page's own in-page tab language (the gold pill row of
/// [LuxeStationPage]) drawn with the shared Luxe primitives, so this hub is not a third
/// navigation style sitting between the hosted world's section bar and the app dock.
class SocialHubPage extends StatefulWidget {
  const SocialHubPage({super.key, this.initial = 0});
  final int initial;

  @override
  State<SocialHubPage> createState() => _SocialHubPageState();
}

class _SocialHubPageState extends State<SocialHubPage> {
  late int _tab = widget.initial;
  final Set<int> _built = <int>{};

  @override
  Widget build(BuildContext context) {
    _built.add(_tab);
    const List<Widget> pages = <Widget>[NovaGalleryPage(), OrbitNetworkPage(), SocialStationPage()];
    final List<(IconData, String)> tabs = <(IconData, String)>[
      (Icons.dynamic_feed_rounded, context.tx('پست و استوری', 'Feed & stories')),
      (Icons.forum_rounded, context.tx('پیام‌ها', 'Messages')),
      (Icons.group_rounded, context.tx('دوستان', 'Friends')),
    ];
    return Scaffold(
      backgroundColor: Luxe.bg,
      body: IndexedStack(index: _tab, children: <Widget>[
        for (int i = 0; i < pages.length; i++) _built.contains(i) ? pages[i] : const SizedBox.shrink(),
      ]),
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(LuxeSpace.md, LuxeSpace.sm, LuxeSpace.md, 0),
          child: Row(children: <Widget>[
            for (int i = 0; i < tabs.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: LuxeSpace.sm),
              Expanded(child: _worldPill(context, i, tabs[i], onSelect: () => setState(() => _tab = i))),
            ],
          ]),
        ),
        const Nx2Dock(current: Nx2Tab.social),
      ]),
    );
  }

  /// One world of the hub, as a Station Luxe pill: gold gradient + glow when selected,
  /// hairline glass when not — the same chip [LuxeStationPage] uses for its own tabs.
  Widget _worldPill(BuildContext context, int i, (IconData, String) tab, {required VoidCallback onSelect}) {
    final bool on = i == _tab;
    final String label = tab.$2;
    return LuxePress(
      onTap: onSelect,
      semantics: label,
      child: AnimatedContainer(
        duration: Luxe.reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 380),
        curve: Luxe.ease,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(LuxeRadius.pill),
          gradient: on ? Luxe.goldGrad : null,
          color: on ? null : const Color(0x0FFFFFFF),
          border: Border.all(color: on ? Colors.transparent : Luxe.line),
          boxShadow: on
              ? const <BoxShadow>[BoxShadow(color: Color(0x88D9B872), blurRadius: 22, spreadRadius: -4)]
              : const <BoxShadow>[],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
          Icon(tab.$1, size: 16, color: on ? const Color(0xFF1A1408) : Luxe.mute),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: on ? const Color(0xFF1A1408) : Luxe.mute,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
