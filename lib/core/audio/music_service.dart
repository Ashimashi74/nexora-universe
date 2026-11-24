import 'dart:async';
import 'dart:io' show Platform;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';

import 'audio_mix.dart';

/// App lifecycle + game-presence tracker (formerly also played menu background music).
///
/// Menu background music is permanently disabled per product design so menus, lobbies, and voice rooms stay clean
/// and quiet while in-game sound effects remain crisp. [inGameListenable] and [primeGlobal] continue to work for
/// the rest of the app (e.g., hiding the corner ORACLE inside games and priming `mixWithOthers` audio context).
class MusicService with WidgetsBindingObserver {
  MusicService._();
  static final MusicService instance = MusicService._();

  static const String asset = 'media/bgm_main.ogg';

  AudioPlayer? _player;
  bool _started = false;
  bool _enabled = false;
  double _volume = 0.0;
  int _games = 0;

  bool get started => _started;
  bool get inGame => _games > 0;

  void configure({required bool enabled, required double volume}) {
    _enabled = false;
    _volume = 0.0;
    _stopIfAny();
  }

  static final bool _underTest = Platform.environment.containsKey('FLUTTER_TEST');

  Future<void> start() async {
    if (_started || _underTest) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    NxAudioMix.primeGlobal();
    _stopIfAny();
  }

  /// True while any game page is open (the corner ORACLE hides itself inside games).
  final ValueNotifier<bool> inGameListenable = ValueNotifier<bool>(false);

  void enterGame() {
    _games++;
    inGameListenable.value = _games > 0;
  }

  void exitGame() {
    if (_games > 0) _games--;
    inGameListenable.value = _games > 0;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _stopIfAny();
    }
  }

  void _stopIfAny() {
    final AudioPlayer? p = _player;
    if (p != null && (_enabled || _volume >= 0)) {
      unawaited(p.stop().catchError((Object _) {}));
    }
  }
}
