import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../settings/app_settings.dart' show NxTx;
import '../ui2/nx2_widgets.dart' show Nx2;
import 'online_config.dart';
import 'voice_connect.dart';

/// Turns every incoming (remote) audio track of [room] on or off: the room's "speaker" switch.
/// Off = this phone hears nobody (the server stops forwarding the audio and the local track is muted too).
Future<void> setRoomIncomingAudio(lk.Room room, bool on) async {
  for (final lk.RemoteParticipant p in room.remoteParticipants.values) {
    for (final lk.RemoteTrackPublication<lk.RemoteAudioTrack> pub in p.audioTrackPublications) {
      try {
        if (on) {
          await pub.enable();
        } else {
          await pub.disable();
        }
        final lk.RemoteAudioTrack? t = pub.track;
        if (t != null) t.mediaStreamTrack.enabled = on;
      } catch (_) {}
    }
  }
  try {
    await lk.Hardware.instance.setSpeakerphoneOn(on);
  } catch (_) {}
}

/// Voice for an online GAME room: the lobby and the match it starts share one LiveKit room, so the conversation keeps
/// going when the match opens. One instance for the whole app ([GameVoice.instance]).
///
/// * [join] asks `nx-call-token` (kind 'game') for a grant: only seated players / the match's players get one.
/// * [mic] publishes the microphone (mute / unmute), [speaker] plays the others (on / off).
/// * Pages [acquire] the room while visible and [release] it when they close; a release is delayed a few seconds so
///   going from the lobby to the match does not drop the call.
class GameVoice extends ChangeNotifier {
  GameVoice._();
  static final GameVoice instance = GameVoice._();

  /// Grant provider (set by the app: SupabaseBackend.liveKitGameGrant). Returns {url, token, room} or {error}.
  /// It caches grants (15 min tokens) per user; `fresh: true` skips the cache.
  Future<Map<String, dynamic>?> Function(String id, {bool match, bool fresh})? grant;

  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _events;
  String? _lkName;
  String? _key;
  bool busy = false;
  bool mic = false;
  bool speaker = true;
  String? error;
  Timer? _release;
  int _holders = 0;

  bool get connected => _room != null;
  String? get key => _key;
  int get peers => _room?.remoteParticipants.length ?? 0;

  bool speaking(String identity) {
    final lk.Room? r = _room;
    if (r == null) return false;
    if (r.localParticipant?.identity == identity) return r.localParticipant?.isSpeaking ?? false;
    for (final lk.RemoteParticipant p in r.remoteParticipants.values) {
      if (p.identity == identity) return p.isSpeaking;
    }
    return false;
  }

  /// Fetches (or reuses) the grant for this room in the background and warms the LiveKit connection, so the
  /// "join voice" tap only has to do the WebRTC handshake. Called when a lobby / match page opens.
  void prefetch(String id, {bool match = false}) {
    final Future<Map<String, dynamic>?> Function(String id, {bool match, bool fresh})? g = grant;
    if (g == null || _room != null) return;
    unawaited(g(id, match: match).then((_) {}, onError: (Object _) {}));
  }

  void acquire(String key) {
    _release?.cancel();
    _holders++;
    if (_key != null && _key != key && connected) {
      // A different room: the old call ends.
      unawaited(leave());
    }
    _key = key;
  }

  void release(String key) {
    _holders = (_holders - 1).clamp(0, 1 << 20);
    if (_holders > 0) return;
    _release?.cancel();
    _release = Timer(const Duration(seconds: 4), () {
      if (_holders == 0) unawaited(leave());
    });
  }

  Future<void> join(String id, {bool match = false}) async {
    final Future<Map<String, dynamic>?> Function(String id, {bool match, bool fresh})? g = grant;
    if (busy || g == null) return;
    busy = true;
    error = null;
    notifyListeners();
    lk.Room? room;
    lk.EventsListener<lk.RoomEvent>? ev;
    // Open the mic in parallel with the grant fetch + handshake (only when the user wants to talk).
    final Future<lk.LocalAudioTrack?>? micF = mic && _room == null ? openMic() : null;
    lk.LocalAudioTrack? micTrack;
    try {
      // Warm DNS/TLS to LiveKit while the grant is fetched (no-op cost if the grant is cached).
      room = lk.Room(roomOptions: voiceRoomOptions());
      warmVoice(room, OnlineConfig.liveKitUrl);
      final Map<String, dynamic>? r = await g(id, match: match);
      final String? token = r?['token'] as String?;
      if (token == null) throw StateError('${r?['error'] ?? 'no_token'}');
      final String name = '${r?['room'] ?? ''}';
      if (_room != null && name == _lkName) {
        // already in this call (lobby -> match)
        if (micF != null) unawaited(micF.then(dropMic));
        await disposeVoice(room);
        room = null;
        return;
      }
      await leave(keepKey: true);
      room.addListener(_changed);
      ev = room.createListener();
      final lk.Room live = room;
      ev
        ..on<lk.TrackSubscribedEvent>((lk.TrackSubscribedEvent e) async {
          if (!speaker) await setRoomIncomingAudio(live, false);
          _changed();
        })
        ..on<lk.RoomDisconnectedEvent>((lk.RoomDisconnectedEvent e) {
          // The SDK already retried (resume + full reconnect) before giving up: drop the dead room instead of
          // looking connected, and do not auto-rejoin (no reconnect loops).
          if (identical(_room, live)) {
            unawaited(leave(keepKey: true));
          }
        });
      final String url = '${r?['url'] ?? OnlineConfig.liveKitUrl}';
      micTrack = await micF;
      if (micF != null && micTrack == null) {
        mic = false; // mic unavailable (permission): join listening only
      }
      try {
        await connectVoice(live, url, token, micTrack: micTrack);
      } catch (_) {
        // Never reuse a grant that failed: the next tap fetches a fresh one. No automatic retry loop.
        unawaited(g(id, match: match, fresh: true).then((_) {}, onError: (Object _) {}));
        rethrow;
      }
      micTrack = null; // owned by the room now
      _room = live;
      _events = ev;
      _lkName = name;
      room = null;
      ev = null;
      unawaited(setRoomIncomingAudio(live, speaker));
    } catch (e) {
      error = '$e';
    } finally {
      if (micF != null && micTrack == null && room != null) unawaited(micF.then(dropMic));
      if (micTrack != null) unawaited(dropMic(micTrack));
      if (room != null) {
        room.removeListener(_changed);
        unawaited(disposeVoice(room, ev));
      }
      busy = false;
      notifyListeners();
    }
  }

  Future<void> leave({bool keepKey = false}) async {
    final lk.Room? r = _room;
    final lk.EventsListener<lk.RoomEvent>? ev = _events;
    _room = null;
    _events = null;
    _lkName = null;
    if (!keepKey) _key = null;
    if (r != null) {
      r.removeListener(_changed);
      await disposeVoice(r, ev);
    }
    notifyListeners();
  }

  Future<void> setMic(bool on) async {
    mic = on;
    final lk.Room? r = _room;
    if (r != null) {
      try {
        await r.localParticipant?.setMicrophoneEnabled(on);
      } catch (e) {
        mic = false;
        error = '$e';
      }
    }
    notifyListeners();
  }

  Future<void> setSpeaker(bool on) async {
    speaker = on;
    final lk.Room? r = _room;
    if (r != null) await setRoomIncomingAudio(r, on);
    notifyListeners();
  }

  void _changed() => notifyListeners();
}

/// Mic + speaker controls for an online game room / match. [id] is the nx_rooms id (lobby) or the nx_matches id
/// ([match] = true). Shows: join voice / leave, mic on-off (mute), speaker on-off, and how many others are in the call.
class RoomVoiceBar extends StatefulWidget {
  const RoomVoiceBar({super.key, required this.id, this.match = false, this.compact = false});
  final String id;
  final bool match;
  final bool compact;

  @override
  State<RoomVoiceBar> createState() => _RoomVoiceBarState();
}

class _RoomVoiceBarState extends State<RoomVoiceBar> {
  final GameVoice v = GameVoice.instance;
  late final String _k = '${widget.match ? 'm' : 'r'}:${widget.id}';

  @override
  void initState() {
    super.initState();
    v.acquire(_k);
    v.addListener(_on);
    v.prefetch(widget.id, match: widget.match);
  }

  @override
  void dispose() {
    v.removeListener(_on);
    v.release(_k);
    super.dispose();
  }

  void _on() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bool live = v.connected;
    final double sz = widget.compact ? 20 : 22;
    Widget btn({required IconData icon, required Color color, required String tip, VoidCallback? onTap, bool on = false}) =>
        Tooltip(
          message: tip,
          child: Material(
            color: on ? color.withValues(alpha: .18) : Colors.black.withValues(alpha: .28),
            shape: CircleBorder(side: BorderSide(color: color.withValues(alpha: .7), width: 1.4)),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Padding(padding: EdgeInsets.all(widget.compact ? 7 : 9), child: Icon(icon, size: sz, color: color)),
            ),
          ),
        );
    return Container(
      padding: EdgeInsets.symmetric(horizontal: widget.compact ? 6 : 10, vertical: widget.compact ? 4 : 6),
      decoration: BoxDecoration(
        color: const Color(0xCC0B1230),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: (live ? Nx2.success : Nx2.muted).withValues(alpha: .45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (v.busy)
            const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
          else
            btn(
              icon: live ? Icons.call_end_rounded : Icons.headset_mic_rounded,
              color: live ? Nx2.danger : Nx2.success,
              tip: live ? context.tx('خروج از صدا', 'Leave voice') : context.tx('ورود به صدا', 'Join voice'),
              onTap: () => live ? v.leave(keepKey: true) : v.join(widget.id, match: widget.match),
            ),
          const SizedBox(width: 6),
          btn(
            icon: v.mic ? Icons.mic_rounded : Icons.mic_off_rounded,
            color: v.mic ? Nx2.success : Nx2.danger,
            on: v.mic,
            tip: v.mic ? context.tx('میکروفون روشن (بی‌صدا کن)', 'Mic on (tap to mute)') : context.tx('میکروفون خاموش', 'Mic muted'),
            onTap: () async {
              await v.setMic(!v.mic);
              if (v.mic && !v.connected && !v.busy) await v.join(widget.id, match: widget.match);
            },
          ),
          const SizedBox(width: 6),
          btn(
            icon: v.speaker ? Icons.volume_up_rounded : Icons.volume_off_rounded,
            color: v.speaker ? Nx2.success : Nx2.danger,
            on: v.speaker,
            tip: v.speaker ? context.tx('بلندگو روشن', 'Speaker on') : context.tx('بلندگو خاموش', 'Speaker off'),
            onTap: () => v.setSpeaker(!v.speaker),
          ),
          if (live) ...<Widget>[
            const SizedBox(width: 8),
            Icon(Icons.people_alt_rounded, size: 15, color: Nx2.muted.withValues(alpha: .9)),
            const SizedBox(width: 2),
            Text('${v.peers + 1}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
          ],
          if (!live && v.error != null && !widget.compact) ...<Widget>[
            const SizedBox(width: 6),
            Tooltip(message: v.error!, child: const Icon(Icons.error_outline_rounded, size: 16, color: Nx2.danger)),
          ],
        ],
      ),
    );
  }
}
