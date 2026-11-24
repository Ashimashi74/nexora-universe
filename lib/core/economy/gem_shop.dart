import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../games/finger_soccer/core/bm_data.dart';
import '../../games/finger_soccer/core/bm_engine.dart';
import '../../games/finger_soccer/core/fs_custom_teams.dart';
import '../online/online_service.dart';
import '../profile/profile_service.dart';

/// Finger-soccer teams that are always unlocked (no purchase). v10 (owner art 2026-11-22): the three starter NX
/// faction coins — NX Core, NX Cyan and NX Mercury. The v9 starter ids (`club32`, `club33`, `nat26`) were the old
/// house badges; their art is gone, so a saved setup that still names one resolves to [kDefaultTeam] (see
/// GemShop.usableTeam) and the server seed keeps those three catalog rows priced 0 but inactive.
const Set<String> kFreeTeams = <String>{'nx_core', 'nx_cyan', 'nx_frost_blue'};

/// Default team for a new player / when a saved team is not owned.
const String kDefaultTeam = 'nx_core';

/// v9 starter ids that no longer exist as art. A saved setup naming one is migrated to [kDefaultTeam].
const Set<String> kRetiredTeams = <String>{'club32', 'club33', 'club34', 'club35', 'club36', 'club37', 'club38', 'club39',
  'nat24', 'nat25', 'nat26', 'nat27'};

/// Inventory / catalog id of a finger-soccer team (`fs_team:club0`).
String teamItemId(String teamId) => 'fs_team:$teamId';

/// The lobby's "create your custom team" tile (not a fieldable team; see bm_data.dart). A saved setup naming it
/// resolves to the player's own shared custom team.
const String kCustomTeamId = 'custom_team';

/// Gem entitlement that lets a player create ONE shared custom team (1000 gems).
const String kCustomTeamItemId = 'fs_custom_team';
const int kCustomTeamPrice = 1000;

/// Result of creating / updating the player's shared custom team.
class CustomTeamResult {
  const CustomTeamResult(this.ok, {this.error, this.team});
  final bool ok;
  final String? error; // not_purchased | already_created | bad_crest | offline | upload | image | network | ...
  final FsCustomTeam? team;
}

/// Built-in gem price of a team (the server catalog, editable by admins, wins when loaded). Free teams cost 0; every
/// other team costs 150..500 gems by strength (power + accuracy 9..20, rounded to 10): weakest 150, luxury 10/10 500.
/// supabase/migrations/20261120000000_nx_gems_shop.sql seeds nx_catalog with exactly these numbers.
int defaultTeamPrice(String teamId) {
  if (kFreeTeams.contains(teamId)) return 0;
  BmTeamDef? d;
  for (final BmTeamDef t in kBmTeamDefs) {
    if (t.id == teamId) d = t;
  }
  if (d == null) return 500;
  final int score = (d.power + d.accuracy).clamp(9, 20);
  return ((150 + (score - 9) * 350 / 11) / 10).round() * 10;
}

/// Result of a gem purchase.
class GemBuyResult {
  const GemBuyResult(this.ok, {this.error, this.gems});
  final bool ok;
  final String? error; // insufficient_gems | offline | not_for_sale | not_signed_in | ...
  final int? gems;
}

/// Gems (الماس) and the gem shop. Balance and ownership are server-side (auth project, public.profiles.gems and
/// nx_profiles.data.inv); every purchase is an RPC that checks the catalog price and deducts atomically.
class GemShop extends ChangeNotifier {
  GemShop._();
  static final GemShop instance = GemShop._();

  /// Live gem prices from nx_catalog (item id -> price); empty until loaded.
  final Map<String, int> _prices = <String, int>{};
  final Set<String> _inactive = <String>{};
  bool loaded = false;
  bool busy = false;
  String? dailyClaimedOn;

  SupabaseClient? get _c {
    final OnlineService? o = OnlineService.current;
    final SupabaseClient? c = o?.client;
    if (c == null || c.auth.currentSession == null) return null;
    return c;
  }

  ProfileService? get _p => ProfileService.current;

  bool get online => _c != null;

  String? get _uid => OnlineService.current?.uid;

  int teamPrice(String teamId) {
    if (teamId == kCustomTeamId) return customTeamPrice;
    if (bmIsCustomTeamId(teamId)) {
      if (isMyCustomTeam(teamId)) return 0;
      return _prices[teamItemId(teamId)] ?? FsCustomTeams.instance.byTeamId(teamId)?.price ?? kFsCustomTeamBuyPrice;
    }
    return kFreeTeams.contains(teamId) ? 0 : (_prices[teamItemId(teamId)] ?? defaultTeamPrice(teamId));
  }

  int get customTeamPrice => _prices[kCustomTeamItemId] ?? kCustomTeamPrice;

  /// The player bought the 1000-gem entitlement to create a custom team.
  bool ownsCustomTeam() => _p?.owns(kCustomTeamItemId) ?? false;

  /// The shared custom team this player created (null until created / loaded).
  FsCustomTeam? get myCustomTeam => FsCustomTeams.instance.ownedBy(_uid);

  /// [teamId] is the custom team this player created (always free for them).
  bool isMyCustomTeam(String teamId) => FsCustomTeams.instance.isOwner(teamId, _uid);

  Future<GemBuyResult> buyCustomTeam() => buy(kCustomTeamItemId);

  bool teamForSale(String teamId) => !_inactive.contains(teamItemId(teamId));

  bool ownsTeam(String teamId) {
    if (teamId == kCustomTeamId) return myCustomTeam != null;
    if (bmIsCustomTeamId(teamId)) return isMyCustomTeam(teamId) || (_p?.owns(teamItemId(teamId)) ?? false);
    if (kFreeTeams.contains(teamId) || teamPrice(teamId) == 0) return true;
    return _p?.owns(teamItemId(teamId)) ?? false;
  }

  /// A team the player may field: [teamId] when owned, otherwise the default free team. A retired v9 id (its art no
  /// longer ships) is never fielded, even if the server inventory still lists it. The "create" tile id resolves to
  /// the player's own custom team; a custom team someone else made needs its 250-gem purchase.
  String usableTeam(String teamId) {
    if (teamId == kCustomTeamId) return myCustomTeam?.teamId ?? kDefaultTeam;
    if (bmIsCustomTeamId(teamId)) return ownsTeam(teamId) ? teamId : kDefaultTeam;
    if (kRetiredTeams.contains(teamId) || !kBmTeamDefs.any((BmTeamDef t) => t.id == teamId)) return kDefaultTeam;
    return ownsTeam(teamId) ? teamId : kDefaultTeam;
  }

  /// Creates the player's shared custom team from a photo (or, when it exists, replaces its crest / name): cuts the
  /// photo to a round 256px crest, uploads it to `nx-media/<uid>/fs_custom_team.png` and calls the server RPC, which
  /// checks the 1000-gem entitlement and grants the team (power 10) to the owner.
  Future<CustomTeamResult> saveCustomTeam(Uint8List photo, {String? name}) async {
    final SupabaseClient? c = _c;
    final String? uid = _uid;
    if (c == null || uid == null) return const CustomTeamResult(false, error: 'offline');
    if (busy) return const CustomTeamResult(false, error: 'busy');
    busy = true;
    notifyListeners();
    try {
      final Uint8List crest;
      try {
        crest = await fsCropRoundCrest(photo);
      } catch (e) {
        debugPrint('custom crest crop: $e');
        return const CustomTeamResult(false, error: 'image');
      }
      const String file = 'fs_custom_team.png';
      final String path = '$uid/$file';
      try {
        await c.storage
            .from('nx-media')
            .uploadBinary(path, crest, fileOptions: const FileOptions(contentType: 'image/png', upsert: true));
      } catch (e) {
        debugPrint('custom crest upload: $e');
        return const CustomTeamResult(false, error: 'upload');
      }
      final String url = '${c.storage.from('nx-media').getPublicUrl(path)}?v=${DateTime.now().millisecondsSinceEpoch}';
      final String nm = (name ?? '').trim();
      final Map<String, dynamic> params = <String, dynamic>{
        'p_name': nm.length > kFsCustomTeamNameMax ? nm.substring(0, kFsCustomTeamNameMax) : nm,
        'p_crest_path': path,
        'p_crest_url': url,
      };
      dynamic r = await c.rpc(myCustomTeam == null ? 'fs_create_custom_team' : 'fs_update_custom_team', params: params);
      if (r is Map && r['error'] == 'already_created') r = await c.rpc('fs_update_custom_team', params: params);
      if (r is! Map) return const CustomTeamResult(false, error: 'failed');
      if (r['ok'] != true) return CustomTeamResult(false, error: '${r['error'] ?? 'failed'}');
      final dynamic row = r['team'];
      final FsCustomTeam? team = row is Map ? FsCustomTeam.fromRow(Map<String, dynamic>.from(row)) : null;
      if (team != null) {
        FsCustomTeams.instance.apply(<FsCustomTeam>[team]);
        _p?.grantItem(teamItemId(team.teamId));
      }
      return CustomTeamResult(true, team: team);
    } on PostgrestException catch (e) {
      return CustomTeamResult(false, error: e.message);
    } catch (e) {
      debugPrint('custom team: $e');
      return const CustomTeamResult(false, error: 'network');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void _applyWallet(dynamic r) {
    if (r is! Map) return;
    _p?.applyWallet(
        xp: (r['xp'] as num?)?.toInt(), coins: (r['coins'] as num?)?.toInt(), gems: (r['gems'] as num?)?.toInt());
  }

  /// Wallet (with the one-time welcome gems) + catalog gem prices.
  Future<void> refresh() async {
    final SupabaseClient? c = _c;
    if (c == null) return;
    try {
      _applyWallet(await c.rpc('nx_wallet'));
    } catch (e) {
      debugPrint('nx_wallet: $e');
    }
    await FsCustomTeams.instance.load(c);
    try {
      final List<dynamic> rows = await c.from('nx_catalog').select('item_id, price, currency, active').eq('currency', 'gems');
      _prices.clear();
      _inactive.clear();
      for (final dynamic e in rows) {
        final Map<String, dynamic> m = Map<String, dynamic>.from(e as Map);
        _prices['${m['item_id']}'] = (m['price'] as num?)?.toInt() ?? 0;
        if (m['active'] == false) _inactive.add('${m['item_id']}');
      }
      loaded = true;
    } catch (e) {
      debugPrint('nx_catalog: $e');
    }
    notifyListeners();
  }

  /// Buys a finger-soccer team with gems (server checks the price, the balance and ownership).
  Future<GemBuyResult> buyTeam(String teamId) => buy(teamId == kCustomTeamId ? kCustomTeamItemId : teamItemId(teamId));

  Future<GemBuyResult> buy(String itemId) async {
    final SupabaseClient? c = _c;
    if (c == null) return const GemBuyResult(false, error: 'offline');
    if (busy) return const GemBuyResult(false, error: 'busy');
    busy = true;
    notifyListeners();
    try {
      final dynamic r = await c.rpc('nx_buy_with_gems', params: <String, dynamic>{'p_item': itemId});
      if (r is Map) {
        _applyWallet(r);
        if (r['ok'] == true) {
          _p?.grantItem(itemId);
          return GemBuyResult(true, gems: (r['gems'] as num?)?.toInt());
        }
        return GemBuyResult(false, error: '${r['error'] ?? 'failed'}', gems: (r['gems'] as num?)?.toInt());
      }
      return const GemBuyResult(false, error: 'failed');
    } on PostgrestException catch (e) {
      return GemBuyResult(false, error: e.message);
    } catch (e) {
      return const GemBuyResult(false, error: 'network');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Daily free gems (once per day, server-checked). Returns the gems granted (0 = already claimed / offline).
  Future<int> claimDaily() async {
    final SupabaseClient? c = _c;
    if (c == null) return 0;
    try {
      final dynamic r = await c.rpc('nx_daily_gems');
      _applyWallet(r);
      notifyListeners();
      return r is Map ? ((r['granted'] as num?)?.toInt() ?? 0) : 0;
    } catch (e) {
      debugPrint('nx_daily_gems: $e');
      return 0;
    }
  }
}

/// Persian / English text for a gem-shop error.
String gemErrorText(String? e, bool fa) => switch (e) {
      'insufficient_gems' => fa ? 'الماس کافی نداری' : 'Not enough gems',
      'offline' || 'not_signed_in' => fa ? 'برای خرید با الماس وارد حساب شو (آنلاین)' : 'Sign in (online) to buy with gems',
      'not_for_sale' => fa ? 'این آیتم فعلاً فروشی نیست' : 'Not for sale right now',
      'network' => fa ? 'اتصال برقرار نیست' : 'No connection',
      'banned' => fa ? 'حساب مسدود است' : 'Account banned',
      'not_purchased' => fa ? 'اول تیم اختصاصی را بخر' : 'Buy the custom team first',
      'bad_crest' || 'upload' => fa ? 'آپلود عکس تیم ناموفق بود' : 'Could not upload the team photo',
      'image' => fa ? 'این عکس قابل استفاده نیست' : 'This photo can not be used',
      _ => fa ? 'خرید انجام نشد' : 'Purchase failed',
    };
