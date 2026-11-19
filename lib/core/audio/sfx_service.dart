import 'dart:async';
import 'dart:io' show Platform;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Short UI / game-flow sound effects (assets/sfx/ui/*.mp3): button tick, chat, join, leave, ready, win, lose.
/// Follows the Sound effects switch and volume in Settings; never throws into the UI.
class NxSfx {
  NxSfx._();
  static final NxSfx instance = NxSfx._();

  static const List<String> names = <String>['tick', 'chat', 'join', 'leave', 'ready', 'win', 'lose'];

  bool _enabled = true;
  double _volume = 0.8;
  final Map<String, AudioPlayer> _players = <String, AudioPlayer>{};
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

  Future<void> _play(String name, double vol) async {
    try {
      final AudioPlayer p = _players.putIfAbsent(name, () {
        final AudioPlayer a = AudioPlayer();
        unawaited(a.setPlayerMode(PlayerMode.lowLatency).then((_) {}, onError: (Object _) {}));
        unawaited(a.setReleaseMode(ReleaseMode.stop).then((_) {}, onError: (Object _) {}));
        return a;
      });
      await p.stop();
      await p.setVolume(vol);
      await p.play(AssetSource('sfx/ui/$name.mp3'));
    } catch (e) {
      debugPrint('sfx $name: $e');
    }
  }
}
