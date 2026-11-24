import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/online/online_service.dart';
import '../../core/online/room_capacity.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/nx_theme.dart';
import '../../core/ui2/anix_kit.dart';
import '../../core/ui2/luxe.dart';
import '../../core/ui2/nx2_widgets.dart';
import '../../core/widgets/nx_widgets.dart';
import '../../games/arcade_kit/arcade_icon.dart';
import '../../games/game_registry.dart';

/// ROOMS — opened by the big GAME button in the dock.
///  * Quick Play: pick a game -> real matchmaking (`nx_quick`) in that game's lobby.
///  * Create Room: pick a game -> a new public room (`nx_create_room`), others can join from this list.
///  * Talk room: a conversation first (`nx_room_open`), games are picked inside.
///  * Open rooms: every public lobby on the server right now (no placeholder rows: empty/offline states only).
///
/// Every surface here is built from the shared Station Luxe kit (LuxeCard / LuxeButton / LuxeSection /
/// LuxeEmpty / showLuxePrompt), so the room list reads exactly like the home page.
class RoomsPage extends ConsumerStatefulWidget {
  const RoomsPage({super.key});

  @override
  ConsumerState<RoomsPage> createState() => _RoomsPageState();
}

class _RoomsPageState extends ConsumerState<RoomsPage> {
  List<Map<String, dynamic>> _rooms = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _talk = <Map<String, dynamic>>[];
  bool _loading = true;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => unawaited(_load(silent: true)));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!mounted) return;
    final OnlineService o = ref.read(onlineProvider);
    if (!silent) setState(() => _loading = true);
    try {
      if (!o.isOnline) await o.ensureSession();
      final SupabaseClient? c = o.games;
      if (c == null || o.client?.auth.currentSession == null) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'offline';
          });
        }
        return;
      }
      final List<dynamic> rows = await c
          .from('nx_rooms')
          .select('id, code, game, seats, host, created_at, nx_room_players(count)')
          .eq('status', 'lobby')
          .eq('is_private', false)
          .eq('quick', false)
          .eq('kind', 'game')
          .gte('updated_at', DateTime.now().toUtc().subtract(const Duration(minutes: 20)).toIso8601String())
          .order('created_at', ascending: false)
          .limit(40);
      List<dynamic> talk = const <dynamic>[];
      try {
        talk = (await c.rpc('nx_talk_rooms')) as List<dynamic>? ?? const <dynamic>[];
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _talk = talk.map((dynamic r) => Map<String, dynamic>.from(r as Map)).toList();
        _rooms = rows.map((dynamic r) => Map<String, dynamic>.from(r as Map)).toList();
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'offline';
        });
      }
    }
  }

  Future<void> _pickGame(String action) async {
    final List<GameInfo> games = kGames.where((GameInfo g) => g.supportsOnline).toList();
    final GameInfo? g = await showLuxeSheet<GameInfo>(
      context,
      builder: (BuildContext ctx) => _GamePickerSheet(
        games: games,
        title: action == 'quick'
            ? ctx.tx('بازی سریع — کدام بازی؟', 'Quick play — which game?')
            : ctx.tx('ساخت اتاق — کدام بازی؟', 'Create room — which game?'),
      ),
    );
    if (g == null || !mounted) return;
    await context.push('/online/${g.id}?action=$action');
    unawaited(_load(silent: true));
  }

  /// Opens a new conversation room (voice + chat; games are picked inside).
  Future<void> _openTalk() async {
    final String? title = await showLuxePrompt(
      context,
      title: context.tx('اتاق جدید', 'New room'),
      message: context.tx('یک نام برای اتاق انتخاب کن؛ بعد از ساخت می‌توانی بازی را عوض کنی.',
          'Name the room; you can change the game inside.'),
      hint: context.tx('نام اتاق (اختیاری)', 'Room name (optional)'),
      confirm: context.tx('ساخت', 'Create'),
      maxLength: 60,
    );
    if (title == null || !mounted) return;
    final OnlineService o = ref.read(onlineProvider);
    try {
      await o.gamesHello();
      final dynamic r = await o.games!.rpc('nx_room_open', params: <String, dynamic>{'p_title': title});
      if (!mounted) return;
      await context.push('/room/${(r as Map)['room_id']}');
      unawaited(_load(silent: true));
    } catch (e) {
      if (mounted) {
        luxeToast(context, context.tx('ساخت اتاق ممکن نشد. وارد حساب شده‌ای؟', 'Could not create the room. Are you signed in?'),
            error: true);
      }
    }
  }

  Widget _talkTile(Map<String, dynamic> r) {
    final GameInfo? g = gameById('${r['game']}');
    final int members = (r['members'] as num?)?.toInt() ?? 0;
    final int capacity = (r['capacity'] as num?)?.toInt() ?? capacityOf('${r['game']}').max;
    final bool locked = r['locked'] == true;
    return LuxeListRow(
      onTap: () async {
        await context.push('/room/${r['id']}');
        unawaited(_load(silent: true));
      },
      leading: Image.asset(AnixAssets.icon('headset'), width: 38, height: 38, errorBuilder: (_, __, ___) => const Icon(Icons.headset_mic_rounded, color: Luxe.gold)),
      title: '${r['title'] ?? r['host_name'] ?? 'NEXORA'}',
      subtitle: '${r['status'] == 'playing' ? context.tx('در حال بازی', 'Playing') : context.tx('گفتگو', 'Talking')}'
          '${g == null ? '' : ' · ${context.tx(g.nameFa, g.nameEn)}'}'
          ' · ${r['host_name'] ?? ''}',
      trailing: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        if (locked) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.lock_rounded, size: 14, color: Luxe.mute)),
        LuxeStat(label: '$members/$capacity', icon: Icons.people_alt_rounded),
      ]),
    );
  }

  int _count(Map<String, dynamic> r) {
    final dynamic p = r['nx_room_players'];
    if (p is List && p.isNotEmpty && p.first is Map) return ((p.first as Map)['count'] as num?)?.toInt() ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return NxWorldScaffold(
      scene: Nx2Scene.voiceStage,
      title: context.tx('اتاق‌ها', 'ROOMS'),
      palette: WorldPalette.arcade,
      dock: Nx2Tab.games,
      room: true,
      body: RefreshIndicator(
        color: Luxe.gold,
        backgroundColor: Luxe.panel,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
          children: <Widget>[
            LuxeCard(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(context.tx('اتاق‌های زنده', 'LIVE ROOMS'),
                    style: const TextStyle(fontFamily: 'ChakraPetch', letterSpacing: 2, fontSize: 11, color: Luxe.gold, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  context.tx('تماشاگر نامحدود؛ مدیر اتاق تعیین می‌کند چند نفر بازی کنند.',
                      'Unlimited audience — the room manager picks how many play.'),
                  style: const TextStyle(fontSize: 12, height: 1.45, color: Luxe.mute),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            Row(children: <Widget>[
              Expanded(
                child: LuxeButton(
                  label: context.tx('بازی سریع', 'QUICK PLAY'),
                  icon: Icons.bolt_rounded,
                  height: 56,
                  onTap: () => _pickGame('quick'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: LuxeButton(
                  label: context.tx('ساخت اتاق', 'NEW ROOM'),
                  icon: Icons.add_circle_outline_rounded,
                  kind: LuxeButtonKind.ghost,
                  height: 56,
                  onTap: () => _pickGame('create'),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            LuxeButton(
              label: context.tx('اتاق گفتگو + بازی', 'TALK ROOM + GAMES'),
              icon: Icons.headset_mic_rounded,
              kind: LuxeButtonKind.ghost,
              height: 50,
              fontSize: 13,
              onTap: _openTalk,
            ),
            const SizedBox(height: 8),
            LuxeButton(
              label: context.tx('همه‌ی بازی‌ها (آفلاین و با ربات)', 'ALL GAMES (OFFLINE & VS BOT)'),
              icon: Icons.sports_esports_rounded,
              kind: LuxeButtonKind.ghost,
              height: 46,
              fontSize: 12,
              onTap: () => context.push('/world/nexora_arcade'),
            ),
            if (_talk.isNotEmpty) ...<Widget>[
              LuxeSection(title: context.tx('اتاق‌های گفتگو', 'Talk rooms'), top: LuxeSpace.lg),
              for (final Map<String, dynamic> r in _talk) _talkTile(r),
            ],
            LuxeSection(title: context.tx('اتاق‌های بازی', 'Game lobbies'), top: LuxeSpace.lg),
            if (_loading && _rooms.isEmpty)
              LuxeLoading(label: context.tx('در حال گرفتن اتاق‌ها…', 'Loading rooms…'))
            else if (_error != null && _rooms.isEmpty && ref.watch(onlineProvider).client?.auth.currentSession == null)
              // Guests (local-only mode) have no session: say so instead of a misleading "server unreachable".
              LuxeEmpty(
                icon: Icons.person_off_rounded,
                title: context.tx('ورود لازم است', 'Sign in required'),
                message: context.tx(
                    'برای اتاق‌های آنلاین با ایمیل وارد شو. بازی آفلاین و با ربات در «همه‌ی بازی‌ها» است.',
                    'Sign in with email for online rooms. Offline and vs-bot games are under “All games”.'),
                action: LuxeButton(
                  label: context.tx('ورود', 'SIGN IN'),
                  height: 44,
                  expand: false,
                  onTap: () => context.go('/auth'),
                ),
              )
            else if (_error != null && _rooms.isEmpty)
              LuxeEmpty(
                icon: Icons.wifi_off_rounded,
                title: context.tx('اتصال برقرار نشد', 'Could not reach the server'),
                message: context.tx('بازی آفلاین در «همه‌ی بازی‌ها» در دسترس است.', 'Offline games are under “All games”.'),
                action: LuxeButton(
                  label: context.tx('تلاش دوباره', 'RETRY'),
                  icon: Icons.refresh_rounded,
                  height: 44,
                  expand: false,
                  onTap: _load,
                ),
              )
            else if (_rooms.isEmpty)
              LuxeEmpty(
                icon: Icons.meeting_room_outlined,
                title: context.tx('الان اتاق بازی وجود ندارد', 'No open rooms right now'),
                message: context.tx('اولین اتاق را بساز!', 'Create the first one!'),
                action: LuxeButton(
                  label: context.tx('اتاق جدید', 'NEW ROOM'),
                  icon: Icons.add_circle_outline_rounded,
                  height: 44,
                  expand: false,
                  onTap: () => _pickGame('create'),
                ),
              )
            else
              for (final Map<String, dynamic> r in _rooms) _roomTile(r),
          ],
        ),
      ),
    );
  }

  Widget _roomTile(Map<String, dynamic> r) {
    final GameInfo? g = gameById('${r['game']}');
    final int n = _count(r), seats = (r['seats'] as num?)?.toInt() ?? 2;
    const Color accent = Luxe.gold;
    return LuxeListRow(
      onTap: () async {
        await context.push('/online/${r['game']}?room=${r['id']}');
        unawaited(_load(silent: true));
      },
      tint: accent,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: accent.withValues(alpha: 0.12),
          border: Border.all(color: accent.withValues(alpha: 0.55), width: 1.2),
        ),
        child: Icon(Icons.sports_esports_rounded, color: accent, size: 20),
      ),
      title: g == null ? '${r['game']}' : context.tx(g.nameFa, g.nameEn),
      subtitle: '${context.tx('کد', 'CODE')} ${r['code']}'
          ' · ${capacityOf('${r['game']}').min}–${capacityOf('${r['game']}').max} ${context.tx('بازیکن', 'players')}',
      trailing: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        LuxeStat(label: '$n/$seats', icon: Icons.groups_rounded),
        const SizedBox(width: 6),
        const Icon(Icons.login_rounded, color: Luxe.ink, size: 18),
      ]),
    );
  }
}

/// Game picker: gold tiles with the arcade pedestal art.
class _GamePickerSheet extends StatelessWidget {
  const _GamePickerSheet({required this.games, required this.title});
  final List<GameInfo> games;
  final String title;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Luxe.ink)),
        const SizedBox(height: 10),
        Flexible(
          child: GridView.count(
            shrinkWrap: true,
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.92,
            children: <Widget>[
              for (final GameInfo g in games)
                LuxeCard(
                  radius: LuxeRadius.md,
                  padding: const EdgeInsets.all(6),
                  onTap: () => Navigator.pop(context, g),
                  semantics: context.tx(g.nameFa, g.nameEn),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
                    Image.asset('assets/arcade/pedestals/${g.id}.webp',
                        height: 48, errorBuilder: (_, __, ___) => SizedBox(height: 48, child: ArcadeMedallion(g.id))),
                    const SizedBox(height: 4),
                    Text(context.tx(g.nameFa, g.nameEn),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Luxe.ink)),
                    Text('${g.onlineMinPlayers}–${g.onlineMaxPlayers}',
                        style: const TextStyle(fontSize: 9.5, color: Luxe.mute)),
                  ]),
                ),
            ],
          ),
        ),
      ]),
    );
  }
}
