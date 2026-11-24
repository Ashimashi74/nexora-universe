import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/audio/music_service.dart';
import '../../core/online/online_service.dart';
import '../../core/profile/profile_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/ui2/anix_kit.dart';
import '../../core/ui2/luxe.dart';
import '../../core/ui2/nx2_widgets.dart';
import 'hub_search.dart';
import 'luxe_station_page.dart';
import 'luxe_worlds.dart';

/// ANIX PRO HUB — native Flutter rebuild of the "Station Luxe" reference:
/// black/gold scene with drifting dust, profile + live-rooms HUD, the ANIX PRO mark,
/// a 3D ring of world cards (swipe to rotate, tap the front card to enter) and the Luxe dock.
/// Every number on screen is real (profile/wallet from ProfileService, room count from the games backend).
class HubPage extends ConsumerStatefulWidget {
  const HubPage({super.key});

  @override
  ConsumerState<HubPage> createState() => _HubPageState();
}

class _HubPageState extends ConsumerState<HubPage> with SingleTickerProviderStateMixin {
  late final List<LuxeWorld> _worlds = buildLuxeWorlds();
  late final PageController _pc = PageController(viewportFraction: 0.6, initialPage: _worlds.length * 200);
  late final AnimationController _sheen =
      AnimationController(vsync: this, duration: const Duration(seconds: 6));
  int _idx = 0;
  int? _liveRooms;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    MusicService.instance.start();
    unawaited(_loadRooms());
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => unawaited(_loadRooms()));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Luxe.reduceMotion(context)) {
      _sheen.stop();
    } else if (!_sheen.isAnimating) {
      _sheen.repeat();
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _pc.dispose();
    _sheen.dispose();
    super.dispose();
  }

  /// Live public talk rooms + open game lobbies on the games project. Offline/guest -> hidden.
  Future<void> _loadRooms() async {
    final OnlineService o = ref.read(onlineProvider);
    if (!o.isOnline) return;
    final SupabaseClient? c = o.games;
    if (c == null || o.client?.auth.currentSession == null) return;
    try {
      int n = 0;
      try {
        n += ((await c.rpc('nx_talk_rooms')) as List<dynamic>? ?? const <dynamic>[]).length;
      } catch (_) {}
      final List<dynamic> lobbies = await c
          .from('nx_rooms')
          .select('id')
          .eq('status', 'lobby')
          .eq('is_private', false)
          .gte('updated_at', DateTime.now().toUtc().subtract(const Duration(minutes: 20)).toIso8601String())
          .limit(99);
      n += lobbies.length;
      if (mounted) setState(() => _liveRooms = n);
    } catch (_) {
      // Keep the last known value; the chip simply stays as it was.
    }
  }

  int _wrap(int page) => page % _worlds.length;

  void _enter(LuxeWorld w) => context.push('/station/${w.k}');

  @override
  Widget build(BuildContext context) {
    final ProfileService p = ref.watch(profileProvider);
    final LuxeWorld cur = _worlds[_idx];
    final bool fa = context.isFa;
    return Scaffold(
      backgroundColor: Luxe.bg,
      extendBody: true,
      bottomNavigationBar: const Nx2Dock(current: Nx2Tab.home),
      body: LuxeScene(
        // Live native orbital-station scene (stars, planet, rings, core, spacecraft) instead of the
        // static art — the §6.2 signature visual, with reduced-motion/quality fallbacks built in.
        stationScene: true,
        child: SafeArea(
          bottom: false,
          child: LayoutBuilder(builder: (BuildContext ctx, BoxConstraints box) {
            final double ringH = math.min(box.maxHeight * 0.5, 450);
            return Column(children: <Widget>[
              _Hud(profile: p, liveRooms: _liveRooms),
              const SizedBox(height: 4),
              const _Brand(),
              const Spacer(),
              SizedBox(
                height: ringH,
                child: PageView.builder(
                  controller: _pc,
                  onPageChanged: (int i) => setState(() => _idx = _wrap(i)),
                  itemBuilder: (BuildContext c, int i) {
                    final LuxeWorld w = _worlds[_wrap(i)];
                    return AnimatedBuilder(
                      animation: _pc,
                      builder: (BuildContext c, Widget? child) {
                        double page = _pc.initialPage.toDouble();
                        if (_pc.hasClients && _pc.position.haveDimensions) page = _pc.page ?? page;
                        final double d = (i - page).clamp(-2.0, 2.0);
                        final double a = d.abs().clamp(0.0, 1.0);
                        final Matrix4 m = Matrix4.identity()
                          ..setEntry(3, 2, 0.0011)
                          ..translateByDouble(0.0, a * 26, -a * 120, 1.0)
                          ..rotateY(-d * 0.62 * (fa ? -1 : 1));
                        return Opacity(
                          opacity: d.abs() > 1.15 ? 0.0 : (1 - a * 0.45).clamp(0.0, 1.0),
                          child: Transform(alignment: Alignment.center, transform: m, child: child),
                        );
                      },
                      child: _WorldCard(
                        world: w,
                        sheen: _sheen,
                        onTap: () {
                          if (_wrap(i) == _idx) {
                            _enter(w);
                          } else {
                            _pc.animateToPage(i, duration: const Duration(milliseconds: 700), curve: Luxe.ease);
                          }
                        },
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 380),
                child: Padding(
                  key: ValueKey<String>(cur.k),
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(children: <Widget>[
                    Text(cur.en, style: Luxe.latin),
                    const SizedBox(height: 4),
                    Text(fa ? cur.fa : cur.en,
                        style: const TextStyle(fontSize: 26, color: Luxe.ink, fontWeight: FontWeight.w400)),
                    const SizedBox(height: 4),
                    Text(fa ? cur.tagFa : cur.tagEn,
                        textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: Luxe.mute)),
                  ]),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List<Widget>.generate(_worlds.length, (int i) {
                  final bool on = i == _idx;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    curve: Luxe.ease,
                    margin: const EdgeInsets.symmetric(horizontal: 3.5),
                    width: on ? 22 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                        color: on ? Luxe.gold : const Color(0x40F6E7BD), borderRadius: BorderRadius.circular(9)),
                  );
                }),
              ),
              SizedBox(height: 118 + MediaQuery.paddingOf(context).bottom),
            ]);
          }),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 92,
        child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
          const Text(
            'YOUR UNIVERSE',
            style: TextStyle(color: Color(0xFFD9B872), fontSize: 10, letterSpacing: 3.0, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          ShaderMask(
            shaderCallback: (Rect r) => Luxe.goldGrad.createShader(r),
            child: const Text(
              'NEXORA.',
              style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 2.0),
            ),
          ),
          const Text(
            'A universe beyond play.',
            style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1.0),
          ),
        ]),
      );
}

class _WorldCard extends StatelessWidget {
  const _WorldCard({required this.world, required this.sheen, required this.onTap});
  final LuxeWorld world;
  final Animation<double> sheen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool fa = context.isFa;
    return Center(
      child: AspectRatio(
        aspectRatio: 3 / 4.3,
        child: LuxePress(
          semantics: fa ? world.fa : world.en,
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: const Color(0x47F6E7BD)),
              boxShadow: <BoxShadow>[
                const BoxShadow(color: Colors.black, blurRadius: 60, offset: Offset(0, 40), spreadRadius: -28),
                BoxShadow(color: world.color.withValues(alpha: 0.45), blurRadius: 50, spreadRadius: -14),
              ],
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Color.lerp(const Color(0xFF1C1A14), world.color, 0.22)!, Luxe.bg],
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: Stack(fit: StackFit.expand, children: <Widget>[
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -1),
                      radius: 1.1,
                      colors: <Color>[world.color.withValues(alpha: 0.23), Colors.transparent],
                    ),
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: <double>[0, 0.85],
                      colors: <Color>[Color(0x0D07080C), Color(0xD907080C)],
                    ),
                  ),
                ),
                Align(
                  alignment: const Alignment(0, -0.5),
                  child: FractionallySizedBox(
                    widthFactor: 0.74,
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: const Color(0x59D9B872), width: 1.2),
                          boxShadow: <BoxShadow>[
                            BoxShadow(color: world.color.withValues(alpha: 0.45), blurRadius: 34, spreadRadius: -8),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(21),
                          child: Image.asset(Luxe.icon(world.icon),
                              fit: BoxFit.cover, cacheWidth: 360, errorBuilder: (_, __, ___) => const SizedBox()),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 22,
                  child: Column(children: <Widget>[
                    Text(fa ? world.fa : world.en,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 19, color: Luxe.ink, fontWeight: FontWeight.w500)),
                    if (fa) const SizedBox(height: 2),
                    if (fa) Text(world.en, style: Luxe.latin.copyWith(fontSize: 10, color: Luxe.gold2)),
                  ]),
                ),
                // Moving sheen across the glass.
                IgnorePointer(
                  child: AnimatedBuilder(
                    animation: sheen,
                    builder: (BuildContext c, _) {
                      final double t = Curves.easeInOut.transform((sheen.value / 0.6).clamp(0.0, 1.0));
                      return FractionalTranslation(
                        translation: Offset(-1.2 + t * 2.4, 0),
                        child: const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment(-1, -0.5),
                              end: Alignment(1, 0.5),
                              stops: <double>[0.4, 0.5, 0.6],
                              colors: <Color>[Colors.transparent, Color(0x24FFFFFF), Colors.transparent],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Hud extends ConsumerWidget {
  const _Hud({required this.profile, required this.liveRooms});
  final ProfileService profile;
  final int? liveRooms;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String name = profile.username.isEmpty ? context.tx('کاوشگر', 'Explorer') : profile.username;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(children: <Widget>[
        LuxePress(
          semantics: context.tx('پروفایل', 'Profile'),
          onTap: () => _profileSheet(context, ref),
          child: Stack(clipBehavior: Clip.none, children: <Widget>[
            Container(
              width: 46,
              height: 46,
              padding: const EdgeInsets.all(1.6),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: <Color>[Luxe.gold2, Luxe.gold3, Luxe.gold2]),
              ),
              child: ClipOval(
                child: ColoredBox(
                  color: const Color(0xFF0C0D12),
                  child: AnixFramedAvatar(
                      avatarId: profile.portrait, photoUrl: profile.avatarUrl, tier: anixTierForLevel(profile.level), size: 43),
                ),
              ),
            ),
            PositionedDirectional(
              bottom: -4,
              end: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(gradient: Luxe.goldGrad, borderRadius: BorderRadius.circular(8)),
                child: Text('${profile.level}',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF1A1408))),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: <Widget>[
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, color: Luxe.ink, fontWeight: FontWeight.w600)),
            Text(context.tx(profile.rankTitleFa, profile.rankTitleEn),
                maxLines: 1, style: const TextStyle(fontSize: 11, color: Luxe.mute)),
          ]),
        ),
        LuxeChip(
          semantics: context.tx('سکه', 'Coins'),
          onTap: () => context.push('/world/nexora_exchange'),
          child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
            const LuxeCoin(size: 14),
            const SizedBox(width: 5),
            Text(_fmt(profile.coins)),
          ]),
        ),
        const SizedBox(width: 6),
        LuxeChip(
          semantics: context.tx('جم', 'Gems'),
          onTap: () => context.push('/world/nexora_exchange'),
          child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
            const LuxeGem(size: 14),
            const SizedBox(width: 5),
            Text(_fmt(profile.gems)),
          ]),
        ),
        if (liveRooms != null) const SizedBox(width: 6),
        if (liveRooms != null) LuxeChip(
          semantics: context.tx('روم‌های فعال', 'Live rooms'),
          onTap: () => context.push('/rooms'),
          child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: liveRooms == null ? Luxe.mute : const Color(0xFF7BE0A1),
                    boxShadow: liveRooms == null
                        ? null
                        : const <BoxShadow>[BoxShadow(color: Color(0xFF7BE0A1), blurRadius: 6)])),
            const SizedBox(width: 5),
            Text(liveRooms == null ? context.tx('روم', 'Rooms') : '$liveRooms'),
          ]),
        ),
        const SizedBox(width: 6),
        LuxePress(
          semantics: context.tx('جستجو', 'Search'),
          onTap: () => showSearch<void>(context: context, delegate: HubSearchDelegate(isFa: context.isFa)),
          child: const LuxeGlass(
              radius: 99, padding: EdgeInsets.all(8), child: Icon(Icons.search_rounded, size: 17, color: Luxe.ink)),
        ),
      ]),
    );
  }

  static String _fmt(int v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 10000) return '${(v / 1000).toStringAsFixed(1)}K';
    final String s = '$v';
    return s.length > 3 ? '${s.substring(0, s.length - 3)},${s.substring(s.length - 3)}' : s;
  }

  void _profileSheet(BuildContext context, WidgetRef ref) {
    showLuxeSheet<void>(context, builder: (BuildContext ctx) {
      return Consumer(builder: (BuildContext ctx, WidgetRef ref, _) {
        final ProfileService p = ref.watch(profileProvider);
        return SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: <Widget>[
            Row(children: <Widget>[
              AnixFramedAvatar(avatarId: p.portrait, photoUrl: p.avatarUrl, tier: anixTierForLevel(p.level), size: 56),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text(p.username.isEmpty ? ctx.tx('کاوشگر', 'Explorer') : p.username,
                      style: const TextStyle(fontSize: 17, color: Luxe.ink, fontWeight: FontWeight.w600)),
                  Text('${ctx.tx('سطح', 'Level')} ${p.level} · ${ctx.tx(p.rankTitleFa, p.rankTitleEn)}',
                      style: const TextStyle(fontSize: 12, color: Luxe.mute)),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            LuxeBar(value: p.levelProgress, height: 7),
            const SizedBox(height: 6),
            Text('XP ${p.xpIntoLevel}', style: const TextStyle(fontSize: 11, color: Luxe.mute)),
            const SizedBox(height: 6),
            LuxeOption(
                label: ctx.tx('سکه', 'Coins'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  const LuxeCoin(),
                  const SizedBox(width: 6),
                  Text('${p.coins}', style: const TextStyle(color: Luxe.gold2, fontWeight: FontWeight.w700)),
                ]),
                onTap: () {
                  Navigator.of(ctx).pop();
                  context.push('/world/nexora_exchange');
                }),
            LuxeOption(
                label: ctx.tx('جم', 'Gems'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  const LuxeGem(),
                  const SizedBox(width: 6),
                  Text('${p.gems}', style: const TextStyle(color: Luxe.gold2, fontWeight: FontWeight.w700)),
                ]),
                onTap: () {
                  Navigator.of(ctx).pop();
                  context.push('/world/nexora_exchange');
                }),
            if (p.canClaimDaily)
              LuxeOption(
                  label: ctx.tx('دریافت جایزه‌ی امروز', 'Claim today\'s reward'),
                  icon: 'r3c6',
                  onTap: () {
                    Navigator.of(ctx).pop();
                    luxeClaimDaily(context, ref);
                  }),
            LuxeOption(
                label: ctx.tx('فضای شخصی و پروفایل', 'Personal orbit'),
                icon: 'r4c4',
                onTap: () {
                  Navigator.of(ctx).pop();
                  context.push('/world/personal_orbit');
                }),
          ]),
        );
      });
    });
  }
}
