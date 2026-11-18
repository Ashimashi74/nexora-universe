import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../profile/profile_service.dart';
import '../settings/app_settings.dart';
import '../theme/nx_theme.dart';
import '../../worlds/world_registry.dart';

class NexoraMenuDestination {
  const NexoraMenuDestination({
    required this.path,
    required this.titleFa,
    required this.titleEn,
    required this.descriptionFa,
    required this.descriptionEn,
    required this.icon,
    this.aliases = const [],
    this.accent,
  });

  factory NexoraMenuDestination.world(
    String id, {
    String? path,
    List<String> aliases = const [],
  }) {
    final world = worldById(id);
    if (world == null) {
      throw ArgumentError.value(id, 'id', 'Unknown NEXORA world');
    }
    return NexoraMenuDestination(
      path: path ?? '/world/${world.id}',
      titleFa: world.nameFa,
      titleEn: world.name,
      descriptionFa: world.taglineFa,
      descriptionEn: world.taglineEn,
      icon: world.icon,
      aliases: aliases,
      accent: world.palette.primary,
    );
  }

  final String path;
  final String titleFa;
  final String titleEn;
  final String descriptionFa;
  final String descriptionEn;
  final IconData icon;
  final List<String> aliases;
  final Color? accent;

  bool matches(String location) =>
      location == path ||
      location.startsWith('$path/') ||
      aliases
          .any((alias) => location == alias || location.startsWith('$alias/'));
}

class NexoraMenuSection {
  const NexoraMenuSection({
    required this.titleFa,
    required this.titleEn,
    required this.destinations,
  });

  final String titleFa;
  final String titleEn;
  final List<NexoraMenuDestination> destinations;
}

/// One source of truth for destinations exposed by the app-wide menu.
final List<NexoraMenuSection> kNexoraMenuSections = <NexoraMenuSection>[
  NexoraMenuSection(
    titleFa: 'شروع',
    titleEn: 'Start here',
    destinations: <NexoraMenuDestination>[
      const NexoraMenuDestination(
        path: '/hub',
        titleFa: 'هاب نکسورا',
        titleEn: 'NEXORA HUB',
        descriptionFa: 'بازگشت به مرکز جهان‌ها',
        descriptionEn: 'Return to the worlds hub',
        icon: Icons.home_rounded,
      ),
    ],
  ),
  NexoraMenuSection(
    titleFa: 'بازی و رقابت',
    titleEn: 'Play & compete',
    destinations: <NexoraMenuDestination>[
      NexoraMenuDestination.world('nexora_arcade',
          aliases: <String>['/arcade']),
      const NexoraMenuDestination(
        path: '/tournaments',
        titleFa: 'مسابقات',
        titleEn: 'Tournaments',
        descriptionFa: 'ثبت‌نام، براکت و نتیجه‌ها',
        descriptionEn: 'Registration, brackets & results',
        icon: Icons.emoji_events_rounded,
        aliases: <String>['/t'],
        accent: NxColors.gold,
      ),
      const NexoraMenuDestination(
        path: '/leaderboard',
        titleFa: 'جدول امتیازها',
        titleEn: 'Leaderboards',
        descriptionFa: 'رکوردها و رتبه‌بندی بازی‌ها',
        descriptionEn: 'Game records and rankings',
        icon: Icons.leaderboard_rounded,
      ),
    ],
  ),
  NexoraMenuSection(
    titleFa: 'ارتباط و اجتماع',
    titleEn: 'Connect & community',
    destinations: <NexoraMenuDestination>[
      NexoraMenuDestination.world('nova_gallery'),
      NexoraMenuDestination.world('orbit_network', aliases: <String>['/call']),
      NexoraMenuDestination.world('social_station'),
    ],
  ),
  NexoraMenuSection(
    titleFa: 'هویت و فروشگاه',
    titleEn: 'Identity & store',
    destinations: <NexoraMenuDestination>[
      NexoraMenuDestination.world('personal_orbit'),
      NexoraMenuDestination.world('nexora_exchange'),
      const NexoraMenuDestination(
        path: '/account',
        titleFa: 'حساب کاربری',
        titleEn: 'Account',
        descriptionFa: 'هویت، همگام‌سازی و امنیت حساب',
        descriptionEn: 'Identity, sync and account security',
        icon: Icons.manage_accounts_rounded,
      ),
    ],
  ),
  NexoraMenuSection(
    titleFa: 'راهنما و تنظیمات',
    titleEn: 'Help & settings',
    destinations: <NexoraMenuDestination>[
      NexoraMenuDestination.world(
        'oracle_core',
        path: '/oracle',
        aliases: <String>['/world/oracle_core'],
      ),
      const NexoraMenuDestination(
        path: '/settings',
        titleFa: 'تنظیمات',
        titleEn: 'Settings',
        descriptionFa: 'زبان، ظاهر، صدا و دسترس‌پذیری',
        descriptionEn: 'Language, appearance, audio and accessibility',
        icon: Icons.settings_rounded,
      ),
      const NexoraMenuDestination(
        path: '/journey',
        titleFa: 'بازپخش سفر آغازین',
        titleEn: 'Replay the first journey',
        descriptionFa: 'مرور دوباره‌ی راهنمای شروع',
        descriptionEn: 'Review the getting-started journey',
        icon: Icons.movie_filter_rounded,
      ),
    ],
  ),
];

Future<void> showNexoraMenu(BuildContext context) {
  final router = GoRouter.of(context);
  final currentPath = router.routeInformationProvider.value.uri.path;
  final visual = NxThemeColors.of(context);
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: visual.background,
    constraints:
        BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .88),
    builder: (sheetContext) => _NexoraMenuSheet(
      router: router,
      currentPath: currentPath,
    ),
  );
}

class _NexoraMenuSheet extends ConsumerWidget {
  const _NexoraMenuSheet({required this.router, required this.currentPath});

  final GoRouter router;
  final String currentPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final visual = NxThemeColors.of(context);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: <Color>[visual.accent, visual.accentSecondary],
                    ),
                  ),
                  child: Icon(Icons.blur_circular_rounded,
                      color: visual.background, size: 25),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('NEXORA',
                          style: TextStyle(
                            color: visual.text,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.4,
                          )),
                      Text(context.tx('منوی جهان', 'Universe menu'),
                          style: TextStyle(color: visual.muted, fontSize: 12)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: context.tx('بستن منو', 'Close menu'),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _ExplorerSummary(
              username:
                  profile.username.isEmpty ? 'Explorer' : profile.username,
              explorerId: profile.explorerId,
              level: profile.level,
              coins: profile.coins,
              onTap: () => _navigate(context, '/world/personal_orbit'),
            ),
            const SizedBox(height: 18),
            for (final section in kNexoraMenuSections) ...<Widget>[
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 4, bottom: 7),
                child: Text(
                  context.tx(section.titleFa, section.titleEn),
                  style: TextStyle(
                    color: visual.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .3,
                  ),
                ),
              ),
              for (final destination in section.destinations)
                _MenuDestinationTile(
                  destination: destination,
                  selected: destination.matches(currentPath),
                  onTap: () => _navigate(context, destination.path),
                ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }

  void _navigate(BuildContext context, String path) {
    Navigator.of(context).pop();
    router.go(path);
  }
}

class _ExplorerSummary extends StatelessWidget {
  const _ExplorerSummary({
    required this.username,
    required this.explorerId,
    required this.level,
    required this.coins,
    required this.onTap,
  });

  final String username;
  final String explorerId;
  final int level;
  final int coins;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visual = NxThemeColors.of(context);
    return Material(
      color: visual.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                backgroundColor: visual.accent.withValues(alpha: .16),
                child: Icon(Icons.person_rounded, color: visual.accent),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: visual.text, fontWeight: FontWeight.w800)),
                    Text(explorerId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: visual.muted, fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(context.tx('سطح $level', 'Level $level'),
                      style: TextStyle(
                          color: visual.text,
                          fontWeight: FontWeight.w800,
                          fontSize: 12)),
                  Text('$coins ${context.tx('سکه', 'coins')}',
                      style: TextStyle(color: visual.muted, fontSize: 11)),
                ],
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, color: visual.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuDestinationTile extends StatelessWidget {
  const _MenuDestinationTile({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final NexoraMenuDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visual = NxThemeColors.of(context);
    final color = destination.accent ?? visual.accent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? color.withValues(alpha: .13) : visual.surface,
        borderRadius: BorderRadius.circular(15),
        child: ListTile(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(destination.icon, color: color, size: 21),
          ),
          title: Text(
            context.tx(destination.titleFa, destination.titleEn),
            style: TextStyle(
              color: visual.text,
              fontSize: 14,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
          subtitle: Text(
            context.tx(destination.descriptionFa, destination.descriptionEn),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: visual.muted, fontSize: 11),
          ),
          trailing: selected
              ? Icon(Icons.check_circle_rounded, color: color, size: 19)
              : Icon(Icons.chevron_right_rounded, color: visual.muted),
          onTap: onTap,
        ),
      ),
    );
  }
}
