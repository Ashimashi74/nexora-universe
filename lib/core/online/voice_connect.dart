import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../audio/audio_mix.dart';

/// Fast voice connect helpers shared by every LiveKit call in the app (Orbit calls, talk rooms, game voice).
///
/// The slow part of joining a call used to be a strictly sequential chain:
///   tap → Edge Function token (cold TLS + auth + 3 DB reads) → Room.connect (DNS/TLS/region lookup) → publish mic.
/// These helpers cut it to: token already cached (prefetched when the page opened) → region already resolved
/// (prepareConnection) → connect with the mic published as part of the join (FastConnectOptions).

/// Caches short-lived LiveKit grants ({url, token, room, ...}) so a call can start without waiting for the
/// Edge Function. Tokens live 15 min on the server; we reuse one for at most [ttl] minus [margin] and dedupe
/// concurrent fetches of the same key, so prefetch + tap never hit the function twice.
class VoiceGrantCache {
  VoiceGrantCache({DateTime Function()? clock, this.margin = const Duration(minutes: 3)})
      : _now = clock ?? DateTime.now;

  static final VoiceGrantCache instance = VoiceGrantCache();

  final DateTime Function() _now;

  /// Safety window before the server-side expiry (clock skew, slow connect).
  final Duration margin;

  final Map<String, _Entry> _cache = <String, _Entry>{};
  final Map<String, Future<Map<String, dynamic>?>> _inFlight = <String, Future<Map<String, dynamic>?>>{};

  /// A valid token grant: one that carries a token. Errors are never cached.
  static bool usable(Map<String, dynamic>? g) => g != null && g['token'] is String && (g['token'] as String).isNotEmpty;

  /// Fresh cached grant for [key], or null.
  Map<String, dynamic>? peek(String key) {
    final _Entry? e = _cache[key];
    if (e == null) return null;
    if (!_now().isBefore(e.expires)) {
      _cache.remove(key);
      return null;
    }
    return e.grant;
  }

  /// Returns the cached grant, joins a fetch already running, or runs [fetch].
  Future<Map<String, dynamic>?> get(String key, Future<Map<String, dynamic>?> Function() fetch) {
    final Map<String, dynamic>? hit = peek(key);
    if (hit != null) return SynchronousFuture<Map<String, dynamic>?>(hit);
    final Future<Map<String, dynamic>?>? running = _inFlight[key];
    if (running != null) return running;
    final Future<Map<String, dynamic>?> f = () async {
      try {
        final Map<String, dynamic>? g = await fetch();
        if (usable(g)) {
          final int ttlSec = (g!['ttl'] is num) ? (g['ttl'] as num).toInt() : 900;
          final Duration life = Duration(seconds: ttlSec) - margin;
          if (life > Duration.zero) _cache[key] = _Entry(g, _now().add(life));
        }
        return g;
      } finally {
        _inFlight.remove(key);
      }
    }();
    _inFlight[key] = f;
    return f;
  }

  /// Warms the cache in the background; never throws.
  void prefetch(String key, Future<Map<String, dynamic>?> Function() fetch) {
    if (peek(key) != null || _inFlight.containsKey(key)) return;
    unawaited(get(key, fetch).then((_) {}, onError: (Object _) {}));
  }

  /// Drops a grant (role changed, token rejected, call left for good).
  void invalidate(String key) => _cache.remove(key);

  void clear() => _cache.clear();
}

class _Entry {
  _Entry(this.grant, this.expires);
  final Map<String, dynamic> grant;
  final DateTime expires;
}

/// Room options tuned for low-latency voice: speech-preset Opus (24 kbps) with DTX + RED, full WebRTC audio
/// processing (AEC / NS / AGC + high-pass), adaptive stream + dynacast for the optional video.
lk.RoomOptions voiceRoomOptions() => const lk.RoomOptions(
      adaptiveStream: true,
      dynacast: true,
      fastPublish: true,
      defaultAudioCaptureOptions: lk.AudioCaptureOptions(
        echoCancellation: true,
        noiseSuppression: true,
        autoGainControl: true,
        highPassFilter: true,
        // 2026-11-24: game taps / keyboard clicks and (iOS 15+) background sound are kept out of the voice.
        typingNoiseDetection: true,
        voiceIsolation: true,
      ),
      defaultAudioPublishOptions: lk.AudioPublishOptions(
        encoding: lk.AudioEncoding.presetSpeech,
        dtx: true,
        red: true,
      ),
    );

/// Shorter connect timeouts than the SDK's 10 s so a dead region fails over (LiveKit Cloud tries the next
/// region) instead of leaving the user staring at "Connecting…".
const lk.ConnectOptions voiceConnectOptions = lk.ConnectOptions(
  autoSubscribe: true,
  timeouts: lk.Timeouts(
    connection: Duration(seconds: 7),
    debounce: Duration(milliseconds: 20),
    publish: Duration(seconds: 8),
    subscribe: Duration(seconds: 8),
    peerConnection: Duration(seconds: 7),
    iceRestart: Duration(seconds: 8),
  ),
);

/// Starts DNS / TLS / LiveKit Cloud region resolution for [url] on [room] without waiting. Safe to call before
/// the token is known (token null = only DNS + TLS warm-up) and again when it arrives.
void warmVoice(lk.Room room, String url, [String? token]) {
  unawaited(room.prepareConnection(url, token).then((_) {}, onError: (Object _) {}));
}

/// Opens the microphone (permission prompt, audio unit start-up) so it can run in parallel with the token fetch
/// and the signalling handshake. Returns null when the mic cannot be opened (denied / busy): the call still joins.
Future<lk.LocalAudioTrack?> openMic() async {
  try {
    return await lk.LocalAudioTrack.create(voiceRoomOptions().defaultAudioCaptureOptions);
  } catch (_) {
    return null;
  }
}

/// Connects [room] and publishes the microphone (and camera) as part of the join instead of after it: the SDK
/// publishes right after the join response, while the media transport is still being set up.
/// [micTrack] is a track already opened with [openMic]; otherwise [mic] lets the SDK open one.
Future<void> connectVoice(lk.Room room, String url, String token,
    {bool mic = false, lk.LocalAudioTrack? micTrack, bool camera = false}) async {
  await room.connect(
    url,
    token,
    connectOptions: voiceConnectOptions,
    fastConnectOptions: lk.FastConnectOptions(
      microphone: lk.TrackOption<bool, lk.LocalAudioTrack>(enabled: micTrack == null && mic, track: micTrack),
      camera: lk.TrackOption<bool, lk.LocalVideoTrack>(enabled: camera),
    ),
  );
  trackVoiceRoom(room);
}

// ---------------------------------------------------------------- live calls -> app sound mix (NxAudioMix)
final Map<lk.Room, VoidCallback> _liveRooms = <lk.Room, VoidCallback>{};

/// Registers a connected call: while any call is live the app's own sounds stop touching the audio session and are
/// ducked (more while somebody speaks). Called by [connectVoice]; the room leaves the set on [disposeVoice] or when
/// it reports itself disconnected (pages that disconnect a room directly).
void trackVoiceRoom(lk.Room room) {
  if (_liveRooms.containsKey(room)) return;
  void onChange() {
    if (room.connectionState == lk.ConnectionState.disconnected) {
      untrackVoiceRoom(room);
    } else {
      _syncVoiceMix();
    }
  }

  _liveRooms[room] = onChange;
  try {
    room.addListener(onChange);
  } catch (_) {}
  _syncVoiceMix();
}

/// Removes [room] from the live calls (idempotent).
void untrackVoiceRoom(lk.Room room) {
  final VoidCallback? l = _liveRooms.remove(room);
  if (l != null) {
    try {
      room.removeListener(l);
    } catch (_) {}
  }
  _syncVoiceMix();
}

void _syncVoiceMix() {
  bool talk = false;
  for (final lk.Room r in _liveRooms.keys) {
    try {
      if (r.activeSpeakers.isNotEmpty) talk = true;
    } catch (_) {}
  }
  NxAudioMix.voice.value = _liveRooms.isNotEmpty;
  NxAudioMix.talking.value = talk && _liveRooms.isNotEmpty;
}

/// Stops a mic track that never made it into a call.
Future<void> dropMic(lk.LocalAudioTrack? t) async {
  if (t == null) return;
  try {
    await t.stop();
  } catch (_) {}
  try {
    await t.dispose();
  } catch (_) {}
}

/// Disconnects and frees a room (listeners first), swallowing errors so leave never throws.
Future<void> disposeVoice(lk.Room? room, [lk.EventsListener<lk.RoomEvent>? events]) async {
  if (room == null) return;
  untrackVoiceRoom(room);
  try {
    await events?.dispose();
  } catch (_) {}
  try {
    await room.disconnect();
  } catch (_) {}
  try {
    await room.dispose();
  } catch (_) {}
}
