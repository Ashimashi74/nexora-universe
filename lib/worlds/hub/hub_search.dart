import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/navigation/nexora_menu.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/nx_theme.dart';
import '../../core/widgets/nx_widgets.dart';
import '../../games/game_registry.dart';

class _SearchHit {
  const _SearchHit({
    required this.titleFa,
    required this.titleEn,
    required this.subtitleFa,
    required this.subtitleEn,
    required this.icon,
    required this.color,
    required this.route,
    this.terms = const <String>[],
  });

  final String titleFa;
  final String titleEn;
  final String subtitleFa;
  final String subtitleEn;
  final IconData icon;
  final Color color;
  final String route;
  final List<String> terms;

  String title(bool isFa) => isFa ? titleFa : titleEn;
  String subtitle(bool isFa) => isFa ? subtitleFa : subtitleEn;

  bool matches(String query) {
    final normalizedQuery = _normalizeSearchText(query);
    if (normalizedQuery.isEmpty) return true;
    final haystack = _normalizeSearchText(<String>[
      titleFa,
      titleEn,
      subtitleFa,
      subtitleEn,
      route,
      ...terms,
    ].join(' '));
    return normalizedQuery.split(' ').every(haystack.contains);
  }

  int score(String query) {
    final q = _normalizeSearchText(query);
    final fa = _normalizeSearchText(titleFa);
    final en = _normalizeSearchText(titleEn);
    if (fa == q || en == q) return 0;
    if (fa.startsWith(q) || en.startsWith(q)) return 1;
    if (fa.contains(q) || en.contains(q)) return 2;
    return 3;
  }
}

String _normalizeSearchText(String value) => value
    .toLowerCase()
    .replaceAll('\u200c', ' ')
    .replaceAll('ي', 'ی')
    .replaceAll('ك', 'ک')
    .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Search over pages, worlds, app features and the full local game catalog.
/// It deliberately does not claim to search remote users or private messages.
class NexoraSearchPage extends StatefulWidget {
  const NexoraSearchPage({super.key});

  @override
  State<NexoraSearchPage> createState() => _NexoraSearchPageState();
}

class _NexoraSearchPageState extends State<NexoraSearchPage> {
  late final TextEditingController _controller;
  late final List<_SearchHit> _index;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _index = _buildIndex();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<_SearchHit> _buildIndex() {
    const routeTerms = <String, List<String>>{
      '/settings': <String>[
        'appearance',
        'theme',
        'light',
        'dark',
        'language',
        'sound',
        'motion',
        'ظاهر',
        'تم',
        'روشن',
        'تیره',
        'زبان',
        'صدا',
        'حرکت'
      ],
      '/account': <String>[
        'identity',
        'sync',
        'security',
        'email',
        'guest',
        'هویت',
        'همگام‌سازی',
        'امنیت',
        'ایمیل',
        'مهمان'
      ],
      '/world/personal_orbit': <String>[
        'profile',
        'avatar',
        'wardrobe',
        'stats',
        'missions',
        'achievements',
        'reward',
        'پروفایل',
        'آواتار',
        'کمد',
        'آمار',
        'ماموریت',
        'دستاورد',
        'جایزه'
      ],
      '/world/orbit_network': <String>[
        'chat',
        'message',
        'group',
        'call',
        'video',
        'voice',
        'چت',
        'پیام',
        'گروه',
        'تماس',
        'ویدئو',
        'صدا'
      ],
      '/world/nova_gallery': <String>[
        'posts',
        'stories',
        'reels',
        'social',
        'پست',
        'استوری',
        'ریلز',
        'اجتماعی'
      ],
      '/tournaments': <String>[
        'competition',
        'bracket',
        'join',
        'create',
        'مسابقه',
        'براکت',
        'پیوستن',
        'ساخت'
      ],
    };
    final hits = <_SearchHit>[
      for (final section in kNexoraMenuSections)
        for (final destination in section.destinations)
          _SearchHit(
            titleFa: destination.titleFa,
            titleEn: destination.titleEn,
            subtitleFa: destination.descriptionFa,
            subtitleEn: destination.descriptionEn,
            icon: destination.icon,
            color: destination.accent ?? NxColors.violet,
            route: destination.path,
            terms: <String>[
              section.titleFa,
              section.titleEn,
              ...destination.aliases,
              ...?routeTerms[destination.path],
            ],
          ),
      for (final game in kGames)
        _SearchHit(
          titleFa: game.nameFa,
          titleEn: game.nameEn,
          subtitleFa: game.taglineFa,
          subtitleEn: game.taglineEn,
          icon: Icons.sports_esports_rounded,
          color: game.accent,
          route: '/arcade/${game.id}',
          terms: <String>[game.id, game.rulesFa, game.rulesEn],
        ),
      const _SearchHit(
        titleFa: 'پاداش روزانه و چالش‌ها',
        titleEn: 'Daily reward & challenges',
        subtitleFa: 'جایزه‌ی قابل‌دریافت و مأموریت‌های فعال',
        subtitleEn: 'Claimable reward and active missions',
        icon: Icons.card_giftcard_rounded,
        color: NxColors.gold,
        route: '/world/personal_orbit',
        terms: <String>['daily', 'challenge', 'روزانه', 'چالش'],
      ),
      const _SearchHit(
        titleFa: 'تورنمنت‌های من',
        titleEn: 'Tournament inbox',
        subtitleFa: 'دعوت‌ها، اعلان‌ها و مسابقه‌های ذخیره‌شده',
        subtitleEn: 'Invites, notices and saved competitions',
        icon: Icons.inbox_rounded,
        color: NxColors.gold,
        route: '/tournaments/inbox',
        terms: <String>['invite', 'invitation', 'دعوت', 'صندوق'],
      ),
      const _SearchHit(
        titleFa: 'ساخت تورنمنت',
        titleEn: 'Create a tournament',
        subtitleFa: 'ساخت مسابقه و تنظیم قوانین و براکت',
        subtitleEn: 'Set up a competition, rules and bracket',
        icon: Icons.add_box_rounded,
        color: NxColors.turquoise,
        route: '/tournaments/new',
        terms: <String>['create', 'new', 'ساخت', 'جدید'],
      ),
    ];
    return hits;
  }

  List<_SearchHit> _results() {
    final hits = _index.where((hit) => hit.matches(_query)).toList();
    hits.sort((a, b) => a.score(_query).compareTo(b.score(_query)));
    return hits;
  }

  @override
  Widget build(BuildContext context) {
    final isFa = context.isFa;
    final visual = NxThemeColors.of(context);
    final results = _results();
    return NxWorldScaffold(
      title: context.tx('جستجوی سراسری', 'Global search'),
      palette: WorldPalette.hub,
      showWallet: false,
      showSearchButton: false,
      body: Padding(
        padding: const EdgeInsets.only(top: kToolbarHeight),
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  NxSpace.md, NxSpace.sm, NxSpace.md, 6),
              child: TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: context.tx('دنیا، بازی یا قابلیت را جستجو کن',
                      'Search worlds, games or features'),
                  prefixIcon: Icon(Icons.search_rounded, color: visual.accent),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: context.tx('پاک کردن', 'Clear search'),
                          onPressed: () {
                            _controller.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.clear_rounded),
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(18, 2, 18, 8),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  context.tx(
                    'صفحات، بازی‌ها و قابلیت‌های موجود روی این دستگاه',
                    'Pages, games and features available in this app',
                  ),
                  style: TextStyle(color: visual.muted, fontSize: 12),
                ),
              ),
            ),
            Expanded(
              child: results.isEmpty
                  ? _NoSearchResults(query: _query)
                  : ListView.separated(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsetsDirectional.fromSTEB(
                          NxSpace.md, 4, NxSpace.md, NxSpace.lg),
                      itemCount: results.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 7),
                      itemBuilder: (context, index) {
                        final hit = results[index];
                        return Material(
                          color: visual.surface,
                          borderRadius: BorderRadius.circular(NxRadius.md),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(NxRadius.md),
                              side: BorderSide(
                                  color: visual.border.withValues(alpha: .45)),
                            ),
                            leading: CircleAvatar(
                              backgroundColor: hit.color.withValues(alpha: .14),
                              child: Icon(hit.icon, color: hit.color),
                            ),
                            title: Text(
                              hit.title(isFa),
                              style: TextStyle(
                                  color: visual.text,
                                  fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text(
                              hit.subtitle(isFa),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  TextStyle(color: visual.muted, fontSize: 12),
                            ),
                            trailing: Icon(Icons.arrow_forward_ios_rounded,
                                size: 15, color: visual.muted),
                            onTap: () => context.go(hit.route),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoSearchResults extends StatelessWidget {
  const _NoSearchResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final visual = NxThemeColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(NxSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.search_off_rounded, color: visual.muted, size: 44),
            const SizedBox(height: NxSpace.sm),
            Text(context.tx('نتیجه‌ای پیدا نشد', 'No results found'),
                style: TextStyle(
                    color: visual.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 16)),
            const SizedBox(height: NxSpace.xs),
            Text(
              context.tx(
                '«$query» را در قابلیت‌های نصب‌شده پیدا نکردم.',
                '“$query” is not in the installed app index.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(color: visual.muted, fontSize: 12),
            ),
            const SizedBox(height: NxSpace.md),
            OutlinedButton.icon(
              onPressed: () => context
                  .go('/oracle?q=${Uri.encodeQueryComponent(query.trim())}'),
              icon: const Icon(Icons.blur_circular_rounded),
              label: Text(context.tx('پرسیدن از ORACLE', 'Ask ORACLE')),
            ),
          ],
        ),
      ),
    );
  }
}
