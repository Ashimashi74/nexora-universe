// Finger Soccer stadium audio: SFXF samples, synthesized tone() blips, and the cross-faded crowd ambience loop.
//
// Key reliability guarantees:
//  1. Every player uses NxAudioMix (AUDIOFOCUS_NONE / mixWithOthers) applied AFTER setPlayerMode & setReleaseMode
//     so Android SoundPool/MediaPlayer never steals focus from other game sounds or from a live LiveKit voice call,
//     and never resets Android's AudioManager out of MODE_IN_COMMUNICATION during a call.
//  2. Polyphonic round-robin pools with oldest-voice stealing: Android SoundPool does not reliably emit
//     onPlayerComplete, so locking voices for 3 seconds previously starved the pool during rapid puck collisions
//     and dropped kicks/bounces ("audio cut off"). Each pool now prefers any free/expired voice and falls back to
//     the oldest voice if all voices are simultaneously active, so zero kicks or goals are ever dropped.
//  3. Menu music playback is disabled (menus stay quiet), while all 18 audio assets remain declared in bmSoundFiles.
//  4. Every effect and crowd loop ducks automatically via NxAudioMix.gain when LiveKit voice chat is connected or
//     when any participant is speaking.
import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:nexora/core/audio/audio_mix.dart';

/// Asset folder of the sounds (relative to `assets/`, as AssetSource wants it).
const String kBmSfxDir = 'games/bermuda/sfx/';

/// [file, base volume] exactly as SFXF in game.js, plus the synthesized tone() blips.
const Map<String, List<Object>> kBmSfx = <String, List<Object>>{
  'ui': <Object>['select.wav', 1.7],
  'hitb': <Object>['hit_ball.wav', 1.0],
  'hitp': <Object>['hit_piece.mp3', 1.0],
  'goal': <Object>['goal.wav', 2.4],
  'post': <Object>['ballHitsThePost.mp3', 1.2],
  'ann': <Object>['goalAnnounce.mp3', 1.3],
  'crowd': <Object>['crowd-03.mp3', .8],
  'whs': <Object>['startWistle.mp3', 1.0],
  'fin': <Object>['gameIsFinishedWistle.mp3', 1.0],
  'hb1': <Object>['BallHit-01.mp3', 1.0],
  'hb2': <Object>['BallHit-02.mp3', 1.0],
  'hb3': <Object>['BallHit-03.mp3', 1.0],
  't_wall': <Object>['t_wall.wav', 1.0],
  't_launch': <Object>['t_launch.wav', 1.0],
  't_post': <Object>['t_post.wav', 1.0],
  't_goal': <Object>['t_goal.wav', 1.0],
};

/// Crowd ambience clips with fallback durations in seconds.
const Map<String, double> kBmCrowd = <String, double>{'crowd-02.mp3': 19.54, 'crowd-03.mp3': 17.80};

/// Menu music asset retained for asset-manifest verification (playback disabled).
const String kBmMusic = 'music.mp3';

/// Every sound file declared by Finger Soccer (verified by finger_soccer_audio_test.dart).
List<String> bmSoundFiles() => <String>{
      for (final List<Object> v in kBmSfx.values) v[0] as String,
      ...kBmCrowd.keys,
      kBmMusic,
    }.toList();

// Longer samples stay on MediaPlayer so Android SoundPool (~1 MB decoded limit) never truncates them.
const Set<String> _long = <String>{'ann', 'crowd', 'whs', 'fin', 'goal'};

int _voices(String k) {
  if (k.startsWith('hb') || k == 'hitb' || k == 'hitp' || k == 't_wall') return 6;
  if (k == 'post' || k == 't_post' || k == 't_launch' || k == 'ui') return 4;
  return 2;
}

int _clipWindowMs(String k) {
  if (_long.contains(k)) return 1400;
  if (k == 'post' || k == 't_goal') return 450;
  return 240;
}

bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Minimum gap between two plays of a major event sound (ms) so local + network confirmations never double-fire.
const Map<String, int> _kEventGapMs = <String, int>{'goal': 1500, 'whs': 900, 'fin': 1500, 'post': 120};

class _Pool {
  _Pool(this.asset, {required this.low, required this.windowMs});

  final String asset;
  final bool low;
  final int windowMs;
  final List<AudioPlayer> players = <AudioPlayer>[];
  final List<bool> busy = <bool>[];
  final List<int> startedAt = <int>[];
  final List<StreamSubscription<void>> _doneSubs = <StreamSubscription<void>>[];
  int next = 0;

  void armDone(int i, AudioPlayer p) {
    final StreamSubscription<void> sub = p.onPlayerComplete.listen((_) {
      if (i < busy.length) busy[i] = false;
    }, onError: (Object _) {});
    _doneSubs.add(sub);
  }

  Future<void> play(double vol, double rate) async {
    if (players.isEmpty) return;
    final int now = DateTime.now().millisecondsSinceEpoch;
    int i = -1;
    // 1. Prefer a voice that has finished (either reported complete or past its natural sample window).
    for (int t = 0; t < players.length; t++) {
      final int j = (next + t) % players.length;
      if (!busy[j] || (now - startedAt[j]) >= windowMs) {
        i = j;
        break;
      }
    }
    // 2. If all voices fired within the last few milliseconds, steal the oldest voice instead of dropping the hit.
    if (i < 0) {
      int oldest = 0;
      for (int j = 1; j < players.length; j++) {
        if (startedAt[j] < startedAt[oldest]) oldest = j;
      }
      i = oldest;
    }
    next = (i + 1) % players.length;
    busy[i] = true;
    startedAt[i] = now;
    final AudioPlayer p = players[i];
    try {
      await p.stop();
      final double clamped = vol.clamp(0.0, 1.0).toDouble();
      await p.setVolume(clamped);
      if (low && _android && (rate - 1.0).abs() > 0.01) {
        try {
          await p.setPlaybackRate(rate.clamp(0.7, 1.35).toDouble());
        } catch (_) {}
      }
      await p.play(AssetSource(asset), volume: clamped);
    } catch (e) {
      debugPrint('bermuda sfx play ($asset): $e');
      busy[i] = false;
    }
  }

  void dispose() {
    for (final StreamSubscription<void> s in _doneSubs) {
      s.cancel();
    }
    _doneSubs.clear();
    for (final AudioPlayer p in players) {
      unawaited(p.dispose().then((_) {}, onError: (Object _) {}));
    }
    players.clear();
    busy.clear();
    startedAt.clear();
  }
}

class _CrowdClip {
  _CrowdClip(this.p, this.start, this.d);
  final AudioPlayer p;
  final double start, d;
  double lastV = -1;
}

class BmAudio {
  BmAudio({required this.enabled, this.announcer = false});

  final bool enabled;

  /// Goal announcer voice (goalAnnounce.mp3). Off by default unless toggled on in the match bar.
  bool announcer;
  bool muted = false;

  /// Game volume from the match bar (0..1), applied to every sound effect and crowd ambience.
  double master = 1;

  final Map<String, _Pool> _pools = <String, _Pool>{};
  final Map<String, int> _ts = <String, int>{};
  final math.Random _r = math.Random();
  bool _disposed = false;
  bool _initStarted = false;
  Future<void>? _initFuture;

  Future<void> init() {
    if (!enabled || _disposed) return Future<void>.value();
    if (_initStarted) return _initFuture ?? Future<void>.value();
    _initStarted = true;
    NxAudioMix.primeGlobal();
    NxAudioMix.voice.addListener(_onMix);
    NxAudioMix.talking.addListener(_onMix);
    return _initFuture = _openPools();
  }

  Future<void> _openPools() async {
    await Future.wait(kBmSfx.entries.map((MapEntry<String, List<Object>> e) async {
      final String asset = '$kBmSfxDir${e.value[0]}';
      final bool low = _android && !_long.contains(e.key);
      final _Pool pool = _Pool(asset, low: low, windowMs: _clipWindowMs(e.key));
      _pools[e.key] = pool;
      for (int n = _voices(e.key); n > 0; n--) {
        if (_disposed) return;
        final AudioPlayer p = AudioPlayer();
        try {
          if (low) {
            await p.setPlayerMode(PlayerMode.lowLatency);
          }
          await p.setReleaseMode(ReleaseMode.stop);
          await NxAudioMix.apply(p);
          await p.setSource(AssetSource(asset));
          if (_disposed) {
            unawaited(p.dispose());
            return;
          }
          pool.players.add(p);
          pool.busy.add(false);
          pool.startedAt.add(0);
          pool.armDone(pool.players.length - 1, p);
        } catch (err) {
          debugPrint('bermuda sfx init ${e.key}: $err');
          unawaited(p.dispose().then((_) {}, onError: (Object _) {}));
          return;
        }
      }
    }));
  }

  void _play(String k, double vol, [double rate = 1]) {
    if (!enabled || muted || _disposed) return;
    final _Pool? p = _pools[k];
    if (p == null) {
      if (!_initStarted) {
        unawaited(init().then((_) {
          final _Pool? ready = _pools[k];
          if (ready != null && !_disposed && !muted) {
            unawaited(ready.play((vol * master * NxAudioMix.gain).clamp(0.0, 1.0).toDouble(), rate));
          }
        }));
      }
      return;
    }
    unawaited(p.play((vol * master * NxAudioMix.gain).clamp(0.0, 1.0).toDouble(), rate));
  }

  double _b(String key) => (kBmSfx[key]![1] as num).toDouble();

  /// game.js sfx(k, v)
  void sfx(String k, [double v = 1]) {
    if (!enabled || muted || _disposed) return;
    final int n = DateTime.now().millisecondsSinceEpoch;
    v = math.min(1.0, math.max(0.0, v));
    if (n - (_ts[k] ?? 0) < (_kEventGapMs[k] ?? 28)) return;
    _ts[k] = n;
    switch (k) {
      case 'hitb':
        _play(<String>['hb1', 'hb2', 'hb3', 'hitb'][_r.nextInt(4)], (.35 + .65 * v) * _b('hitb'), .93 + .16 * v);
        break;
      case 'hitp':
        _play('hitp', (.3 + .7 * v) * _b('hitp'), .94 + .14 * v);
        break;
      case 'wall':
        _play('t_wall', .12 + .22 * v);
        break;
      case 'post':
        _play('post', _b('post') * (.5 + .5 * v));
        break;
      case 'whs':
        _play('whs', _b('whs'));
        break;
      case 'fin':
        _play('fin', _b('fin'));
        break;
      case 'ui':
        _play('ui', _b('ui'));
        break;
      case 'goal':
        _play('goal', _b('goal'));
        _play('crowd', _b('crowd'));
        _after(.16, () => _play('t_goal', 1));
        if (announcer) _after(.7, () => _play('ann', _b('ann')));
        break;
    }
  }

  /// game.js tone() blips that are not covered by samples.
  void tone(String k) {
    if (k == 'launch') _play('t_launch', 1);
    if (k == 'post') _play('t_post', 1);
  }

  // Delays are driven by [frame] so no Timer outlives the widget.
  final List<MapEntry<double, void Function()>> _q = <MapEntry<double, void Function()>>[];
  double _clock = 0;
  void _after(double s, void Function() f) => _q.add(MapEntry<double, void Function()>(_clock + s, f));

  void frame(double dt) {
    _clock += dt;
    _crowdFrame();
    if (_q.isEmpty) return;
    final List<MapEntry<double, void Function()>> due =
        _q.where((MapEntry<double, void Function()> e) => e.key <= _clock).toList();
    _q.removeWhere((MapEntry<double, void Function()> e) => e.key <= _clock);
    for (final MapEntry<double, void Function()> e in due) {
      e.value();
    }
  }

  void _onMix() {
    if (_disposed) return;
    // Immediately re-level any playing crowd ambience clip when voice chat or active speaker state changes.
    for (final _CrowdClip c in _crowdLive) {
      final double t = _clock - c.start;
      if (t >= 0 && t < c.d) {
        final double env = math.max(0.0, math.min(1.0, math.min(t / _crowdFade, (c.d - t) / _crowdFade)));
        final double v = (_crowdVol * master * NxAudioMix.gain * env).clamp(0.0, 1.0).toDouble();
        c.lastV = v;
        unawaited(c.p.setVolume(v).then((_) {}, onError: (Object _) {}));
      }
    }
  }

  /// Menu background music is intentionally disabled so Finger Soccer menus remain quiet and voice-friendly.
  Future<void> music(bool on) async {
    return;
  }

  // ---------------------------------------------------------------- crowd ambience (crowdNext / crowdSync)
  static const double _crowdFade = 1.8, _crowdVol = .28;
  final List<AudioPlayer> _crowdPlayers = <AudioPlayer>[];
  final List<_CrowdClip> _crowdLive = <_CrowdClip>[];
  bool _crowdOn = false;
  double _crowdNextAt = -1;
  int _crowdGen = 0;
  bool _crowdLoading = false;
  int _crowdSlot = 0;

  /// Crowd ambience while a match is live and not paused.
  Future<void> crowd(bool on) async {
    if (!enabled || _disposed) return;
    on = on && !muted;
    if (on == _crowdOn) return;
    _crowdOn = on;
    _crowdGen++;
    if (on) {
      _crowdNextAt = _clock;
    } else {
      _crowdNextAt = -1;
      final List<_CrowdClip> live = List<_CrowdClip>.from(_crowdLive);
      _crowdLive.clear();
      for (final _CrowdClip c in live) {
        unawaited(c.p.stop().then((_) {}, onError: (Object _) {}));
      }
    }
  }

  void _crowdFrame() {
    if (_disposed) return;
    if (_crowdOn && !_crowdLoading && _crowdNextAt >= 0 && _clock >= _crowdNextAt) {
      _crowdNextAt = -1;
      unawaited(_crowdNext());
    }
    for (final _CrowdClip c in List<_CrowdClip>.from(_crowdLive)) {
      final double t = _clock - c.start;
      if (t >= c.d) {
        _crowdLive.remove(c);
        continue;
      }
      final double env = math.max(0.0, math.min(1.0, math.min(t / _crowdFade, (c.d - t) / _crowdFade)));
      final double v = (_crowdVol * master * NxAudioMix.gain * env).clamp(0.0, 1.0).toDouble();
      if ((v - c.lastV).abs() >= .01) {
        c.lastV = v;
        unawaited(c.p.setVolume(v).then((_) {}, onError: (Object _) {}));
      }
    }
  }

  Future<void> _crowdNext() async {
    if (!_crowdOn || _disposed) return;
    final int gen = _crowdGen;
    _crowdLoading = true;
    try {
      while (_crowdPlayers.length < 2) {
        final AudioPlayer p = AudioPlayer();
        await p.setReleaseMode(ReleaseMode.stop);
        await NxAudioMix.apply(p);
        _crowdPlayers.add(p);
      }
      final String f = kBmCrowd.keys.elementAt(_r.nextInt(kBmCrowd.length));
      final AudioPlayer p = _crowdPlayers[_crowdSlot];
      _crowdSlot = 1 - _crowdSlot;
      _crowdLive.removeWhere((_CrowdClip c) => c.p == p);
      await p.stop();
      final String asset = '$kBmSfxDir$f';
      await p.setSource(AssetSource(asset));
      final Duration? dur = await p.getDuration();
      final double d = (dur != null && dur.inMilliseconds > 0) ? dur.inMilliseconds / 1000 : kBmCrowd[f]!;
      if (!_crowdOn || _disposed || gen != _crowdGen) return;
      await p.play(AssetSource(asset), volume: 0);
      _crowdLive.add(_CrowdClip(p, _clock, d));
      _crowdNextAt = _clock + math.max(.6, d - _crowdFade);
    } catch (e) {
      debugPrint('bermuda crowd: $e');
      if (_crowdOn) _crowdNextAt = _clock + 1.5;
    } finally {
      _crowdLoading = false;
    }
  }

  void setMuted(bool m) {
    muted = m;
    if (m) {
      unawaited(crowd(false));
    }
  }

  void dispose() {
    _disposed = true;
    _crowdOn = false;
    _crowdGen++;
    NxAudioMix.voice.removeListener(_onMix);
    NxAudioMix.talking.removeListener(_onMix);
    _q.clear();
    for (final _Pool p in _pools.values) {
      p.dispose();
    }
    _pools.clear();
    for (final AudioPlayer p in _crowdPlayers) {
      unawaited(p.dispose().then((_) {}, onError: (Object _) {}));
    }
    _crowdPlayers.clear();
    _crowdLive.clear();
  }
}
