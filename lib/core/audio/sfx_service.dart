import 'dart:async';
import 'dart:io' show Platform;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'audio_mix.dart';

/// Short UI / game-flow sound effects (assets/sfx/ui/*.mp3): button tick, chat, join, leave, ready, win, lose.
/// Follows the Sound effects switch and volume in Settings; never steals audio focus from a LiveKit voice call.
class NxSfx {
  NxSfx._();
  static final NxSfx instance = NxSfx._();

  static const List<String> names = <String>['tick', 'chat', 'join', 'leave', 'ready', 'win', 'lose'];

  bool _enabled = true;
  double _volume = 0.8;
  final Map<String, Future<AudioPlayer>> _players = <String, Future<AudioPlayer>>{};
  DateTime _lastTick = DateTime.fromMillisecondsSinceEpoch(0);

  static final bool _inTests = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  bool get enabled => _enabled;
  double get volume => _volume;

  void configure({required bool enabled, required double volume}) {
    _enabled = enabled;
    _volume = volume.clamp(0.0, 1.0);
  }

  /// Plays [name] (one of [names]); quiet no-op when sound is off, the volume is 0 or audio is unavailable (tests).
  void play(String name, {double gain = 1}) {
    if (_inTests) return;
    if (!_enabled || _volume <= 0 || !names.contains(name)) return;
    if (name == 'tick') {
      final DateTime now = DateTime.now();
      if (now.difference(_lastTick).inMilliseconds < 60) return;
      _lastTick = now;
    }
    unawaited(_play(name, (_volume * gain).clamp(0.0, 1.0)));
  }

  Future<AudioPlayer> _open(String name) {
    return _players.putIfAbsent(name, () async {
      final AudioPlayer a = AudioPlayer();
      // Set mode/release BEFORE applying audio context so SoundPool/MediaPlayer recreation does not reset focus.
      try {
        await a.setPlayerMode(PlayerMode.lowLatency);
      } catch (_) {}
      try {
        await a.setReleaseMode(ReleaseMode.stop);
      } catch (_) {}
      await NxAudioMix.apply(a);
      return a;
    });
  }

  Future<void> _play(String name, double vol) async {
    try {
      final AudioPlayer p = await _open(name);
      await p.stop();
      await p.setVolume((vol * NxAudioMix.gain).clamp(0.0, 1.0).toDouble());
      await p.play(AssetSource('sfx/ui/$name.mp3'));
    } catch (e) {
      debugPrint('sfx $name: $e');
    }
  }
}
