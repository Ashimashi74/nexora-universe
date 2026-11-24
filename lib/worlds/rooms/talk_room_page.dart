import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/audio/sfx_service.dart';
import '../../core/backend/backend_gateway.dart';
import '../../core/backend/supabase_backend.dart';
import '../../core/online/online_config.dart';
import '../../core/online/online_service.dart';
import '../../core/online/room_capacity.dart';
import '../../core/online/room_voice.dart';
import '../../core/online/voice_connect.dart';
import '../../core/economy/gem_shop.dart';
import '../../core/settings/app_settings.dart';
import '../../core/ui2/anix_kit.dart';
import '../../core/ui2/luxe.dart';
import '../../core/ui2/nx2_widgets.dart';
import '../../core/widgets/user_avatar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../games/finger_soccer/core/bm_data.dart';
import '../../games/finger_soccer/core/bm_engine.dart';
import '../../games/game_registry.dart';
import '../arcade/online/online_match_page.dart';
import '../nova_gallery/ui/nova_follow.dart';

/// A ROOM is a conversation first: a voice stage (LiveKit, unlimited speakers and listeners), a text chat and the
/// member list. Its manager can pick a game, tick the players, and start; picked players choose their team and
/// formation (finger soccer), the manager the field and ball. When the match ends everyone is back in the room.
class TalkRoomPage extends ConsumerStatefulWidget {
  const TalkRoomPage({super.key, required this.roomId});
  final String roomId;

  @override
  ConsumerState<TalkRoomPage> createState() => _TalkRoomPageState();
}

/// Player limits per game inside a room.
///
/// The numbers are not repeated here any more: they come from [capacityOf] (which reads the
/// game registry's online bounds), and the games project mirrors the same table in
/// `nx_game_bounds`. That removes the old drift where this class said carrom 6 (the carrom
/// board is a two-seat duel) and quiz 21 (the quiz engine is 1v1).
class TalkRoomLimits {
  static int maxPlayersFor(String game) => capacityOf(game).max;

  static int minPlayersFor(String game) => capacityOf(game).min;

  static RoomCategory categoryFor(String game) => categoryOf(game);
}

/// v5 finger soccer (owner request 2026-11-20): the room manager swaps Team 1 and Team 2 before the match. Seats
/// alternate sides (0,2,4 = home / team 1; 1,3,5 = away / team 2), so swapping each seat pair (0<->1, 2<->3, 4<->5)
/// moves every player to the other side and keeps their place in the side's turn order. [idsBySeat] is the picked
/// players in seat order; an unpaired last seat (odd count, which can't start anyway) stays where it is.
List<String> fsSwapSides(List<String> idsBySeat) {
  final List<String> out = List<String>.of(idsBySeat);
  for (int i = 0; i + 1 < idsBySeat.length; i += 2) {
    out[i] = idsBySeat[i + 1];
    out[i + 1] = idsBySeat[i];
  }
  return out;
}

class RoomMember {
  RoomMember(this.userId, this.role, this.name, this.avatar, this.muted);
  final String userId, role, name;
  final String? avatar;
  final bool muted;
  bool get isManager => role == 'manager';
  bool get onStage => role == 'manager' || role == 'speaker';
}

class RoomMessage {
  RoomMessage(this.id, this.author, this.text, this.at);
  final String id, author, text;
  final DateTime at;
}

class _TalkRoomPageState extends ConsumerState<TalkRoomPage> {
  /// Finger soccer: a picked player with no room team yet gets the team they last chose in the game's own setup.
  bool _fsTeamSeeded = false;

  SupabaseClient? get _c => ref.read(onlineProvider).games;
  String? get _me => ref.read(onlineProvider).uid;

  Map<String, dynamic>? _room;
  List<RoomMember> _members = <RoomMember>[];

  /// Live capacity of this room (host-set board size + unlimited audience). Recomputed from
  /// every refresh and replaced by the server payload after each manager action.
  RoomCapacity _capacity = RoomCapacity.fallback('finger_soccer');
  bool _capacityBusy = false;
  final Map<String, Map<String, dynamic>> _picked = <String, Map<String, dynamic>>{}; // user -> {seat, prefs}
  final List<RoomMessage> _messages = <RoomMessage>[];
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  RealtimeChannel? _channel;
  Timer? _poll, _ping;
  String? _error;
  bool _joined = false, _inMatch = false, _sending = false;
  String? _lastMatch;
  int _tab = 0; // 0 chat, 1 members, 2 games

  // voice
  lk.Room? _voice;
  lk.EventsListener<lk.RoomEvent>? _voiceEvents;
  bool _voiceBusy = false, _mic = false, _canPublish = false, _speaker = true;
  String? _voiceError;

  RoomMember? get _myMember {
    for (final RoomMember m in _members) {
      if (m.userId == _me) return m;
    }
    return null;
  }

  bool get _isManager => _myMember?.isManager ?? false;
  String get _game => '${_room?['selected_game'] ?? _room?['game'] ?? 'finger_soccer'}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_enter()));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _ping?.cancel();
    final RealtimeChannel? ch = _channel;
    if (ch != null) unawaited(_c?.removeChannel(ch));
    final lk.Room? v = _voice;
    final lk.EventsListener<lk.RoomEvent>? vev = _voiceEvents;
    _voice = null;
    _voiceEvents = null;
    if (v != null) unawaited(disposeVoice(v, vev));
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _enter() async {
    final OnlineService o = ref.read(onlineProvider);
    if (!o.isOnline) await o.ensureSession();
    final SupabaseClient? c = _c;
    if (c == null || o.uid == null) {
      setState(() => _error = 'offline');
      return;
    }
    try {
      await o.gamesHello();
      await c.rpc('nx_room_join', params: <String, dynamic>{'p_room': widget.roomId, 'p_role': 'speaker'});
      _joined = true;
      // Voice joins instantly later: fetch the 15 min stage grant now, in the background.
      final BackendGateway be = ref.read(backendProvider);
      if (be is SupabaseBackend) unawaited(be.liveKitRoomGrant(widget.roomId).then((_) {}, onError: (Object _) {}));
      await Future.wait(<Future<void>>[_refresh(), _loadMessages()]);
      _subscribe();
      _poll = Timer.periodic(const Duration(seconds: 6), (_) => unawaited(_refresh()));
      _ping = Timer.periodic(const Duration(seconds: 60),
          (_) => unawaited(c.rpc('nx_room_ping', params: <String, dynamic>{'p_room': widget.roomId}).then((_) {}, onError: (Object _) {})));
    } catch (e) {
      if (mounted) setState(() => _error = _clean(e));
    }
  }

  String _clean(Object e) {
    final String s = e is PostgrestException ? e.message : '$e';
    return s.replaceFirst('Exception: ', '');
  }

  void _subscribe() {
    final SupabaseClient? c = _c;
    if (c == null) return;
    _channel = c
        .channel('room-${widget.roomId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'nx_room_messages',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'room_id', value: widget.roomId),
          callback: (PostgresChangePayload p) => _addMessage(p.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'nx_room_members',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'room_id', value: widget.roomId),
          callback: (_) => unawaited(_refresh()),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'nx_rooms',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: widget.roomId),
          callback: (_) => unawaited(_refresh()),
        )
        .subscribe();
  }

  void _addMessage(Map<String, dynamic> r) {
    final String id = '${r['id']}';
    if (r['deleted'] == true || _messages.any((RoomMessage m) => m.id == id)) return;
    if (_joined && '${r['author']}' != _me && _messages.isNotEmpty) NxSfx.instance.play('chat', gain: 0.7);
    _messages.add(RoomMessage(id, '${r['author']}', '${r['text']}',
        DateTime.tryParse('${r['created_at']}')?.toLocal() ?? DateTime.now()));
    _messages.sort((RoomMessage a, RoomMessage b) => a.at.compareTo(b.at));
    if (mounted) setState(() {});
    _toBottom();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _loadMessages() async {
    final SupabaseClient? c = _c;
    if (c == null) return;
    final List<dynamic> rows = await c
        .from('nx_room_messages')
        .select('id, author, text, created_at, deleted')
        .eq('room_id', widget.roomId)
        .order('created_at', ascending: false)
        .limit(100);
    for (final dynamic r in rows.reversed) {
      _addMessage(Map<String, dynamic>.from(r as Map));
    }
  }

  Future<void> _refresh() async {
    final SupabaseClient? c = _c;
    if (c == null || !_joined) return;
    try {
      final Map<String, dynamic>? room = await c
          .from('nx_rooms')
          .select('id, code, title, game, selected_game, status, match_id, host, settings, kind, seats, join_locked')
          .eq('id', widget.roomId)
          .maybeSingle();
      final List<dynamic> mem = await c
          .from('nx_room_members')
          .select('user_id, role, muted, joined_at, profiles(username, avatar)')
          .eq('room_id', widget.roomId)
          .order('joined_at');
      final List<dynamic> gp = await c
          .from('nx_room_game_players')
          .select('user_id, seat, prefs, ready')
          .eq('room_id', widget.roomId)
          .order('seat');
      if (!mounted) return;
      final int before = _members.length;
      if (before > 0 && mem.length != before) NxSfx.instance.play(mem.length > before ? 'join' : 'leave', gain: 0.6);
      setState(() {
        _room = room;
        _members = mem.map((dynamic r) {
          final Map<String, dynamic> m = Map<String, dynamic>.from(r as Map);
          final dynamic p = m['profiles'];
          return RoomMember('${m['user_id']}', '${m['role']}', p is Map ? '${p['username'] ?? 'Pilot'}' : 'Pilot',
              p is Map ? p['avatar'] as String? : null, m['muted'] == true);
        }).toList();
        _picked
          ..clear()
          ..addAll(<String, Map<String, dynamic>>{
            for (final dynamic r in gp) '${(r as Map)['user_id']}': Map<String, dynamic>.from(r),
          });
        _capacity = _capacityFromRoom();
      });
      await _syncVoiceRole();
      _maybeOpenMatch();
    } catch (_) {}
  }

  /// Local mirror of `nx_room_capacity` from the room row we already poll (no extra request).
  RoomCapacity _capacityFromRoom() {
    final Map<String, dynamic>? r = _room;
    return RoomCapacity.fallback(
      _game,
      capacity: (r?['seats'] as num?)?.toInt(),
      selected: _picked.length,
      audience: _members.length,
      locked: r?['join_locked'] == true,
      isManager: _isManager,
      status: '${r?['status'] ?? 'lobby'}',
    );
  }

  /// Manager action that returns the fresh `nx_room_capacity` payload. The server re-validates
  /// every rule, so a stale client can never widen a limit. Returns false when the server
  /// refused (or the call failed), so a caller never announces a success that did not happen.
  Future<bool> _capacityAction(String fn, Map<String, dynamic> params) async {
    final SupabaseClient? c = _c;
    if (c == null || _capacityBusy) return false;
    setState(() => _capacityBusy = true);
    try {
      final dynamic r = await c.rpc(fn, params: <String, dynamic>{'p_room': widget.roomId, ...params});
      if (mounted && r is Map) setState(() => _capacity = RoomCapacity.fromRpc(Map<String, dynamic>.from(r)));
      await _refresh();
      return true;
    } catch (e) {
      _snack(_clean(e));
      await _refresh();
      return false;
    } finally {
      if (mounted) setState(() => _capacityBusy = false);
    }
  }

  Future<void> _setCapacity(int n) async {
    final RoomRuleError? err = _capacity.checkCapacity(n);
    if (err != null) {
      _snack(err.message(context.isFa, value: err == RoomRuleError.aboveMaximum ? _capacity.maxPlayers : _capacity.minPlayers));
      return;
    }
    await _capacityAction('nx_room_set_capacity', <String, dynamic>{'p_capacity': n});
  }

  Future<void> _setLocked(bool locked) async {
    await _capacityAction('nx_room_set_locked', <String, dynamic>{'p_locked': locked});
  }

  /// Hands the manager role to [m] (server re-checks that we are the manager). The old host
  /// stays in the room as a speaker, so the conversation is not interrupted.
  Future<void> _transferHost(RoomMember m) async {
    final bool? ok = await showLuxeConfirm(
      context,
      title: context.isFa ? 'مدیر اتاق را به ${m.name} بدهی؟' : 'Make ${m.name} the room manager?',
      message: context.isFa
          ? '${m.name} می‌تواند ظرفیت، بازیکن‌ها و شروع بازی را کنترل کند. تو در اتاق می‌مانی.'
          : '${m.name} will control capacity, the line-up and starting matches. You stay in the room.',
      confirm: context.isFa ? 'واگذاری' : 'Transfer',
    );
    if (ok != true) return;
    // Only announce the hand-over when the server actually did it: a refusal (not the manager,
    // member gone, function missing) already showed why through _capacityAction's own toast.
    final bool done =
        await _capacityAction('nx_room_transfer_host', <String, dynamic>{'p_user': m.userId});
    if (!done || !mounted) return;
    luxeToast(context, context.tx('مدیر اتاق تغییر کرد', 'The room has a new manager'));
  }

  /// Ends the room for everyone (server: manager only, refused while a match runs).
  Future<void> _closeRoom() async {
    final bool? ok = await showLuxeConfirm(
      context,
      title: context.tx('اتاق بسته شود؟', 'Close this room?'),
      message: context.tx('همه از اتاق خارج می‌شوند و ورود جدید ممکن نیست.', 'Everyone leaves and no one can join.'),
      confirm: context.tx('بستن اتاق', 'Close room'),
      danger: true,
    );
    if (ok != true) return;
    try {
      await _c?.rpc('nx_room_close', params: <String, dynamic>{'p_room': widget.roomId});
    } catch (e) {
      _snack(_clean(e));
      return;
    }
    await _leave();
  }

  Future<void> _kick(RoomMember m) async {
    final bool? ok = await showLuxeConfirm(
      context,
      title: context.isFa ? 'حذف ${m.name} از اتاق؟' : 'Remove ${m.name} from the room?',
      message: context.isFa
          ? 'این بازیکن از اتاق و از لیست بازیکنان حذف می‌شود و می‌تواند دوباره وارد شود (اگر اتاق باز باشد).'
          : 'They leave the room and the line-up. They can join again while the room is open.',
      confirm: context.isFa ? 'حذف' : 'Remove',
      danger: true,
    );
    if (ok != true) return;
    await _capacityAction('nx_room_kick', <String, dynamic>{'p_user': m.userId});
  }

  void _maybeOpenMatch() {
    final Map<String, dynamic>? r = _room;
    final String? mid = r?['match_id'] as String?;
    if (r == null || r['status'] != 'playing' || mid == null || _inMatch || mid == _lastMatch) return;
    if (!_picked.containsKey(_me)) return;
    unawaited(_openMatch(mid));
  }

  Future<void> _openMatch(String matchId) async {
    _inMatch = true;
    NxSfx.instance.play('ready');
    _lastMatch = matchId;
    final bool micWas = _mic;
    if (micWas) await _setMic(false);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => OnlineMatchPage(matchId: matchId, gameId: _game),
    ));
    _inMatch = false;
    if (micWas) await _setMic(true);
    if (mounted) await _refresh();
  }

  // ------------------------------------------------------------------ chat
  Future<void> _send() async {
    final String t = _input.text.trim();
    final SupabaseClient? c = _c;
    if (t.isEmpty || c == null || _sending) return;
    setState(() => _sending = true);
    try {
      final dynamic r = await c.rpc('nx_room_send_message', params: <String, dynamic>{'p_room': widget.roomId, 'p_text': t});
      _input.clear();
      if (r is Map) _addMessage(Map<String, dynamic>.from(r));
    } catch (e) {
      _snack(_clean(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _snack(String s) {
    if (!mounted) return;
    luxeToast(context, s);
  }

  // ------------------------------------------------------------------ voice
  Future<void> _joinVoice() async {
    final BackendGateway be = ref.read(backendProvider);
    if (be is! SupabaseBackend || _voiceBusy || _voice != null) return;
    setState(() {
      _voiceBusy = true;
      _voiceError = null;
    });
    final lk.Room room = lk.Room(roomOptions: voiceRoomOptions());
    warmVoice(room, OnlineConfig.liveKitUrl);
    lk.EventsListener<lk.RoomEvent>? ev;
    bool ok = false;
    try {
      final Map<String, dynamic>? g = await be.liveKitRoomGrant(widget.roomId);
      final String? token = g?['token'] as String?;
      if (token == null) throw StateError('${g?['error'] ?? 'no_token'}');
      _canPublish = g?['canPublish'] == true;
      room.addListener(_onVoice);
      ev = room.createListener();
      ev
        ..on<lk.TrackSubscribedEvent>((lk.TrackSubscribedEvent _) async {
          if (!_speaker) await setRoomIncomingAudio(room, false);
        })
        ..on<lk.RoomDisconnectedEvent>((lk.RoomDisconnectedEvent e) {
          // SDK reconnects already failed: drop the room (no auto-rejoin loop); the user can tap join again.
          if (identical(_voice, room)) unawaited(_leaveVoice());
        });
      // Listeners join muted; speakers publish the mic only when they unmute (unchanged behaviour).
      await connectVoice(room, '${g?['url'] ?? OnlineConfig.liveKitUrl}', token);
      _voice = room;
      _voiceEvents = ev;
      ok = true;
      unawaited(setRoomIncomingAudio(room, _speaker));
    } catch (e) {
      be.invalidateLiveKitGrant('room', widget.roomId);
      _voiceError = '$e';
    } finally {
      if (!ok) {
        room.removeListener(_onVoice);
        unawaited(disposeVoice(room, ev));
      }
      if (mounted) setState(() => _voiceBusy = false);
    }
  }

  Future<void> _leaveVoice() async {
    final lk.Room? v = _voice;
    final lk.EventsListener<lk.RoomEvent>? ev = _voiceEvents;
    _voice = null;
    _voiceEvents = null;
    _mic = false;
    if (v != null) {
      v.removeListener(_onVoice);
      await disposeVoice(v, ev);
    }
    if (mounted) setState(() {});
  }

  void _onVoice() {
    if (mounted) setState(() {});
  }

  Future<void> _setSpeaker(bool on) async {
    _speaker = on;
    final lk.Room? v = _voice;
    if (v != null) await setRoomIncomingAudio(v, on);
    if (mounted) setState(() {});
  }

  Future<void> _setMic(bool on) async {
    final lk.Room? v = _voice;
    if (v == null) return;
    if (on && !_canPublish) {
      _snack(context.tx('شنونده هستی؛ مدیر اتاق می‌تواند تو را سخنران کند.', 'You are a listener; the room manager can make you a speaker.'));
      return;
    }
    try {
      await v.localParticipant?.setMicrophoneEnabled(on);
      _mic = on;
    } catch (e) {
      _snack('$e');
    }
    if (mounted) setState(() {});
  }

  /// When the manager changes my role (speaker/listener/muted) the voice grant changes: reconnect with the new one.
  Future<void> _syncVoiceRole() async {
    final RoomMember? me = _myMember;
    if (me != null) {
      // A role / mute change makes any prefetched grant stale.
      final String seen = '${me.role}:${me.muted}';
      if (_seenRole != null && seen != _seenRole) {
        final BackendGateway be = ref.read(backendProvider);
        if (be is SupabaseBackend) be.invalidateLiveKitGrant('room', widget.roomId);
      }
      _seenRole = seen;
    }
    if (_voice == null || me == null || _roleSyncing) return;
    final bool should = me.onStage && !me.muted;
    if (should == _canPublish) return;
    // At most one re-grant per role change (the 6 s poll must not turn a server/client mismatch into a loop).
    final String sig = '${me.role}:${me.muted}';
    if (sig == _lastRoleSync) return;
    _lastRoleSync = sig;
    _roleSyncing = true;
    try {
      final BackendGateway be = ref.read(backendProvider);
      if (be is SupabaseBackend) be.invalidateLiveKitGrant('room', widget.roomId);
      await _leaveVoice();
      await _joinVoice();
    } finally {
      _roleSyncing = false;
    }
  }

  bool _roleSyncing = false;
  String? _lastRoleSync, _seenRole;

  bool _speaking(String userId) {
    final lk.Room? v = _voice;
    if (v == null) return false;
    if (userId == _me) return v.localParticipant?.isSpeaking ?? false;
    for (final lk.RemoteParticipant p in v.remoteParticipants.values) {
      if (p.identity == userId) return p.isSpeaking;
    }
    return false;
  }

  bool _inVoice(String userId) {
    final lk.Room? v = _voice;
    if (v == null) return false;
    if (userId == _me) return true;
    return v.remoteParticipants.values.any((lk.RemoteParticipant p) => p.identity == userId);
  }

  // ------------------------------------------------------------------ manager actions
  Future<void> _rpc(String fn, Map<String, dynamic> params) async {
    try {
      await _c!.rpc(fn, params: params);
      await _refresh();
    } catch (e) {
      _snack(_clean(e));
    }
  }

  Future<void> _leave() async {
    await _leaveVoice();
    try {
      await _c?.rpc('nx_room_leave', params: <String, dynamic>{'p_room': widget.roomId});
    } catch (_) {}
    if (mounted) Navigator.of(context).maybePop();
  }

  // ------------------------------------------------------------------ UI
  @override
  Widget build(BuildContext context) {
    final String title = '${_room?['title'] ?? context.tx('اتاق', 'Room')}';
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (didPop) {
          final lk.Room? v = _voice;
          _voice = null;
          if (v != null) unawaited(v.disconnect().then((_) => v.dispose()));
        }
      },
      child: Scaffold(
        backgroundColor: Luxe.bg,
        body: Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
                image: AssetImage(AnixAssets.sceneVoiceStage),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(Color(0xE0070306), BlendMode.darken)),
          ),
          child: SafeArea(
            child: Column(children: <Widget>[
              LuxeHeader(
                title: title,
                subtitle: _headerSubtitle(),
                trailing: <Widget>[
                  if (_capacity.canManage)
                    LuxeIconButton(
                      icon: _capacity.locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                      tooltip: _capacity.locked
                          ? context.tx('ورود بسته است — باز کن', 'Admission closed — open it')
                          : context.tx('ورود آزاد است — ببند', 'Admission open — close it'),
                      color: _capacity.locked ? Nx2.danger : Luxe.gold,
                      onTap: _capacityBusy ? null : () => unawaited(_setLocked(!_capacity.locked)),
                    ),
                  if (_capacity.canManage)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.tune_rounded, color: Luxe.gold2),
                      color: Nx2.night,
                      tooltip: context.tx('مدیریت اتاق', 'Room controls'),
                      onSelected: (String a) {
                        if (a == 'close') unawaited(_closeRoom());
                      },
                      itemBuilder: (_) => <PopupMenuEntry<String>>[
                        PopupMenuItem<String>(
                          value: 'close',
                          child: Text(context.tx('بستن اتاق', 'Close the room'),
                              style: const TextStyle(color: Nx2.danger)),
                        ),
                      ],
                    ),
                  const SizedBox(width: 8),
                  LuxeIconButton(
                    icon: Icons.logout_rounded,
                    tooltip: context.tx('خروج از اتاق', 'Leave room'),
                    onTap: _leave,
                  ),
                ],
              ),
              Expanded(
                child: _error != null
                    ? _errorView()
                    : _room == null
                        ? LuxeLoading(label: context.tx('در حال ورود به اتاق…', 'Joining the room…'))
                        : Column(children: <Widget>[
                            _stage(),
                            _tabs(),
                            Expanded(
                              child: switch (_tab) {
                                1 => _membersList(),
                                2 => _gamesPanel(),
                                _ => _chat(),
                              },
                            ),
                          ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  /// Code · everyone in the room · players on the board (capacity) · admission state.
  String _headerSubtitle() {
    final Map<String, dynamic>? r = _room;
    if (r == null) return '';
    final String code = '${context.tx('کد', 'CODE')} ${r['code']}';
    final String here = '${_capacity.audience} ${context.tx('نفر', 'here')}';
    final String board = '${_capacity.selected}/${_capacity.capacity} ${context.tx('بازیکن', 'players')}';
    final String lock = _capacity.locked ? ' · ${context.tx('بسته', 'closed')}' : '';
    return '$code · $here · $board$lock';
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: LuxeEmpty(
            icon: Icons.wifi_off_rounded,
            title: _error == 'offline'
                ? context.tx('برای اتاق‌ها باید وارد حساب شوی.', 'Sign in to use rooms.')
                : (_error == 'room locked'
                    ? context.tx('ورود به این اتاق بسته است.', 'This room is not taking new people.')
                    : _error!),
            message: context.tx('اگر اتصال قطع شد، دوباره امتحان کن.', 'Check your connection and try again.'),
            action: LuxeButton(
              label: context.tx('تلاش دوباره', 'RETRY'),
              icon: Icons.refresh_rounded,
              height: 44,
              expand: false,
              onTap: _enter,
            ),
          ),
        ),
      );

  Widget _stage() {
    final List<RoomMember> stage = _members.where((RoomMember m) => m.onStage).toList();
    final bool live = _voice != null;
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: Nx2.night.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Luxe.line),
      ),
      child: Column(children: <Widget>[
        Row(children: <Widget>[
          Image.asset(AnixAssets.icon('mic'), width: 24, height: 24),
          const SizedBox(width: 6),
          Text(context.tx('صحنه‌ی صدا', 'Voice stage'),
              style: const TextStyle(color: Nx2.text, fontWeight: FontWeight.w900)),
          const Spacer(),
          // Mic (mute / unmute) and speaker (on / off) are always visible with their state; using either while
          // outside the call joins it first.
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: _mic
                ? context.tx('میکروفون روشن (بی‌صدا کن)', 'Mic on (tap to mute)')
                : context.tx('میکروفون خاموش', 'Mic muted'),
            onPressed: _voiceBusy
                ? null
                : () async {
                    if (!live) await _joinVoice();
                    await _setMic(!_mic);
                  },
            icon: Icon(_mic ? Icons.mic_rounded : Icons.mic_off_rounded, color: _mic ? Nx2.success : Nx2.danger),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: _speaker ? context.tx('بلندگو روشن', 'Speaker on') : context.tx('بلندگو خاموش', 'Speaker off'),
            onPressed: () => _setSpeaker(!_speaker),
            icon: Icon(_speaker ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                color: _speaker ? Nx2.success : Nx2.danger),
          ),
          TextButton.icon(
            onPressed: _voiceBusy ? null : (live ? _leaveVoice : _joinVoice),
            icon: Icon(live ? Icons.call_end_rounded : Icons.headset_mic_rounded,
                color: live ? Nx2.danger : Nx2.cyan, size: 18),
            label: Text(
                _voiceBusy
                    ? '…'
                    : live
                        ? context.tx('قطع صدا', 'Leave voice')
                        : context.tx('ورود به صدا', 'Join voice'),
                style: TextStyle(color: live ? Nx2.danger : Nx2.cyan, fontWeight: FontWeight.w800)),
          ),
        ]),
        if (_voiceError != null)
          Text(context.tx('اتصال صدا ممکن نشد', 'Voice could not connect'),
              style: const TextStyle(color: Nx2.danger, fontSize: 11)),
        SizedBox(
          height: 70,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: stage.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, int i) {
              final RoomMember m = stage[i];
              final bool talking = _speaking(m.userId);
              return SizedBox(
                width: 56,
                child: Column(children: <Widget>[
                  Stack(clipBehavior: Clip.none, children: <Widget>[
                    NxUserAvatar(
                      avatar: m.avatar,
                      name: m.name,
                      size: 44,
                      ring: talking ? Nx2.success : (m.isManager ? Nx2.gold : (_inVoice(m.userId) ? Nx2.cyan : null)),
                    ),
                    if (m.muted)
                      const Positioned(right: -2, bottom: -2, child: Icon(Icons.mic_off_rounded, size: 14, color: Nx2.danger)),
                  ]),
                  const SizedBox(height: 3),
                  Text(m.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Nx2.text, fontSize: 10, fontWeight: FontWeight.w700)),
                ]),
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _tabs() {
    Widget tab(int i, String icon, String label) {
      final bool on = _tab == i;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _tab = i),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: on ? Nx2.magenta : Colors.transparent, width: 3)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
              Image.asset(AnixAssets.icon(icon), width: 22, height: 22),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(color: on ? Nx2.text : Nx2.muted, fontWeight: FontWeight.w800, fontSize: 13)),
            ]),
          ),
        ),
      );
    }

    return Row(children: <Widget>[
      tab(0, 'chat', context.tx('گفتگو', 'Chat')),
      tab(1, 'friends', '${context.tx('اعضا', 'Members')} ${_members.length}'),
      tab(2, 'gamepad', context.tx('بازی‌ها', 'Games')),
    ]);
  }

  Widget _chat() {
    final Map<String, RoomMember> byId = <String, RoomMember>{for (final RoomMember m in _members) m.userId: m};
    return Column(children: <Widget>[
      Expanded(
        child: _messages.isEmpty
            ? Center(
                child: Text(context.tx('اولین پیام را بفرست 👋', 'Say hi 👋'),
                    style: const TextStyle(color: Nx2.muted)))
            : ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                itemCount: _messages.length,
                itemBuilder: (_, int i) {
                  final RoomMessage m = _messages[i];
                  final bool mine = m.author == _me;
                  final RoomMember? who = byId[m.author];
                  final String name = who?.name ?? 'Pilot';
                  final Widget bubble = Flexible(
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      padding: const EdgeInsets.fromLTRB(10, 6, 10, 7),
                      decoration: BoxDecoration(
                        color: mine ? Nx2.goldDeep.withValues(alpha: 0.45) : Nx2.night.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: mine ? Luxe.gold.withValues(alpha: 0.35) : Luxe.line),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                        if (!mine)
                          Text(name,
                              style: const TextStyle(color: Nx2.cyan, fontSize: 11, fontWeight: FontWeight.w800)),
                        Text(m.text, style: const TextStyle(color: Nx2.text, fontSize: 14)),
                        Text(
                            '${m.at.hour.toString().padLeft(2, '0')}:${m.at.minute.toString().padLeft(2, '0')}',
                            style: const TextStyle(color: Nx2.muted, fontSize: 9)),
                      ]),
                    ),
                  );
                  return Row(
                    mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      if (!mine) ...<Widget>[NxUserAvatar(avatar: who?.avatar, name: name, size: 26), const SizedBox(width: 6)],
                      bubble,
                    ],
                  );
                },
              ),
      ),
      SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
          color: Nx2.night.withValues(alpha: 0.92),
          child: Row(children: <Widget>[
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                maxLength: 4000,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                style: const TextStyle(color: Nx2.text),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: context.tx('پیام…', 'Message…'),
                  hintStyle: const TextStyle(color: Nx2.muted),
                  filled: true,
                  fillColor: Nx2.plum.withValues(alpha: 0.7),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                ),
              ),
            ),
            IconButton(
              onPressed: _sending ? null : _send,
              icon: const Icon(Icons.send_rounded, color: Nx2.magenta),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _membersList() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
      children: <Widget>[
        LuxeSection(
          title: context.tx('اعضا', 'Members'),
          top: LuxeSpace.sm,
          trailing: LuxeStat(
            label: '${_members.length}',
            icon: Icons.people_alt_rounded,
          ),
        ),
        for (final RoomMember m in _members)
          LuxeListRow(
            title: m.name + (m.userId == _me ? context.tx(' (تو)', ' (you)') : ''),
            subtitle: switch (m.role) {
                  'manager' => context.tx('مدیر اتاق', 'Room manager'),
                  'speaker' => context.tx('سخنران', 'Speaker'),
                  _ => context.tx('شنونده', 'Listener'),
                } +
                (m.muted ? context.tx(' · بی‌صدا', ' · muted') : '') +
                (_picked.containsKey(m.userId) ? context.tx(' · بازیکن', ' · playing') : ''),
            leading: NxUserAvatar(avatar: m.avatar, name: m.name, size: 34,
                ring: _speaking(m.userId) ? Nx2.success : (m.isManager ? Nx2.gold : null)),
            selected: m.userId == _me,
            onTap: () => _showMember(m),
            trailing: _isManager && m.userId != _me
                ? PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded, color: Luxe.ink),
                    color: Nx2.night,
                    onSelected: (String a) {
                      switch (a) {
                        case 'speaker':
                        case 'spectator':
                          unawaited(_rpc('nx_room_set_role',
                              <String, dynamic>{'p_room': widget.roomId, 'p_user': m.userId, 'p_role': a}));
                        case 'mute':
                          unawaited(_rpc('nx_room_set_muted',
                              <String, dynamic>{'p_room': widget.roomId, 'p_user': m.userId, 'p_muted': !m.muted}));
                        case 'host':
                          unawaited(_transferHost(m));
                        case 'kick':
                          // Server re-checks that the caller is the manager and that the room has not started.
                          unawaited(_kick(m));
                      }
                    },
                    itemBuilder: (_) => <PopupMenuEntry<String>>[
                      if (m.role != 'speaker')
                        PopupMenuItem<String>(value: 'speaker', child: Text(context.tx('سخنران کن', 'Make speaker'))),
                      if (m.role != 'spectator')
                        PopupMenuItem<String>(value: 'spectator', child: Text(context.tx('شنونده کن', 'Make listener'))),
                      PopupMenuItem<String>(
                          value: 'mute', child: Text(m.muted ? context.tx('باصدا کن', 'Unmute') : context.tx('بی‌صدا کن', 'Mute'))),
                      PopupMenuDivider(),
                      PopupMenuItem<String>(
                          value: 'host',
                          child: Text(context.tx('مدیر اتاق کن', 'Make room manager'))),
                      PopupMenuItem<String>(
                          value: 'kick',
                          child: Text(context.tx('حذف از اتاق', 'Remove from room'),
                              style: const TextStyle(color: Nx2.danger))),
                    ],
                  )
                : null,
          ),
      ],
    );
  }

  /// Member card: big avatar, name, follower / following counts and a follow button (shared follows table).
  void _showMember(RoomMember m) {
    showLuxeSheet<void>(
      context,
      builder: (BuildContext ctx) => Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        NxUserAvatar(avatar: m.avatar, name: m.name, size: 84, ring: m.isManager ? Nx2.gold : Nx2.goldDeep),
        const SizedBox(height: 8),
        Text(m.name, style: const TextStyle(color: Luxe.ink, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        NovaFollowBar(uid: m.userId, self: m.userId == _me),
        if (m.userId != _me)
          TextButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              final String? reason = await showLuxePrompt(
                context,
                title: context.tx('گزارش ${m.name}', 'Report ${m.name}'),
                hint: context.tx('چه اتفاقی افتاد؟', 'What happened?'),
                confirm: context.tx('ارسال', 'Send'),
                maxLength: 300,
              );
              if (reason != null && reason.trim().length >= 2) {
                try {
                  await ref.read(onlineProvider).rpc('nx_report_user', <String, dynamic>{
                    'p_target': m.userId, 'p_kind': 'room', 'p_target_id': widget.roomId, 'p_reason': reason.trim(),
                  });
                  if (mounted) {
                    luxeToast(context, context.tx('گزارش برای مدیران فرستاده شد', 'Report sent to the admins'));
                  }
                } catch (_) {}
              }
            },
            icon: const Icon(Icons.flag_rounded, color: Luxe.mute, size: 18),
            label: Text(context.tx('گزارش تخلف', 'Report'), style: const TextStyle(color: Luxe.mute)),
          ),
      ]),
    );
  }

  // ------------------------------------------------------------------ games
  Widget _gamesPanel() {
    final GameInfo? g = gameById(_game);
    final bool playing = _room?['status'] == 'playing';
    final bool iAmPicked = _picked.containsKey(_me);
    final RoomCapacity cap = _capacity.copyWith(
        selected: _picked.length, audience: _members.length, isManager: _isManager, status: '${_room?['status'] ?? 'lobby'}');
    final int maxP = cap.capacity, minP = cap.minPlayers;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      children: <Widget>[
        _capacityCard(cap),
        const SizedBox(height: 10),
        Nx2Panel(
          padding: const EdgeInsets.all(12),
          child: Row(children: <Widget>[
            Image.asset('assets/arcade/pedestals/$_game.webp', width: 64, height: 64,
                errorBuilder: (_, __, ___) => Image.asset(AnixAssets.icon('gamepad'), width: 48)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(g == null ? _game : context.tx(g.nameFa, g.nameEn),
                    style: const TextStyle(color: Nx2.text, fontWeight: FontWeight.w900, fontSize: 16)),
                Text(
                    _game == 'finger_soccer'
                        ? context.tx('۱ به ۱، ۲ به ۲ یا ۳ به ۳ — نوبت‌ها در هر تیم می‌چرخد',
                            '1v1, 2v2 or 3v3 — turns rotate inside each side')
                        : context.tx('$minP تا $maxP بازیکن', '$minP–$maxP players'),
                    style: const TextStyle(color: Nx2.muted, fontSize: 12)),
              ]),
            ),
            if (_isManager && !playing)
              TextButton(onPressed: _pickGame, child: Text(context.tx('تغییر', 'Change'))),
          ]),
        ),
        const SizedBox(height: 10),
        if (playing)
          Nx2Panel(
            padding: const EdgeInsets.all(14),
            child: Row(children: <Widget>[
              Image.asset(AnixAssets.icon('versus'), width: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Text(context.tx('بازی در جریان است. بعد از پایان همه به اتاق برمی‌گردند.',
                    'A match is on. Everyone returns to the room when it ends.'),
                    style: const TextStyle(color: Nx2.text)),
              ),
              if (iAmPicked && _room?['match_id'] != null)
                TextButton(
                    onPressed: () => _openMatch('${_room!['match_id']}'), child: Text(context.tx('ورود', 'Rejoin'))),
            ]),
          )
        else ...<Widget>[
          Nx2SectionHeader(
              title: '${context.tx('بازیکن‌ها', 'Players')} ${_picked.length}/$maxP',
              action: _isManager && !_capacityBusy ? context.tx('ظرفیت', 'Capacity') : null,
              onAction: _isManager ? () => unawaited(_openCapacitySheet(cap)) : null),
          const SizedBox(height: 4),
          for (final RoomMember m in _members)
            CheckboxListTile(
              dense: true,
              value: _picked.containsKey(m.userId),
              onChanged: !_isManager
                  ? null
                  : (bool? on) {
                      final List<String> ids = <String>[
                        for (final MapEntry<String, Map<String, dynamic>> e in (_picked.entries.toList()
                          ..sort((MapEntry<String, Map<String, dynamic>> a, MapEntry<String, Map<String, dynamic>> b) =>
                              ((a.value['seat'] as num?) ?? 0).compareTo((b.value['seat'] as num?) ?? 0))))
                          e.key
                      ];
                      if (on == true) {
                        if (ids.length >= maxP) {
                          _snack(context.tx('حداکثر $maxP بازیکن', 'At most $maxP players'));
                          return;
                        }
                        ids.add(m.userId);
                      } else {
                        ids.remove(m.userId);
                      }
                      unawaited(_rpc('nx_room_select_players', <String, dynamic>{'p_room': widget.roomId, 'p_users': ids}));
                    },
              secondary: NxUserAvatar(avatar: m.avatar, name: m.name, size: 30),
              title: Text(m.name, style: const TextStyle(color: Nx2.text, fontWeight: FontWeight.w700)),
              subtitle: _picked.containsKey(m.userId)
                  ? Text(_seatLabel(_picked[m.userId]!), style: const TextStyle(color: Nx2.cyan, fontSize: 11))
                  : null,
            ),
          if (_isManager && _game == 'finger_soccer' && _picked.length >= 2)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey<String>('fs-swap-sides'),
                // The new seats go to the server (nx_room_select_players) and reach every member's room view; the
                // match is built from these seats, so it starts with the sides swapped on every phone.
                onPressed: () => unawaited(_rpc('nx_room_select_players',
                    <String, dynamic>{'p_room': widget.roomId, 'p_users': fsSwapSides(_pickedBySeat())})),
                icon: const Icon(Icons.swap_horiz_rounded, color: Nx2.cyan),
                label: Text(context.tx('جابه‌جایی تیم ۱ و تیم ۲', 'Swap Team 1 and Team 2'),
                    style: const TextStyle(color: Nx2.cyan, fontWeight: FontWeight.w800)),
              ),
            ),
          const SizedBox(height: 8),
          if (iAmPicked && _game == 'finger_soccer') _fingerSoccerSetup(),
          if (_isManager && _game == 'finger_soccer') _arenaSetup(),
          const SizedBox(height: 12),
          if (_isManager)
            LuxeButton(
              label: context.tx('شروع بازی', 'START MATCH'),
              icon: Icons.play_arrow_rounded,
              height: 54,
              loading: _capacityBusy,
              onTap: () => unawaited(_start(cap)),
            )
          else
            Text(
                iAmPicked
                    ? context.tx('انتخاب شدی! تیم و چیدمانت را بچین؛ مدیر بازی را شروع می‌کند.',
                        'You are in! Pick your team and formation; the manager starts the match.')
                    : context.tx('مدیر اتاق بازی و بازیکن‌ها را انتخاب می‌کند.', 'The room manager picks the game and players.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Nx2.muted)),
        ],
      ],
    );
  }

  /// Room capacity, in the app's design language. The manager sets how many of the people in
  /// the room play the next match (the game's own rules cap it); everyone else stays in the
  /// audience and keeps talking.
  Widget _capacityCard(RoomCapacity cap) {
    final bool fa = context.isFa;
    final String category = switch (cap.bounds.category) {
      RoomCategory.team => fa ? 'بازی تیمی — دو طرف برابر' : 'Team game — two equal sides',
      RoomCategory.social => fa ? 'استدلال اجتماعی — نقش‌های مخفی' : 'Social deduction — hidden roles',
      RoomCategory.duel => fa ? 'دو نفره' : 'Head to head',
      RoomCategory.group => fa ? 'بازی گروهی دور یک میز' : 'Group game around one table',
    };
    final String people = fa
        ? '$category · ${cap.minPlayers} تا ${cap.maxPlayers} بازیکن · تماشاگر نامحدود'
        : '$category · ${cap.minPlayers}–${cap.maxPlayers} players · unlimited audience';
    return LuxeCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          const Icon(Icons.groups_2_rounded, color: Luxe.gold, size: 19),
          const SizedBox(width: 8),
          Expanded(
            child: Text(fa ? 'ظرفیت بازیکن‌ها' : 'Player capacity',
                style: const TextStyle(color: Luxe.ink, fontWeight: FontWeight.w700, fontSize: 14)),
          ),
          LuxeStat(label: '${cap.selected}/${cap.capacity}', icon: Icons.sports_esports_rounded),
        ]),
        const SizedBox(height: 4),
        Text(people, style: const TextStyle(color: Luxe.mute, fontSize: 11.5, height: 1.4)),
        if (cap.canManage) ...<Widget>[
          const SizedBox(height: 10),
          Row(children: <Widget>[
            LuxeIconButton(
              icon: Icons.remove_rounded,
              tooltip: fa ? 'کم کردن ظرفیت' : 'Fewer players',
              onTap: _capacityBusy || cap.capacity <= cap.capacityOptions.first
                  ? null
                  : () => unawaited(_setCapacity(cap.step(-1))),
            ),
            Expanded(
              child: Text('${cap.capacity}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Luxe.ink, fontWeight: FontWeight.w800, fontSize: 20)),
            ),
            LuxeIconButton(
              icon: Icons.add_rounded,
              tooltip: fa ? 'بیشتر کردن ظرفیت' : 'More players',
              onTap: _capacityBusy || cap.capacity >= cap.maxPlayers ? null : () => unawaited(_setCapacity(cap.step(1))),
            ),
          ]),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              fa ? 'مدیر اتاق تعیین می‌کند چند نفر بازی کنند.' : 'The room manager decides how many people play.',
              style: const TextStyle(color: Luxe.mute, fontSize: 11),
            ),
          ),
      ]),
    );
  }

  /// Big capacity picker (manager): every legal size for this game, plus the admission switch.
  Future<void> _openCapacitySheet(RoomCapacity cap) async {
    final bool fa = context.isFa;
    final String range = cap.bounds.category == RoomCategory.team
        ? (fa ? 'بازی تیمی: ۲، ۴ یا ۶ بازیکن' : 'Team game: 2, 4 or 6 players')
        : (fa ? 'بین ${cap.minPlayers} و ${cap.maxPlayers} بازیکن' : 'Between ${cap.minPlayers} and ${cap.maxPlayers} players');
    final String note = fa ? 'ورود به اتاق برای همه باز است؛ تماشاگر نامحدود.' : 'Joining the room stays open; audience is unlimited.';
    final String lockLabel = cap.locked
        ? (fa ? 'باز کردن ورود' : 'OPEN ADMISSION')
        : (fa ? 'بستن ورود' : 'CLOSE ADMISSION');
    await showLuxeSheet<void>(
      context,
      builder: (BuildContext ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(fa ? 'ظرفیت این اتاق' : 'Room capacity',
              style: const TextStyle(color: Luxe.ink, fontWeight: FontWeight.w700, fontSize: 17)),
          const SizedBox(height: 4),
          Text('$range — $note', style: const TextStyle(color: Luxe.mute, fontSize: 12, height: 1.45)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final int n in cap.capacityOptions)
                LuxeStat(
                  label: '$n',
                  icon: n == cap.capacity ? Icons.check_rounded : null,
                  color: n == cap.capacity ? Luxe.gold2 : Luxe.gold,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    unawaited(_setCapacity(n));
                  },
                ),
            ],
          ),
          const SizedBox(height: 14),
          LuxeButton(
            label: lockLabel,
            icon: cap.locked ? Icons.lock_open_rounded : Icons.lock_rounded,
            kind: LuxeButtonKind.ghost,
            height: 46,
            fontSize: 12,
            onTap: () {
              Navigator.of(ctx).pop();
              unawaited(_setLocked(!cap.locked));
            },
          ),
        ],
      ),
    );
  }

  /// Picked players' ids in seat order.
  List<String> _pickedBySeat() => <String>[
        for (final MapEntry<String, Map<String, dynamic>> e in (_picked.entries.toList()
          ..sort((MapEntry<String, Map<String, dynamic>> a, MapEntry<String, Map<String, dynamic>> b) =>
              ((a.value['seat'] as num?) ?? 0).compareTo((b.value['seat'] as num?) ?? 0))))
          e.key
      ];

  String _seatLabel(Map<String, dynamic> p) {
    final int seat = (p['seat'] as num?)?.toInt() ?? 0;
    final String ready = p['ready'] == true ? ' ✓' : '';
    if (_game == 'finger_soccer') {
      return '${seat % 2 == 0 ? context.tx('تیم میزبان', 'Home side') : context.tx('تیم مهمان', 'Away side')}$ready';
    }
    return '${context.tx('صندلی', 'Seat')} ${seat + 1}$ready';
  }

  Future<void> _start(RoomCapacity cap) async {
    // The same rules run again in nx_start_room_match, so a stale screen cannot start an illegal match.
    final RoomRuleError? err = cap.checkStart(_picked.length);
    if (err != null) {
      final String msg = err.message(context.isFa, value: err == RoomRuleError.aboveMaximum ? cap.capacity : cap.minPlayers);
      _snack(context.isFa && err == RoomRuleError.belowMinimum ? '$msg (${cap.minPlayers})' : msg);
      return;
    }
    await _rpc('nx_start_room_match', <String, dynamic>{'p_room': widget.roomId});
  }

  Future<void> _pickGame() async {
    final List<GameInfo> games = kGames.where((GameInfo g) => g.supportsOnline).toList();
    final GameInfo? g = await showModalBottomSheet<GameInfo>(
      context: context,
      backgroundColor: Nx2.night,
      builder: (BuildContext ctx) => SafeArea(
        child: GridView.count(
          crossAxisCount: 3,
          padding: const EdgeInsets.all(12),
          children: <Widget>[
            for (final GameInfo g in games)
              InkWell(
                onTap: () => Navigator.of(ctx).pop(g),
                child: Column(children: <Widget>[
                  Expanded(
                    child: Image.asset('assets/arcade/pedestals/${g.id}.webp',
                        errorBuilder: (_, __, ___) => const Icon(Icons.sports_esports_rounded, color: Nx2.text)),
                  ),
                  Text(ctx.tx(g.nameFa, g.nameEn),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Nx2.text, fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
              ),
          ],
        ),
      ),
    );
    if (g == null) return;
    await _rpc('nx_room_change_game', <String, dynamic>{'p_room': widget.roomId, 'p_game': g.id});
  }

  Map<String, dynamic> get _myPrefs {
    final dynamic p = _picked[_me]?['prefs'];
    return p is Map ? Map<String, dynamic>.from(p) : <String, dynamic>{};
  }

  Widget _fingerSoccerSetup() {
    final Map<String, dynamic> pr = _myPrefs;
    final int seat = (_picked[_me]?['seat'] as num?)?.toInt() ?? 0;
    final bool captain = seat < 2;
    final String team = '${pr['team'] ?? ''}';
    final int form = (pr['form'] as num?)?.toInt() ?? 0;
    Future<void> save(Map<String, dynamic> patch) =>
        _rpc('nx_room_set_prefs', <String, dynamic>{'p_room': widget.roomId, 'p_prefs': <String, dynamic>{...pr, ...patch}});
    if (team.isEmpty && !_fsTeamSeeded) {
      _fsTeamSeeded = true;
      unawaited(SharedPreferences.getInstance().then((SharedPreferences p) {
        final String? t = p.getString('bm.team');
        if (t != null && kBmTeams.any((BmTeam x) => x.id == t) && GemShop.instance.ownsTeam(t) && mounted) {
          return save(<String, dynamic>{'team': t});
        }
        return null;
      }).catchError((Object _) => null));
    }
    return Nx2Panel(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text(context.tx('ترکیب من', 'My line-up'),
            style: const TextStyle(color: Nx2.text, fontWeight: FontWeight.w900)),
        if (!captain)
          Text(
              context.tx('در بازی تیمی، تیم و چیدمان را کاپیتان هر طرف (اولین بازیکن) تعیین می‌کند؛ انتخاب تو به‌عنوان پیشنهاد ذخیره می‌شود.',
                  'In team games each side plays its captain’s (first player’s) team and formation; yours is saved as a suggestion.'),
              style: const TextStyle(color: Nx2.muted, fontSize: 11)),
        const SizedBox(height: 6),
        for (final List<Object> cat in kBmCats) ...<Widget>[
          Text(context.tx('${cat[2]}', '${cat[1]}'),
              style: const TextStyle(color: Nx2.gold, fontSize: 12, fontWeight: FontWeight.w800)),
          SizedBox(
            height: 64,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: <Widget>[
                for (final BmTeam t in kBmTeams.where((BmTeam t) => t.cat == cat[0]))
                  GestureDetector(
                    // Locked teams (not bought with gems) can't be picked here; buy them in the game / shop.
                    onTap: () {
                      if (!GemShop.instance.ownsTeam(t.id)) {
                        _snack(context.tx('این تیم قفل است (${GemShop.instance.teamPrice(t.id)} الماس) — از فروشگاه بخرش.',
                            'Locked team (${GemShop.instance.teamPrice(t.id)} gems) — buy it in the shop.'));
                        return;
                      }
                      unawaited(save(<String, dynamic>{'team': t.id}));
                    },
                    child: Container(
                      width: 56,
                      margin: const EdgeInsets.only(right: 6, top: 4),
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: team == t.id ? Nx2.magenta : Colors.white24, width: team == t.id ? 2.5 : 1),
                      ),
                      child: Opacity(
                        opacity: GemShop.instance.ownsTeam(t.id) ? 1 : .4,
                        child: Image.asset(t.asset, fit: BoxFit.contain, cacheWidth: 140,
                            errorBuilder: (_, __, ___) => Center(
                                child: Text(t.name, style: const TextStyle(color: Nx2.text, fontSize: 9)))),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
          for (int i = 0; i < kBmForms.length; i++)
            ChoiceChip(
              label: Text(kBmForms[i].fa),
              selected: form == i && pr.containsKey('form'),
              onSelected: (_) => unawaited(save(<String, dynamic>{'form': i})),
            ),
        ]),
      ]),
    );
  }

  Widget _arenaSetup() {
    final Map<String, dynamic> st = Map<String, dynamic>.from((_room?['settings'] as Map?) ?? const <String, dynamic>{});
    final int field = bmFieldIndex((st['field'] as num?)?.toInt()), ball = bmBallIndex((st['ball'] as num?)?.toInt());
    final bool fa = context.isFa;
    Future<void> save(Map<String, dynamic> patch) =>
        _rpc('nx_room_set_settings', <String, dynamic>{'p_room': widget.roomId, 'p_settings': patch});
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Nx2Panel(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(context.tx('زمین و توپ (مدیر)', 'Pitch & ball (manager)'),
              style: const TextStyle(color: Nx2.text, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
            for (int i = 0; i < kBmFieldsRaw.length; i++)
              ChoiceChip(
                label: Text(bmFieldName(i, fa)),
                selected: field == i,
                onSelected: (_) => unawaited(save(<String, dynamic>{'field': i})),
              ),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
            for (int i = 0; i < NB; i++)
              ChoiceChip(
                label: Text(fa ? kBmBallFa[i] : kBmBallN[i]),
                selected: ball == i,
                onSelected: (_) => unawaited(save(<String, dynamic>{'ball': i})),
              ),
          ]),
        ]),
      ),
    );
  }
}
