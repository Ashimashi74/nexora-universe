import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// How the app's own sounds (game SFX, crowd, menu music, UI ticks) share the phone's audio with a live LiveKit call.
///
/// Why this exists (owner report 2026-11-24: "in the voice room we often can't hear each other, game sound comes
/// into the conversation"): audioplayers applies an [AudioContext] to the *whole device* on every
/// `setAudioContext` call. On Android it sets `AudioManager.mode = MODE_NORMAL` and `isSpeakerphoneOn = false`, on
/// iOS it sets the AVAudioSession category to `.playback`. Finger soccer configures ~30 players when a match opens
/// (and the crowd players mid-match), usually while the lobby call is already running, so every match start pulled
/// the call out of communication mode: no hardware echo cancellation, the other side routed to the earpiece, and on
/// iOS the microphone stopped recording.
///
/// Rules:
///  * While a call is live, [apply] never touches the session: LiveKit owns it (communication mode, AEC / NS / AGC,
///    speaker routing). Players created then inherit the global mix-with-others context set before the call.
///  * Every app player mixes (no audio focus request), so a game sound never takes focus from the call.
///  * [gain] ducks app sounds while a call is live, and further while somebody (local or remote) is speaking, so the
///    game is not picked up by the microphone over the voices.
class NxAudioMix {
  NxAudioMix._();

  /// A LiveKit call (game room, talk room, Orbit call) is connected on this phone.
  static final ValueNotifier<bool> voice = ValueNotifier<bool>(false);

  /// Somebody in a live call is speaking right now (LiveKit active speakers, local included).
  static final ValueNotifier<bool> talking = ValueNotifier<bool>(false);

  /// App sound level while a call is live / while somebody speaks in it.
  static const double voiceGain = .45, talkGain = .18;

  /// Multiplier for every app sound right now.
  static double get gain => !voice.value ? 1.0 : (talking.value ? talkGain : voiceGain);

  static bool _globalSet = false;

  /// Mix with every other sound, never request audio focus, keep the device's normal (non-call) routing.
  static AudioContext mixContext() => AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build();

  /// Configures [p] to mix with everything else. A no-op while a call is live (see the class comment); the player
  /// then uses the global mix context set by an earlier call of this method.
  static Future<void> apply(AudioPlayer p) async {
    if (voice.value) return;
    final AudioContext ctx = mixContext();
    if (!_globalSet) {
      _globalSet = true;
      try {
        // New players (and NxSfx, which never sets a context) start from this instead of AUDIOFOCUS_GAIN.
        await AudioPlayer.global.setAudioContext(ctx);
      } catch (e) {
        debugPrint('nx audio mix (global): $e');
      }
      if (voice.value) return;
    }
    await p.setAudioContext(ctx);
  }

  /// Sets the global mix context once at startup, before any call can be live. Safe to call repeatedly.
  static void primeGlobal() {
    if (_globalSet || voice.value) return;
    _globalSet = true;
    unawaited(AudioPlayer.global.setAudioContext(mixContext()).then((_) {}, onError: (Object e) {
      debugPrint('nx audio mix (global): $e');
    }));
  }
}
