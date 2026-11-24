import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../online/online_config.dart';
import '../online/online_service.dart';
import '../online/voice_connect.dart';
import 'backend_gateway.dart';

/// Online implementation of [BackendGateway] (Supabase + Edge Functions).
class SupabaseBackend extends BackendGateway {
  SupabaseBackend(this._online);

  final OnlineService _online;

  SupabaseClient? get _c => _online.client;

  @override
  BackendStatus get status => _online.status;

  @override
  Future<bool> signInWithEmailOtp(String email) async {
    final SupabaseClient? c = _c;
    if (c == null) return false;
    try {
      await c.auth.signInWithOtp(email: email.trim(), shouldCreateUser: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> submitXpEvent(String event, {required String idempotencyKey}) async {
    try {
      await _online.rpc('nx_award', <String, dynamic>{'p_event': event, 'p_xp': 0, 'p_coins': 0, 'p_key': idempotencyKey});
    } catch (_) {}
  }

  @override
  Future<Map<String, dynamic>?> submitMove(String gameId, String matchId, Map<String, dynamic> move) async {
    try {
      final dynamic r = await _online.grpc('nx_push_move', <String, dynamic>{
        'p_match': matchId,
        'p_seq': move['seq'],
        'p_kind': move['kind'] ?? 'move',
        'p_move': move['data'] ?? move,
        'p_hash': move['hash'],
      });
      return r is Map ? Map<String, dynamic>.from(r) : null;
    } catch (_) {
      return null;
    }
  }

  /// Short-lived LiveKit token from the `nx-call-token` Edge Function (Orbit Network calls).
  @override
  Future<String?> liveKitToken(String room) async {
    final Map<String, dynamic>? r = await liveKitGrant(room);
    return r?['token'] as String?;
  }

  /// Grant cache key: per signed-in user, so switching accounts never reuses someone else's token.
  String? _voiceKey(String kind, String id) {
    final String? uid = _c?.auth.currentUser?.id;
    return uid == null ? null : '$uid|$kind|$id';
  }

  Future<Map<String, dynamic>?> _cachedGrant(String kind, String id, bool fresh,
      Future<Map<String, dynamic>?> Function() fetch) {
    final String? k = _voiceKey(kind, id);
    if (k == null) return fetch();
    if (fresh) VoiceGrantCache.instance.invalidate(k);
    return VoiceGrantCache.instance.get(k, fetch);
  }

  /// Orbit Network call grant. Cached for most of its 15 min life, so a call opened right after [prefetch]
  /// (chat page open / incoming ring) skips the Edge Function round-trip entirely.
  Future<Map<String, dynamic>?> liveKitGrant(String room, {bool video = false, bool fresh = false}) =>
      _cachedGrant('call${video ? 'v' : ''}', room, fresh, () => _invoke(<String, dynamic>{'room': room, 'video': video}));

  /// Warms the voice grant for a chat in the background (no-op offline).
  void prefetchLiveKitGrant(String room, {bool video = false}) {
    if (_c?.auth.currentSession == null) return;
    unawaited(liveKitGrant(room, video: video).then((_) {}, onError: (Object _) {}));
  }

  /// Forget a cached grant (role changed, token rejected).
  void invalidateLiveKitGrant(String kind, String id) {
    final String? k = _voiceKey(kind, id);
    if (k != null) VoiceGrantCache.instance.invalidate(k);
  }

  Future<Map<String, dynamic>?> _invoke(Map<String, dynamic> body, {bool errorMap = false}) async {
    final SupabaseClient? c = _c;
    if (c == null || c.auth.currentSession == null) return null;
    try {
      final FunctionResponse r = await c.functions.invoke('nx-call-token',
          body: body, region: OnlineConfig.functionsRegion.isEmpty ? null : OnlineConfig.functionsRegion);
      final dynamic d = r.data;
      return d is Map ? Map<String, dynamic>.from(d) : null;
    } catch (e) {
      return errorMap ? <String, dynamic>{'error': '$e'} : null;
    }
  }

  /// Voice-stage token for a ROOM (games project room id): speakers publish, listeners only subscribe.
  Future<Map<String, dynamic>?> liveKitRoomGrant(String roomId, {bool fresh = false}) => _cachedGrant(
      'room', roomId, fresh, () => _invoke(<String, dynamic>{'kind': 'room', 'room': roomId}, errorMap: true));

  /// Voice grant for an online GAME room (lobby) or match: `nx-call-token` kind 'game'.
  Future<Map<String, dynamic>?> liveKitGameGrant(String id, {bool match = false, bool fresh = false}) =>
      _cachedGrant('game${match ? 'm' : ''}', id, fresh,
          () => _invoke(<String, dynamic>{'kind': 'game', 'room': id, if (match) 'match': true}, errorMap: true));

  /// ORACLE remote replies through the `nx-oracle` Edge Function (key lives server-side).
  @override
  Future<String?> oracleRemote(String prompt, {required String languageCode}) async {
    final Map<String, dynamic>? r = await oracleInvoke(<String, dynamic>{
      'messages': <Map<String, dynamic>>[
        <String, dynamic>{'role': 'user', 'content': prompt},
      ],
      'ctx': <String, dynamic>{'mode': 'chat', 'lang': languageCode},
    });
    final Object? m = r?['message'];
    return m is Map ? m['content'] as String? : null;
  }

  /// Raw call to `oracle-chat` (JSON in → JSON out). Throws on network/HTTP errors.
  Future<Map<String, dynamic>?> oracleInvoke(Map<String, dynamic> body) async {
    final SupabaseClient? c = _c;
    if (c == null || c.auth.currentSession == null) return null;
    final FunctionResponse r = await c.functions.invoke('nx-oracle', body: body).timeout(const Duration(seconds: 40));
    final dynamic d = r.data;
    return d is Map ? Map<String, dynamic>.from(d) : null;
  }
}
