// Sounds of game.js: SFXF samples, tone() blips (rendered to small wav files), the crowd ambience loop
// (crowdNext: random crowd clips, 1.8 s cross-fade, volume .3) and the menu music (musicSync, volume .4).
//
// Why this file is not a thin AudioPool wrapper any more (the sounds were silent on Android):
//  * audioplayers asks Android for AUDIOFOCUS_GAIN on every play() by default. Each new sound took the
//    focus from the player before it and audioplayers *pauses* a player that loses focus, so the crowd
//    ambience died at the first collision, and on a goal `goal.wav` -> crowd cheer -> t_goal stole the focus
//    from each other (only the last survived); `post` was cut by the `t_post` blip fired in the same frame.
//    Every player here uses focus=none (mixWithOthers), like the Web Audio graph of game.js where all
//    sources simply mix.
//  * Short effects run in PlayerMode.lowLatency (Android SoundPool) with ReleaseMode.stop and are always
//    stop()+resume()d: SoundPool never reports completion, so a plain resume() on a finished stream was a
//    no-op and every pooled hit played only once.
//  * A small round-robin of preloaded players per sound lets rapid collisions overlap.
//  * 2026-11-24 (voice rooms): the session is configured through NxAudioMix, which never touches it while a LiveKit
//    call is live (audioplayers used to reset Android to MODE_NORMAL / earpiece and iOS to .playback on every
//    setAudioContext, breaking the call), and every sound is ducked by NxAudioMix.gain while the call is live / while
//    somebody speaks. Goal / whistle effects are de-duplicated (a goal seen by the local simulation and confirmed by
//    the network no longer plays twice) and the crowd ambience can never run two loops at once.
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

/// Crowd ambience clips (game.js loads crowd-01..09 and keeps the ones that exist: 02 and 03) with their
/// lengths in seconds, used when the platform cannot report a duration.
const Map<String, double> kBmCrowd = <String, double>{'crowd-02.mp3': 19.54, 'crowd-03.mp3': 17.80};

/// Menu music.
const String kBmMusic = 'music.mp3';

/// Every sound file this module plays (for the asset test).
List<String> bmSoundFiles() => <String>{
      for (final List<Object> v in kBmSfx.values) v[0] as String,
      ...kBmCrowd.keys,
      kBmMusic,
    }.toList();

// Effects up to ~1 s go to SoundPool (fast, overlapping); longer clips stay on MediaPlayer
// (SoundPool truncates samples above ~1 MB decoded).
const Set<String> _long = <String>{'ann', 'crowd', 'whs', 'fin'};

int _voices(String k) {
  if (k.startsWith('hb') || k == 'hitb' || k == 'hitp' || k == 't_wall') return 4;
  if (k == 'post' || k == 't_post' || k == 't_launch' || k == 'ui') return 3;
  return 1;
}

bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Minimum gap between two plays of an event sound (ms): a goal / whistle reported twice (local simulation + the
/// opponent's logged event, or a replayed snapshot) plays once.
const Map<String, int> _kEventGapMs = <String, int>{'goal': 1500, 'whs': 900, 'fin': 1500, 'post': 120};

/// Voices are released on real completion ([onPlayerComplete]) or, for platforms whose SoundPool does not
/// report completion, after this generous cap. Pooled effects are short, so the cap only ever fires on a
/// sound that has long finished — it never cuts a still-playing clip, but it does guarantee a stuck voice is
/// reused eventually instead of starving the pool.
const Duration kBmPoolFreeCap = Duration(milliseconds: 3000);

class _Pool {
  _Pool(this.low);
  final bool low;
  final List<AudioPlayer> players = <AudioPlayer>[];
  final List<bool> busy = <bool>[];
  final List<StreamSubscription<void>> _doneSubs = <StreamSubscription<void>>[];
  final List<Timer?> _caps = <Timer?>[];
  int next = 0;

  /// Starts [i]'s completion listener: the voice is released only when its sound actually finishes,
  /// not when [resume] returns. Clearing `busy` right after `resume()` made the next rapid hit take the
  /// same voice and `stop()` the still-playing sound — the garbled / cut-off audio the player reported.
  void _armDone(int i, AudioPlayer p) {
    final StreamSubscription<void> sub =
        p.onPlayerComplete.listen((_) {
      if (i < busy.length) busy[i] = false;
      _freeCap(i);
    }, onError: (Object _) {});
    _doneSubs.add(sub);
  }

  void _freeCap(int i) {
    if (i < _caps.length) {
      final Timer? t = _caps[i];
      if (t != null) {
        t.cancel();
        _caps[i] = null;
      }
    }
  }

  Future<void> play(double vol, double rate) async {
    if (players.isEmpty) return;
    int i = -1;
    for (int t = 0; t < players.length; t++) {
      final int j = (next + t) % players.length;
      if (!busy[j]) {
        i = j;
        break;
      }
    }
    if (i < 0) return; // every voice is still playing; drop like a saturated mixer would
    next = (i + 1) % players.length;
    busy[i] = true;
    final AudioPlayer p = players[i];
    try {
      await p.stop(); // a stopped stream restarts from 0 (required for SoundPool, cuts the oldest voice)
      await p.setVolume(vol);
      if (low && _android) await p.setPlaybackRate(rate);
      await p.resume();
      // Safety net for SoundPool voices that never emit onPlayerComplete: free after the cap so the pool
      // keeps rotating. onPlayerComplete (armed at init) frees the voice promptly on platforms that do.
      if (i < _caps.length) {
        _freeCap(i);
        _caps[i] = Timer(kBmPoolFreeCap, () {
          if (busy[i]) {
            busy[i] = false;
            _freeCap(i);
          }
        });
      }
    } catch (e) {
      debugPrint('bermuda sfx play: $e');
      busy[i] = false; // a failed start frees the voice immediately
      _freeCap(i);
    }
  }

  void dispose() {
    for (final StreamSubscription<void> s in _doneSubs) {
      s.cancel();
    }
    _doneSubs.clear();
    for (final Timer? t in _caps) {
      t?.cancel();
    }
    _caps.clear();
    for (final AudioPlayer p in players) {
      unawaited(p.dispose().then((_) {}, onError: (Object _) {}));
    }
    players.clear();
    busy.clear();
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

  /// Goal announcer voice (goalAnnounce.mp3). Off by default: the user turned the commentator down.
  bool announcer;
  bool muted = false;

  /// Game volume from the game bar (0..1), applied to every sound effect.
  double master = 1;

  final Map<String, _Pool> _pools = <String, _Pool>{};
  final Map<String, int> _ts = <String, int>{};
  final math.Random _r = math.Random();
  AudioPlayer? _music;
  bool _disposed = false;

  Future<void> init() async {
    if (!enabled) return;
    NxAudioMix.voice.addListener(_onMix);
    NxAudioMix.talking.addListener(_onMix);
    await Future.wait(kBmSfx.entries.map((MapEntry<String, List<Object>> e) async {
      final bool low = _android && !_long.contains(e.key);
      final _Pool pool = _Pool(low);
      _pools[e.key] = pool;
      for (int n = _voices(e.key); n > 0; n--) {
        final AudioPlayer p = AudioPlayer();
        try {
          await NxAudioMix.apply(p);
          // ignore: deprecated_member_use
          if (low) await p.setPlayerMode(PlayerMode.lowLatency);
          await p.setReleaseMode(ReleaseMode.stop);
          await p.setSource(AssetSource('$kBmSfxDir${e.value[0]}'));
          if (_disposed) {
            unawaited(p.dispose());
            return;
          }
          pool.players.add(p);
          pool.busy.add(false);
          pool._caps.add(null);
          pool._armDone(pool.players.length - 1, p);
        } catch (err) {
          debugPrint('bermuda sfx ${e.key}: $err');
          unawaited(p.dispose().then((_) {}, onError: (Object _) {}));
          return;
        }
      }
    }));
  }

  void _play(String k, double vol, [double rate = 1]) {
    if (!enabled || muted || _disposed) return;
    final _Pool? p = _pools[k];
    if (p == null) return;
    unawaited(p.play((vol * master * NxAudioMix.gain).clamp(0.0, 1.0).toDouble(), rate));
  }

  double _b(String key) => (kBmSfx[key]![1] as num).toDouble();

  /// game.js sfx(k, v)
  void sfx(String k, [double v = 1]) {
    if (!enabled || muted) return;
    final int n = DateTime.now().millisecondsSinceEpoch;
    v = math.min(1.0, v);
    if (n - (_ts[k] ?? 0) < (_kEventGapMs[k] ?? 45)) return;
    _ts[k] = n;
    switch (k) {
      case 'hitb':
        _play(<String>['hb1', 'hb2', 'hb3', 'hitb'][_r.nextInt(4)], (.35 + .65 * v) * _b('hitb'), .93 + .16 * v);
        break;
      case 'hitp':
        _play('hitp', (.3 + .7 * v) * _b('hitp'), .94 + .14 * v);
        break;
      case 'wall':
        _play('t_wall', .06 + .16 * v);
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
        _play('crowd', _b('crowd')); // crowd cheer
        _after(.16, () => _play('t_goal', 1)); // the 523/659/784/1046 Hz chime, 160 ms after the sample
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
    final List<MapEntry<double, void Function()>> due = _q.where((MapEntry<double, void Function()> e) => e.key <= _clock).toList();
    _q.removeWhere((MapEntry<double, void Function()> e) => e.key <= _clock);
    for (final MapEntry<double, void Function()> e in due) {
      e.value();
    }
  }

  /// Menu music (game.js musicSync: plays while the menu is open, volume .4).
  /// v4 (owner request 2026-11-20): never during a match. The last call wins: a music(true) still creating its
  /// player when music(false) arrives (the setup frame right before an auto-started match) checks [_musicWant]
  /// after every await and stops instead of starting the soundtrack under the match.
  bool _musicWant = false;
  static const double _musicVol = .4;

  /// The call started / ended or somebody started / stopped talking: re-level the music now (the crowd follows on
  /// the next frame, pooled effects on their next play).
  void _onMix() {
    if (_disposed) return;
    final AudioPlayer? m = _music;
    if (m != null && m.state == PlayerState.playing) {
      unawaited(m.setVolume(_musicVol * NxAudioMix.gain).then((_) {}, onError: (Object _) {}));
    }
  }
  Future<void> music(bool on) async {
    _musicWant = on;
    if (!enabled || _disposed) return;
    try {
      if (on && !muted) {
        AudioPlayer? m = _music;
        if (m == null) {
          m = AudioPlayer();
          _music = m;
          await NxAudioMix.apply(m);
          await m.setReleaseMode(ReleaseMode.loop);
        }
        if (!_musicWant || _disposed) return;
        if (m.state == PlayerState.playing) return;
        await m.setVolume(_musicVol * NxAudioMix.gain);
        if (!_musicWant || _disposed) return;
        await m.play(AssetSource('$kBmSfxDir$kBmMusic'));
        if (!_musicWant || _disposed) await m.pause();
      } else {
        final AudioPlayer? m = _music;
        if (m != null && m.state != PlayerState.paused && m.state != PlayerState.stopped) await m.pause();
      }
    } catch (e) {
      debugPrint('bermuda music: $e');
    }
  }

  // ---------------------------------------------------------------- crowd ambience (crowdNext / crowdSync)
  static const double _crowdFade = 1.8, _crowdVol = .3;
  final List<AudioPlayer> _crowdPlayers = <AudioPlayer>[];
  final List<_CrowdClip> _crowdLive = <_CrowdClip>[];
  bool _crowdOn = false;
  double _crowdNextAt = -1;

  /// Bumped on every crowd on/off switch: a [_crowdNext] still loading a clip from an older switch never starts it
  /// (a quick off -> on used to leave two ambience loops playing over each other).
  int _crowdGen = 0;
  bool _crowdLoading = false;
  int _crowdSlot = 0;

  /// Crowd ambience while a match is on and not paused.
  Future<void> crowd(bool on) async {
    if (!enabled || _disposed) return;
    on = on && !muted;
    if (on == _crowdOn) return;
    _crowdOn = on;
    _crowdGen++;
    if (on) {
      _crowdNextAt = _clock; // start now
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
      // gain: 0 -> V over fd, hold, V -> 0 over the last fd seconds
      final double v = _crowdVol * NxAudioMix.gain * math.max(0.0, math.min(1.0, math.min(t / _crowdFade, (c.d - t) / _crowdFade)));
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
        _crowdPlayers.add(p);
        await NxAudioMix.apply(p);
        await p.setReleaseMode(ReleaseMode.stop);
      }
      final String f = kBmCrowd.keys.elementAt(_r.nextInt(kBmCrowd.length));
      final AudioPlayer p = _crowdPlayers[_crowdSlot];
      _crowdSlot = 1 - _crowdSlot;
      _crowdLive.removeWhere((_CrowdClip c) => c.p == p);
      await p.stop();
      await p.setVolume(0);
      await p.setSource(AssetSource('$kBmSfxDir$f'));
      final Duration? dur = await p.getDuration();
      final double d = (dur != null && dur.inMilliseconds > 0) ? dur.inMilliseconds / 1000 : kBmCrowd[f]!;
      if (!_crowdOn || _disposed || gen != _crowdGen) return;
      await p.resume();
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
      unawaited(music(false));
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
    final AudioPlayer? m = _music;
    if (m != null) unawaited(m.dispose().then((_) {}, onError: (Object _) {}));
  }
}
