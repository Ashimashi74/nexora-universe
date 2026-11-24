import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/online/online_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/nx_theme.dart';
import 'admin_access.dart';

import '../../core/ui2/anix_kit.dart';
import '../../core/ui2/luxe.dart';

/// Admin panel. Tabs appear only for the permissions the signed-in admin holds; the server checks every call again
/// (auth project: users/bans, grants, admins, announcements, moderation, ORACLE · games project: rooms, tournaments)
/// and writes an audit entry.
class AdminPage extends ConsumerStatefulWidget {
  const AdminPage({super.key});

  @override
  ConsumerState<AdminPage> createState() => _AdminPageState();
}

class _Tab {
  const _Tab(this.id, this.fa, this.en, this.icon);
  final String id, fa, en;
  final IconData icon;
}

class _AdminPageState extends ConsumerState<AdminPage> {
  @override
  void initState() {
    super.initState();
    unawaited(ref.read(adminAccessProvider).refresh());
  }

  @override
  Widget build(BuildContext context) {
    final AdminAccess a = ref.watch(adminAccessProvider);
    final List<_Tab> tabs = <_Tab>[
      const _Tab('home', 'خلاصه', 'Overview', Icons.dashboard_rounded),
      if (a.can(AdminPerm.users) || a.can(AdminPerm.currency))
        const _Tab('users', 'کاربران', 'Users', Icons.people_alt_rounded),
      if (a.can(AdminPerm.admins)) const _Tab('admins', 'ادمین‌ها', 'Admins', Icons.admin_panel_settings_rounded),
      if (a.can(AdminPerm.tournaments)) const _Tab('tournaments', 'تورنمنت', 'Tournaments', Icons.emoji_events_rounded),
      if (a.can(AdminPerm.moderation)) const _Tab('moderation', 'نظارت', 'Moderation', Icons.shield_rounded),
      if (a.can(AdminPerm.moderation)) const _Tab('reports', 'گزارش‌ها', 'Reports', Icons.flag_rounded),
      if (a.can(AdminPerm.users)) const _Tab('banned', 'مسدودها', 'Banned', Icons.block_rounded),
      if (a.can(AdminPerm.shop)) const _Tab('shop', 'فروشگاه', 'Shop & prices', Icons.storefront_rounded),
      if (a.can(AdminPerm.rooms)) const _Tab('rooms', 'اتاق‌ها', 'Rooms', Icons.meeting_room_rounded),
      if (a.can(AdminPerm.rooms)) const _Tab('matches', 'بازی‌های زنده', 'Live matches', Icons.sports_esports_rounded),
      if (a.can(AdminPerm.announcements)) const _Tab('announcements', 'اطلاعیه', 'Announcements', Icons.campaign_rounded),
      if (a.can(AdminPerm.oracle)) const _Tab('oracle', 'اوراکل', 'ORACLE', Icons.psychology_alt_rounded),
      if (a.can(AdminPerm.admins)) const _Tab('audit', 'گزارش', 'Audit log', Icons.receipt_long_rounded),
    ];
    if (!a.loaded) {
      return const Scaffold(backgroundColor: NxColors.luxeBg, body: Center(child: CircularProgressIndicator()));
    }
    if (!a.isAdmin) {
      return Scaffold(
        backgroundColor: NxColors.luxeBg,
        appBar: AppBar(title: Text(context.tx('پنل مدیریت', 'Admin panel'))),
        body: Center(child: Text(context.tx('این بخش فقط برای ادمین‌هاست.', 'Admins only.'))),
      );
    }
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        backgroundColor: NxColors.luxeBg,
        appBar: AppBar(
          backgroundColor: NxColors.panel,
          title: Text(a.owner ? context.tx('پنل مدیر اصلی', 'Main admin panel') : context.tx('پنل مدیریت', 'Admin panel')),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: NxColors.gold,
            tabs: <Widget>[
              for (final _Tab t in tabs) Tab(icon: Icon(t.icon, size: 20), text: context.tx(t.fa, t.en)),
            ],
          ),
        ),
        body: TabBarView(children: <Widget>[
          for (final _Tab t in tabs)
            switch (t.id) {
              'home' => const _Overview(),
              'users' => const _UsersTab(),
              'admins' => const _AdminsTab(),
              'tournaments' => const _TournamentsTab(),
              'moderation' => const _ModerationTab(),
              'rooms' => const _RoomsTab(),
              'banned' => const _BannedTab(),
              'shop' => const _ShopTab(),
              'reports' => const _ReportsTab(),
              'matches' => const _MatchesTab(),
              'announcements' => const _AnnouncementsTab(),
              'oracle' => const _OracleTab(),
              _ => const _AuditTab(),
            },
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ helpers
AdminApi _api(WidgetRef ref) => AdminApi(ref.read(onlineProvider));

Future<void> _toast(BuildContext context, Map<String, dynamic> r, {String? okFa, String? okEn}) async {
  if (!context.mounted) return;
  final bool fa = context.isFa;
  luxeToast(
      context,
      r['ok'] == true ? (fa ? (okFa ?? 'انجام شد ✓') : (okEn ?? 'Done ✓')) : adminErrorText(r['error'] as String?, fa),
  );
}

Future<String?> _ask(BuildContext context, String title, {String hint = '', String initial = ''}) async {
  final TextEditingController c = TextEditingController(text: initial);
  final String? r = await showDialog<String>(
    context: context,
    builder: (BuildContext ctx) => AnixDialog(
      title: Text(title),
      content: TextField(controller: c, autofocus: true, decoration: InputDecoration(hintText: hint)),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tx('انصراف', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(ctx.tx('تأیید', 'OK'))),
      ],
    ),
  );
  c.dispose();
  return r;
}

Widget _card({required Widget child}) => Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NxColors.goldLine),
      ),
      child: child,
    );

String _shortTime(Object? iso) {
  final DateTime? t = DateTime.tryParse('${iso ?? ''}')?.toLocal();
  if (t == null) return '';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}/${two(t.month)}/${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

/// Loads a JSON result once and shows a list; pull to refresh.
class _Loader extends StatefulWidget {
  const _Loader({super.key, required this.load, required this.build});
  final Future<Map<String, dynamic>> Function() load;
  final Widget Function(BuildContext context, Map<String, dynamic> data, VoidCallback reload) build;

  @override
  State<_Loader> createState() => _LoaderState();
}

class _LoaderState extends State<_Loader> {
  Map<String, dynamic>? _d;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    widget.load().then((Map<String, dynamic> d) {
      if (mounted) setState(() => _d = d);
    });
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic>? d = _d;
    if (d == null) return const Center(child: CircularProgressIndicator());
    if (d['ok'] != true) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        const Icon(Icons.cloud_off_rounded, color: NxColors.gold, size: 36),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(adminErrorText(d['error'] as String?, context.isFa), textAlign: TextAlign.center),
        ),
        TextButton(onPressed: _reload, child: Text(context.tx('دوباره', 'Retry'))),
      ]));
    }
    return RefreshIndicator(onRefresh: () async => _reload(), child: widget.build(context, d, _reload));
  }
}

// ------------------------------------------------------------------ overview
class _Overview extends ConsumerWidget {
  const _Overview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AdminAccess a = ref.watch(adminAccessProvider);
    return _Loader(
      load: () => _api(ref).stats(),
      build: (BuildContext context, Map<String, dynamic> d, VoidCallback reload) {
        Widget stat(String fa, String en, Object? v, IconData icon) => _card(
                child: Row(children: <Widget>[
              Icon(icon, color: NxColors.gold),
              const SizedBox(width: 12),
              Expanded(child: Text(context.tx(fa, en))),
              Text('${v ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            ]));
        return ListView(padding: const EdgeInsets.symmetric(vertical: 10), children: <Widget>[
          _card(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(a.owner ? context.tx('تو مدیر اصلی هستی — همه‌ی دسترسی‌ها', 'You are the main admin — every permission') : context.tx('دسترسی‌های تو', 'Your permissions'),
                style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
              for (final String p in AdminPerm.all)
                if (a.can(p)) Chip(label: Text(AdminPerm.label(p, context.isFa)), visualDensity: VisualDensity.compact),
            ]),
          ])),
          stat('کاربران', 'Users', d['users'], Icons.people_rounded),
          stat('مهمان‌ها', 'Guests', d['guests'], Icons.person_outline_rounded),
          stat('مسدود', 'Banned', d['banned'], Icons.block_rounded),
          stat('مدیران تورنمنت', 'Tournament managers', d['organizers'], Icons.emoji_events_rounded),
        ]);
      },
    );
  }
}

// ------------------------------------------------------------------ users
class _UsersTab extends ConsumerStatefulWidget {
  const _UsersTab();

  @override
  ConsumerState<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends ConsumerState<_UsersTab> {
  final TextEditingController _q = TextEditingController();
  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  bool _loading = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    unawaited(_search());
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _loading = true);
    final Map<String, dynamic> r = await _api(ref).users(_q.text.trim());
    if (!mounted) return;
    setState(() {
      _loading = false;
      _err = r['ok'] == true ? null : adminErrorText(r['error'] as String?, context.isFa);
      _rows = ((r['users'] as List<dynamic>?) ?? const <dynamic>[]).map((dynamic e) => Map<String, dynamic>.from(e as Map)).toList();
    });
  }

  Future<void> _grant(Map<String, dynamic> u) async {
    final TextEditingController coins = TextEditingController(text: '0');
    final TextEditingController gems = TextEditingController(text: '0');
    final TextEditingController reason = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AnixDialog(
        title: Text(ctx.tx('اهدا به ${u['username'] ?? ''}', 'Grant to ${u['username'] ?? ''}')),
        content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          TextField(controller: coins, keyboardType: const TextInputType.numberWithOptions(signed: true),
              decoration: InputDecoration(labelText: ctx.tx('سکه (منفی = کسر)', 'Coins (negative = take)'))),
          TextField(controller: gems, keyboardType: const TextInputType.numberWithOptions(signed: true),
              decoration: InputDecoration(labelText: ctx.tx('جم (منفی = کسر)', 'Gems (negative = take)'))),
          TextField(controller: reason, decoration: InputDecoration(labelText: ctx.tx('دلیل', 'Reason'))),
        ]),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tx('انصراف', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tx('ثبت', 'Grant'))),
        ],
      ),
    );
    if (ok == true) {
      final Map<String, dynamic> r = await _api(ref).grant(
          '${u['id']}', int.tryParse(coins.text.trim()) ?? 0, int.tryParse(gems.text.trim()) ?? 0, reason.text.trim());
      if (mounted) await _toast(context, r);
      unawaited(_search());
    }
    coins.dispose();
    gems.dispose();
    reason.dispose();
  }

  Future<void> _mute(Map<String, dynamic> u) async {
    final bool muted = u['muted_until'] != null;
    int minutes = 0;
    String? reason;
    if (!muted) {
      final int? m = await showDialog<int>(
        context: context,
        builder: (BuildContext ctx) => SimpleDialog(
          title: Text(ctx.tx('سکوت چت برای ${u['username'] ?? ''}', 'Mute ${u['username'] ?? ''}')),
          children: <Widget>[
            for (final (int v, String fa, String en) in const <(int, String, String)>[
              (15, '۱۵ دقیقه', '15 minutes'), (60, '۱ ساعت', '1 hour'), (1440, '۱ روز', '1 day'),
              (10080, '۱ هفته', '1 week'), (525600, 'دائمی (۱ سال)', 'Permanent (1 year)'),
            ])
              SimpleDialogOption(onPressed: () => Navigator.pop(ctx, v), child: Text(ctx.tx(fa, en))),
          ],
        ),
      );
      if (m == null || !mounted) return;
      minutes = m;
      reason = await _ask(context, context.tx('دلیل سکوت', 'Mute reason'));
      if (reason == null) return;
    }
    final Map<String, dynamic> r = await _api(ref).mute('${u['id']}', minutes, reason);
    if (mounted) await _toast(context, r);
    unawaited(_search());
  }

  Future<void> _item(Map<String, dynamic> u) async {
    final TextEditingController item = TextEditingController();
    bool grant = true;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter set) => AnixDialog(
          title: Text(ctx.tx('آیتم / تیم برای ${u['username'] ?? ''}', 'Item / team for ${u['username'] ?? ''}')),
          content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            TextField(
                controller: item,
                decoration: InputDecoration(
                    labelText: ctx.tx('شناسه‌ی آیتم یا تیم', 'Item or team id'), hintText: 'lux0 · club12 · nx_green')),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: <ButtonSegment<bool>>[
                ButtonSegment<bool>(value: true, label: Text(ctx.tx('اهدا', 'Give'))),
                ButtonSegment<bool>(value: false, label: Text(ctx.tx('پس‌گرفتن', 'Take'))),
              ],
              selected: <bool>{grant},
              onSelectionChanged: (Set<bool> v) => set(() => grant = v.first),
            ),
          ]),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tx('انصراف', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tx('ثبت', 'Apply'))),
          ],
        ),
      ),
    );
    if (ok == true) {
      final Map<String, dynamic> r = await _api(ref).grantItem('${u['id']}', item.text.trim(), grant, null);
      if (mounted) await _toast(context, r);
    }
    item.dispose();
  }

  Future<void> _rename(Map<String, dynamic> u) async {
    final String? n =
        await _ask(context, context.tx('نام کاربری جدید', 'New username'), initial: '${u['username'] ?? ''}');
    if (n == null || n.trim().isEmpty) return;
    final Map<String, dynamic> r = await _api(ref).rename('${u['id']}', n.trim(), null);
    if (mounted) await _toast(context, r);
    unawaited(_search());
  }

  Future<void> _resetPassword(Map<String, dynamic> u) async {
    final String? t = await _ask(context, context.tx('رمز موقت (حداقل ۸ نویسه)', 'Temporary password (8+ chars)'),
        hint: context.tx('بازیکن بعد از ورود باید عوضش کند', 'The player must change it after signing in'));
    if (t == null || t.isEmpty) return;
    final Map<String, dynamic> r = await _api(ref).resetPassword('${u['id']}', t);
    if (mounted) await _toast(context, r, okFa: 'رمز موقت ثبت شد؛ همه‌ی نشست‌ها بسته شد', okEn: 'Temporary password set; sessions closed');
  }

  Future<void> _ban(Map<String, dynamic> u) async {
    final bool banned = u['banned'] == true;
    String? reason;
    if (!banned) {
      reason = await _ask(context, context.tx('دلیل مسدودسازی', 'Ban reason'));
      if (reason == null) return;
    }
    final Map<String, dynamic> r = await _api(ref).ban('${u['id']}', !banned, reason);
    if (mounted) await _toast(context, r);
    unawaited(_search());
  }

  @override
  Widget build(BuildContext context) {
    final AdminAccess a = ref.watch(adminAccessProvider);
    return Column(children: <Widget>[
      Padding(
        padding: const EdgeInsets.all(12),
        child: TextField(
          controller: _q,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: context.tx('نام کاربری، ایمیل یا شناسه', 'Username, email or id'),
            suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward_rounded), onPressed: _search),
          ),
        ),
      ),
      if (_loading) const LinearProgressIndicator(),
      if (_err != null) Padding(padding: const EdgeInsets.all(8), child: Text(_err!)),
      Expanded(
        child: ListView.builder(
          itemCount: _rows.length,
          itemBuilder: (BuildContext context, int i) {
            final Map<String, dynamic> u = _rows[i];
            final bool banned = u['banned'] == true;
            return _card(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Row(children: <Widget>[
                Icon(banned ? Icons.block_rounded : Icons.person_rounded, color: banned ? NxColors.danger : NxColors.champagne),
                const SizedBox(width: 8),
                Expanded(
                    child: Text('${u['username'] ?? 'Pilot'}', style: const TextStyle(fontWeight: FontWeight.w900))),
                Text('${u['role']}', style: const TextStyle(color: NxColors.gold, fontSize: 12)),
              ]),
              const SizedBox(height: 4),
              Text(
                  '${u['guest'] == true ? context.tx('مهمان', 'guest') : (u['email'] ?? '')} · Lv ${u['level']} · '
                  '🪙 ${u['coins']} · 💎 ${u['gems']}',
                  style: const TextStyle(color: NxColors.textDim, fontSize: 12)),
              if (banned && (u['ban_reason'] ?? '').toString().isNotEmpty)
                Text('⛔ ${u['ban_reason']}', style: const TextStyle(color: NxColors.danger, fontSize: 12)),
              if (u['muted_until'] != null)
                Text('🔇 ${context.tx('ساکت تا', 'muted until')} ${_shortTime(u['muted_until'])} ${u['mute_reason'] ?? ''}',
                    style: const TextStyle(color: NxColors.gold, fontSize: 12)),
              Wrap(spacing: 6, children: <Widget>[
                if (a.can(AdminPerm.users))
                  TextButton.icon(
                      onPressed: () async {
                        await showPlayerSheet(context, ref, '${u['id']}');
                        unawaited(_search());
                      },
                      icon: const Icon(Icons.manage_accounts_rounded, size: 18),
                      label: Text(context.tx('پروفایل', 'Profile'))),
                if (a.can(AdminPerm.currency))
                  TextButton.icon(
                      onPressed: () => _grant(u),
                      icon: const Icon(Icons.card_giftcard_rounded, size: 18),
                      label: Text(context.tx('اهدا', 'Grant'))),
                if (a.can(AdminPerm.users) && u['role'] != 'owner')
                  TextButton.icon(
                      onPressed: () => _ban(u),
                      icon: Icon(banned ? Icons.lock_open_rounded : Icons.block_rounded, size: 18),
                      label: Text(banned ? context.tx('رفع مسدودی', 'Unban') : context.tx('مسدود', 'Ban'))),
                if (a.can(AdminPerm.admins) && u['role'] != 'owner' && u['guest'] != true)
                  TextButton.icon(
                      onPressed: () => showAdminEditor(context, ref, u),
                      icon: const Icon(Icons.admin_panel_settings_rounded, size: 18),
                      label: Text(context.tx('نقش', 'Role'))),
                if (u['role'] != 'owner')
                  PopupMenuButton<String>(
                    tooltip: context.tx('بیشتر', 'More'),
                    icon: const Icon(Icons.more_horiz_rounded),
                    onSelected: (String v) => switch (v) {
                      'mute' => _mute(u),
                      'item' => _item(u),
                      'rename' => _rename(u),
                      'password' => _resetPassword(u),
                      _ => null,
                    },
                    itemBuilder: (BuildContext c) => <PopupMenuEntry<String>>[
                      if (a.can(AdminPerm.users))
                        PopupMenuItem<String>(
                            value: 'mute',
                            child: Text(u['muted_until'] != null ? c.tx('رفع سکوت', 'Unmute') : c.tx('سکوت چت', 'Mute chat'))),
                      if (a.can(AdminPerm.currency))
                        PopupMenuItem<String>(value: 'item', child: Text(c.tx('اهدای آیتم / تیم', 'Give item / team'))),
                      if (a.can(AdminPerm.users))
                        PopupMenuItem<String>(value: 'rename', child: Text(c.tx('تغییر اجباری نام', 'Force rename'))),
                      if (a.can(AdminPerm.users) && u['guest'] != true)
                        PopupMenuItem<String>(value: 'password', child: Text(c.tx('رمز موقت', 'Reset password'))),
                    ],
                  ),
              ]),
            ]));
          },
        ),
      ),
    ]);
  }
}

/// Edit one admin's permissions (+ tournament manager gem options).
Future<void> showAdminEditor(BuildContext context, WidgetRef ref, Map<String, dynamic> u, {VoidCallback? done}) async {
  final AdminAccess me = ref.read(adminAccessProvider);
  final Set<String> perms = ((u['perms'] as List<dynamic>?) ?? const <dynamic>[]).map((dynamic e) => '$e').toSet();
  bool unlimited = u['unlimited_gems'] == true || u['unlimited'] == true;
  final TextEditingController budget = TextEditingController(text: '${u['gem_budget'] ?? 0}');
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => StatefulBuilder(
      builder: (BuildContext ctx, StateSetter set) => AnixDialog(
        title: Text(ctx.tx('دسترسی ${u['username'] ?? ''}', 'Access · ${u['username'] ?? ''}')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            // Role presets (admin / moderator / player) fill the permission boxes; the owner can still fine-tune.
            Wrap(spacing: 6, children: <Widget>[
              for (final MapEntry<String, List<String>> e in kAdminRolePresets.entries)
                ActionChip(
                  label: Text(switch (e.key) {
                    'admin' => ctx.tx('ادمین', 'Admin'),
                    'mod' => ctx.tx('ناظر', 'Moderator'),
                    _ => ctx.tx('بازیکن', 'Player'),
                  }),
                  onPressed: () => set(() {
                    perms
                      ..clear()
                      ..addAll(e.value);
                  }),
                ),
            ]),
            for (final String p in AdminPerm.all)
              AnixCheckboxTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: perms.contains(p),
                title: Text(AdminPerm.label(p, ctx.isFa)),
                onChanged: (p == AdminPerm.admins && !me.owner)
                    ? null
                    : (bool? v) => set(() => v == true ? perms.add(p) : perms.remove(p)),
              ),
            const Divider(),
            Text(ctx.tx('جایزه‌ی جم در تورنمنت‌هایش', 'Gem prizes in their tournaments'),
                style: const TextStyle(fontWeight: FontWeight.w800)),
            AnixSwitchTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: unlimited,
              title: Text(ctx.tx('نامحدود (فقط مدیر اصلی)', 'Unlimited (main admin only)')),
              onChanged: me.owner ? (bool v) => set(() => unlimited = v) : null,
            ),
            if (!unlimited)
              TextField(
                controller: budget,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: ctx.tx('سقف جم', 'Gem budget')),
              ),
          ]),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tx('انصراف', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tx('ذخیره', 'Save'))),
        ],
      ),
    ),
  );
  if (ok == true) {
    final int b = int.tryParse(budget.text.trim()) ?? 0;
    final Map<String, dynamic> r = await _api(ref).setPerms('${u['id']}', perms.toList(),
        unlimitedGems: unlimited, gemBudget: unlimited ? null : b);
    if (r['ok'] == true && perms.contains(AdminPerm.tournaments) == false && (b > 0 || unlimited)) {
      // a manager without the tournaments permission: organizer role with the gem option
      await _api(ref).setManager('${u['id']}', true, unlimited: unlimited, gemBudget: b);
    }
    if (context.mounted) await _toast(context, r);
    done?.call();
  }
  budget.dispose();
}

// ------------------------------------------------------------------ admins
class _AdminsTab extends ConsumerWidget {
  const _AdminsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) => _Loader(
        load: () => _api(ref).admins(),
        build: (BuildContext context, Map<String, dynamic> d, VoidCallback reload) {
          final List<dynamic> rows = (d['admins'] as List<dynamic>?) ?? const <dynamic>[];
          return ListView(padding: const EdgeInsets.symmetric(vertical: 10), children: <Widget>[
            _card(
                child: Text(
                    context.tx('برای افزودن ادمین، کاربر را در زبانه‌ی «کاربران» پیدا کن و «دسترسی» را بزن.',
                        'To add an admin, find the user in Users and tap Access.'),
                    style: const TextStyle(color: NxColors.textDim))),
            for (final dynamic e in rows)
              Builder(builder: (BuildContext context) {
                final Map<String, dynamic> u = Map<String, dynamic>.from(e as Map);
                final List<dynamic> p = (u['perms'] as List<dynamic>?) ?? const <dynamic>[];
                return _card(
                    child: Row(children: <Widget>[
                  Icon(u['owner'] == true ? Icons.workspace_premium_rounded : Icons.shield_rounded,
                      color: u['owner'] == true ? NxColors.gold : NxColors.champagne),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Text('${u['username'] ?? 'Pilot'}', style: const TextStyle(fontWeight: FontWeight.w900)),
                    Text(
                        u['owner'] == true
                            ? context.tx('مدیر اصلی — همه‌ی دسترسی‌ها', 'Main admin — everything')
                            : <String>[
                                for (final dynamic x in p) AdminPerm.label('$x', context.isFa),
                                if (u['staff_role'] == 'organizer') context.tx('مدیر تورنمنت', 'tournament manager'),
                                if (u['unlimited_gems'] == true) context.tx('جم نامحدود', 'unlimited gems')
                                else if (u['gem_budget'] != null) context.tx('سقف جم ${u['gem_budget']}', 'gem budget ${u['gem_budget']}'),
                              ].join(' · '),
                        style: const TextStyle(color: NxColors.textDim, fontSize: 12)),
                  ])),
                  if (u['owner'] != true)
                    IconButton(
                        icon: const Icon(Icons.edit_rounded),
                        onPressed: () => showAdminEditor(context, ref, u, done: reload)),
                ]));
              }),
          ]);
        },
      );
}

// ------------------------------------------------------------------ tournaments
class _TournamentsTab extends ConsumerWidget {
  const _TournamentsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) => _Loader(
        load: () => _api(ref).tournaments(),
        build: (BuildContext context, Map<String, dynamic> d, VoidCallback reload) {
          final List<dynamic> rows = (d['tournaments'] as List<dynamic>?) ?? const <dynamic>[];
          return ListView(padding: const EdgeInsets.symmetric(vertical: 10), children: <Widget>[
            _card(
                child: Row(children: <Widget>[
              Expanded(child: Text(context.tx('ساخت تورنمنت جدید', 'Create a tournament'))),
              FilledButton.icon(
                  onPressed: () => context.push('/tournaments/new'),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(context.tx('جدید', 'New'))),
            ])),
            for (final dynamic e in rows)
              Builder(builder: (BuildContext context) {
                final Map<String, dynamic> t = Map<String, dynamic>.from(e as Map);
                return _card(
                    child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${t['title']}', style: const TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text(
                      '${t['game']} · ${t['status']} · ${t['players']}/${t['capacity']} · ${t['creator'] ?? ''}'
                      '${(t['disputes'] ?? 0) > 0 ? ' · ⚠ ${t['disputes']}' : ''}',
                      style: const TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/tournaments/${t['id']}/manage'),
                ));
              }),
          ]);
        },
      );
}

// ------------------------------------------------------------------ moderation
class _ModerationTab extends ConsumerWidget {
  const _ModerationTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) => _Loader(
        load: () => _api(ref).recentContent(),
        build: (BuildContext context, Map<String, dynamic> d, VoidCallback reload) {
          Future<void> remove(String kind, String id) async {
            final String? reason = await _ask(context, context.tx('دلیل حذف', 'Reason for removal'));
            if (reason == null) return;
            final Map<String, dynamic> r = await _api(ref).remove(kind, id, reason);
            if (context.mounted) await _toast(context, r);
            reload();
          }

          Widget item(String kind, Map<String, dynamic> m) => _card(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Icon(kind == 'post' ? Icons.photo_rounded : Icons.chat_bubble_rounded, color: NxColors.champagne),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text('${m['username'] ?? 'Pilot'} · ${_shortTime(m['created_at'])}',
                      style: const TextStyle(color: NxColors.textDim, fontSize: 12)),
                  Text('${m['text'] ?? ''}', maxLines: 4, overflow: TextOverflow.ellipsis),
                ])),
                IconButton(
                    icon: const Icon(Icons.delete_forever_rounded, color: NxColors.danger),
                    onPressed: () => remove(kind, '${m['id']}')),
              ]));
          return ListView(padding: const EdgeInsets.symmetric(vertical: 10), children: <Widget>[
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(context.tx('پست‌ها و استوری‌های اخیر', 'Recent posts & stories'),
                    style: const TextStyle(fontWeight: FontWeight.w900))),
            for (final dynamic e in (d['posts'] as List<dynamic>?) ?? const <dynamic>[])
              item('post', Map<String, dynamic>.from(e as Map)),
            Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(context.tx('نظرهای اخیر', 'Recent comments'), style: const TextStyle(fontWeight: FontWeight.w900))),
            for (final dynamic e in (d['comments'] as List<dynamic>?) ?? const <dynamic>[])
              item('comment', Map<String, dynamic>.from(e as Map)),
          ]);
        },
      );
}

// ------------------------------------------------------------------ rooms
class _RoomsTab extends ConsumerWidget {
  const _RoomsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) => _Loader(
        load: () => _api(ref).rooms(),
        build: (BuildContext context, Map<String, dynamic> d, VoidCallback reload) {
          final List<dynamic> rows = (d['rooms'] as List<dynamic>?) ?? const <dynamic>[];
          if (rows.isEmpty) {
            return ListView(children: <Widget>[
              _broadcastButton(context, ref),
              const SizedBox(height: 80),
              Center(child: Text(context.tx('اتاق فعالی نیست', 'No active rooms'))),
            ]);
          }
          return ListView(padding: const EdgeInsets.symmetric(vertical: 10), children: <Widget>[
            _broadcastButton(context, ref),
            for (final dynamic e in rows)
              Builder(builder: (BuildContext context) {
                final Map<String, dynamic> r = Map<String, dynamic>.from(e as Map);
                final Map<String, dynamic> st = Map<String, dynamic>.from((r['settings'] as Map?) ?? const <String, dynamic>{});
                return _card(
                    child: Row(children: <Widget>[
                  Icon(r['status'] == 'playing' ? Icons.sports_esports_rounded : Icons.meeting_room_rounded,
                      color: NxColors.gold),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Text('${r['game']} · ${r['code']}${st['tmatch'] != null ? ' · 🏆' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                    Text(
                        '${r['status']} · ${r['players']}/${r['seats']} · ${r['is_private'] == true ? context.tx('خصوصی', 'private') : context.tx('عمومی', 'public')}'
                        '${st['category'] != null ? ' · ${st['category']}' : ''} · ${r['host_name'] ?? ''}',
                        style: const TextStyle(color: NxColors.textDim, fontSize: 12)),
                  ])),
                  PopupMenuButton<String>(
                    tooltip: context.tx('بیشتر', 'More'),
                    icon: const Icon(Icons.more_vert_rounded, color: NxColors.champagne),
                    onSelected: (String v) async {
                      final AdminApi api = _api(ref);
                      final String id = '${r['id']}';
                      Map<String, dynamic>? x;
                      if (v == 'msg') {
                        final String? t = await _ask(context, context.tx('پیام مدیریت به این اتاق', 'Admin message to this room'));
                        if (t == null || t.trim().isEmpty) return;
                        x = await api.roomMessage(id, t.trim());
                      } else if (v == 'private') {
                        x = await api.roomUpdate(id, private: r['is_private'] != true);
                      } else if (v == 'seats') {
                        final String? t = await _ask(context, context.tx('تعداد صندلی (۲ تا ۲۱)', 'Seats (2-21)'),
                            initial: '${r['seats'] ?? 2}');
                        final int? n = int.tryParse(t?.trim() ?? '');
                        if (n == null) return;
                        x = await api.roomUpdate(id, seats: n);
                      } else if (v == 'clear') {
                        x = await api.roomClearChat(id);
                      }
                      if (x != null && context.mounted) await _toast(context, x);
                      reload();
                    },
                    itemBuilder: (BuildContext c) => <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(value: 'msg', child: Text(c.tx('ارسال پیام مدیریت', 'Send admin message'))),
                      PopupMenuItem<String>(
                          value: 'private',
                          child: Text(r['is_private'] == true ? c.tx('عمومی کن', 'Make public') : c.tx('خصوصی کن', 'Make private'))),
                      PopupMenuItem<String>(value: 'seats', child: Text(c.tx('تغییر صندلی‌ها', 'Change seats'))),
                      PopupMenuItem<String>(value: 'clear', child: Text(c.tx('پاک کردن چت', 'Clear chat'))),
                    ],
                  ),
                  IconButton(
                    tooltip: context.tx('اعضا / اخراج', 'Members / kick'),
                    icon: const Icon(Icons.group_rounded, color: NxColors.champagne),
                    onPressed: () => _showMembers(context, ref, '${r['id']}'),
                  ),
                  IconButton(
                    tooltip: context.tx('بستن اتاق', 'Close room'),
                    icon: const Icon(Icons.cancel_rounded, color: NxColors.danger),
                    onPressed: () async {
                      final String? reason = await _ask(context, context.tx('دلیل بستن اتاق', 'Reason'));
                      if (reason == null) return;
                      final Map<String, dynamic> x = await _api(ref).closeRoom('${r['id']}', reason);
                      if (context.mounted) await _toast(context, x);
                      reload();
                    },
                  ),
                ]));
              }),
          ]);
        },
      );
}

Future<void> _showMembers(BuildContext context, WidgetRef ref, String room) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext c) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(c).height * .6,
        child: _Loader(
          load: () => _api(ref).roomMembers(room),
          build: (BuildContext context, Map<String, dynamic> d, VoidCallback reload) => ListView(children: <Widget>[
            for (final dynamic e in (d['members'] as List<dynamic>?) ?? const <dynamic>[])
              Builder(builder: (BuildContext context) {
                final Map<String, dynamic> m = Map<String, dynamic>.from(e as Map);
                return ListTile(
                  dense: true,
                  leading: Icon(m['muted'] == true ? Icons.mic_off_rounded : Icons.person_rounded),
                  title: Text('${m['username'] ?? m['user_id']}'),
                  subtitle: Text('${m['role'] ?? ''}'),
                  trailing: TextButton(
                    onPressed: () async {
                      final String? reason = await _ask(context, context.tx('دلیل اخراج', 'Kick reason'));
                      if (reason == null) return;
                      final Map<String, dynamic> x = await _api(ref).kick(room, '${m['user_id']}', reason);
                      if (context.mounted) await _toast(context, x);
                      reload();
                    },
                    child: Text(context.tx('اخراج', 'Kick'), style: const TextStyle(color: NxColors.danger)),
                  ),
                );
              }),
          ]),
        ),
      ),
    ),
  );
}

// ------------------------------------------------------------------ live matches
class _MatchesTab extends ConsumerWidget {
  const _MatchesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) => _Loader(
        load: () => _api(ref).liveMatches(),
        build: (BuildContext context, Map<String, dynamic> d, VoidCallback reload) {
          final List<dynamic> rows = (d['matches'] as List<dynamic>?) ?? const <dynamic>[];
          if (rows.isEmpty) {
            return ListView(children: <Widget>[
              const SizedBox(height: 80),
              Center(child: Text(context.tx('بازی زنده‌ای نیست', 'No live matches'))),
            ]);
          }
          return ListView(padding: const EdgeInsets.symmetric(vertical: 10), children: <Widget>[
            for (final dynamic e in rows)
              Builder(builder: (BuildContext context) {
                final Map<String, dynamic> m = Map<String, dynamic>.from(e as Map);
                final List<dynamic> names = (m['names'] as List<dynamic>?) ?? const <dynamic>[];
                return _card(
                    child: Row(children: <Widget>[
                  const Icon(Icons.sports_esports_rounded, color: NxColors.gold),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Text('${m['game']}${m['tournament'] == true ? ' · 🏆' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                    Text('${names.join(' · ')}  ${m['scores'] ?? ''}',
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: NxColors.textDim, fontSize: 12)),
                    Text(_shortTime(m['started_at']), style: const TextStyle(color: NxColors.textDim, fontSize: 11)),
                  ])),
                  if (m['tournament'] != true)
                    TextButton(
                      onPressed: () async {
                        final String? reason = await _ask(context, context.tx('دلیل پایان بازی', 'Reason'));
                        if (reason == null) return;
                        final Map<String, dynamic> x = await _api(ref).endMatch('${m['id']}', reason);
                        if (context.mounted) await _toast(context, x);
                        reload();
                      },
                      child: Text(context.tx('پایان', 'End'), style: const TextStyle(color: NxColors.danger)),
                    ),
                ]));
              }),
          ]);
        },
      );
}

// ------------------------------------------------------------------ player reports
class _ReportsTab extends ConsumerStatefulWidget {
  const _ReportsTab();

  @override
  ConsumerState<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends ConsumerState<_ReportsTab> {
  String _status = 'open';
  int _v = 0;

  @override
  Widget build(BuildContext context) => Column(children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: SegmentedButton<String>(
            segments: <ButtonSegment<String>>[
              ButtonSegment<String>(value: 'open', label: Text(context.tx('باز', 'Open'))),
              ButtonSegment<String>(value: 'resolved', label: Text(context.tx('رسیدگی‌شده', 'Resolved'))),
              ButtonSegment<String>(value: 'dismissed', label: Text(context.tx('ردشده', 'Dismissed'))),
            ],
            selected: <String>{_status},
            onSelectionChanged: (Set<String> v) => setState(() {
              _status = v.first;
              _v++;
            }),
          ),
        ),
        Expanded(
          child: _Loader(
            key: ValueKey<String>('rep_$_status$_v'),
            load: () => _api(ref).reports(_status),
            build: (BuildContext context, Map<String, dynamic> d, VoidCallback reload) {
              final List<dynamic> rows = (d['reports'] as List<dynamic>?) ?? const <dynamic>[];
              if (rows.isEmpty) {
                return ListView(children: <Widget>[
                  const SizedBox(height: 80),
                  Center(child: Text(context.tx('گزارشی نیست', 'No reports'))),
                ]);
              }
              return ListView(padding: const EdgeInsets.symmetric(vertical: 10), children: <Widget>[
                for (final dynamic e in rows)
                  Builder(builder: (BuildContext context) {
                    final Map<String, dynamic> r = Map<String, dynamic>.from(e as Map);
                    Future<void> set(String st) async {
                      final Map<String, dynamic> x = await _api(ref).setReport((r['id'] as num).toInt(), st, null);
                      if (context.mounted) await _toast(context, x);
                      reload();
                    }

                    return _card(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      Text('${r['kind']} · ${r['target_name'] ?? r['target_id'] ?? ''}',
                          style: const TextStyle(fontWeight: FontWeight.w900)),
                      Text('${r['reason']}'),
                      Text('${context.tx('از', 'by')} ${r['reporter_name'] ?? ''} · ${_shortTime(r['created_at'])}',
                          style: const TextStyle(color: NxColors.textDim, fontSize: 11)),
                      if (_status == 'open')
                        Wrap(spacing: 6, children: <Widget>[
                          TextButton(onPressed: () => set('resolved'), child: Text(context.tx('رسیدگی شد', 'Resolve'))),
                          TextButton(onPressed: () => set('dismissed'), child: Text(context.tx('رد', 'Dismiss'))),
                        ])
                      else
                        TextButton(onPressed: () => set('open'), child: Text(context.tx('بازگشایی', 'Reopen'))),
                    ]));
                  }),
              ]);
            },
          ),
        ),
      ]);
}

// ------------------------------------------------------------------ announcements
class _AnnouncementsTab extends ConsumerWidget {
  const _AnnouncementsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) => _Loader(
        load: () => _api(ref).announcements(),
        build: (BuildContext context, Map<String, dynamic> d, VoidCallback reload) {
          Future<void> create() async {
            final TextEditingController title = TextEditingController();
            final TextEditingController body = TextEditingController();
            int hours = 72;
            final bool? ok = await showDialog<bool>(
              context: context,
              builder: (BuildContext ctx) => StatefulBuilder(
                builder: (BuildContext ctx, StateSetter set) => AnixDialog(
                  title: Text(ctx.tx('اطلاعیه‌ی جدید', 'New announcement')),
                  content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                    TextField(controller: title, decoration: InputDecoration(labelText: ctx.tx('عنوان', 'Title'))),
                    TextField(
                        controller: body,
                        minLines: 3,
                        maxLines: 6,
                        decoration: InputDecoration(labelText: ctx.tx('متن', 'Text'))),
                    const SizedBox(height: 8),
                    DropdownButton<int>(
                      value: hours,
                      isExpanded: true,
                      items: <DropdownMenuItem<int>>[
                        for (final int h in const <int>[6, 24, 72, 168, 0])
                          DropdownMenuItem<int>(
                              value: h,
                              child: Text(h == 0 ? ctx.tx('بدون انقضا', 'No expiry') : ctx.tx('$h ساعت', '$h hours'))),
                      ],
                      onChanged: (int? v) => set(() => hours = v ?? 72),
                    ),
                  ]),
                  actions: <Widget>[
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tx('انصراف', 'Cancel'))),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tx('انتشار', 'Publish'))),
                  ],
                ),
              ),
            );
            if (ok == true) {
              final Map<String, dynamic> r = await _api(ref).announce(title.text.trim(), body.text.trim(), hours);
              if (context.mounted) await _toast(context, r, okFa: 'برای همه منتشر شد', okEn: 'Published to everyone');
              reload();
            }
            title.dispose();
            body.dispose();
          }

          return ListView(padding: const EdgeInsets.symmetric(vertical: 10), children: <Widget>[
            _card(
                child: Row(children: <Widget>[
              Expanded(child: Text(context.tx('اطلاعیه برای همه‌ی بازیکن‌ها', 'Announcement to every player'))),
              FilledButton.icon(onPressed: create, icon: const Icon(Icons.campaign_rounded), label: Text(context.tx('جدید', 'New'))),
            ])),
            for (final dynamic e in (d['items'] as List<dynamic>?) ?? const <dynamic>[])
              Builder(builder: (BuildContext context) {
                final Map<String, dynamic> a = Map<String, dynamic>.from(e as Map);
                final bool live = a['active'] == true;
                return _card(
                    child: Row(children: <Widget>[
                  Icon(Icons.campaign_rounded, color: live ? NxColors.gold : NxColors.textDim),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Text('${a['title']}', style: const TextStyle(fontWeight: FontWeight.w900)),
                    Text('${a['body']}', maxLines: 3, overflow: TextOverflow.ellipsis),
                    Text(_shortTime(a['created_at']), style: const TextStyle(color: NxColors.textDim, fontSize: 11)),
                  ])),
                  if (live)
                    IconButton(
                        tooltip: context.tx('ویرایش', 'Edit'),
                        icon: const Icon(Icons.edit_rounded, size: 20),
                        onPressed: () async {
                          final String? t = await _ask(context, context.tx('عنوان', 'Title'), initial: '${a['title']}');
                          if (t == null || !context.mounted) return;
                          final String? b = await _ask(context, context.tx('متن', 'Text'), initial: '${a['body']}');
                          if (b == null || !context.mounted) return;
                          final Map<String, dynamic> r = await _api(ref).editAnnouncement((a['id'] as num).toInt(), t, b);
                          if (context.mounted) await _toast(context, r);
                          reload();
                        }),
                  if (live)
                    TextButton(
                        onPressed: () async {
                          final Map<String, dynamic> r = await _api(ref).endAnnouncement((a['id'] as num).toInt());
                          if (context.mounted) await _toast(context, r);
                          reload();
                        },
                        child: Text(context.tx('پایان', 'End'))),
                ]));
              }),
          ]);
        },
      );
}

// ------------------------------------------------------------------ ORACLE
class _OracleTab extends StatelessWidget {
  const _OracleTab();

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.symmetric(vertical: 10), children: <Widget>[
        _card(
            child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.psychology_alt_rounded, color: NxColors.gold),
          title: Text(context.tx('ویرایش شخصیت اوراکل', 'Edit ORACLE personality')),
          subtitle: Text(context.tx('بازیکن‌ها، جمله‌ها، خوشامدها، آموزش‌ها، تور و تنظیمات — با فرم',
              'Players, lines, greetings, tutorials, tour and settings — as a form')),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.push('/admin/oracle'),
        )),
      ]);
}

// ------------------------------------------------------------------ audit
class _AuditTab extends ConsumerWidget {
  const _AuditTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) => _Loader(
        load: () => _api(ref).audit(),
        build: (BuildContext context, Map<String, dynamic> d, VoidCallback reload) => ListView(
          padding: const EdgeInsets.symmetric(vertical: 10),
          children: <Widget>[
            for (final dynamic e in (d['entries'] as List<dynamic>?) ?? const <dynamic>[])
              Builder(builder: (BuildContext context) {
                final Map<String, dynamic> x = Map<String, dynamic>.from(e as Map);
                return _card(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text('${x['action']} · ${x['actor_name'] ?? ''}${x['target_name'] != null ? ' → ${x['target_name']}' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(_shortTime(x['created_at']), style: const TextStyle(color: NxColors.textDim, fontSize: 11)),
                  if (x['data'] != null)
                    Text('${x['data']}', maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                ]));
              }),
          ],
        ),
      );
}


// ------------------------------------------------------------------ admin v3: broadcast, banned, shop, player
Widget _broadcastButton(BuildContext context, WidgetRef ref) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: FilledButton.icon(
        onPressed: () async {
          final String? t = await _ask(context, context.tx('پیام به همه‌ی اتاق‌های باز', 'Message to every open room'));
          if (t == null || t.trim().isEmpty) return;
          final Map<String, dynamic> r = await _api(ref).roomsBroadcast(t.trim());
          if (context.mounted) {
            await _toast(context, r, okFa: 'به ${r['rooms'] ?? 0} اتاق ارسال شد', okEn: 'Sent to ${r['rooms'] ?? 0} rooms');
          }
        },
        icon: const Icon(Icons.campaign_rounded),
        label: Text(context.tx('اعلان در همه‌ی اتاق‌ها', 'Broadcast to all rooms')),
      ),
    );

class _BannedTab extends ConsumerWidget {
  const _BannedTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) => _Loader(
        load: () => _api(ref).banned(),
        build: (BuildContext context, Map<String, dynamic> d, VoidCallback reload) {
          final List<dynamic> rows = (d['users'] as List<dynamic>?) ?? const <dynamic>[];
          return ListView(padding: const EdgeInsets.symmetric(vertical: 10), children: <Widget>[
            if (rows.isEmpty)
              Padding(
                  padding: const EdgeInsets.all(40),
                  child: Center(child: Text(context.tx('هیچ کاربری مسدود نیست', 'Nobody is banned')))),
            for (final dynamic e in rows)
              Builder(builder: (BuildContext context) {
                final Map<String, dynamic> u = Map<String, dynamic>.from(e as Map);
                return _card(
                    child: Row(children: <Widget>[
                  const Icon(Icons.block_rounded, color: NxColors.danger),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Text('${u['username'] ?? 'Pilot'}', style: const TextStyle(fontWeight: FontWeight.w900)),
                    Text('${u['ban_reason'] ?? ''} · ${_shortTime(u['banned_at'])}',
                        style: const TextStyle(color: NxColors.textDim, fontSize: 12)),
                  ])),
                  TextButton(
                    onPressed: () => showPlayerSheet(context, ref, '${u['id']}'),
                    child: Text(context.tx('پروفایل', 'Profile')),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final Map<String, dynamic> r = await _api(ref).ban('${u['id']}', false, null);
                      if (context.mounted) await _toast(context, r);
                      reload();
                    },
                    icon: const Icon(Icons.lock_open_rounded, size: 18),
                    label: Text(context.tx('رفع', 'Unban')),
                  ),
                ]));
              }),
          ]);
        },
      );
}

/// Shop & prices: every catalog item (finger-soccer teams in gems, store items in coins). Edit price, currency, on/off.
class _ShopTab extends ConsumerStatefulWidget {
  const _ShopTab();
  @override
  ConsumerState<_ShopTab> createState() => _ShopTabState();
}

class _ShopTabState extends ConsumerState<_ShopTab> {
  String _q = '';
  int _key = 0;

  Future<void> _edit(Map<String, dynamic>? it, VoidCallback reload) async {
    final TextEditingController id = TextEditingController(text: '${it?['item_id'] ?? 'fs_team:'}');
    final TextEditingController price = TextEditingController(text: '${it?['price'] ?? 150}');
    final TextEditingController name = TextEditingController(text: '${it?['name'] ?? ''}');
    String currency = '${it?['currency'] ?? 'gems'}';
    bool active = it?['active'] != false;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter set) => AnixDialog(
          title: Text(it == null ? ctx.tx('آیتم جدید', 'New item') : '${it['item_id']}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            if (it == null)
              TextField(controller: id, decoration: InputDecoration(labelText: ctx.tx('شناسه', 'Item id'))),
            TextField(controller: name, decoration: InputDecoration(labelText: ctx.tx('نام', 'Name'))),
            TextField(
                controller: price,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: ctx.tx('قیمت', 'Price'))),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: <ButtonSegment<String>>[
                ButtonSegment<String>(value: 'gems', label: Text(ctx.tx('الماس', 'Gems')), icon: const Icon(Icons.diamond_rounded)),
                ButtonSegment<String>(value: 'coins', label: Text(ctx.tx('سکه', 'Coins')), icon: const Icon(Icons.toll_rounded)),
              ],
              selected: <String>{currency},
              onSelectionChanged: (Set<String> v) => set(() => currency = v.first),
            ),
            SwitchListTile(
              value: active,
              onChanged: (bool v) => set(() => active = v),
              title: Text(ctx.tx('فروشی است', 'For sale')),
            ),
          ]),
          actions: <Widget>[
            if (it != null)
              TextButton(
                onPressed: () async {
                  final Map<String, dynamic> r = await _api(ref).deleteItem('${it['item_id']}');
                  if (ctx.mounted) Navigator.pop(ctx, false);
                  if (mounted) await _toast(context, r);
                  reload();
                },
                child: Text(ctx.tx('حذف', 'Delete'), style: const TextStyle(color: NxColors.danger)),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tx('انصراف', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tx('ذخیره', 'Save'))),
          ],
        ),
      ),
    );
    if (ok == true) {
      final Map<String, dynamic> r = await _api(ref).setPrice(id.text.trim(), int.tryParse(price.text.trim()) ?? -1,
          currency: currency, active: active, name: name.text.trim().isEmpty ? null : name.text.trim());
      if (mounted) await _toast(context, r);
      reload();
    }
    id.dispose();
    price.dispose();
    name.dispose();
  }

  @override
  Widget build(BuildContext context) => _Loader(
        key: ValueKey<int>(_key),
        load: () => _api(ref).catalog(),
        build: (BuildContext context, Map<String, dynamic> d, VoidCallback reload) {
          final List<Map<String, dynamic>> rows = ((d['items'] as List<dynamic>?) ?? const <dynamic>[])
              .map((dynamic e) => Map<String, dynamic>.from(e as Map))
              .where((Map<String, dynamic> m) =>
                  _q.isEmpty || '${m['item_id']} ${m['name'] ?? ''}'.toLowerCase().contains(_q.toLowerCase()))
              .toList();
          return ListView(padding: const EdgeInsets.symmetric(vertical: 10), children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: <Widget>[
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded), hintText: context.tx('جستجوی آیتم', 'Search items')),
                    onSubmitted: (String v) => setState(() {
                      _q = v.trim();
                      _key++;
                    }),
                  ),
                ),
                IconButton(
                  tooltip: context.tx('آیتم جدید', 'New item'),
                  icon: const Icon(Icons.add_circle_rounded, color: NxColors.gold),
                  onPressed: () => _edit(null, reload),
                ),
              ]),
            ),
            for (final Map<String, dynamic> it in rows)
              _card(
                child: InkWell(
                  onTap: () => _edit(it, reload),
                  child: Row(children: <Widget>[
                    Icon(it['currency'] == 'gems' ? Icons.diamond_rounded : Icons.toll_rounded,
                        color: it['currency'] == 'gems' ? const Color(0xFF3BD0FF) : NxColors.gold),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      Text('${it['name'] ?? it['item_id']}', style: const TextStyle(fontWeight: FontWeight.w900)),
                      Text('${it['item_id']}${it['active'] == false ? ' · ${context.tx('غیرفعال', 'off')}' : ''}',
                          style: const TextStyle(color: NxColors.textDim, fontSize: 11)),
                    ])),
                    Text(it['price'] == 0 ? context.tx('رایگان', 'Free') : '${it['price']}',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    const Icon(Icons.edit_rounded, size: 16, color: NxColors.textDim),
                  ]),
                ),
              ),
          ]);
        },
      );
}

/// Full player view + edit: wallet (set exact or add/take), inventory (give / take / remove), profile fields, gem
/// ledger and the audit trail. Every action is an admin RPC checked server-side.
Future<void> showPlayerSheet(BuildContext context, WidgetRef ref, String userId) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: NxColors.luxeBg,
    builder: (BuildContext c) => SizedBox(
      height: MediaQuery.sizeOf(c).height * .88,
      child: _PlayerSheet(userId: userId),
    ),
  );
}

class _PlayerSheet extends ConsumerStatefulWidget {
  const _PlayerSheet({required this.userId});
  final String userId;
  @override
  ConsumerState<_PlayerSheet> createState() => _PlayerSheetState();
}

class _PlayerSheetState extends ConsumerState<_PlayerSheet> {
  Map<String, dynamic>? _d;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final Map<String, dynamic> d = await _api(ref).player(widget.userId);
    if (mounted) setState(() => _d = d);
  }

  Future<void> _done(Map<String, dynamic> r) async {
    if (mounted) await _toast(context, r);
    await _load();
  }

  Future<void> _setWallet() async {
    final Map<String, dynamic> d = _d!;
    final TextEditingController coins = TextEditingController(text: '${d['coins']}');
    final TextEditingController gems = TextEditingController(text: '${d['gems']}');
    final TextEditingController xp = TextEditingController(text: '${d['xp']}');
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AnixDialog(
        title: Text(ctx.tx('تنظیم دقیق موجودی', 'Set exact balances')),
        content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          TextField(controller: coins, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: ctx.tx('سکه', 'Coins'))),
          TextField(controller: gems, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: ctx.tx('الماس', 'Gems'))),
          TextField(controller: xp, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'XP')),
        ]),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tx('انصراف', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tx('ذخیره', 'Save'))),
        ],
      ),
    );
    if (ok == true) {
      await _done(await _api(ref).setWallet(widget.userId,
          coins: int.tryParse(coins.text.trim()), gems: int.tryParse(gems.text.trim()), xp: int.tryParse(xp.text.trim())));
    }
    coins.dispose();
    gems.dispose();
    xp.dispose();
  }

  Future<void> _addItem() async {
    final String? it = await _ask(context, context.tx('شناسه‌ی آیتم یا تیم (مثل fs_team:club0)', 'Item / team id (e.g. fs_team:club0)'));
    if (it == null || it.trim().isEmpty) return;
    await _done(await _api(ref).grantItem(widget.userId, it.trim(), true, 'admin panel'));
  }

  Future<void> _editBio() async {
    final String? b = await _ask(context, context.tx('بیو', 'Bio'), initial: '${_d?['bio'] ?? ''}');
    if (b == null) return;
    await _done(await _api(ref).editProfile(widget.userId, <String, dynamic>{'bio': b}, 'admin panel'));
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic>? d = _d;
    final AdminAccess a = ref.watch(adminAccessProvider);
    if (d == null) return const Center(child: CircularProgressIndicator());
    if (d['ok'] != true) return Center(child: Text(adminErrorText(d['error'] as String?, context.isFa)));
    final List<String> inv = ((d['inv'] as List<dynamic>?) ?? const <dynamic>[]).map((dynamic e) => '$e').toList()..sort();
    final List<dynamic> tx = (d['gem_tx'] as List<dynamic>?) ?? const <dynamic>[];
    final List<dynamic> audit = (d['audit'] as List<dynamic>?) ?? const <dynamic>[];
    final bool banned = d['banned'] == true;
    return ListView(padding: const EdgeInsets.only(bottom: 30), children: <Widget>[
      ListTile(
        leading: Icon(banned ? Icons.block_rounded : Icons.person_rounded, color: banned ? NxColors.danger : NxColors.champagne),
        title: Text('${d['username'] ?? 'Pilot'}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        subtitle: Text('${d['email'] ?? (d['guest'] == true ? 'guest' : '')} · ${d['role']} · ${_shortTime(d['created_at'])}'),
        trailing: IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
      ),
      _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text('🪙 ${d['coins']}   💎 ${d['gems']}   ⭐ XP ${d['xp']} · Lv ${d['level']}',
              style: const TextStyle(fontWeight: FontWeight.w900)),
          if (banned) Text('⛔ ${d['ban_reason'] ?? ''}', style: const TextStyle(color: NxColors.danger)),
          if (d['muted_until'] != null) Text('🔇 ${_shortTime(d['muted_until'])}', style: const TextStyle(color: NxColors.gold)),
          Wrap(spacing: 6, children: <Widget>[
            if (a.can(AdminPerm.currency))
              TextButton.icon(onPressed: _setWallet, icon: const Icon(Icons.edit_rounded, size: 18), label: Text(context.tx('موجودی', 'Wallet'))),
            if (a.can(AdminPerm.users) && d['role'] != 'owner')
              TextButton.icon(
                onPressed: () async {
                  String? reason;
                  if (!banned) {
                    reason = await _ask(context, context.tx('دلیل مسدودسازی', 'Ban reason'));
                    if (reason == null) return;
                  }
                  await _done(await _api(ref).ban(widget.userId, !banned, reason));
                },
                icon: Icon(banned ? Icons.lock_open_rounded : Icons.block_rounded, size: 18),
                label: Text(banned ? context.tx('رفع مسدودی', 'Unban') : context.tx('مسدود', 'Ban')),
              ),
            if (a.can(AdminPerm.users))
              TextButton.icon(onPressed: _editBio, icon: const Icon(Icons.notes_rounded, size: 18), label: Text(context.tx('بیو', 'Bio'))),
            if (a.can(AdminPerm.users))
              TextButton.icon(
                onPressed: () async {
                  final String? n = await _ask(context, context.tx('نام جدید', 'New name'), initial: '${d['username'] ?? ''}');
                  if (n == null || n.trim().isEmpty) return;
                  await _done(await _api(ref).rename(widget.userId, n.trim(), 'admin panel'));
                },
                icon: const Icon(Icons.badge_rounded, size: 18),
                label: Text(context.tx('نام', 'Rename')),
              ),
          ]),
        ]),
      ),
      _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Row(children: <Widget>[
            Expanded(
                child: Text('${context.tx('کوله‌پشتی', 'Inventory')} (${inv.length})',
                    style: const TextStyle(fontWeight: FontWeight.w900))),
            if (a.can(AdminPerm.currency))
              IconButton(icon: const Icon(Icons.add_rounded, color: NxColors.gold), onPressed: _addItem),
            if (a.can(AdminPerm.currency) && inv.isNotEmpty)
              IconButton(
                tooltip: context.tx('خالی کردن', 'Clear all'),
                icon: const Icon(Icons.delete_sweep_rounded, color: NxColors.danger),
                onPressed: () async => _done(await _api(ref).setInventory(widget.userId, const <String>[], 'admin clear')),
              ),
          ]),
          Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
            for (final String it in inv)
              InputChip(
                label: Text(it, style: const TextStyle(fontSize: 11)),
                onDeleted: a.can(AdminPerm.currency)
                    ? () async => _done(await _api(ref).grantItem(widget.userId, it, false, 'admin panel'))
                    : null,
              ),
          ]),
        ]),
      ),
      _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(context.tx('تراکنش‌های الماس', 'Gem ledger'), style: const TextStyle(fontWeight: FontWeight.w900)),
          if (tx.isEmpty) Text(context.tx('خالی', 'Empty'), style: const TextStyle(color: NxColors.textDim)),
          for (final dynamic e in tx)
            Text('${(e as Map)['delta']} → ${e['balance']} · ${e['reason']}${e['item'] != null ? ' · ${e['item']}' : ''} · ${_shortTime(e['created_at'])}',
                style: const TextStyle(color: NxColors.textDim, fontSize: 12)),
        ]),
      ),
      _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(context.tx('سابقه‌ی مدیریت', 'Admin history'), style: const TextStyle(fontWeight: FontWeight.w900)),
          for (final dynamic e in audit)
            Text('${(e as Map)['action']} · ${_shortTime(e['created_at'])}',
                style: const TextStyle(color: NxColors.textDim, fontSize: 12)),
        ]),
      ),
    ]);
  }
}
