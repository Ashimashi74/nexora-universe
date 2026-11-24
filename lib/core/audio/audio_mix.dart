import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// How the app's own sounds (game SFX, crowd ambience, UI ticks) share the phone's audio with a live LiveKit call.
///
/// Rules:
///  * [primeGlobal] sets the global `mixWithOthers` (Android `AUDIOFOCUS_NONE`) context at app startup before any
///    voice call can start, so every [AudioPlayer] created later inherits `AUDIOFOCUS_NONE` without resetting
///    Android's `AudioManager.mode` (`MODE_IN_COMMUNICATION`) or iOS's `AVAudioSession` (`playAndRecord`).
///  * While a LiveKit call is live ([voice.value] == true), [apply] never calls `setAudioContext` on the device:
///    LiveKit owns hardware echo cancellation (AEC), noise suppression, and speaker/Bluetooth routing.
///  * [gain] ducks game/UI sounds while a call is connected ([voiceGain]) and ducks further whenever anyone in the
///    call speaks ([talkGain]) so game audio never bleeds into the microphone or masks conversation.
class NxAudioMix {
  NxAudioMix._();

  /// A LiveKit call (game room, talk room, Orbit call) is connected on this phone.
  static final ValueNotifier<bool> voice = ValueNotifier<bool>(false);

  /// Somebody in a live call is speaking right now (LiveKit active speakers, local included).
  static final ValueNotifier<bool> talking = ValueNotifier<bool>(false);

  /// App sound level while a call is live / while somebody speaks in it.
  static const double voiceGain = .42, talkGain = .16;

  /// Multiplier for every app sound right now.
  static double get gain => !voice.value ? 1.0 : (talking.value ? talkGain : voiceGain);

  static bool _globalSet = false;

  /// Mix with every other sound, never request audio focus, keep the device's normal (non-call) routing.
  static AudioContext mixContext() => AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build();

  /// Configures [p] to mix with everything else. A no-op while a call is live so WebRTC keeps communication mode;
  /// players created during a call inherit the global mix context set by [primeGlobal].
  static Future<void> apply(AudioPlayer p) async {
    if (voice.value) return;
    final AudioContext ctx = mixContext();
    if (!_globalSet) {
      _globalSet = true;
      try {
        await AudioPlayer.global.setAudioContext(ctx);
      } catch (e) {
        debugPrint('nx audio mix (global): $e');
      }
      if (voice.value) return;
    }
    try {
      await p.setAudioContext(ctx);
    } catch (e) {
      debugPrint('nx audio mix (player): $e');
    }
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
