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
import '../../core/online/room_voice.dart';
import '../../core/economy/gem_shop.dart';
import '../../core/settings/app_settings.dart';
import '../../core/ui2/anix_kit.dart';
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

/// Player limits per game inside a room (mirrors nx_game_bounds on the games project).
class TalkRoomLimits {
  static int maxPlayersFor(String game) => switch (game) {
        'finger_soccer' || 'carrom' => 6,
        'mafia' || 'spy_mafia' => 12,
        'quiz' => 21,
        _ => gameById(game)?.maxPlayers ?? 2,
      };

  static int minPlayersFor(String game) => switch (game) {
        'mafia' => 6,
        'spy_mafia' => 3,
        _ => 2,
      };
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
    _voice = null;
    if (v != null) unawaited(v.disconnect().then((_) => v.dispose()));
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
          .select('id, code, title, game, selected_game, status, match_id, host, settings, kind')
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
      });
      await _syncVoiceRole();
      _maybeOpenMatch();
    } catch (_) {}
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  // ------------------------------------------------------------------ voice
  Future<void> _joinVoice() async {
    final BackendGateway be = ref.read(backendProvider);
    if (be is! SupabaseBackend || _voiceBusy) return;
    setState(() {
      _voiceBusy = true;
      _voiceError = null;
    });
    try {
      final Map<String, dynamic>? g = await be.liveKitRoomGrant(widget.roomId);
      final String? token = g?['token'] as String?;
      if (token == null) throw StateError('${g?['error'] ?? 'no_token'}');
      _canPublish = g?['canPublish'] == true;
      final lk.Room room = lk.Room(roomOptions: const lk.RoomOptions(adaptiveStream: true, dynacast: true));
      room.addListener(_onVoice);
      await room.connect('${g?['url'] ?? OnlineConfig.liveKitUrl}', token);
      _voice = room;
      await setRoomIncomingAudio(room, _speaker);
      room.createListener().on<lk.TrackSubscribedEvent>((lk.TrackSubscribedEvent _) async {
        if (!_speaker) await setRoomIncomingAudio(room, false);
      });
    } catch (e) {
      _voiceError = '$e';
    } finally {
      if (mounted) setState(() => _voiceBusy = false);
    }
  }

  Future<void> _leaveVoice() async {
    final lk.Room? v = _voice;
    _voice = null;
    _mic = false;
    if (v != null) {
      v.removeListener(_onVoice);
      await v.disconnect();
      await v.dispose();
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
    if (_voice == null || me == null) return;
    final bool should = me.onStage && !me.muted;
    if (should != _canPublish) {
      await _leaveVoice();
      await _joinVoice();
    }
  }

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
        backgroundColor: Nx2.deep,
        appBar: AppBar(
          backgroundColor: Nx2.night.withValues(alpha: 0.9),
          foregroundColor: Nx2.text,
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            if (_room != null)
              Text('${context.tx('کد', 'Code')} ${_room!['code']} · ${_members.length} ${context.tx('نفر', 'people')}',
                  style: const TextStyle(fontSize: 11, color: Nx2.muted)),
          ]),
          actions: <Widget>[
            IconButton(
              tooltip: context.tx('خروج از اتاق', 'Leave room'),
              icon: const Icon(Icons.logout_rounded),
              onPressed: _leave,
            ),
          ],
        ),
        body: Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
                image: AssetImage(AnixAssets.sceneVoiceStage),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(Color(0xB307031A), BlendMode.darken)),
          ),
          child: _error != null
              ? _errorView()
              : _room == null
                  ? const Center(child: CircularProgressIndicator())
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
      ),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            const Icon(Icons.wifi_off_rounded, color: Nx2.muted, size: 48),
            const SizedBox(height: 10),
            Text(
                _error == 'offline'
                    ? context.tx('برای اتاق‌ها باید وارد حساب شوی.', 'Sign in to use rooms.')
                    : _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Nx2.text)),
          ]),
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
        border: Border.all(color: Nx2.violet.withValues(alpha: 0.5)),
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
                        color: mine ? Nx2.violet.withValues(alpha: 0.55) : Nx2.night.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(14),
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
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 16),
      children: <Widget>[
        for (final RoomMember m in _members)
          ListTile(
            dense: true,
            onTap: () => _showMember(m),
            leading: NxUserAvatar(avatar: m.avatar, name: m.name, size: 34,
                ring: _speaking(m.userId) ? Nx2.success : (m.isManager ? Nx2.gold : null)),
            title: Text(m.name + (m.userId == _me ? context.tx(' (تو)', ' (you)') : ''),
                style: const TextStyle(color: Nx2.text, fontWeight: FontWeight.w800)),
            subtitle: Text(
                switch (m.role) {
                  'manager' => context.tx('مدیر اتاق', 'Room manager'),
                  'speaker' => context.tx('سخنران', 'Speaker'),
                  _ => context.tx('شنونده', 'Listener'),
                } +
                    (m.muted ? context.tx(' · بی‌صدا', ' · muted') : ''),
                style: const TextStyle(color: Nx2.muted, fontSize: 12)),
            trailing: _isManager && m.userId != _me
                ? PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded, color: Nx2.text),
                    onSelected: (String a) {
                      switch (a) {
                        case 'speaker':
                        case 'spectator':
                          unawaited(_rpc('nx_room_set_role',
                              <String, dynamic>{'p_room': widget.roomId, 'p_user': m.userId, 'p_role': a}));
                        case 'mute':
                          unawaited(_rpc('nx_room_set_muted',
                              <String, dynamic>{'p_room': widget.roomId, 'p_user': m.userId, 'p_muted': !m.muted}));
                      }
                    },
                    itemBuilder: (_) => <PopupMenuEntry<String>>[
                      if (m.role != 'speaker')
                        PopupMenuItem<String>(value: 'speaker', child: Text(context.tx('سخنران کن', 'Make speaker'))),
                      if (m.role != 'spectator')
                        PopupMenuItem<String>(value: 'spectator', child: Text(context.tx('شنونده کن', 'Make listener'))),
                      PopupMenuItem<String>(
                          value: 'mute', child: Text(m.muted ? context.tx('باصدا کن', 'Unmute') : context.tx('بی‌صدا کن', 'Mute'))),
                    ],
                  )
                : null,
          ),
      ],
    );
  }

  /// Member card: big avatar, name, follower / following counts and a follow button (shared follows table).
  void _showMember(RoomMember m) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Nx2.night,
      builder: (BuildContext ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            NxUserAvatar(avatar: m.avatar, name: m.name, size: 84, ring: m.isManager ? Nx2.gold : Nx2.violet),
            const SizedBox(height: 8),
            Text(m.name, style: const TextStyle(color: Nx2.text, fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            NovaFollowBar(uid: m.userId, self: m.userId == _me),
            if (m.userId != _me)
              TextButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final TextEditingController t = TextEditingController();
                  final bool? ok = await showDialog<bool>(
                    context: context,
                    builder: (BuildContext d) => AlertDialog(
                      title: Text(context.tx('گزارش ${m.name}', 'Report ${m.name}')),
                      content: TextField(controller: t, maxLength: 300,
                          decoration: InputDecoration(hintText: context.tx('چه اتفاقی افتاد؟', 'What happened?'))),
                      actions: <Widget>[
                        TextButton(onPressed: () => Navigator.pop(d, false), child: Text(context.tx('انصراف', 'Cancel'))),
                        FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(context.tx('ارسال', 'Send'))),
                      ],
                    ),
                  );
                  if (ok == true && t.text.trim().length >= 2) {
                    try {
                      await ref.read(onlineProvider).rpc('nx_report_user', <String, dynamic>{
                        'p_target': m.userId, 'p_kind': 'room', 'p_target_id': widget.roomId, 'p_reason': t.text.trim(),
                      });
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(context.tx('گزارش برای مدیران فرستاده شد', 'Report sent to the admins'))));
                      }
                    } catch (_) {}
                  }
                  t.dispose();
                },
                icon: const Icon(Icons.flag_rounded, color: Nx2.muted, size: 18),
                label: Text(context.tx('گزارش تخلف', 'Report'), style: const TextStyle(color: Nx2.muted)),
              ),
          ]),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ games
  Widget _gamesPanel() {
    final GameInfo? g = gameById(_game);
    final bool playing = _room?['status'] == 'playing';
    final bool iAmPicked = _picked.containsKey(_me);
    final int maxP = TalkRoomLimits.maxPlayersFor(_game), minP = TalkRoomLimits.minPlayersFor(_game);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      children: <Widget>[
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
              title: '${context.tx('بازیکن‌ها', 'Players')} ${_picked.length}/$maxP'),
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
            Nx2Button(
              label: context.tx('شروع بازی', 'START MATCH'),
              icon: Icons.play_arrow_rounded,
              kind: Nx2ButtonKind.pink,
              height: 54,
              onTap: () => unawaited(_start(minP)),
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

  Future<void> _start(int minP) async {
    if (_picked.length < minP) {
      _snack(context.tx('حداقل $minP بازیکن انتخاب کن', 'Pick at least $minP players'));
      return;
    }
    if (_game == 'finger_soccer' && _picked.length.isOdd) {
      _snack(context.tx('فوتبال انگشتی: تعداد بازیکن‌ها زوج باشد (۱×۱، ۲×۲، ۳×۳)', 'Finger soccer needs 2, 4 or 6 players'));
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
                label: Text(kBmFieldsRaw[i].name),
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
