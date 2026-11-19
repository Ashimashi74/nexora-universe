import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/online/online_service.dart';

/// Admin permissions (server-enforced on both projects; this list only drives the UI).
class AdminPerm {
  const AdminPerm._();
  static const String users = 'users';
  static const String currency = 'currency';
  static const String tournaments = 'tournaments';
  static const String moderation = 'moderation';
  static const String rooms = 'rooms';
  static const String announcements = 'announcements';
  static const String oracle = 'oracle';
  static const String admins = 'admins';
  static const String shop = 'shop';
  static const List<String> all = <String>[users, currency, tournaments, moderation, rooms, announcements, oracle, shop, admins];

  static String label(String p, bool fa) => switch (p) {
        users => fa ? 'کاربران و مسدودسازی' : 'Users & bans',
        currency => fa ? 'اهدای سکه و جم' : 'Coin & gem grants',
        tournaments => fa ? 'تورنمنت‌ها' : 'Tournaments',
        moderation => fa ? 'نظارت محتوا' : 'Moderation',
        rooms => fa ? 'اتاق‌ها' : 'Rooms',
        announcements => fa ? 'اطلاعیه‌ها' : 'Announcements',
        oracle => fa ? 'تنظیمات اوراکل' : 'ORACLE config',
        admins => fa ? 'مدیریت ادمین‌ها' : 'Admin management',
        shop => fa ? 'فروشگاه و قیمت‌ها' : 'Shop & prices',
        _ => p,
      };
}

/// What the signed-in user may do (`nx_my_access` on the auth project). Refreshed on every auth change.
class AdminAccess extends ChangeNotifier {
  AdminAccess(this._online) {
    _online.addListener(_onAuth);
    _onAuth();
  }

  final OnlineService _online;
  String? _for;
  bool owner = false;
  Set<String> perms = <String>{};
  bool mustChangePassword = false;
  bool organizer = false;
  bool unlimitedGems = false;
  int? gemBudget;
  bool loaded = false;

  bool get isAdmin => owner || perms.isNotEmpty;
  bool can(String p) => owner || perms.contains(p);

  void _onAuth() {
    final String? uid = _online.isOnline ? _online.uid : null;
    if (uid == _for) return;
    _for = uid;
    unawaited(refresh());
  }

  Future<void> refresh() async {
    final SupabaseClient? c = _online.client;
    if (c == null || c.auth.currentSession == null) {
      owner = false;
      perms = <String>{};
      mustChangePassword = false;
      loaded = true;
      notifyListeners();
      return;
    }
    try {
      final dynamic r = await c.rpc('nx_my_access');
      if (r is Map) {
        owner = r['owner'] == true;
        perms = ((r['perms'] as List<dynamic>?) ?? const <dynamic>[]).map((dynamic e) => '$e').toSet();
        mustChangePassword = r['must_change_password'] == true;
        organizer = r['organizer'] == true;
        unlimitedGems = r['unlimited'] == true;
        gemBudget = (r['gem_budget'] as num?)?.toInt();
      }
    } catch (e) {
      debugPrint('my access: $e');
    }
    loaded = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _online.removeListener(_onAuth);
    super.dispose();
  }
}

final adminAccessProvider = ChangeNotifierProvider<AdminAccess>((ref) => AdminAccess(ref.read(onlineProvider)));

/// Thin wrappers around the admin RPCs. Every call is re-checked and audited on the server.
class AdminApi {
  AdminApi(this._o);
  final OnlineService _o;

  Future<Map<String, dynamic>> _auth(String fn, [Map<String, dynamic>? p]) async {
    try {
      final dynamic r = await _o.rpc(fn, p);
      return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{'ok': r != null, 'value': r};
    } on PostgrestException catch (e) {
      return <String, dynamic>{'ok': false, 'error': e.message};
    } catch (e) {
      return <String, dynamic>{'ok': false, 'error': 'network'};
    }
  }

  Future<Map<String, dynamic>> _games(String fn, [Map<String, dynamic>? p]) async {
    try {
      final dynamic r = await _o.grpc(fn, p);
      return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{'ok': r != null, 'value': r};
    } on PostgrestException catch (e) {
      return <String, dynamic>{'ok': false, 'error': e.message};
    } catch (e) {
      return <String, dynamic>{'ok': false, 'error': 'network'};
    }
  }

  Future<Map<String, dynamic>> stats() => _auth('nx_owner_stats');
  Future<Map<String, dynamic>> users(String q) =>
      _auth('nx_owner_users', <String, dynamic>{'p_q': q, 'p_limit': 60, 'p_offset': 0});
  Future<Map<String, dynamic>> ban(String user, bool ban, String? reason) =>
      _auth('nx_owner_ban', <String, dynamic>{'p_user': user, 'p_ban': ban, 'p_reason': reason});
  /// Grant (+) / take (-) coins and gems: permission 'currency' (non-owners capped per call server-side).
  Future<Map<String, dynamic>> grant(String user, int coins, int gems, String? reason) => _auth(
      'nx_admin_grant_wallet', <String, dynamic>{'p_user': user, 'p_coins': coins, 'p_gems': gems, 'p_reason': reason});

  // ---- admin powers v3 (gems, shop, full player view/edit, rooms broadcast)
  Future<Map<String, dynamic>> setWallet(String user, {int? coins, int? gems, int? xp, String? reason}) =>
      _auth('nx_admin_set_wallet', <String, dynamic>{
        'p_user': user, 'p_coins': coins, 'p_gems': gems, 'p_xp': xp, 'p_reason': reason});
  Future<Map<String, dynamic>> player(String user) => _auth('nx_admin_player', <String, dynamic>{'p_user': user});
  Future<Map<String, dynamic>> setInventory(String user, List<String> items, String? reason) =>
      _auth('nx_admin_set_inventory', <String, dynamic>{'p_user': user, 'p_items': items, 'p_reason': reason});
  Future<Map<String, dynamic>> editProfile(String user, Map<String, dynamic> patch, String? reason) =>
      _auth('nx_admin_edit_profile', <String, dynamic>{'p_user': user, 'p_patch': patch, 'p_reason': reason});
  Future<Map<String, dynamic>> banned() => _auth('nx_admin_banned', <String, dynamic>{'p_limit': 300});
  Future<Map<String, dynamic>> catalog() => _auth('nx_admin_catalog');
  Future<Map<String, dynamic>> setPrice(String item, int price,
          {String currency = 'gems', bool active = true, String? name, String? kind}) =>
      _auth('nx_admin_set_price', <String, dynamic>{
        'p_item': item, 'p_price': price, 'p_currency': currency, 'p_active': active, 'p_name': name, 'p_kind': kind});
  Future<Map<String, dynamic>> deleteItem(String item) => _auth('nx_admin_delete_item', <String, dynamic>{'p_item': item});
  Future<Map<String, dynamic>> roomMessage(String room, String text) =>
      _games('nx_admin_room_message', <String, dynamic>{'p_room': room, 'p_text': text});
  Future<Map<String, dynamic>> roomsBroadcast(String text) =>
      _games('nx_admin_rooms_broadcast', <String, dynamic>{'p_text': text});
  Future<Map<String, dynamic>> roomUpdate(String room, {bool? private, int? seats, String? title}) =>
      _games('nx_admin_room_update', <String, dynamic>{'p_room': room, 'p_private': private, 'p_seats': seats, 'p_title': title});
  Future<Map<String, dynamic>> roomClearChat(String room) =>
      _games('nx_admin_room_clear_chat', <String, dynamic>{'p_room': room});
  Future<Map<String, dynamic>> admins() => _auth('nx_admin_list');
  /// Redeems an owner-issued, single-use tournament-admin invitation code.
  /// The database validates expiry, account status, rate limits and ownership.
  Future<Map<String, dynamic>> redeemAdminCode(String code) =>
      _auth('nx_redeem_admin_code', <String, dynamic>{'p_code': code.trim()});
  Future<Map<String, dynamic>> setPerms(String user, List<String> perms, {bool unlimitedGems = false, int? gemBudget}) =>
      _auth('nx_admin_set_perms', <String, dynamic>{
        'p_user': user,
        'p_perms': perms,
        'p_unlimited_gems': unlimitedGems,
        'p_gem_budget': gemBudget,
      });
  Future<Map<String, dynamic>> setManager(String user, bool manager, {bool unlimited = false, int gemBudget = 0}) =>
      _auth('nx_admin_set_manager', <String, dynamic>{
        'p_user': user,
        'p_manager': manager,
        'p_unlimited': unlimited,
        'p_gem_budget': gemBudget,
      });
  Future<Map<String, dynamic>> audit() => _auth('nx_owner_audit_list');
  Future<Map<String, dynamic>> announcements() => _auth('nx_admin_announcements');
  Future<Map<String, dynamic>> announce(String title, String body, int hours) =>
      _auth('nx_admin_announce', <String, dynamic>{'p_title': title, 'p_body': body, 'p_hours': hours});
  Future<Map<String, dynamic>> endAnnouncement(int id) => _auth('nx_admin_announce_end', <String, dynamic>{'p_id': id});
  Future<Map<String, dynamic>> recentContent() => _auth('nx_admin_recent_content', <String, dynamic>{'p_limit': 60});
  Future<Map<String, dynamic>> remove(String kind, String id, String? reason) =>
      _auth('nx_admin_remove', <String, dynamic>{'p_kind': kind, 'p_id': id, 'p_reason': reason});
  Future<Map<String, dynamic>> rooms() => _games('nx_admin_rooms', <String, dynamic>{'p_limit': 120});
  Future<Map<String, dynamic>> closeRoom(String room, String? reason) =>
      _games('nx_admin_close_room', <String, dynamic>{'p_room': room, 'p_reason': reason});
  Future<Map<String, dynamic>> tournaments() => _games('nx_owner_tournaments', <String, dynamic>{'p_limit': 200});

  // ---- admin powers v2 (server-checked RPCs, both projects where the state lives in both)
  /// Mute chat / posting for [minutes] (0 = unmute) on the auth project and in room chat on the games project.
  Future<Map<String, dynamic>> mute(String user, int minutes, String? reason) async {
    final Map<String, dynamic> a =
        await _auth('nx_admin_mute', <String, dynamic>{'p_user': user, 'p_minutes': minutes, 'p_reason': reason});
    if (a['ok'] != true) return a;
    final Map<String, dynamic> g =
        await _games('nx_admin_mute', <String, dynamic>{'p_user': user, 'p_minutes': minutes, 'p_reason': reason});
    return g['ok'] == true ? a : g;
  }

  Future<Map<String, dynamic>> grantItem(String user, String item, bool grant, String? reason) => _auth(
      'nx_admin_grant_item', <String, dynamic>{'p_user': user, 'p_item': item, 'p_grant': grant, 'p_reason': reason});
  Future<Map<String, dynamic>> rename(String user, String name, String? reason) =>
      _auth('nx_admin_rename', <String, dynamic>{'p_user': user, 'p_name': name, 'p_reason': reason});
  Future<Map<String, dynamic>> resetPassword(String user, String temp) =>
      _auth('nx_admin_reset_password', <String, dynamic>{'p_user': user, 'p_temp': temp});
  Future<Map<String, dynamic>> reports(String status) =>
      _auth('nx_admin_reports', <String, dynamic>{'p_status': status, 'p_limit': 150});
  Future<Map<String, dynamic>> setReport(int id, String status, String? note) =>
      _auth('nx_admin_report_set', <String, dynamic>{'p_id': id, 'p_status': status, 'p_note': note});
  Future<Map<String, dynamic>> editAnnouncement(int id, String title, String body) =>
      _auth('nx_admin_announce_edit', <String, dynamic>{'p_id': id, 'p_title': title, 'p_body': body});
  Future<Map<String, dynamic>> roomMembers(String room) => _games('nx_admin_room_members', <String, dynamic>{'p_room': room});
  Future<Map<String, dynamic>> kick(String room, String user, String? reason) =>
      _games('nx_admin_kick', <String, dynamic>{'p_room': room, 'p_user': user, 'p_reason': reason});
  Future<Map<String, dynamic>> liveMatches() => _games('nx_admin_live_matches', <String, dynamic>{'p_limit': 150});
  Future<Map<String, dynamic>> endMatch(String match, String? reason) =>
      _games('nx_admin_end_match', <String, dynamic>{'p_match': match, 'p_reason': reason});
}

/// Role presets for the Access editor: admin = every permission except managing admins; moderator = users, chat
/// moderation and rooms; player = none.
const Map<String, List<String>> kAdminRolePresets = <String, List<String>>{
  'admin': <String>[
    AdminPerm.users, AdminPerm.currency, AdminPerm.tournaments, AdminPerm.moderation, AdminPerm.rooms,
    AdminPerm.announcements, AdminPerm.oracle, AdminPerm.shop,
  ],
  'mod': <String>[AdminPerm.users, AdminPerm.moderation, AdminPerm.rooms],
  'player': <String>[],
};

String adminErrorText(String? e, bool fa) => switch (e) {
      'forbidden' => fa ? 'دسترسی نداری' : 'Not allowed',
      'name_taken' => fa ? 'این نام قبلاً گرفته شده' : 'That name is taken',
      'bad_name' => fa ? 'نام باید ۳ تا ۲۰ نویسه باشد' : 'Names are 3-20 characters',
      'weak_password' => fa ? 'رمز موقت حداقل ۸ نویسه' : 'Temporary password needs 8+ characters',
      'bad_item' => fa ? 'شناسه‌ی آیتم نامعتبر است' : 'Invalid item id',
      'not_live' => fa ? 'این بازی در جریان نیست' : 'That match is not live',
      'password_change_required' => fa ? 'اول رمزت را عوض کن' : 'Change your password first',
      'cannot_ban_owner' => fa ? 'مدیر اصلی را نمی‌شود مسدود کرد' : 'The main admin cannot be banned',
      'cannot_ban_admin' => fa ? 'فقط مدیر اصلی می‌تواند ادمین را مسدود کند' : 'Only the main admin can ban an admin',
      'cannot_change_owner' => fa ? 'مدیر اصلی قابل تغییر نیست' : 'The main admin cannot be changed',
      'cannot_change_self' => fa ? 'دسترسی خودت را نمی‌توانی عوض کنی' : 'You cannot change your own access',
      'owner_only_admins' => fa ? 'فقط مدیر اصلی «مدیریت ادمین‌ها» را می‌دهد' : 'Only the main admin grants admin management',
      'owner_only_unlimited' => fa ? 'جم نامحدود فقط با مدیر اصلی' : 'Only the main admin grants unlimited gems',
      'account_required' => fa ? 'کاربر باید حساب دائمی داشته باشد (نه مهمان)' : 'The user needs a full account (not a guest)',
      'already_staff' => fa ? 'این حساب از قبل دسترسی مدیریتی دارد' : 'This account already has staff access',
      'bad_code' => fa ? 'کد دعوت معتبر نیست' : 'Invalid admin invitation code',
      'expired' => fa ? 'کد دعوت منقضی شده است' : 'This invitation code has expired',
      'used' => fa ? 'کد دعوت قبلاً استفاده شده است' : 'This invitation code has already been used',
      'amount_too_large' => fa ? 'مقدار بیش از حد مجاز است' : 'Amount too large',
      'zero_amount' => fa ? 'مقدار صفر است' : 'Amount is zero',
      'bad_price' => fa ? 'قیمت نامعتبر است' : 'Invalid price',
      'bad_amount' => fa ? 'مقدار نامعتبر است' : 'Invalid amount',
      'bad_text' => fa ? 'متن خالی یا خیلی بلند است' : 'Text empty or too long',
      'bad_field' => fa ? 'فیلد نامعتبر است' : 'Invalid field',
      'insufficient_balance' => fa ? 'موجودی کافی نیست' : 'Insufficient balance',
      'not_found' => fa ? 'پیدا نشد' : 'Not found',
      'tournament_room' => fa ? 'اتاق تورنمنت — از ابزار بازی‌های تورنمنت استفاده کن' : 'Tournament room — use the match tools',
      'network' => fa ? 'اتصال برقرار نیست' : 'No connection',
      null => fa ? 'بارگیری از سرور ممکن نشد. اتصال را بررسی کن.' : 'Could not load from the server. Check your connection.',
      _ => e,
    };
