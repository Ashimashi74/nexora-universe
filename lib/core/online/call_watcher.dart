import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../backend/backend_gateway.dart';
import '../backend/supabase_backend.dart';
import '../settings/app_settings.dart';
import '../ui2/luxe.dart';
import 'online_service.dart';

/// Rings anywhere in the app when someone starts an Orbit Network call in one of my chats
/// (nx_calls inserts reach only chat members through RLS).
class CallWatcher {
  CallWatcher(this._ref, this._messenger, this._open);

  final WidgetRef _ref;
  final GlobalKey<ScaffoldMessengerState> _messenger;

  /// Opens the call page: (chatId, callId, video, title).
  final void Function(String chatId, String callId, bool video, String title) _open;

  RealtimeChannel? _ch;
  String? _uid;
  final Set<String> _seen = <String>{};

  void sync() {
    final OnlineService o = _ref.read(onlineProvider);
    final String? uid = o.isOnline ? o.uid : null;
    if (uid == _uid) return;
    _detach();
    _uid = uid;
    final SupabaseClient? c = o.client;
    if (uid == null || c == null) return;
    _ch = c
        .channel('nxcall:$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'nx_calls',
          callback: (PostgresChangePayload p) => unawaited(_ring(c, uid, p.newRecord)),
        )
        .subscribe();
  }

  Future<void> _ring(SupabaseClient c, String uid, Map<String, dynamic> r) async {
    final String id = '${r['id']}';
    final String caller = '${r['caller']}';
    if (caller == uid || !_seen.add(id)) return;
    final String chatId = '${r['chat_id']}';
    final bool video = r['video'] == true;
    // Fetch the call grant while the phone rings, so "Answer" goes straight to the LiveKit handshake.
    try {
      final BackendGateway be = _ref.read(backendProvider);
      if (be is SupabaseBackend) be.prefetchLiveKitGrant(chatId, video: video);
    } catch (_) {}
    String who = 'Pilot';
    String title = who;
    try {
      final List<Map<String, dynamic>?> got = await Future.wait<Map<String, dynamic>?>(<Future<Map<String, dynamic>?>>[
        c.from('profiles').select('username').eq('id', caller).maybeSingle(),
        c.from('nx_chats').select('kind, name').eq('id', chatId).maybeSingle(),
      ]);
      final Map<String, dynamic>? p = got[0];
      who = '${p?['username'] ?? 'Pilot'}';
      final Map<String, dynamic>? ch = got[1];
      title = ch == null || ch['kind'] == 'direct' ? who : '${ch['name']}';
    } catch (_) {}
    final bool fa = _ref.read(settingsProvider).isFa;
    final ScaffoldMessengerState? m = _messenger.currentState;
    if (m == null) return;
    // The app's own themed toast (gold panel) keeps its call/videocam glyph and the ANSWER
    // shortcut; an invitation stays up for 30 s instead of the 3 s default.
    luxeToastState(
      m,
      title == who
          ? (fa ? '$who تماس ${video ? 'تصویری' : 'صوتی'} گرفته است' : '$who is calling you (${video ? 'video' : 'voice'})')
          : (fa ? '$who در «$title» تماس شروع کرد' : '$who started a call in "$title"'),
      icon: video ? Icons.videocam_rounded : Icons.call_rounded,
      actionLabel: fa ? 'پاسخ' : 'Answer',
      onAction: () => _open(chatId, id, video, title),
      duration: const Duration(seconds: 30),
    );
  }

  void _detach({bool disposing = false}) {
    final RealtimeChannel? ch = _ch;
    _ch = null;
    if (ch == null) return;
    // On dispose the app's `ref` is already unusable (Riverpod throws), so only unsubscribe the channel itself.
    if (disposing) {
      unawaited(ch.unsubscribe());
      return;
    }
    final SupabaseClient? c = _ref.read(onlineProvider).client;
    if (c != null) unawaited(c.removeChannel(ch));
  }

  void dispose() => _detach(disposing: true);
}
