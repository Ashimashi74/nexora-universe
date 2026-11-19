import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../games/finger_soccer/core/bm_data.dart';
import '../online/online_service.dart';
import '../profile/profile_service.dart';

/// Finger-soccer teams that are always unlocked (no purchase): Persepolis, Esteghlal and Iran.
const Set<String> kFreeTeams = <String>{'club32', 'club33', 'nat26'};

/// Default team for a new player / when a saved team is not owned.
const String kDefaultTeam = 'club32';

/// Inventory / catalog id of a finger-soccer team (`fs_team:club0`).
String teamItemId(String teamId) => 'fs_team:$teamId';

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

  int teamPrice(String teamId) => kFreeTeams.contains(teamId) ? 0 : (_prices[teamItemId(teamId)] ?? defaultTeamPrice(teamId));

  bool teamForSale(String teamId) => !_inactive.contains(teamItemId(teamId));

  bool ownsTeam(String teamId) {
    if (kFreeTeams.contains(teamId) || teamPrice(teamId) == 0) return true;
    return _p?.owns(teamItemId(teamId)) ?? false;
  }

  /// A team the player may field: [teamId] when owned, otherwise the default free team.
  String usableTeam(String teamId) => ownsTeam(teamId) ? teamId : kDefaultTeam;

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
  Future<GemBuyResult> buyTeam(String teamId) => buy(teamItemId(teamId));

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
      _ => fa ? 'خرید انجام نشد' : 'Purchase failed',
    };
