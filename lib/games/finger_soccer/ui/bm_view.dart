// BERMUDA NXG disc football inside the ANIX hub: pre-match setup (team / formation / field / ball),
// the match (engine + painter + HUD) and the online wiring over the hub's NetLink (Supabase move log).
// 2026-11-24 (owner request): the app's own black-gold match lobby (_setupScreen) is the ONLY pre-match screen,
// offline and online. The reference-game intro (intro/fs_splash, fs_team_select, fs_formation_select, fs_shop,
// fs_online_pick) is no longer opened: online it flashed this lobby first and then swapped to the navy screens.
// Online the lobby shows from the first frame (disabled + "connecting" until the log is replayed), then the side
// picks with one shared countdown ([kOnlinePickSeconds]) that sends the shown pick when it runs out.
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:nexora/core/theme/nx_theme.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nexora/core/economy/gem_shop.dart';
import 'package:nexora/core/online/online_service.dart';
import 'package:nexora/core/profile/profile_service.dart';
import 'package:nexora/core/widgets/user_avatar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexora/games/core/game_contract.dart';
import '../core/bm_data.dart';
import '../core/bm_engine.dart';
import '../core/fs_custom_teams.dart';
import 'bm_audio.dart';
import 'bm_ball.dart';
import 'bm_painter.dart';
import 'bm_rematch.dart';
import 'fs_flame.dart';
import '../intro/fs_game_bar.dart';
import '../intro/fs_intro_data.dart';
import '../intro/fs_score_table.dart';
import '../../../core/ui2/luxe.dart';

const String _a = 'assets/games/bermuda/';

/// Online match settings (config.js MATCH_SECONDS / TURN_SECONDS).
const int kBmMatchSeconds = 300;

/// v9 match chrome: the top bar (clock, menu, formation button) below the status bar and the bottom strip (voice
/// controls online, the "one minute left" toast) above the gesture bar. The pitch art is fitted between them, so no
/// control ever sits on the playfield.
/// v12: the top bar is the match scoreboard (menu, both sides' crest + score, the clock, the formation button).
const double kFsTopBarHeight = 56;
const double kFsBottomStripHeight = 58;
/// v12: offline there are no voice controls, so the bottom strip shrinks and the pitch gets the room (bigger pitch).
const double kFsBottomStripCompact = 10;
const double kBmOnlineTurnSeconds = 10;

/// v6 reference: how long the "one minute left" toast stays up (about 3 s in the recordings).
const double kBmMinuteToastSeconds = 3;

class BermudaView extends StatefulWidget {
  const BermudaView({super.key, required this.launch, this.autoStart = false, this.pick});
  final GameLaunch launch;

  /// Offline: teams and formations chosen in the pre-match intro (intro/fs_intro_flow.dart); with [autoStart] the
  /// match starts with them once the saved field / ball are loaded.
  final FsMatchPick? pick;

  /// Offline only: skip the setup screen with the saved/default picks (used by tests).
  final bool autoStart;

  @override
  State<BermudaView> createState() => _BermudaViewState();
}

class _Setup {
  _Setup(this.team, this.form, this.field, this.ball);
  String team;
  int form, field, ball;
  Map<String, dynamic> toJson() => <String, dynamic>{
        'a': 'setup',
        'team': team,
        'form': form,
        'field': field,
        'ball': ball
      };
  static _Setup? fromJson(Map<String, dynamic> d) {
    final String? t = d['team'] as String?;
    if (t == null) return null;
    int i(String k) => (d[k] as num?)?.toInt() ?? 0;
    return _Setup(
        t,
        i('form').clamp(0, kBmForms.length - 1).toInt(),
        bmFieldIndex(i('field')),
        bmBallIndex((d['ball'] as num?)?.toInt()));
  }
}

class _BermudaViewState extends State<BermudaView>
    with TickerProviderStateMixin, WidgetsBindingObserver
    implements BmHooks {
  late final BmEngine e = BmEngine(this);
  final BmImages im = BmImages();
  final BmView view = BmView();
  late final BmAudio audio = BmAudio(enabled: widget.launch.soundOn);
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  /// v12: the scoreboard's data; it only notifies when something it shows changes (not every frame).
  final ValueNotifier<FsHudData> _hud = ValueNotifier<FsHudData>(FsHudData.empty);
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _nowMs = 0;
  late final AnimationController _goalAnim =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2000)); // v6: = kBmGoalHold (was 1800)

  // setup
  String stage = 'setup'; // setup | waiting | match
  late _Setup my = _Setup(kDefaultTeam, 0, 0, kBmDefaultBall);
  int _cat = 0;
  BmConfig? cfg;

  // toast
  String _toast = '';
  bool _toastBig = false;
  double _toastT = 0;

  // end
  double _finishIn = -1;
  bool _reported = false;

  /// v6: seconds left on the end-of-match score table (reference "جدول امتیازات"), -1 when it is not shown.
  double _tableT = -1;

  /// v13: online rematch on the score table (bm_rematch.dart); null offline, in tournaments and before the end.
  FsRematchController? _rematch;

  /// v6 reference toast "یک دقیقه تا پایان بازی": seconds it stays up, fired once when the match clock enters its
  /// last minute.
  double _minuteT = 0;
  double _prevMleft = -1;

  /// v6 score table avatars per global seat (ANIX avatar id or photo url), exchanged on the live channel ('fs_av').
  final Map<int, String> _avatars = <int, String>{};
  /// Uploaded custom-team crest per global online seat, exchanged with the avatar event.
  final Map<int, String> _customTeamUrls = <int, String>{};

  /// The team id saved in the prefs (a shared custom team may load after the prefs; see _customTeamsChanged).
  String? _savedTeam;
  StreamSubscription<NetLiveMessage>? _liveSub;
  bool _disposed = false;
  bool _paused = false;
  final FsBarSettings _barSettings = FsBarSettings();

  // online
  NetInbox? _inbox;
  bool _netReady = true;
  final Map<int, _Setup> _setups = <int, _Setup>{};
  Map<String, dynamic>? _pendingShot;
  int _pendingShotSeat = -1;
  final List<Completer<void>> _waiters = <Completer<void>>[];

  /// v4 online picks: a play move was replayed before any match started (a match logged before the online
  /// pre-match picks existed); such a room match starts from its room prefs exactly as before.
  bool _sawPlay = false;

  /// v4: started when this phone's setup is sent; if the other side's setup has not arrived when it fires, this
  /// phone logs a default setup FOR that side (first setup per side in the log wins on both phones).
  Timer? _setupFallback;

  /// v5 shared picks: team picks logged so far ({'a': 'tpick'}, or a side's 'setup'), by side.
  final Map<int, String> _teamPicks = <int, String>{};

  /// Pass-and-play (offline, no bot): which side the lobby is picking for (0 = team one, 1 = team two) and side two's
  /// pick (null = a random opponent as before).
  int _pickSide = 0;
  String? _oppTeam;
  int? _oppForm;
  bool get _localTwo => !online && !launch.vsBot;

  GameLaunch get launch => widget.launch;
  bool get online => launch.online;
  int get mySeat => launch.mySeat;
  bool get isHostSeat => mySeat == 0;

  /// Tests: the running match's engine (null before the match starts).
  @visibleForTesting
  BmEngine? get matchEngine => stage == 'match' ? e : null;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    WidgetsBinding.instance.addObserver(this);
    // shared custom teams (تیم‌های اختصاصی): the lobby lists them; reload so a team made since the last load shows
    FsCustomTeams.instance.addListener(_customTeamsChanged);
    final OnlineService? onl = OnlineService.current;
    if (onl?.client != null && onl!.client!.auth.currentSession != null) {
      unawaited(FsCustomTeams.instance.load(onl.client!));
    }
    unawaited(audio.init());
    final Future<void> prefs = _loadPrefs();
    final NetLink? net = launch.net;
    if (net != null) {
      _netReady = false;
      final NetInbox inbox = NetInbox(_onNet);
      _inbox = inbox;
      _avatars[mySeat] = _myAvatar;
      _liveSub = net.live.listen(_onLive, onError: (Object _) {});
      _announceAvatar();
      net.listen(inbox.add,
          onReplayDone: () => inbox.add(const NetMove(
              seq: -1,
              seat: -1,
              kind: 'replayDone',
              data: <String, dynamic>{})));
    } else if (widget.autoStart && widget.pick != null) {
      prefs.then((_) {
        if (mounted && stage == 'setup') _startOffline();
      });
    } else if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && stage == 'setup') _startOffline();
      });
    }
  }

  Future<void> _loadPrefs() async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      final String t = p.getString('bm.team') ?? kDefaultTeam;
      _savedTeam = t;
      my = _Setup(
          // Only an owned (or free) team can be fielded; locked teams fall back to the default free team. A shared
          // custom team (cx_...) may not be in the list yet; usableTeam checks its ownership.
          GemShop.instance.usableTeam(kBmTeams.any((BmTeam x) => x.id == t) || bmIsCustomTeamId(t) ? t : kDefaultTeam),
          (p.getInt('bm.form') ?? 0).clamp(0, kBmForms.length - 1).toInt(),
          bmFieldIndex(p.getInt(kBmFieldPref)),
          bmBallIndex(p.getInt(kBmBallPref)));
      _cat = math.max(0,
          kBmCats.indexWhere((List<Object> c) => c[0] == bmTeam(my.team).cat));
      audio.announcer = p.getBool('bm.ann') ??
          false; // goal announcer voice: off unless the player turns it on
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _savePrefs() async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      await p.setString('bm.team', my.team);
      await p.setInt('bm.form', my.form);
      await p.setInt(kBmFieldPref, my.field);
      await p.setInt(kBmBallPref, my.ball);
    } catch (_) {}
  }

  /// This player's avatar for the score table: an uploaded photo (https) or the chosen ANIX portrait.
  String get _myAvatar {
    final ProfileService? pr = ProfileService.current;
    final String? url = pr?.avatarUrl;
    if (url != null && NxUserAvatar.isPhoto(url)) return url;
    return pr?.portrait ?? '01-vanguard';
  }

  void _announceAvatar() {
    try {
      launch.net?.sendLive('fs_av', <String, dynamic>{
        'av': _myAvatar,
        // custom team crest (network url) + its id, so a phone that has not loaded that team still draws it
        'team': bmTeam(my.team).crestUrl ?? '',
        'tid': my.team,
      });
    } catch (_) {}
  }

  void _onLive(NetLiveMessage m) {
    if (_disposed || m.event != 'fs_av' || m.seat < 0 || m.seat == mySeat) return;
    final dynamic av = m.data['av'];
    if (av is! String || av.isEmpty || av.length > 512) return;
    final bool known = _avatars.containsKey(m.seat);
    _avatars[m.seat] = av;
    final dynamic team = m.data['team'];
    if (team is String && team.startsWith('https://') && team.length <= 2048) {
      _customTeamUrls[m.seat] = team;
      if (stage == 'match' && cfg != null) unawaited(_loadMatchImages(cfg!));
    }
    final dynamic tid = m.data['tid'];
    if (tid is String && bmIsCustomTeamId(tid) && FsCustomTeams.instance.byTeamId(tid) == null) {
      unawaited(FsCustomTeams.instance.ensure(OnlineService.current?.client, tid));
    }
    // a phone we had not heard from yet (joined late): tell it ours once
    if (!known) _announceAvatar();
  }

  // ------------------------------------------------------------------ loop
  void _onTick(Duration el) {
    double dt = (el - _last).inMicroseconds / 1e6;
    _last = el;
    if (dt < 0) dt = 0;
    _nowMs = el.inMicroseconds / 1000;
    // v9: while the Flame scene is running the match it advances the game (FsFlameGame.update -> _advance); this
    // ticker only keeps the clock for the painters and drives the screens before / without the Flame scene.
    if (stage == 'match' && _nowMs - _flameAtMs < 250) return;
    _advance(dt);
  }

  /// Time of the last Flame frame on the ticker's clock (ms).
  double _flameAtMs = -1e9;

  void _flameFrame(double dt) {
    if (_disposed) return;
    _flameAtMs = _nowMs;
    _advance(dt);
  }

  /// One frame of the match screen: audio, toasts, the engine, clocks, net waiters and the end of the match.
  void _advance(double dt) {
    audio.frame(dt);
    if (_toastT > 0) _toastT -= dt;
    if (_minuteT > 0) _minuteT -= dt;
    if (stage == 'match') {
      _ensureBallRenderer();
      e.frame(dt);
      // v6 reference: "یک دقیقه تا پایان بازی" once, when the clock enters the last minute (not on a rejoin that
      // starts inside it, not in golden goal).
      if (e.mt > 60 && !e.sd && e.phase != 'over' && _prevMleft > 60 && e.mleft <= 60) {
        _minuteT = kBmMinuteToastSeconds;
      }
      _prevMleft = e.mleft;
      if (_waiters.isNotEmpty && e.phase != 'goal') {
        final List<Completer<void>> w = List<Completer<void>>.from(_waiters);
        _waiters.clear();
        for (final Completer<void> c in w) {
          if (!c.isCompleted) c.complete();
        }
      }
      if (_finishIn > 0) {
        _finishIn -= dt;
        if (_finishIn <= 0) {
          // v6: the score table comes up and the result is reported at once; the host holds its own result screen
          // until the table's countdown is over (GameResult.holdMs).
          _tableT = kFsScoreTableSeconds.toDouble();
          // v13: online room matches offer "بازی مجدد" on the table; the host's result overlay waits while a rematch
          // request is open (GameResult.holdUntil).
          if (online && _rematch == null) {
            _rematch = FsRematchController.forLink(launch.net,
                tournamentMatchId: launch.tournamentMatchId, onGo: _goRematch);
          }
          _report(holdMs: kFsScoreTableSeconds * 1000, holdUntil: _rematch?.released);
          // v6.1 fix: the table is a child of build(), not of the per-frame builders: rebuild once to show it.
          if (mounted && !_disposed) setState(() {});
        }
      }
      if (_tableT > 0) {
        _tableT = math.max(0, _tableT - dt);
        if (_tableT <= 0) _rematch?.tableDone();
      }
      _checkSideLeft();
    }
    if (_disposed) return;
    _frame.value++;
    if (stage == 'match') _hud.value = _hudData();
  }

  /// The scoreboard's current data (quantised so it changes a few times a second, not every frame).
  FsHudData _hudData() {
    final bool hasBodies = e.bodies.isNotEmpty;
    return FsHudData(
      clock: _clockText(),
      red: ((e.mt > 0 && !e.sd ? bmClockRed(e.mleft, e.mt) : (e.sd ? 1.0 : 0.0)) * 20).round() / 20,
      turn: e.phase == 'aim' && e.tt > 0 ? ((e.tleft / e.tt).clamp(0.0, 1.0) * 60).round() / 60 : -1,
      turnMine: e.turn == 0,
      score0: e.score[0],
      score1: e.score[1],
      name0: hasBodies ? e.nm(0) : '',
      name1: hasBodies ? e.nm(1) : '',
      crest0: _hudCrests[0],
      crest1: _hudCrests[1],
      pulse0: (e.shake[0].clamp(0.0, 1.0) * 10).round() / 10,
      pulse1: (e.shake[1].clamp(0.0, 1.0) * 10).round() / 10,
      formation: _tableT < 0,
    );
  }

  void _ensureBallRenderer() {
    final ui.Image? b = im.ball;
    if (b == null || view.s <= 0 || im.ballSheet != null) return;
    final double dpr =
        math.min(MediaQuery.maybeDevicePixelRatioOf(context) ?? 1, 1.75);
    final int n = math.max(
        40, math.min(96, math.max(2, (BR * 2 * view.s * dpr).round())));
    if (im.ballR == null || im.ballR!.n != n) {
      im.ballR?.dispose();
      final BmBallRenderer r = BmBallRenderer(n, flat: true);
      im.ballR = r;
      unawaited(r.setTexture(b));
    }
  }

  // ------------------------------------------------------------------ hooks
  @override
  void sfx(String k, [double v = 1]) => audio.sfx(k, v);

  @override
  void tone(String k) => audio.tone(k);

  @override
  void vib(List<int> pattern) {
    if (!launch.soundOn) return;
    final int total = pattern.fold(0, (int a, int b) => a + b);
    if (total >= 100) {
      HapticFeedback.heavyImpact();
    } else if (total >= 30) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.lightImpact();
    }
  }

  @override
  void toast(String text, bool big) {
    _toast = text;
    _toastBig = big;
    _toastT = big ? 1.5 : 1.2;
  }

  @override
  void goalFx() {
    if (_disposed) return;
    _goalAnim.forward(from: 0);
  }

  @override
  void emit(String event, Map<String, dynamic> data) {
    final NetLink? net = launch.net;
    switch (event) {
      case 'shot':
        net?.send(<String, dynamic>{
          'a': 'shot',
          'cid': data['cid'],
          'vx': data['vx'],
          'vy': data['vy'],
          'power': data['power'],
        }, kind: 'move');
        break;
      case 'settled':
        net?.send(<String, dynamic>{
          'a': 'settled',
          'snap': data['snap'],
          'mt': data['mt']
        });
        break;
      case 'goal':
        net?.send(<String, dynamic>{
          'a': 'goal',
          'team': data['team'],
          'nogoal': data['nogoal']
        });
        break;
      case 'timeout':
        net?.send(<String, dynamic>{'a': 'timeout', 'seat': data['team']}, kind: 'timeout');
        break;
      case 'turn':
        if (net != null) {
          final int side = data['turn'] as int;
          final int seat = e.controllerSeat(side);
          net.turnSeat = seat;
          if (e.perSide > 1 && seat < net.names.length) {
            toast(seat == mySeat ? launch.tx('نوبت توست!', 'Your shot!') : net.names[seat], false);
          }
        }
        break;
      case 'end':
        final List<int> local = (data['local'] as List<dynamic>).cast<int>();
        _end(local);
        break;
    }
  }

  // ------------------------------------------------------------------ start / end
  void _startOffline() {
    final math.Random r = math.Random(launch.seed);
    // Bots / local opponents draw from every category (Club, National, Luxury) so all supplied crests appear.
    final List<BmTeam> clubs = kBmTeams
        .where((BmTeam t) => t.id != my.team && t.cat != 'custom' && (t.cat != 'nx' || r.nextInt(4) == 0))
        .toList();
    final FsMatchPick? pk = widget.pick;
    final String opp = pk != null ? pk.teams[1] : (_localTwo ? _oppTeam : null) ?? clubs[r.nextInt(clubs.length)].id;
    final String mine = pk != null ? pk.teams[0] : my.team;
    final bool bot = launch.vsBot;
    final int lvl = switch (launch.difficulty) {
      BotDifficulty.easy => 0,
      BotDifficulty.normal => 1,
      BotDifficulty.hard => 2
    };
    final String me =
        launch.playerName.isEmpty ? 'Player 1' : launch.playerName;
    _begin(BmConfig(
      mode: bot ? 'bot' : 'local',
      teams: <String>[mine, opp],
      form: pk != null
          ? <int>[pk.forms[0].clamp(0, kBmForms.length - 1).toInt(), pk.forms[1].clamp(0, kBmForms.length - 1).toInt()]
          : <int>[my.form, (_localTwo ? _oppForm : null) ?? r.nextInt(kBmForms.length)],
      names: bot
          ? <String>[
              me,
              'Bot ${<String>['Rookie', 'Pro', 'Legend'][lvl]}'
            ]
          : <String>['Player 1', 'Player 2'],
      field: my.field,
      ball: my.ball,
      limit: 0,
      matchTime: kBmMatchSeconds,
      turnTime: 0,
      ai: bot,
      aiLvl: lvl,
    ));
  }

  /// Players per side online: seats alternate sides (0,2,4 vs 1,3,5) -> 1v1, 2v2 or 3v3.
  int get _perSide => online ? math.max(1, (launch.net?.seatCount ?? 2) ~/ 2) : 1;
  int get _mySide => mySeat % 2;

  /// Room matches carry each picked player's pre-game choices (team / formation) and the room manager's field / ball,
  /// so the match starts straight away without the in-game setup screen.
  Map<String, dynamic>? get _roomPrefs {
    final dynamic p = launch.net?.settings['room_prefs'];
    return p is Map ? Map<String, dynamic>.from(p) : null;
  }

  _Setup? _prefSetup(int seat) {
    final Map<String, dynamic>? rp = _roomPrefs;
    if (rp == null) return null;
    final Map<String, dynamic> st = launch.net!.settings;
    final dynamic mine = rp['$seat'];
    final Map<String, dynamic> m = mine is Map ? Map<String, dynamic>.from(mine) : <String, dynamic>{};
    final String t = '${m['team'] ?? ''}';
    final String team =
        kBmTeams.any((BmTeam x) => x.id == t) || bmIsCustomTeamId(t) ? t : (seat == 0 ? 'club0' : 'club1');
    int i(dynamic v, int max) => ((v as num?)?.toInt() ?? 0).clamp(0, max - 1).toInt();
    return _Setup(team, i(m['form'], kBmForms.length), bmFieldIndex((st['field'] as num?)?.toInt()),
        bmBallIndex((st['ball'] as num?)?.toInt()));
  }

  /// Side name: "Ali" for 1v1, "Ali · Sara · Reza" for team games.
  String _sideName(NetLink net, int side) => <String>[
        for (int s = side; s < net.seatCount; s += 2)
          if (s < net.names.length) net.names[s]
      ].join(' · ');

  void _maybeStartOnline({bool quiet = false}) {
    if (stage == 'match') return;
    _Setup? h = _setups[0], g = _setups[1];
    if (_roomPrefs != null && _sawPlay) {
      h ??= _prefSetup(0);
      g ??= _prefSetup(1);
    }
    if (h == null || g == null) return;
    final NetLink net = launch.net!;
    e.localSeat = mySeat;
    // v5: a teammate takes the turns of a seat that left (team games), so the match plays on without dead turns.
    e.seatGone = (int s) => launch.net?.forfeitedSeats.contains(s) ?? false;
    _begin(
        BmConfig(
          mode: 'online',
          teams: <String>[h.team, g.team],
          form: <int>[h.form, g.form],
          names: <String>[_sideName(net, 0), _sideName(net, 1)],
          field: h.field,
          ball: h.ball,
          // Tournament rules (server-set in nx_matches.settings): first to N goals, or 3/5/7 minutes.
          // A golden-goal decider game is first to 1. Engine and physics are unchanged.
          limit: _goalLimit(net.settings),
          matchTime: _goalLimit(net.settings) > 0 ? 0 : _matchSeconds(net.settings),
          turnTime: kBmOnlineTurnSeconds,
          mirror: _mySide == 1,
          first: 0,
          perSide: _perSide,
        ),
        quiet: quiet);
  }

  static int _goalLimit(Map<String, dynamic> st) {
    if (st['golden_goal'] == true) return 1;
    final int g = (st['goal_target'] as num?)?.toInt() ?? 0;
    return g.clamp(0, 20);
  }

  static int _matchSeconds(Map<String, dynamic> st) {
    final int m = (st['match_minutes'] as num?)?.toInt() ?? 0;
    return (m == 3 || m == 5 || m == 7) ? m * 60 : kBmMatchSeconds;
  }

  void _begin(BmConfig c, {bool quiet = false}) {
    cfg = c;
    e.startMatch(c);
    if (quiet) e.menuOpen = false;
    stage = 'match';
    _finishIn = -1;
    _tableT = -1;
    _minuteT = 0;
    _prevMleft = -1;
    if (online) _announceAvatar();
    _loadMatchImages(c);
    unawaited(audio.music(false));
    unawaited(audio.crowd(true));
    if (mounted) setState(() {});
  }

  Future<ui.Image?> _img(String path, {int? w}) async {
    try {
      final ByteData data = await DefaultAssetBundle.of(context).load(path);
      final ui.Codec codec = await ui
          .instantiateImageCodec(data.buffer.asUint8List(), targetWidth: w);
      final ui.FrameInfo f = await codec.getNextFrame();
      codec.dispose();
      return f.image;
    } catch (err) {
      debugPrint('bermuda image $path: $err');
      return null;
    }
  }

  Future<ui.Image?> _imgNetwork(String? url, {int? w}) async {
    if (url == null || !url.startsWith('http')) return null;
    try {
      final ByteData data = await NetworkAssetBundle(Uri.parse(url)).load(url);
      final ui.Codec codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: w);
      final ui.FrameInfo f = await codec.getNextFrame();
      codec.dispose();
      return f.image;
    } catch (err) {
      debugPrint('bermuda network image $url: $err');
      return null;
    }
  }

  Future<void> _loadMatchImages(BmConfig c) async {
    final BmFieldS f = kBmFields[bmFieldIndex(c.field)];
    // shared custom teams draw their uploaded crest: from the list (fetched now when this phone does not know the
    // team yet), else the url the other phone sent with its avatar; the team's fallback disc when both fail
    Future<String?> crest(int side) async {
      final String id = c.teams[e.ct(side)];
      if (!bmIsCustomTeamId(id)) return null;
      final FsCustomTeam? t = await FsCustomTeams.instance.ensure(OnlineService.current?.client, id);
      return t?.crestUrl ?? (online ? _customTeamUrls[side] : null);
    }

    final List<String?> crests = await Future.wait(<Future<String?>>[crest(0), crest(1)]);
    if (!mounted || _disposed) return;
    final String? team0Custom = crests[0], team1Custom = crests[1];
    final List<ui.Image?> r = await Future.wait(<Future<ui.Image?>>[
      _img(f.asset),
      f.builtInGoals ? Future<ui.Image?>.value(null) : _img('${_a}goals/${f.gs}.webp'),
      // v9: every ball is a flat art the 3D roller rolls with the ball's motion (no sprite sheet)
      _img(bmBallArt(c.ball)),
      _imgNetwork(team0Custom, w: 192).then((ui.Image? x) => x ?? _img(bmTeam(c.teams[e.ct(0)]).asset, w: 192)),
      _imgNetwork(team1Custom, w: 192).then((ui.Image? x) => x ?? _img(bmTeam(c.teams[e.ct(1)]).asset, w: 192)),
    ]);
    if (!mounted || _disposed) {
      for (final ui.Image? i in r) {
        i?.dispose();
      }
      return;
    }
    final anim = kBmAnimBalls[c.ball];
    final ui.Image? sheet = anim == null ? null : await _img(anim.sheet);
    if (!mounted || _disposed) {
      for (final ui.Image? i in r) {
        i?.dispose();
      }
      sheet?.dispose();
      return;
    }
    im.dispose();
    im.field = r[0];
    im.goal = r[1];
    im.ball = r[2];
    if (anim != null && sheet != null) {
      im.ballSheet = sheet;
      im.ballFrames = anim.frames;
      im.ballFrameMs = anim.frameMs;
      im.ballTimed = anim.gifTimed;
      im.animMs = 0;
    }
    im.team[0] = r[3];
    im.team[1] = r[4];
    _refreshHudCrests();
  }

  /// v12: the scoreboard holds its own handles (clones) of the two crests, so replacing / disposing the match images
  /// never leaves it painting a disposed image: the old handles are released only after the next frame, when the
  /// scoreboard has been rebuilt with the new ones.
  List<ui.Image?> _hudCrests = <ui.Image?>[null, null];
  void _refreshHudCrests() {
    final List<ui.Image?> old = _hudCrests;
    _hudCrests = <ui.Image?>[im.team[0]?.clone(), im.team[1]?.clone()];
    if (stage == 'match') _hud.value = _hudData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final ui.Image? i in old) {
        i?.dispose();
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _end(List<int> local) {
    if (_finishIn > 0 || _reported) return;
    _finishIn = 1.6;
    unawaited(audio.crowd(false));
  }

  /// v5 team games: every seat of one side has left (forfeited) while the match runs -> the other side wins now
  /// instead of playing on against nobody.
  void _checkSideLeft() {
    final NetLink? net = launch.net;
    if (net == null || _reported || _finishIn > 0 || e.perSide < 2) return;
    final Set<int> gone = net.forfeitedSeats;
    if (gone.isEmpty) return;
    for (int side = 0; side < 2; side++) {
      bool all = true;
      for (int s = side; s < net.seatCount; s += 2) {
        if (!gone.contains(s)) all = false;
      }
      if (all) {
        _report(sideLeft: side);
        return;
      }
    }
  }

  void _report({bool forfeit = false, int? sideLeft, bool leftTeam = false, int? holdMs, Future<void>? holdUntil}) {
    if (_reported) return;
    _reported = true;
    final List<int> sc = e.score; // local: [me, opponent]
    // v5: a whole side left (team games): the side still playing wins whatever the score.
    final bool won = sideLeft != null ? sideLeft != _mySide : (!forfeit && sc[0] > sc[1]);
    final bool draw = sideLeft == null && !forfeit && sc[0] == sc[1];
    final int winSide = won ? _mySide : 1 - _mySide;
    final int seats = launch.net?.seatCount ?? 2;
    final List<int> global = <int>[sc[e.ct(0)], sc[e.ct(1)]];
    // v5 team games (owner bug: players 3+ got the wrong result): the server books seat i's score from scores[i],
    // so every seat gets its own side's goals (seats 0,2,4 = side 0; 1,3,5 = side 1), not only seats 0 and 1.
    // A seat that left (forfeited) is never among the winners: it books a loss while its side keeps its result.
    final Set<int> gone = launch.net?.forfeitedSeats ?? const <int>{};
    launch.onFinish(GameResult(
      outcome:
          draw ? GameOutcome.draw : (won ? GameOutcome.win : GameOutcome.loss),
      score: sc[0],
      opponentScore: sc[1],
      winnerSeats: draw
          ? <int>[]
          : <int>[
              for (int s = winSide; s < math.max(2, seats); s += 2)
                if (!gone.contains(s)) s
            ],
      scores: <int>[for (int s = 0; s < math.max(2, seats); s++) global[s % 2]],
      tournamentMatchId: launch.tournamentMatchId,
      endsMatch: !leftTeam,
      holdMs: holdMs,
      holdUntil: holdUntil,
      summaryFa:
          'نتیجه‌ی فوتبال: ${sc[0]} - ${sc[1]}${forfeit ? ' (انصراف)' : ''}',
      summaryEn:
          'Football final: ${sc[0]} - ${sc[1]}${forfeit ? ' (forfeit)' : ''}',
    ));
  }

  // ------------------------------------------------------------------ online
  Future<void> _waitPlayable() async {
    if (stage == 'match' && e.phase != 'goal') return;
    final Completer<void> c = Completer<void>();
    _waiters.add(c);
    await c.future;
  }

  Future<void> _onNet(NetMove m) async {
    if (_disposed) return;
    if (m.kind == 'replayDone') {
      _netReady = true;
      final Map<String, dynamic>? ps = _pendingShot;
      _pendingShot = null;
      if (stage == 'match') {
        e.menuOpen = false;
        if (ps != null && e.phase == 'aim') {
          if (_pendingShotSeat == mySeat) {
            // our own shot was logged but never settled: run it locally so we post the snapshot
            final int cid = (ps['cid'] as num).toInt();
            for (final BmBody b in e.bodies) {
              if (b.cid == cid) {
                final int sg = e.mirror ? -1 : 1;
                e.launch(b, (ps['vx'] as num).toDouble() * sg,
                    (ps['vy'] as num).toDouble() * sg, false);
              }
            }
          } else {
            e.remoteShot(ps);
          }
        }
      } else {
        _maybeStartOnline();
        if (stage != 'match') {
          if (_roomPrefs != null && !_setups.containsKey(mySeat)) {
            // v4: the room's pre-game choice is the starting pick on the online team / formation screens.
            final _Setup? rp = _prefSetup(mySeat);
            if (rp != null) my = _Setup(GemShop.instance.usableTeam(rp.team), rp.form, rp.field, rp.ball);
          }
          if (_setups.containsKey(mySeat)) {
            stage = 'waiting';
          } else if (mySeat > 1) {
            // team games: seats 0 and 1 pick their side's team / formation; the others wait for them.
            stage = 'waiting';
          }
          // ANIX PRO watchdog on every phone from the moment the log is replayed (picks included).
          _armSetupFallback();
          // v13 rematch: this phone's team / formation (and the host's pitch / ball) from the match just played are
          // logged at once, so the rematch starts without the pick screens.
          final Map<String, dynamic>? carry = FsRematchCarry.take(launch.net!);
          final _Setup? cs = carry == null ? null : _Setup.fromJson(carry);
          if (cs != null && mySeat <= 1 && !_setups.containsKey(mySeat) && stage != 'match') {
            my = _Setup(GemShop.instance.usableTeam(cs.team), cs.form, cs.field, cs.ball);
            _sendSetup();
          }
        }
      }
      if (mounted) setState(() {});
      return;
    }
    if (m.kind == 'ownSetup') {
      // our own setup (or a fallback we logged for a side) is confirmed in the log at this point of the stream
      final _Setup? s = _Setup.fromJson(m.data);
      if (s != null && !_setups.containsKey(m.seat)) _setups[m.seat] = s;
      _maybeStartOnline();
      if (mounted) setState(() {});
      return;
    }
    if (m.kind != 'move' && m.kind != 'timeout') return;
    final Map<String, dynamic> d = m.data;
    final String a = '${d['a']}';
    if (a == 'tpick') {
      // v5: a side's team pick (before its formation). Never a play move, so it does not mark a legacy room match.
      final int seat = ((d['for'] as num?)?.toInt() ?? m.seat);
      final dynamic t = d['team'];
      if (t is String && seat >= 0 && !_teamPicks.containsKey(seat)) _teamPicks[seat] = t;
      if (mounted) setState(() {});
      return;
    }
    if (a == 'setup') {
      final _Setup? s = _Setup.fromJson(d);
      // v4: a setup may be logged FOR an absent side ('for', see _armSetupFallback); the first per side wins.
      final int seat = ((d['for'] as num?)?.toInt() ?? m.seat);
      if (s != null && seat >= 0 && !_setups.containsKey(seat)) _setups[seat] = s;
      _maybeStartOnline(quiet: m.replay);
      if (mounted) setState(() {});
      return;
    }
    if (stage != 'match') {
      if (m.replay) _sawPlay = true;
      return;
    }
    if (m.replay) {
      _replayMove(m.seat, a, d);
      return;
    }
    await _waitPlayable();
    if (_disposed) return;
    switch (a) {
      case 'shot':
        e.remoteShot(d);
        break;
      case 'settled':
        e.remoteSettled(d);
        break;
      case 'goal':
        e.remoteGoal(d);
        break;
      case 'timeout':
        e.remoteTimeout(d);
        break;
      case 'form':
        applyFormationChange((d['side'] as num).toInt(), (d['form'] as num).toInt(), quiet: true);
        break;
    }
  }

  /// Fast-forwards the logged match after a (re)join without animating shots.
  void _replayMove(int seat, String a, Map<String, dynamic> d) {
    switch (a) {
      case 'shot':
        _pendingShot = d;
        _pendingShotSeat = seat;
        break;
      case 'settled':
        _pendingShot = null;
        final Map<String, dynamic>? snap =
            (d['snap'] as Map?)?.cast<String, dynamic>();
        e.applySnapshot(snap);
        e.applyRotation(snap);
        final List<dynamic>? sc = snap?['sc'] as List<dynamic>?;
        if (sc != null && sc.length == 2) {
          e.score[e.ct(0)] = (sc[0] as num).toInt();
          e.score[e.ct(1)] = (sc[1] as num).toInt();
        }
        final num? tn = snap?['tn'] as num?;
        if (tn != null) e.turn = e.ct(tn.toInt());
        e.phase = 'aim';
        e.remote = false;
        e.shots = 1;
        final num? mt = d['mt'] as num?;
        if (mt != null) e.mleft = mt.toDouble();
        break;
      case 'goal':
        _pendingShot = null;
        final int t = e.ct((d['team'] as num).toInt());
        final bool ng = d['nogoal'] == true;
        if (!ng) e.score[t]++;
        e.reset(ng ? e.turn : 1 - t);
        break;
      case 'form':
        e.changeForm((d['side'] as num).toInt(), (d['form'] as num).toInt());
        break;
      case 'timeout':
        final num? s = d['seat'] as num?;
        if (s == null || e.ct(e.turn) == s.toInt()) {
          e.turn = 1 - e.turn;
          e.bumpRotation();
          e.phase = 'aim';
        }
        break;
    }
  }

  void _sendSetup() {
    final NetLink? net = launch.net;
    if (net == null) return;
    final _Setup mine = _Setup(GemShop.instance.usableTeam(my.team), my.form, my.field, my.ball);
    // ANIX PRO: the setup counts only once it is in the server log (order-independent 'fl' move, re-posted after a
    // seq race). A default setup logged FOR this side before it (fallback of another phone) wins on every phone, so
    // this phone adopts the log instead of its local pick: both phones always start from the same setups.
    stage = 'waiting';
    _armSetupFallback();
    unawaited(net.send(<String, dynamic>{...mine.toJson(), kNetFloat: true}).then((bool ok) {
      if (_disposed) return;
      if (ok) {
        _inbox?.add(NetMove(seq: -2, seat: mySeat, kind: 'ownSetup', data: mine.toJson()));
      } else {
        _setupSendFailed = true;
        if (mounted) setState(() {});
      }
    }));
    setState(() {});
  }


  /// ANIX PRO watchdog: after this many seconds without a match the waiting screen offers to leave.
  static const int kOnlineStallSeconds = 75;

  /// Seconds from the end of the log replay (the picks open) before missing setups are filled in: the shared pick
  /// time (team 15 s + grace 3 s + formation 15 s) plus a margin, so a slow but present opponent always gets to pick.
  static const int kOnlineFirstFillSeconds = 45;

  /// A send of this phone's setup was refused (offline / match over): the waiting screen shows retry / leave.
  bool _setupSendFailed = false;
  Timer? _stallTimer;
  int _waitedSeconds = 0;

  /// The pre-match watchdog (every phone, every seat): every 20 s (from [kOnlineFirstFillSeconds]) without a match it logs a
  /// default setup FOR each side (0 / 1) that still has none, so an absent or silent side can never hold the match
  /// on the pick screens. The first setup per side in the log wins on every phone, so this never desyncs.
  void _armSetupFallback() {
    if (_stallTimer != null || stage == 'match') return;
    _stallTimer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (_disposed || stage == 'match') {
        t.cancel();
        return;
      }
      _waitedSeconds++;
      if (_onlinePicking) {
        if (_waitedSeconds >= kOnlinePickSeconds) {
          _sendSetup(); // time is up: the pick on screen goes out
        } else if (mounted) {
          setState(() {}); // the countdown on the READY button
        }
      }
      // seats 0 / 1 fill in after the shared pick time; seats 2+ (team games) a little later
      final int first = kOnlineFirstFillSeconds + (mySeat > 1 ? 10 : 0);
      if (_waitedSeconds >= first && (_waitedSeconds - first) % 20 == 0) _fillMissingSetups();
      if (_waitedSeconds == kOnlineStallSeconds && mounted) setState(() {});
    });
  }

  void _fillMissingSetups() {
    final NetLink? net = launch.net;
    if (_disposed || net == null || stage == 'match') return;
    for (final int side in <int>[0, 1]) {
      if (_setups.containsKey(side)) continue;
      // our own side: our real pick is in flight (or about to be); only fill the OTHER sides
      if (side == mySeat) continue;
      final _Setup d = (_roomPrefs != null ? _prefSetup(side) : null) ??
          _Setup(side == 0 ? 'club0' : 'club1', 0, my.field, my.ball);
      unawaited(net.send(<String, dynamic>{...d.toJson(), 'for': side, kNetFloat: true}).then((bool ok) {
        if (ok && !_disposed) {
          _inbox?.add(NetMove(seq: -2, seat: side, kind: 'ownSetup', data: d.toJson()));
        }
      }));
    }
  }

  /// Shown on the waiting screen after [kOnlineStallSeconds] (or a refused send): never a dead end.
  bool get _stalled => _setupSendFailed || _waitedSeconds >= kOnlineStallSeconds;

  void _leaveStalled() {
    final NetLink? net = launch.net;
    if (net != null) unawaited(net.send(<String, dynamic>{'a': 'leave', 'seat': mySeat}, kind: 'forfeit'));
    _report(forfeit: true);
  }

  /// Seconds the online lobby gives seats 0 / 1 to pick (the old team 15 s + formation 15 s). When they run out the
  /// shown pick is sent, so an idle phone never holds the match ([kOnlineFirstFillSeconds] covers an absent one).
  static const int kOnlinePickSeconds = 30;

  /// This phone still has to pick its side online (seats 0 / 1; team-game seats 2+ wait for them).
  bool get _onlinePicking => online && _netReady && mySeat <= 1 && stage == 'setup' && !_setups.containsKey(mySeat);

  int get _pickLeft => math.max(0, kOnlinePickSeconds - _waitedSeconds);

  // ------------------------------------------------------------------ in-match formation change
  /// Global side whose formation the button changes: online this phone's side, vs bot the player's side (0),
  /// pass-and-play the side whose turn it is.
  int get _reformSide => online ? _mySide : (launch.vsBot ? 0 : e.ct(e.turn));

  /// Opens the 3 x 3 formation picker during the match. Rule (docs/DECISIONS.md D11): the new shape applies at once
  /// when it is that side's kickoff shot (its turn, nothing shot since the kickoff), otherwise from the next kickoff.
  /// Online the pick is a logged 'form' move, so the other phone applies the same change in the same order.
  Future<void> _changeFormation() async {
    if (stage != 'match' || e.phase == 'over' || _reported) return;
    final int side = _reformSide;
    audio.sfx('ui');
    final int? fi = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: const Color(0xF0101418),
      isScrollControlled: true,
      builder: (BuildContext ctx) => BmFormationPicker(
        title: launch.tx('تغییر ترکیب', 'Change formation'),
        hint: e.canReformNow(side)
            ? launch.tx('همین الان اعمال می‌شود', 'Applies now')
            : launch.tx('از شروع بعدی اعمال می‌شود', 'Applies from the next kickoff'),
        current: e.form[side],
        selectLabel: launch.tx('انتخاب', 'Select'),
        selectedLabel: launch.tx('انتخاب شده', 'Selected'),
      ),
    );
    if (fi == null || !mounted || stage != 'match' || e.phase == 'over') return;
    // Never during a goal pause: the receiving phone applies logged moves only once play resumes (after the kickoff
    // reset), so the sender waits for the same point and both phones see the same kickoff state.
    await _waitPlayable();
    if (_disposed || stage != 'match' || e.phase == 'over') return;
    applyFormationChange(side, fi, send: true);
  }

  /// Applies a formation change (local pick or a logged 'form' move) and, for a local pick online, logs it.
  void applyFormationChange(int side, int fi, {bool send = false, bool quiet = false}) {
    final bool now = e.changeForm(side, fi);
    if (send) launch.net?.send(<String, dynamic>{'a': 'form', 'side': side, 'form': fi});
    if (!quiet) {
      toast(now ? launch.tx('ترکیب عوض شد', 'Formation changed') : launch.tx('ترکیب از شروع بعدی', 'New formation at next kickoff'),
          false);
    }
    if (mounted) setState(() {});
  }

  // ------------------------------------------------------------------ pause (flow.js pause())
  Future<void> _pause() async {
    if (_reported || _finishIn > 0) return;
    final bool isOnline = online, bot = launch.vsBot;
    if (!isOnline) e.menuOpen = true;
    _paused = true;
    unawaited(audio
        .crowd(false)); // game.js crowdSync: no crowd while the menu is open
    // Reference game bar ("نوار بازی", intro/fs_game_bar.dart) instead of the old pause dialog: exit, mute all and the
    // game volume act on this match; restart (pass-and-play) and the goal announcer keep their old actions.
    String? act;
    _barSettings.mutedAll = audio.muted;
    _barSettings.gameVolume = audio.master;
    await FsGameBar.show(
      context,
      settings: _barSettings,
      players: cfg?.names ?? <String>[launch.playerName],
      me: online ? _mySide : 0,
      online: isOnline,
      connected: _netReady,
      onRestart: (!isOnline && !bot) ? () => act = 'restart' : null,
      extra: <FsBarToggle>[
        FsBarToggle(launch.tx('گزارشگر گل', 'Goal announcer'), audio.announcer, (bool v) {
          audio.announcer = v;
          unawaited(SharedPreferences.getInstance()
              .then((SharedPreferences p) => p.setBool('bm.ann', audio.announcer))
              .then((_) {}, onError: (Object _) {}));
        }),
      ],
      onChanged: (FsBarSettings s) {
        if (audio.muted != s.mutedAll) audio.setMuted(s.mutedAll);
        audio.master = s.gameVolume;
      },
      onExit: () => act = 'leave',
    );
    _paused = false;
    if (!mounted) return;
    if (!isOnline) e.menuOpen = false;
    switch (act) {
      case 'restart':
        e.restart(0);
        break;
      case 'leave':
        if (isOnline && e.perSide > 1 && launch.net != null) {
          // v5 team games: only this seat forfeits (logged, so every phone hands its turns to a teammate); the match
          // goes on for the others and this player books a loss. When a whole side has left, the other side wins.
          unawaited(launch.net!.send(<String, dynamic>{'a': 'leave', 'seat': mySeat}, kind: 'forfeit'));
          _report(forfeit: true, leftTeam: true);
        } else if (isOnline || bot) {
          // flow.js: leaving counts as a loss
          _report(forfeit: true);
        } else {
          // Already confirmed in the game bar: leave without the host's second confirmation.
          final NavigatorState nav = Navigator.of(context);
          if (nav.canPop()) nav.pop();
        }
        break;
    }
    _crowdSync();
  }

  /// game.js crowdSync(): crowd ambience only while a match runs, the menu is closed and the app is visible.
  void _crowdSync() {
    if (_disposed || !mounted) return;
    final bool want = stage == 'match' &&
        !_paused &&
        !_reported &&
        _finishIn <= 0 &&
        _visible;
    unawaited(audio.crowd(want));
  }

  bool _visible = true;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // game.js musicSync/crowdSync stop on document.hidden
    _visible = state == AppLifecycleState.resumed;
    if (!_visible) unawaited(audio.music(false));
    _crowdSync();
    if (_visible && stage != 'match' && launch.soundOn && !_paused) {
      unawaited(audio.music(true));
    }
  }

  void _customTeamsChanged() {
    if (!mounted || _disposed) return;
    // a saved custom team that was not loaded yet when the prefs were read
    if (my.team == kDefaultTeam && _savedTeam != null && bmIsCustomTeamId(_savedTeam!) &&
        GemShop.instance.usableTeam(_savedTeam!) == _savedTeam) {
      my.team = _savedTeam!;
    }
    setState(() {});
  }

  @override
  void dispose() {
    FsCustomTeams.instance.removeListener(_customTeamsChanged);
    _disposed = true;
    _setupFallback?.cancel();
    _stallTimer?.cancel();
    unawaited(_liveSub?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _goalAnim.dispose();
    _inbox?.close();
    for (final Completer<void> c in _waiters) {
      if (!c.isCompleted) c.complete();
    }
    audio.dispose();
    im.dispose();
    _frame.dispose();
    _hud.dispose();
    for (final ui.Image? i in _hudCrests) {
      i?.dispose();
    }
    e.stop();
    _rematch?.dispose();
    super.dispose();
  }

  /// v13: everyone accepted the rematch and its match exists: keep this phone's picks for it and leave the finished
  /// match page; the room page opens the new match like any other.
  void _goRematch(String matchId) {
    final NetLink? net = launch.net;
    final BmConfig? c = cfg;
    if (net == null || _disposed) return;
    if (c != null && mySeat <= 1) {
      final int side = _mySide;
      FsRematchCarry.put(net.matchId, net.names, _Setup(c.teams[side], c.form[side], c.field, c.ball).toJson());
    }
    if (!mounted) return;
    final ModalRoute<dynamic>? route = ModalRoute.of(context);
    final NavigatorState? nav = Navigator.maybeOf(context);
    if (route == null || nav == null) return;
    if (route.isCurrent) {
      nav.pop();
    } else {
      nav.removeRoute(route);
    }
  }

  /// ANIX PRO: the pre-match screen is never a dead end. After [kOnlineStallSeconds] without a match (or a refused
  /// send) it says so and offers to try again (re-logs any missing setup) or to leave.
  Widget _stallBar() => Positioned(
        left: 18,
        right: 18,
        bottom: 28 + MediaQuery.paddingOf(context).bottom,
        child: Material(
          key: const ValueKey<String>('online-stall'),
          color: const Color(0xF0141210),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              Text(
                  _setupSendFailed
                      ? 'ارسال انتخابت به سرور ناموفق بود.'
                      : 'حریف هنوز آماده نشده یا اتصالش قطع است.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5)),
              const SizedBox(height: 10),
              Row(children: <Widget>[
                Expanded(
                  child: FilledButton(
                    key: const ValueKey<String>('online-stall-retry'),
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black),
                    onPressed: () {
                      setState(() {
                        _waitedSeconds = 0;
                        if (_setupSendFailed && !_setups.containsKey(mySeat)) {
                          _setupSendFailed = false;
                          _sendSetup();
                        }
                      });
                      _fillMissingSetups();
                    },
                    child: const Text('تلاش دوباره'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey<String>('online-stall-leave'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: _leaveStalled,
                    child: const Text('خروج'),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      );

  // ------------------------------------------------------------------ build
  @override
  Widget build(BuildContext context) {
    if (stage != 'match') {
      _syncImmersive(false);
      // v4: no menu soundtrack on the screen that only hands over to an auto-started match (offline intro), and
      // none during a match; it comes back on the setup screen after leaving a match.
      if (launch.soundOn && !_paused && _visible && !widget.autoStart) unawaited(audio.music(true));
      final Widget pre = _setupScreen(context);
      if (!online || !_stalled) return pre;
      return Stack(fit: StackFit.expand, children: <Widget>[pre, _stallBar()]);
    }
    final double dpr = math.min(MediaQuery.devicePixelRatioOf(context), 1.75);
    // v9 layout: the top bar and the bottom strip are outside the pitch; the pitch art is fitted between them.
    final EdgeInsets pad = MediaQuery.paddingOf(context);
    view.insetTop = pad.top + kFsTopBarHeight;
    view.insetBottom = pad.bottom + (online ? kFsBottomStripHeight : kFsBottomStripCompact);
    final bool fancy = launch.fancyEffects && !launch.reducedMotion;
    final FsFlameGame game = _flame ??= FsFlameGame(
      painter: BmPainter(e, im, view, () => _nowMs, dpr, fancy, repaint: _frame),
      onFrame: _flameFrame,
      pointer: FsPointerSink(
        down: e.pointerDown,
        move: e.pointerMove,
        up: e.pointerUp,
        cancel: e.pointerCancel,
      ),
    );
    _syncImmersive(true);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF03060D),
        child: Stack(children: <Widget>[
          // The playfield: a Flame scene (pitch, discs, ball, goals, score displays and touch input).
          Positioned.fill(child: GameWidget<FsFlameGame>(game: game)),
          Positioned.fill(child: IgnorePointer(child: _overlays())),
          // Top bar: the match clock, the menu and the formation button, nothing else.
          Positioned(
            left: 0,
            right: 0,
            top: pad.top,
            height: kFsTopBarHeight,
            child: RepaintBoundary(
              child: ValueListenableBuilder<FsHudData>(
                valueListenable: _hud,
                builder: (BuildContext context, FsHudData h, Widget? __) => FsMatchTopBar(
                  clock: h.clock,
                  red: h.red,
                  turn: h.turn,
                  turnMine: h.turnMine,
                  scores: <int>[h.score0, h.score1],
                  names: <String>[h.name0, h.name1],
                  crests: <ui.Image?>[h.crest0, h.crest1],
                  pulse: <double>[h.pulse0, h.pulse1],
                  fa: launch.isFa,
                  menuLabel: launch.tx('منو', 'Menu'),
                  formLabel: launch.tx('تغییر ترکیب', 'Formation'),
                  onMenu: _pause,
                  onFormation: h.formation ? _changeFormation : null,
                ),
              ),
            ),
          ),
          // Bottom strip (outside the pitch): the v6 "one minute left" toast; online the host page centres the voice
          // controls here.
          Positioned(
            left: 8,
            right: 8,
            bottom: pad.bottom,
            height: kFsBottomStripHeight,
            child: IgnorePointer(
              child: ValueListenableBuilder<int>(
                valueListenable: _frame,
                builder: (BuildContext context, int _, Widget? __) => _minuteT > 0 && _tableT < 0
                    ? Align(
                        alignment: online ? Alignment.centerLeft : Alignment.center,
                        child: BmMinuteToast(
                            text: launch.tx('یک دقیقه تا پایان بازی', 'One minute left'),
                            opacity: (_minuteT / .25).clamp(0.0, 1.0).toDouble()))
                    : const SizedBox.shrink(),
              ),
            ),
          ),
          if (_tableT >= 0) Positioned.fill(child: _scoreTable()),
          if (_tableT >= 0 && _rematch != null)
            Positioned(
              left: 24,
              right: 24,
              bottom: pad.bottom + 96,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: FsRematchPanel(c: _rematch!, fa: launch.isFa),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  FsFlameGame? _flame;

  /// Tests: the Flame scene of the running match (null before the match screen is built).
  @visibleForTesting
  FsFlameGame? get flameGame => _flame;

  bool _immersiveSent = false;

  /// Tells the host page (GameLaunch.immersive) that the match screen draws its own chrome, after this frame.
  void _syncImmersive(bool on) {
    if (_immersiveSent == on) return;
    _immersiveSent = on;
    final ValueNotifier<bool>? n = launch.immersive;
    if (n == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) n.value = on;
    });
  }

  /// The match clock: played time counting up (v3), "GOLDEN" in golden goal, empty for goal-limit matches.
  String _clockText() {
    if (e.mt <= 0) return '';
    if (e.sd) return launch.tx('گل طلایی', 'GOLDEN');
    final int el = math.min(e.mt, math.max(0, (e.mt - e.mleft).floor()));
    final String c = '${(el ~/ 60).toString().padLeft(2, '0')}:${(el % 60).toString().padLeft(2, '0')}';
    return launch.isFa ? fsFa(c) : c;
  }

  Widget _overlays() {
    return ValueListenableBuilder<int>(
      valueListenable: _frame,
      builder: (BuildContext context, int _, Widget? __) {
        final Size sz = MediaQuery.sizeOf(context);
        return Stack(children: <Widget>[
          if (_toastT > 0)
            Positioned(
              left: 18,
              right: 18,
              top: sz.height * .30,
              child: Center(child: _ToastPill(text: _toast, big: _toastBig)),
            ),
          AnimatedBuilder(
            animation: _goalAnim,
            builder: (BuildContext context, Widget? child) {
              final double t = _goalAnim.value;
              if (t <= 0 || t >= 1 || !_goalAnim.isAnimating) {
                return const SizedBox.shrink();
              }
              // Keep the original goal-pop motion; only the surrounding HUD is restyled.
              double sc, op = 1, rot = 0, ty = 0;
              if (t < .14) {
                final double k = t / .14;
                sc = .25 + (1.2 - .25) * k;
                op = k;
                rot = -5 + 6 * k;
              } else if (t < .24) {
                final double k = (t - .14) / .10;
                sc = 1.2 + (.97 - 1.2) * k;
                rot = 1 - k;
              } else if (t < .32) {
                final double k = (t - .24) / .08;
                sc = .97 + (1.03 - .97) * k;
              } else if (t < .78) {
                sc = 1.03;
              } else {
                final double k = (t - .78) / .22;
                sc = 1.03 + (1.12 - 1.03) * k;
                op = 1 - k;
                ty = -16 * k;
              }
              return Positioned(
                left: 0,
                right: 0,
                top: sz.height * .22 + ty,
                child: Center(
                  child: Opacity(
                    opacity: op.clamp(0.0, 1.0),
                    child: Transform.rotate(
                      angle: rot * math.pi / 180,
                      child: Transform.scale(scale: sc, child: child),
                    ),
                  ),
                ),
              );
            },
            child: Image.asset('${_a}ui/goal.webp',
                width: math.min(sz.width * .82, 460)),
          ),
        ]);
      },
    );
  }

  /// v6: the reference's end-of-match score table: one row per player with their avatar and the match points (their
  /// side's goals; there are no room points), winner side first (local side first on a draw).
  Widget _scoreTable() {
    return ValueListenableBuilder<int>(
      valueListenable: _frame,
      builder: (BuildContext context, int _, Widget? __) => FsScoreTable(
        fa: launch.isFa,
        topLane: 50,
        seconds: _tableT.ceil(),
        rows: scoreRows(),
      ),
    );
  }

  /// Rows of the score table (tests read them).
  @visibleForTesting
  List<FsScoreRow> scoreRows() {
    final List<int> sc = e.score;
    final List<int> order = sc[1] > sc[0] ? <int>[1, 0] : <int>[0, 1];
    final NetLink? net = launch.net;
    final List<FsScoreRow> rows = <FsScoreRow>[];
    for (final int t in order) {
      final String crest = bmTeam(e.sel[e.ct(t)]).asset;
      final bool win = sc[t] > sc[1 - t];
      if (net == null) {
        // offline: side 0 is this player, side 1 the bot / the second local player
        rows.add(FsScoreRow(
          name: e.nm(t),
          score: sc[t],
          crest: crest,
          winner: win,
          avatar: t == 0 ? _myAvatar : (launch.vsBot ? '04-iron-warden' : '02-cyber-scout'),
        ));
        continue;
      }
      // online: every seat of the side (global side g = seats g, g+2, g+4), each with the side's goals
      final int g = e.ct(t);
      for (int seat = g; seat < net.seatCount; seat += 2) {
        final String n = seat < net.names.length ? net.names[seat] : '';
        rows.add(FsScoreRow(
          name: n.isNotEmpty ? n : e.nm(t),
          score: sc[t],
          crest: crest,
          winner: win,
          avatar: seat == mySeat ? _myAvatar : _avatars[seat],
        ));
      }
    }
    return rows;
  }

  /// Black-gold gem purchase confirmation (the app's Luxe look). True when the player confirmed.
  Future<bool> _confirmGems({required Widget art, required String title, required String body, required int price}) async {
    final bool fa = launch.isFa;
    final int bal = ProfileService.current?.gems ?? 0;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => Directionality(
        textDirection: fa ? TextDirection.rtl : TextDirection.ltr,
        child: AlertDialog(
          backgroundColor: Luxe.panel,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(LuxeRadius.md), side: const BorderSide(color: Luxe.gold3)),
          title: Row(children: <Widget>[
            SizedBox(width: 40, height: 40, child: art),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: const TextStyle(color: Luxe.ink, fontWeight: FontWeight.w900))),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(body, style: const TextStyle(color: Luxe.ink, height: 1.4)),
            const SizedBox(height: 8),
            Row(children: <Widget>[
              const Icon(Icons.diamond_rounded, size: 16, color: Luxe.gold),
              const SizedBox(width: 4),
              Text(fa ? 'موجودی: ${fsFa(bal)}' : 'Balance: $bal', style: const TextStyle(color: Luxe.mute)),
            ]),
          ]),
          actions: <Widget>[
            TextButton(
                style: TextButton.styleFrom(foregroundColor: Luxe.mute),
                onPressed: () => Navigator.pop(c, false),
                child: Text(fa ? 'انصراف' : 'Cancel')),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Luxe.gold, foregroundColor: Luxe.bg),
              onPressed: bal >= price ? () => Navigator.pop(c, true) : null,
              icon: const Icon(Icons.diamond_rounded, size: 16),
              label: Text(fa ? 'خرید با ${fsFa(price)}' : 'Buy for $price'),
            ),
          ],
        ),
      ),
    );
    return ok == true;
  }

  Future<bool> _buyTeam(BmTeam t) async {
    final GemShop shop = GemShop.instance;
    final int price = shop.teamPrice(t.id);
    final bool fa = launch.isFa;
    final String name = fa ? t.faName : t.name;
    final bool custom = bmIsCustomTeamId(t.id);
    final bool ok = await _confirmGems(
      art: _crest(t),
      title: name,
      body: custom
          ? (fa
              ? 'تیم اختصاصی «$name» را یک بازیکن ساخته است (قدرت ۱۰). با ${fsFa(price)} الماس برای همیشه مال تو می‌شود.'
              : 'A player made the custom team "$name" (power 10). Own it forever for $price gems.')
          : (fa ? 'این تیم قفل است. با ${fsFa(price)} الماس بازش کن؟' : 'This team is locked. Unlock it for $price gems?'),
      price: price,
    );
    if (!ok || !mounted) return false;
    final GemBuyResult r = await shop.buyTeam(t.id);
    if (!mounted) return r.ok;
    luxeToast(context, r.ok ? (fa ? '$name باز شد ✓' : '$name unlocked ✓') : gemErrorText(r.error, fa));
    if (r.ok) setState(() {});
    return r.ok;
  }

  /// A team's round crest: the uploaded network crest of a shared custom team (fallback disc on error), else its art.
  Widget _crest(BmTeam t, {double? cache = 128}) {
    final String? url = t.crestUrl;
    final Widget art = Image.asset(t.asset, cacheWidth: cache?.toInt());
    if (url == null || url.isEmpty) return art;
    return AspectRatio(
        aspectRatio: 1,
        child: Image.network(url, fit: BoxFit.contain, gaplessPlayback: true, errorBuilder: (_, __, ___) => art));
  }

  /// Optional custom team name (defaults to the player's name). Null when cancelled.
  Future<String?> _askTeamName(String initial) async {
    final bool fa = launch.isFa;
    final TextEditingController ctl = TextEditingController(text: initial);
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext c) => Directionality(
        textDirection: fa ? TextDirection.rtl : TextDirection.ltr,
        child: AlertDialog(
          backgroundColor: Luxe.panel,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(LuxeRadius.md), side: const BorderSide(color: Luxe.gold3)),
          title: Text(fa ? 'نام تیم اختصاصی' : 'Custom team name',
              style: const TextStyle(color: Luxe.ink, fontWeight: FontWeight.w900)),
          content: TextField(
            controller: ctl,
            autofocus: true,
            maxLength: kFsCustomTeamNameMax,
            style: const TextStyle(color: Luxe.ink),
            cursorColor: Luxe.gold,
            decoration: InputDecoration(
              hintText: fa ? 'نام تیم' : 'Team name',
              hintStyle: const TextStyle(color: Luxe.mute),
              counterStyle: const TextStyle(color: Luxe.mute),
              enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Luxe.gold3)),
              focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Luxe.gold)),
            ),
          ),
          actions: <Widget>[
            TextButton(
                style: TextButton.styleFrom(foregroundColor: Luxe.mute),
                onPressed: () => Navigator.pop(c),
                child: Text(fa ? 'انصراف' : 'Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Luxe.gold, foregroundColor: Luxe.bg),
              onPressed: () => Navigator.pop(c, ctl.text.trim()),
              child: Text(fa ? 'ادامه' : 'Continue'),
            ),
          ],
        ),
      ),
    );
    ctl.dispose();
    return name;
  }

  /// Custom team (تیم اختصاصی): buys the 1000-gem entitlement once, then the player picks a photo; the app cuts it to
  /// a round crest and the server creates the shared team (power 10; free for its owner forever, 250 gems for
  /// everyone else). Called again (long-press) it replaces the crest. True when the player's custom team exists.
  Future<bool> _customTeam() async {
    final bool fa = launch.isFa;
    final OnlineService? net = OnlineService.current;
    final GemShop shop = GemShop.instance;
    if (net == null || !net.isOnline || net.isGuest || !shop.online) {
      luxeToast(context, launch.tx('برای ساخت تیم اختصاصی باید آنلاین وارد حساب باشی', 'Sign in online to create a custom team'));
      return false;
    }
    final bool creating = shop.myCustomTeam == null;
    if (creating && !shop.ownsCustomTeam()) {
      final int price = shop.customTeamPrice;
      final bool ok = await _confirmGems(
        art: const Icon(Icons.add_a_photo_rounded, color: Luxe.gold, size: 30),
        title: launch.tx('تیم اختصاصی', 'Custom team'),
        body: fa
            ? 'با عکس دلخواهت تیم اختصاصی خودت را بساز (قدرت ۱۰). ساخت تیم ${fsFa(price)} الماس است؛ تیمت برای همیشه برای خودت رایگان است و در فهرست «تیم‌های اختصاصی» به بقیه با ${fsFa(kFsCustomTeamBuyPrice)} الماس فروخته می‌شود. عکس را هر زمان می‌توانی عوض کنی (نگه داشتن انگشت روی تیم).'
            : 'Make your own team from a photo (power 10). Creating it costs $price gems; it is free for you forever and '
                'other players can buy it in the Custom teams list for $kFsCustomTeamBuyPrice gems. Change the photo any time (long-press the team).',
        price: price,
      );
      if (!ok || !mounted) return false;
      final GemBuyResult r = await shop.buyCustomTeam();
      if (!mounted) return false;
      if (!r.ok) {
        luxeToast(context, gemErrorText(r.error, fa));
        return false;
      }
    }
    String? name;
    if (creating) {
      name = await _askTeamName(ProfileService.current?.username.trim() ?? '');
      if (name == null || !mounted) return false;
    }
    final XFile? file =
        await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1024, maxHeight: 1024, imageQuality: 92);
    if (file == null || !mounted) return false;
    final CustomTeamResult r = await shop.saveCustomTeam(await file.readAsBytes(), name: name);
    if (!mounted) return false;
    if (!r.ok) {
      luxeToast(context, gemErrorText(r.error, fa));
      return false;
    }
    // the opponent's phone learns the new crest with the avatar event
    _announceAvatar();
    luxeToast(context, launch.tx('تیم اختصاصی ذخیره شد ✓', 'Custom team saved ✓'));
    setState(() {});
    return true;
  }

  // ------------------------------------------------------------------ setup screen
  Widget _setupScreen(BuildContext context) {
    final bool waiting = stage == 'waiting' || (online && !_netReady);
    final bool chooseArena = !online || isHostSeat;
    // pass-and-play: the lobby picks for team one or team two (side two needs no owned team)
    final int pickSide = _localTwo ? _pickSide : 0;
    final String sideTeam = pickSide == 1 ? (_oppTeam ?? '') : my.team;
    final int sideForm = pickSide == 1 ? (_oppForm ?? -1) : my.form;
    final String waitText = online && !_netReady
        ? launch.tx('در حال اتصال به بازی…', 'Connecting to the match…')
        : (online && mySeat > 1
            ? launch.tx('هم‌تیمی‌ها تیم و ترکیب را انتخاب می‌کنند…', 'Your teammates are picking…')
            : launch.tx('در انتظار حریف…', 'Waiting for the opponent…'));
    final bool oppReady = online && _setups.containsKey(1 - _mySide);
    // custom category: the "create" tile until the player made their team, then every shared custom team
    final bool madeCustom = GemShop.instance.myCustomTeam != null;
    final List<BmTeam> teams = kBmTeams
        .where((BmTeam t) => t.cat == kBmCats[_cat][0] && !(madeCustom && t.id == kCustomTeamId))
        .toList();
    final NxThemeColors visual = NxThemeColors.of(context);

    Widget sectionTitle(String title, String hint, IconData icon) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: <Widget>[
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: visual.accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: visual.accent.withValues(alpha: .34)),
                ),
                child: Icon(icon, size: 17, color: visual.accent),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title,
                        style: TextStyle(
                            color: visual.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .4)),
                    const SizedBox(height: 1),
                    Text(hint,
                        style: TextStyle(color: visual.muted, fontSize: 10.5)),
                  ],
                ),
              ),
            ],
          ),
        );

    Widget section(Widget child) => Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: visual.surface.withValues(alpha: .86),
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: visual.border.withValues(alpha: .48)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                  color: Colors.black.withValues(alpha: .12),
                  blurRadius: 14,
                  offset: const Offset(0, 5))
            ],
          ),
          child: child,
        );

    return Directionality(
      textDirection: TextDirection.ltr,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              visual.background,
              visual.backgroundMid,
              visual.background
            ],
          ),
        ),
        child: SafeArea(
          child: AbsorbPointer(
            absorbing: waiting,
            // The host overlays its exit + ORACLE buttons (48dp) in the top corners: start the lobby below
            // them, and pin START/READY under the list so it is reachable without scrolling at 360x800.
            child: Column(
              children: <Widget>[
                Expanded(
                  child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 56, 16, 16),
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 17, 16, 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        visual.surfaceRaised,
                        visual.surface.withValues(alpha: .82)
                      ],
                    ),
                    borderRadius: BorderRadius.circular(22),
                    border:
                        Border.all(color: visual.accent.withValues(alpha: .38)),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                          color: visual.accent.withValues(alpha: .09),
                          blurRadius: 26,
                          offset: const Offset(0, 8))
                    ],
                  ),
                  child: Column(
                    children: <Widget>[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(Icons.sports_soccer_rounded,
                              size: 15, color: visual.accent),
                          const SizedBox(width: 6),
                          Text('NEXORA  /  MATCH LOBBY',
                              style: TextStyle(
                                  color: visual.accent,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.8)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        launch.tx('فوتبال انگشتی', 'FINGER SOCCER'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: visual.text,
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.1),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        online
                            ? launch.tx('تیم و ترکیبت را انتخاب کن',
                                'Choose your side and formation')
                            : launch.tx('۵ دقیقه · گل طلایی در تساوی',
                                'Five minutes · golden goal if tied'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: visual.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w500),
                      ),
                      if (online && _netReady && stage != 'match') ...<Widget>[
                        const SizedBox(height: 8),
                        Container(
                          key: const ValueKey<String>('online-opp-status'),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(99),
                            color: visual.background.withValues(alpha: .6),
                            border: Border.all(color: (oppReady ? visual.accent : visual.border).withValues(alpha: .6)),
                          ),
                          child: Text(
                              oppReady
                                  ? launch.tx('حریف آماده است ✓', 'Opponent is ready ✓')
                                  : launch.tx('حریف در حال انتخاب…', 'Opponent is picking…'),
                              style: TextStyle(
                                  color: oppReady ? visual.accent : visual.muted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ],
                  ),
                ),
                section(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      sectionTitle(
                          launch.tx('تیم', 'YOUR TEAM'),
                          launch.tx('یک نشان را انتخاب کن', 'Choose your club'),
                          Icons.shield_outlined),
                      if (_localTwo) ...<Widget>[
                        SizedBox(
                          height: 38,
                          child: Row(children: <Widget>[
                            for (int sd = 0; sd < 2; sd++)
                              _Chip(
                                key: ValueKey<String>('side-$sd'),
                                label: sd == 0 ? launch.tx('تیم یک', 'Team one') : launch.tx('تیم دو', 'Team two'),
                                on: pickSide == sd,
                                onTap: () => setState(() {
                                  _pickSide = sd;
                                  audio.sfx('ui');
                                }),
                              ),
                          ]),
                        ),
                        const SizedBox(height: 8),
                      ],
                      SizedBox(
                        height: 38,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: <Widget>[
                            for (int i = 0; i < kBmCats.length; i++)
                              _Chip(
                                label: launch.tx(kBmCats[i][2] as String, kBmCats[i][1] as String),
                                on: _cat == i,
                                onTap: () => setState(() {
                                  _cat = i;
                                  audio.sfx('ui');
                                }),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 128,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: teams.length,
                          itemBuilder: (BuildContext c, int i) {
                            final BmTeam t = teams[i];
                            final GemShop shop = GemShop.instance;
                            // the "create your custom team" tile (1000 gems + a photo); the shared custom teams
                            // (cx_..., power 10) follow it: free for their owner, 250 gems for everyone else
                            final bool create = t.id == kCustomTeamId;
                            final FsCustomTeam? mine = shop.myCustomTeam;
                            final bool myTeam = create ? mine != null : shop.isMyCustomTeam(t.id);
                            final BmTeam shown = create && mine != null ? bmTeam(mine.teamId) : t;
                            final bool on = shown.id == sideTeam;
                            // side two (pass-and-play) fields any team; side one needs it owned
                            final bool owned = create ? mine != null : (pickSide == 1 || shop.ownsTeam(t.id));
                            return GestureDetector(
                              key: ValueKey<String>('team-${t.id}'),
                              onLongPress: myTeam && pickSide == 0 ? () => unawaited(_customTeam()) : null,
                              onTap: () async {
                                if (create && pickSide == 1) {
                                  luxeToast(context, launch.tx('ساخت تیم اختصاصی فقط برای تیم یک است', 'Create a custom team for team one'));
                                  return;
                                }
                                if (!owned) {
                                  final bool ok = create ? await _customTeam() : await _buyTeam(t);
                                  if (!ok) return;
                                }
                                if (!mounted) return;
                                final String pick = create ? (GemShop.instance.myCustomTeam?.teamId ?? '') : t.id;
                                if (pick.isEmpty) return;
                                setState(() {
                                  if (pickSide == 1) {
                                    _oppTeam = pick;
                                  } else {
                                    my.team = pick;
                                    _savedTeam = pick;
                                    unawaited(_savePrefs());
                                    if (online) _announceAvatar();
                                  }
                                  audio.sfx('ui');
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                width: 82,
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(15),
                                  color: on
                                      ? visual.accent.withValues(alpha: .14)
                                      : visual.background
                                          .withValues(alpha: .52),
                                  border: Border.all(
                                      color: on
                                          ? visual.accent
                                          : visual.border
                                              .withValues(alpha: .42),
                                      width: on ? 1.6 : 1),
                                  boxShadow: on
                                      ? <BoxShadow>[
                                          BoxShadow(
                                              color: visual.accent
                                                  .withValues(alpha: .12),
                                              blurRadius: 12)
                                        ]
                                      : null,
                                ),
                                child: Column(
                                  children: <Widget>[
                                    Expanded(
                                        child: Stack(
                                      alignment: Alignment.center,
                                      children: <Widget>[
                                        Opacity(
                                            opacity: owned ? 1 : .45,
                                            child: create && mine == null
                                                ? const FittedBox(
                                                    child: Icon(Icons.add_a_photo_rounded, color: Luxe.gold, size: 40))
                                                : _crest(shown)),
                                        if (!owned && pickSide == 0)
                                          Positioned(
                                            bottom: 0,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: const Color(0xE607080C),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: Luxe.gold),
                                              ),
                                              child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                                                const Icon(Icons.diamond_rounded, size: 10, color: Luxe.gold),
                                                const SizedBox(width: 2),
                                                Text(
                                                    create && shop.ownsCustomTeam()
                                                        ? launch.tx('عکس', 'Photo')
                                                        : '${shop.teamPrice(t.id)}',
                                                    style: const TextStyle(
                                                        color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w900)),
                                              ]),
                                            ),
                                          ),
                                        if (!owned && pickSide == 0)
                                          const Positioned(
                                              top: 0,
                                              right: 0,
                                              child: Icon(Icons.lock_rounded, size: 14, color: Luxe.gold)),
                                      ],
                                    )),
                                    const SizedBox(height: 3),
                                    Text('${myTeam && !create ? '★ ' : ''}${launch.isFa ? shown.faName : shown.name}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color:
                                                on ? visual.text : visual.muted,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800)),
                                    const SizedBox(height: 3),
                                    _StatBar(icon: Icons.bolt_rounded, value: t.power, color: const Color(0xFFFFB020)),
                                    const SizedBox(height: 2),
                                    _StatBar(icon: Icons.gps_fixed_rounded, value: t.accuracy, color: const Color(0xFF3BD0FF)),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                section(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      sectionTitle(
                          launch.tx('ترکیب', 'FORMATION'),
                          launch.tx(
                              'آرایش مهره‌های تیم', 'Set your team shape'),
                          Icons.account_tree_outlined),
                      // The reference's 3 x 3 formation board: a mini pitch per shape (own goal on the left,
                      // halfway line on the right), its name and a select button.
                      LayoutBuilder(
                        builder: (BuildContext context, BoxConstraints c) {
                          final double w = (c.maxWidth - 2 * 8) / 3;
                          return Wrap(
                            spacing: 8,
                            runSpacing: 10,
                            children: <Widget>[
                              for (int i = 0; i < kBmForms.length; i++)
                                SizedBox(
                                  width: w,
                                  child: BmFormationCard(
                                    form: kBmForms[i],
                                    on: sideForm == i,
                                    selectLabel: launch.tx('انتخاب', 'Select'),
                                    selectedLabel: launch.tx('انتخاب شده', 'Selected'),
                                    onTap: () => setState(() {
                                      if (pickSide == 1) {
                                        _oppForm = i;
                                      } else {
                                        my.form = i;
                                        unawaited(_savePrefs());
                                      }
                                      audio.sfx('ui');
                                    }),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                if (chooseArena)
                  section(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        sectionTitle(
                            launch.tx('زمین', 'ARENA'),
                            launch.tx('محل مسابقه را برگزین',
                                'Choose the match venue'),
                            Icons.stadium_outlined),
                        SizedBox(
                          height: 146,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: kBmFields.length,
                            itemBuilder: (BuildContext c, int i) {
                              final bool on = my.field == i;
                              return GestureDetector(
                                onTap: () => setState(() {
                                  my.field = i;
                                  audio.sfx('ui');
                                  unawaited(_savePrefs());
                                }),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 160),
                                  width: 116,
                                  margin: const EdgeInsets.only(right: 9),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(15),
                                    border: Border.all(
                                        color: on
                                            ? visual.accent
                                            : visual.border
                                                .withValues(alpha: .48),
                                        width: on ? 1.8 : 1),
                                    boxShadow: on
                                        ? <BoxShadow>[
                                            BoxShadow(
                                                color: visual.accent
                                                    .withValues(alpha: .15),
                                                blurRadius: 12)
                                          ]
                                        : null,
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: <Widget>[
                                      Image.asset(
                                          '${_a}thumbs/${kBmFields[i].id}.webp',
                                          fit: BoxFit.cover,
                                          cacheWidth: 220),
                                      Positioned(
                                        left: 0,
                                        right: 0,
                                        bottom: 0,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 6),
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                                colors: <Color>[
                                                  Colors.transparent,
                                                  Colors.black
                                                      .withValues(alpha: .88)
                                                ]),
                                          ),
                                          child: Text(bmFieldName(i, launch.isFa),
                                              textAlign: TextAlign.center,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.w800)),
                                        ),
                                      ),
                                      if (on)
                                        Positioned(
                                          right: 6,
                                          top: 6,
                                          child: Icon(
                                              Icons.check_circle_rounded,
                                              color: visual.accent,
                                              size: 18),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 13),
                        sectionTitle(
                            launch.tx('توپ', 'BALL'),
                            launch.tx('توپ مسابقه را انتخاب کن', 'Pick the match ball'),
                            Icons.sports_soccer_outlined),
                        SizedBox(
                          height: 92,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: NB,
                            itemBuilder: (BuildContext c, int i) {
                              final bool on = my.ball == i;
                              return GestureDetector(
                                onTap: () => setState(() {
                                  my.ball = i;
                                  audio.sfx('ui');
                                  unawaited(_savePrefs());
                                }),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 160),
                                  width: 86,
                                  margin: const EdgeInsets.only(right: 8),
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    color: on ? visual.accent.withValues(alpha: .14) : visual.background.withValues(alpha: .52),
                                    border: Border.all(
                                        color: on ? visual.accent : visual.border.withValues(alpha: .42), width: on ? 1.6 : 1),
                                  ),
                                  child: Column(
                                    children: <Widget>[
                                      Expanded(child: Image.asset(bmBallThumb(i), cacheWidth: 120)),
                                      const SizedBox(height: 3),
                                      Text(launch.tx(kBmBallFa[i], kBmBallN[i]),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              color: on ? visual.text : visual.muted, fontSize: 9.5, fontWeight: FontWeight.w800)),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  section(
                    Row(
                      children: <Widget>[
                        Icon(Icons.info_outline_rounded,
                            color: visual.accent, size: 18),
                        const SizedBox(width: 9),
                        Expanded(
                            child: Text(
                                launch.tx('زمین و توپ را میزبان انتخاب می‌کند',
                                    'The host picks the field and the ball'),
                                style: TextStyle(
                                    color: visual.muted,
                                    fontSize: 12,
                                    height: 1.35))),
                      ],
                    ),
                  ),
                  ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: waiting
                      ? Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                              color: visual.surface,
                              borderRadius: BorderRadius.circular(17),
                              border: Border.all(
                                  color: visual.border.withValues(alpha: .5))),
                          child: Column(
                            children: <Widget>[
                              SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.5, color: visual.accent)),
                              const SizedBox(height: 9),
                              Text(waitText,
                                  key: const ValueKey<String>('online-wait'),
                                  style: TextStyle(
                                      color: visual.text,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                        )
                      : SizedBox(
                          height: 54,
                          child: FilledButton.icon(
                            key: const ValueKey<String>('setup-ready'),
                            style: FilledButton.styleFrom(
                              backgroundColor: visual.accent,
                              foregroundColor: visual.background,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(17)),
                              elevation: 5,
                              shadowColor: visual.accent.withValues(alpha: .30),
                              textStyle: const TextStyle(
                                  fontFamily: kNxFont,
                                  fontFamilyFallback: kNxFontFallback,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                  letterSpacing: .5),
                            ),
                            onPressed: () {
                              audio.sfx('ui');
                              unawaited(_savePrefs());
                              if (online) {
                                _sendSetup();
                              } else {
                                _startOffline();
                              }
                            },
                            icon:
                                const Icon(Icons.play_arrow_rounded, size: 24),
                            label: Text(online
                                ? '${launch.tx('آماده‌ام', 'READY')}  ·  ${launch.isFa ? fsFa(_pickLeft) : '$_pickLeft'}'
                                : launch.tx('شروع بازی', 'START MATCH')),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Height of the in-match formation button (v9: in the top bar).
const double kBmFormButtonHeight = 44;

/// v12: what the match scoreboard shows. Values are quantised by the caller, so == only changes a few times a second
/// and the scoreboard (a ValueListenableBuilder on this) does not rebuild every frame.
@immutable
class FsHudData {
  const FsHudData({
    required this.clock,
    required this.red,
    required this.turn,
    required this.turnMine,
    required this.score0,
    required this.score1,
    required this.name0,
    required this.name1,
    required this.crest0,
    required this.crest1,
    required this.pulse0,
    required this.pulse1,
    required this.formation,
  });
  static const FsHudData empty = FsHudData(
      clock: '', red: 0, turn: -1, turnMine: true, score0: 0, score1: 0, name0: '', name1: '',
      crest0: null, crest1: null, pulse0: 0, pulse1: 0, formation: false);
  final String clock, name0, name1;
  final double red, turn, pulse0, pulse1;
  final bool turnMine, formation;
  final int score0, score1;
  final ui.Image? crest0, crest1;

  @override
  bool operator ==(Object other) =>
      other is FsHudData &&
      other.clock == clock &&
      other.red == red &&
      other.turn == turn &&
      other.turnMine == turnMine &&
      other.score0 == score0 &&
      other.score1 == score1 &&
      other.name0 == name0 &&
      other.name1 == name1 &&
      identical(other.crest0, crest0) &&
      identical(other.crest1, crest1) &&
      other.pulse0 == pulse0 &&
      other.pulse1 == pulse1 &&
      other.formation == formation;

  @override
  int get hashCode => Object.hash(clock, red, turn, turnMine, score0, score1, name0, name1, crest0, crest1, pulse0,
      pulse1, formation);
}

/// v12 match scoreboard (rebuilt HUD), above the pitch, never on it: the menu button, the local side (crest, name,
/// score; green), the match clock with the turn clock under it, the other side (score, name, crest; gold) and the
/// formation button. Every tap target is at least 44 dp.
class FsMatchTopBar extends StatelessWidget {
  const FsMatchTopBar({
    super.key,
    required this.clock,
    required this.red,
    required this.turn,
    required this.turnMine,
    required this.menuLabel,
    required this.formLabel,
    required this.onMenu,
    required this.onFormation,
    this.scores = const <int>[0, 0],
    this.names = const <String>['', ''],
    this.crests = const <ui.Image?>[null, null],
    this.pulse = const <double>[0, 0],
    this.fa = true,
  });

  final String clock;
  /// 0 = normal clock, 1 = red (last-minute pulse / final whistle / golden goal), see [bmClockRed].
  final double red;
  /// Share of the turn clock left (0..1), or < 0 when no turn clock runs.
  final double turn;
  /// The turn being timed is the local side's (green) or the other side's (gold).
  final bool turnMine;
  /// Goals of the local side [0] and the other side [1]; their names and crests; goal pulse 0..1 per side.
  final List<int> scores;
  final List<String> names;
  final List<ui.Image?> crests;
  final List<double> pulse;
  /// Persian digits.
  final bool fa;
  final String menuLabel, formLabel;
  final VoidCallback onMenu;
  final VoidCallback? onFormation;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0xF21A1650), Color(0xF20B0A2A)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Luxe.line),
          boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x80000000), blurRadius: 12, offset: Offset(0, 4))],
        ),
        child: Row(children: <Widget>[
          const SizedBox(width: 2),
          LuxeIconButton(icon: Icons.menu_rounded, tooltip: menuLabel, size: 44, onTap: onMenu),
          const SizedBox(width: 4),
          Expanded(child: _FsHudSide(
            name: names[0], score: scores[0], crest: crests[0], pulse: pulse[0], fa: fa, mine: true,
            active: turn >= 0 && turnMine)),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 108),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: FsClockPill(clock: clock, red: red, turn: turn, turnMine: turnMine),
            ),
          ),
          Expanded(child: _FsHudSide(
            name: names[1], score: scores[1], crest: crests[1], pulse: pulse[1], fa: fa, mine: false,
            active: turn >= 0 && !turnMine)),
          const SizedBox(width: 4),
          BmChangeFormButton(label: formLabel, onTap: onFormation),
          const SizedBox(width: 2),
        ]),
      ),
    );
  }
}

/// One side of the scoreboard: crest + name + score (mirrored for the other side, so the scores meet at the clock).
class _FsHudSide extends StatelessWidget {
  const _FsHudSide({
    required this.name,
    required this.score,
    required this.crest,
    required this.pulse,
    required this.fa,
    required this.mine,
    required this.active,
  });
  final String name;
  final int score;
  final ui.Image? crest;
  final double pulse;
  final bool fa, mine, active;

  @override
  Widget build(BuildContext context) {
    final Color accent = mine ? kBmRingGreen : kBmRingGold;
    final ui.Image? c = crest;
    final Widget badge = Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF07080C),
        border: Border.all(color: active ? accent : Luxe.line, width: active ? 2 : 1),
      ),
      child: c == null
          ? Icon(Icons.shield_rounded, size: 14, color: accent)
          : ClipOval(child: RawImage(image: c, fit: BoxFit.cover, filterQuality: FilterQuality.medium)),
    );
    final Widget label = Flexible(
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: mine ? TextAlign.left : TextAlign.right,
        style: const TextStyle(color: Luxe.mute, fontSize: 10.5, fontWeight: FontWeight.w700, height: 1.1),
      ),
    );
    final String digits = fa ? fsFa(score) : '$score';
    final Widget value = Transform.scale(
      scale: 1 + pulse * .35,
      child: Container(
        constraints: const BoxConstraints(minWidth: 32),
        height: 32,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF07080C),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: accent.withValues(alpha: .55)),
        ),
        child: Text(digits,
            maxLines: 1,
            style: TextStyle(
              color: Color.lerp(Luxe.gold2, accent, pulse)!,
              fontSize: 20,
              height: 1,
              fontWeight: FontWeight.w900,
              fontFeatures: const <ui.FontFeature>[ui.FontFeature.tabularFigures()],
            )),
      ),
    );
    return Semantics(
      label: '$name $digits',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: LayoutBuilder(builder: (BuildContext context, BoxConstraints box) {
          // Narrow phones: the score always shows; the crest and then the name give way first.
          final double w = box.maxWidth;
          final List<Widget> row = <Widget>[
            if (w >= 72) ...<Widget>[badge, const SizedBox(width: 5)],
            if (w >= 104) ...<Widget>[label, const SizedBox(width: 5)],
            value,
          ];
          return Row(
            mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: mine ? row : row.reversed.toList(growable: false),
          );
        }),
      ),
    );
  }
}

/// The match clock pill (Luxe gold hairline); it warms to red with [red] and carries the turn clock underneath.
class FsClockPill extends StatelessWidget {
  const FsClockPill({super.key, required this.clock, required this.red, required this.turn, required this.turnMine});
  final String clock;
  final double red;
  final double turn;
  final bool turnMine;

  @override
  Widget build(BuildContext context) {
    final double k = red.clamp(0.0, 1.0).toDouble();
    final Color ink = Color.lerp(Luxe.gold2, const Color(0xFFFF6B6B), k)!;
    return Container(
      constraints: const BoxConstraints(minWidth: 92),
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xE6101014),
        borderRadius: BorderRadius.circular(LuxeRadius.pill),
        border: Border.all(color: Color.lerp(Luxe.line, const Color(0x99FF6B6B), k)!),
        boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x66000000), blurRadius: 10, offset: Offset(0, 3))],
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: <Widget>[
        Text(clock.isEmpty ? '--:--' : clock,
            maxLines: 1,
            style: TextStyle(
              color: ink,
              fontSize: 17,
              height: 1.1,
              fontWeight: FontWeight.w800,
              letterSpacing: .6,
              fontFeatures: const <ui.FontFeature>[ui.FontFeature.tabularFigures()],
            )),
        if (turn >= 0)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: SizedBox(
              width: 56,
              height: 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: Stack(children: <Widget>[
                  const Positioned.fill(child: ColoredBox(color: Color(0x33FFFFFF))),
                  FractionallySizedBox(
                    widthFactor: turn,
                    child: ColoredBox(color: turnMine ? kBmRingGreen : kBmRingGold),
                  ),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

/// The in-match "تغییر ترکیب" button. v12: a compact 44 dp scoreboard button (the pitch icon), its label read by
/// screen readers and shown as a tooltip; dimmed and inert while the formation cannot change.
class BmChangeFormButton extends StatelessWidget {
  const BmChangeFormButton({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Opacity(
        opacity: onTap == null ? .45 : 1,
        child: LuxePress(
          onTap: onTap,
          semantics: label,
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0x0FFFFFFF),
              shape: BoxShape.circle,
              border: Border.all(color: Luxe.line),
            ),
            child: Container(
              width: 24,
              height: 18,
              decoration: BoxDecoration(
                color: const Color(0xFF2E9B32),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF9CFF7A)),
              ),
              child: const Icon(Icons.grid_view_rounded, size: 12, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

/// In-match 3 x 3 formation picker (same cards as the setup board); pops the picked index.
class BmFormationPicker extends StatelessWidget {
  const BmFormationPicker({
    super.key,
    required this.title,
    required this.hint,
    required this.current,
    this.selectLabel = 'Select',
    this.selectedLabel = 'Selected',
  });
  final String title, hint, selectLabel, selectedLabel;
  final int current;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(hint, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 10),
          LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
            final double w = (c.maxWidth - 2 * 8) / 3;
            return Wrap(spacing: 8, runSpacing: 10, children: <Widget>[
              for (int i = 0; i < kBmForms.length; i++)
                SizedBox(
                  width: w,
                  child: BmFormationCard(
                    form: kBmForms[i],
                    on: current == i,
                    selectLabel: selectLabel,
                    selectedLabel: selectedLabel,
                    onTap: () => Navigator.of(context).pop(i),
                  ),
                ),
            ]);
          }),
        ]),
      ),
    );
  }
}

/// One formation on the setup board: a mini horizontal pitch (own goal left, halfway right, like the reference's
/// formation screen) with the five discs, the Persian name, the English label and a select button.
class BmFormationCard extends StatelessWidget {
  const BmFormationCard(
      {super.key, required this.form, required this.on, required this.onTap, this.selectLabel = 'Select', this.selectedLabel = 'Selected'});
  final BmFormation form;
  final bool on;
  final VoidCallback onTap;
  final String selectLabel, selectedLabel;

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    return Semantics(
      button: true,
      selected: on,
      label: form.label,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AspectRatio(
              aspectRatio: 82 / 54,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: on ? const Color(0xFF7CFF4A) : Colors.white24, width: on ? 2 : 1),
                ),
                child: CustomPaint(painter: BmFormationMiniPainter(form)),
              ),
            ),
            const SizedBox(height: 3),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1E22),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                children: <Widget>[
                  Text(form.fa,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(
                          fontFamily: 'Estedad', color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800, height: 1.2)),
                  Text(form.en,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: visual.muted, fontSize: 8.5, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                gradient: on
                    ? const LinearGradient(colors: <Color>[Color(0xFFE6E6E6), Color(0xFFBDBDBD)])
                    : const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[Color(0xFFB6F55A), Color(0xFF5FB61E)]),
              ),
              child: Text(on ? selectedLabel : selectLabel,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: 'Estedad',
                      color: on ? const Color(0xFF555555) : const Color(0xFF14320A),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      height: 1.2)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mini pitch of a formation: striped grass, white lines, the own goal box on the left and the centre circle on
/// the right edge; discs at the formation's slots (depth -> x, width -> y; the width is drawn stretched 1.3x like
/// the reference board).
class BmFormationMiniPainter extends CustomPainter {
  BmFormationMiniPainter(this.form);
  final BmFormation form;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width, h = size.height;
    for (int i = 0; i < 8; i++) {
      canvas.drawRect(Rect.fromLTWH(i * w / 8, 0, w / 8 + .5, h),
          Paint()..color = i.isEven ? const Color(0xFF4FA83A) : const Color(0xFF5DB845));
    }
    final Paint line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, w / 110)
      ..color = Colors.white.withValues(alpha: .85);
    canvas.drawRect(Rect.fromLTWH(1, 1, w - 2, h - 2), line);
    canvas.drawRect(Rect.fromLTWH(1, h * .22, w * .2, h * .56), line);
    canvas.drawRect(Rect.fromLTWH(1, h * .36, w * .08, h * .28), line);
    canvas.drawArc(Rect.fromCircle(center: Offset(w - 1, h / 2), radius: h * .2), math.pi / 2, math.pi, false, line);
    final double r = math.max(3, h * .075);
    for (final List<double> s in form.slots) {
      final Offset c = Offset(w * (.03 + .94 * s[1]), h * (.5 + (s[0] - .5) * 1.3).clamp(.08, .92).toDouble());
      canvas.drawCircle(c + Offset(r * .25, r * .35), r, Paint()..color = Colors.black38);
      canvas.drawCircle(c, r, Paint()..color = const Color(0xFFE53935));
      canvas.drawCircle(c, r * .45, Paint()..color = const Color(0xFFFFD54F));
      canvas.drawCircle(
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(.8, r * .22)
            ..color = const Color(0xFF1A1A1A));
    }
  }

  @override
  bool shouldRepaint(covariant BmFormationMiniPainter old) => old.form != form;
}

class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.label, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    return Semantics(
      button: true,
      selected: on,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            color: on
                ? visual.accent
                : visual.surfaceRaised.withValues(alpha: .84),
            border: Border.all(
                color:
                    on ? visual.accent : visual.border.withValues(alpha: .55)),
            boxShadow: on
                ? <BoxShadow>[
                    BoxShadow(
                        color: visual.accent.withValues(alpha: .18),
                        blurRadius: 10)
                  ]
                : null,
          ),
          child: Text(label,
              style: TextStyle(
                  color: on ? visual.background : visual.text,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }
}

/// Ten-segment rating bar (team power / accuracy) on the team cards.
class _StatBar extends StatelessWidget {
  const _StatBar({required this.icon, required this.value, required this.color});
  final IconData icon;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(children: <Widget>[
      Icon(icon, size: 9, color: color),
      const SizedBox(width: 2),
      for (int i = 1; i <= 10; i++)
        Expanded(
          child: Container(
            height: 4,
            margin: const EdgeInsets.symmetric(horizontal: .5),
            decoration: BoxDecoration(
              color: i <= value ? color : Colors.white.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
      const SizedBox(width: 2),
      Text('$value', style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w900)),
    ]);
  }
}

class _ToastPill extends StatelessWidget {
  const _ToastPill({required this.text, required this.big});
  final String text;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    return Container(
      constraints:
          BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width - 36),
      padding: EdgeInsets.symmetric(
          horizontal: big ? 26 : 20, vertical: big ? 12 : 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: big
            ? LinearGradient(
                colors: <Color>[visual.accent, visual.accentSecondary])
            : null,
        color: big ? null : visual.surfaceRaised.withValues(alpha: .97),
        border:
            Border.all(color: visual.accent.withValues(alpha: .82), width: 1.2),
        boxShadow: <BoxShadow>[
          BoxShadow(
              color: visual.accent.withValues(alpha: .24),
              blurRadius: 26,
              offset: const Offset(0, 6))
        ],
      ),
      child: Text(
        text.toUpperCase(),
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            color: big ? visual.background : visual.text,
            fontSize: big ? 30 : 15,
            fontWeight: FontWeight.w900,
            letterSpacing: .8),
      ),
    );
  }
}

/// v6 reference banner colour: 0 = white plates + yellow clock, 1 = red. Over the last minute it pulses
/// yellow -> red -> yellow every 4 s (01:00 yellow, 00:58 red, 00:56 yellow in the recordings); once the time is up
/// it stays red.
double bmClockRed(double mleft, int mt) {
  if (mt <= 0) return 0;
  if (mleft <= 0) return 1;
  if (mleft > 60) return 0;
  return .5 - .5 * math.cos(2 * math.pi * (60 - mleft) / 4);
}

/// v6 reference: the dark rounded "یک دقیقه تا پایان بازی" pill.
class BmMinuteToast extends StatelessWidget {
  const BmMinuteToast({super.key, required this.text, this.opacity = 1});
  final String text;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xF0101318),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: Text(text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
