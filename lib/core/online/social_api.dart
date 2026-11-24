import 'package:supabase_flutter/supabase_flutter.dart';

import 'online_service.dart';

/// A real ANIX / NEXORA user (public profile row / `_nx_user_card`).
class NxUser {
  const NxUser({
    required this.id,
    required this.username,
    this.displayName,
    this.avatar,
    this.avatarUrl,
    this.level = 1,
    this.xp = 0,
    this.onlineAt,
    this.bio,
    this.isPrivate = false,
    this.isFollowing = false,
    this.followsMe = false,
    this.isPending = false,
  });

  final String id;
  final String username;
  final String? displayName;
  final String? avatar;
  final String? avatarUrl;
  final int level;
  final int xp;
  final DateTime? onlineAt;
  final String? bio;
  final bool isPrivate;
  final bool isFollowing;
  final bool followsMe;
  final bool isPending;

  bool get isOnlineNow => onlineAt != null && DateTime.now().toUtc().difference(onlineAt!.toUtc()).inMinutes < 3;

  NxUser copyWith({
    bool? isFollowing,
    bool? isPending,
  }) =>
      NxUser(
        id: id,
        username: username,
        displayName: displayName,
        avatar: avatar,
        avatarUrl: avatarUrl,
        level: level,
        xp: xp,
        onlineAt: onlineAt,
        bio: bio,
        isPrivate: isPrivate,
        isFollowing: isFollowing ?? this.isFollowing,
        followsMe: followsMe,
        isPending: isPending ?? this.isPending,
      );

  static NxUser fromRow(Map<String, dynamic> r) {
    final String? url = r['avatar_url'] as String?;
    return NxUser(
      id: '${r['id']}',
      username: '${r['username'] ?? 'Pilot'}',
      displayName: r['display_name'] as String?,
      avatar: r['avatar'] as String?,
      avatarUrl: (url != null && url.isNotEmpty) ? url : null,
      level: (r['level'] as num?)?.toInt() ?? 1,
      xp: (r['xp'] as num?)?.toInt() ?? 0,
      onlineAt: DateTime.tryParse('${r['online_at'] ?? r['last_active'] ?? ''}'),
      bio: r['bio'] as String?,
      isPrivate: r['is_private'] == true,
      isFollowing: r['is_following'] == true,
      followsMe: r['follows_me'] == true,
      isPending: r['is_pending'] == true,
    );
  }
}

class FriendRequest {
  const FriendRequest({required this.from, required this.to, required this.user, required this.incoming});
  final String from;
  final String to;
  final NxUser user;
  final bool incoming;
}

/// Friends, follows, profile previews, and explorer directory on the Social Supabase project.
class SocialApi {
  SocialApi(this.c, {String? userId}) : _uid = userId;
  final SupabaseClient c;
  final String? _uid;

  String get me => _uid ?? OnlineService.current?.uid ?? c.auth.currentUser!.id;

  static const String _cols = 'id, username, display_name, avatar, avatar_url, level, xp, online_at, bio, is_private';

  Future<List<NxUser>> friends() async {
    final List<dynamic> mine = await c.from('follows').select('followee').eq('follower', me);
    final List<dynamic> back = await c.from('follows').select('follower').eq('followee', me);
    final Set<String> a = mine.map((dynamic r) => '${(r as Map)['followee']}').toSet();
    final Set<String> b = back.map((dynamic r) => '${(r as Map)['follower']}').toSet();
    final List<String> ids = a.intersection(b).toList();
    if (ids.isEmpty) return <NxUser>[];
    final List<dynamic> rows = await c.from('profiles').select(_cols).inFilter('id', ids);
    final List<NxUser> out = rows
        .map((dynamic r) => NxUser.fromRow(Map<String, dynamic>.from(r as Map)).copyWith(isFollowing: true))
        .toList();
    out.sort((NxUser x, NxUser y) {
      if (x.isOnlineNow != y.isOnlineNow) return x.isOnlineNow ? -1 : 1;
      return x.username.toLowerCase().compareTo(y.username.toLowerCase());
    });
    return out;
  }

  /// People I follow (one-way or mutual).
  Future<List<NxUser>> following() async {
    final List<dynamic> mine = await c.from('follows').select('followee').eq('follower', me);
    final List<String> ids = mine.map((dynamic r) => '${(r as Map)['followee']}').toList();
    if (ids.isEmpty) return <NxUser>[];
    final List<dynamic> rows = await c.from('profiles').select(_cols).inFilter('id', ids);
    return rows
        .map((dynamic r) => NxUser.fromRow(Map<String, dynamic>.from(r as Map)).copyWith(isFollowing: true))
        .toList();
  }

  Future<List<FriendRequest>> requests() async {
    final List<dynamic> rows = await c
        .from('friend_requests')
        .select('from_user, to_user, status')
        .or('from_user.eq.$me,to_user.eq.$me')
        .eq('status', 'pending');
    if (rows.isEmpty) return <FriendRequest>[];
    final Set<String> ids = <String>{};
    for (final dynamic r in rows) {
      final Map<dynamic, dynamic> m = r as Map;
      ids.add('${m['from_user']}');
      ids.add('${m['to_user']}');
    }
    ids.remove(me);
    final Map<String, NxUser> users = await profiles(ids.toList());
    final List<FriendRequest> out = <FriendRequest>[];
    for (final dynamic r in rows) {
      final Map<dynamic, dynamic> m = r as Map;
      final bool incoming = '${m['to_user']}' == me;
      final String other = incoming ? '${m['from_user']}' : '${m['to_user']}';
      final NxUser? u = users[other];
      if (u == null) continue;
      out.add(FriendRequest(from: '${m['from_user']}', to: '${m['to_user']}', user: u, incoming: incoming));
    }
    return out;
  }

  Future<Map<String, NxUser>> profiles(List<String> ids) async {
    if (ids.isEmpty) return <String, NxUser>{};
    final List<dynamic> rows = await c.from('profiles').select(_cols).inFilter('id', ids);
    return <String, NxUser>{
      for (final dynamic r in rows) '${(r as Map)['id']}': NxUser.fromRow(Map<String, dynamic>.from(r)),
    };
  }

  Future<NxUser?> profile(String id) async => (await profiles(<String>[id]))[id];

  /// Rich public profile preview (counts, follow relationship, bio, wins, explorer id).
  Future<Map<String, dynamic>?> socialProfile(String userId) async {
    final dynamic res = await c.rpc('nx_social_profile', params: <String, dynamic>{'p_user': userId});
    if (res is Map) return Map<String, dynamic>.from(res);
    return null;
  }

  /// Follow / unfollow a user via `nx_social_toggle_follow` (private-account & notification aware).
  /// Returns the updated `nx_social_profile` JSON map.
  Future<Map<String, dynamic>?> toggleFollow(String userId, bool follow) async {
    final dynamic res = await c.rpc('nx_social_toggle_follow', params: <String, dynamic>{
      'p_target': userId,
      'p_follow': follow,
    });
    if (res is Map) return Map<String, dynamic>.from(res);
    return null;
  }

  /// Universal directory / search via `nx_social_search` (also works with an empty query to browse explorers).
  Future<List<NxUser>> directory([String q = '', int limit = 30]) async {
    final String clean = q.trim().replaceAll('%', '').replaceAll('@', '');
    try {
      final dynamic res = await c.rpc('nx_social_search', params: <String, dynamic>{
        'p_q': clean,
        'p_limit': limit,
      });
      if (res is List) {
        return res
            .whereType<Map>()
            .map((Map r) => NxUser.fromRow(Map<String, dynamic>.from(r)))
            .toList();
      }
    } catch (_) {
      // Fallback if RPC is not yet available.
    }
    var req = c.from('profiles').select(_cols).neq('id', me);
    if (clean.isNotEmpty) {
      req = req.ilike('username', '%$clean%');
    }
    final List<dynamic> rows = await req.order('online_at', ascending: false).limit(limit);
    return rows.map((dynamic r) => NxUser.fromRow(Map<String, dynamic>.from(r as Map))).toList();
  }

  Future<List<NxUser>> search(String q) async {
    final String t = q.trim();
    if (t.isEmpty) return <NxUser>[];
    return directory(t, 25);
  }

  Future<String> sendRequest(String userId) async => '${await c.rpc('send_friend_request', params: <String, dynamic>{'p_user': userId})}';
  Future<void> respond(String fromUser, bool accept) =>
      c.rpc('respond_friend_request', params: <String, dynamic>{'p_from': fromUser, 'p_accept': accept});
  Future<void> cancelRequest(String userId) => c.rpc('cancel_friend_request', params: <String, dynamic>{'p_user': userId});
  Future<void> removeFriend(String userId) => c.rpc('remove_friend', params: <String, dynamic>{'p_user': userId});
  Future<void> touchPresence() => c.rpc('touch_presence');
}
