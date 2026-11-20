// BERMUDA NXG disc football inside the ANIX hub: pre-match setup (team / formation / field / ball),
// the match (engine + painter + HUD) and the online wiring over the hub's NetLink (Supabase move log).
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:nexora/core/theme/nx_theme.dart';
import 'package:nexora/core/economy/gem_shop.dart';
import 'package:nexora/core/profile/profile_service.dart';
import 'package:nexora/core/ui2/anix_kit.dart';
import 'package:nexora/core/widgets/user_avatar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexora/games/core/game_contract.dart';
import '../core/bm_data.dart';
import '../core/bm_engine.dart';
import 'bm_audio.dart';
import 'bm_ball.dart';
import 'bm_painter.dart';
import '../intro/fs_game_bar.dart';
import '../intro/fs_intro_data.dart';
import '../intro/fs_intro_ui.dart' show FsBarHandle, kFsBarHandleHeight, kFsBarHandleWidth;
import '../intro/fs_online_pick.dart';
import '../intro/fs_score_table.dart';
import '../intro/fs_team_select.dart' show FsSidePlayer;

const String _a = 'assets/games/bermuda/';

/// Online match settings (config.js MATCH_SECONDS / TURN_SECONDS).
const int kBmMatchSeconds = 300;

/// Width reserved at each side of the top row for the host's exit / ORACLE buttons (6dp + 48dp + 4dp).
const double kBmHostButtonLane = 58;

/// Height of the match scoreboard (team chips + clock) below the status bar.
const double kBmScoreboardHeight = 64;
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

  /// v6 reference toast "یک دقیقه تا پایان بازی": seconds it stays up, fired once when the match clock enters its
  /// last minute.
  double _minuteT = 0;
  double _prevMleft = -1;

  /// v6 score table avatars per global seat (ANIX avatar id or photo url), exchanged on the live channel ('fs_av').
  final Map<int, String> _avatars = <int, String>{};
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

  /// v5: the online pick screens were opened on this phone; they stay up (waiting) until the match starts.
  bool _pickShown = false;

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
      my = _Setup(
          // Only an owned (or free) team can be fielded; locked teams fall back to the default free team.
          GemShop.instance.usableTeam(kBmTeams.any((BmTeam x) => x.id == t) ? t : kDefaultTeam),
          (p.getInt('bm.form') ?? 0).clamp(0, kBmForms.length - 1).toInt(),
          bmFieldIndex(p.getInt('bm.field')),
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
      await p.setInt('bm.field', my.field);
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
      launch.net?.sendLive('fs_av', <String, dynamic>{'av': _myAvatar});
    } catch (_) {}
  }

  void _onLive(NetLiveMessage m) {
    if (_disposed || m.event != 'fs_av' || m.seat < 0 || m.seat == mySeat) return;
    final dynamic av = m.data['av'];
    if (av is! String || av.isEmpty || av.length > 512) return;
    final bool known = _avatars.containsKey(m.seat);
    _avatars[m.seat] = av;
    // a phone we had not heard from yet (joined late): tell it ours once
    if (!known) _announceAvatar();
  }

  // ------------------------------------------------------------------ loop
  void _onTick(Duration el) {
    double dt = (el - _last).inMicroseconds / 1e6;
    _last = el;
    if (dt < 0) dt = 0;
    _nowMs = el.inMicroseconds / 1000;
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
          _report(holdMs: kFsScoreTableSeconds * 1000);
          // v6.1 fix: the table is a child of build(), not of the per-frame builders: rebuild once to show it.
          if (mounted && !_disposed) setState(() {});
        }
      }
      if (_tableT > 0) _tableT = math.max(0, _tableT - dt);
      _checkSideLeft();
    }
    if (_disposed) return;
    _frame.value++;
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
        .where((BmTeam t) => t.id != my.team && (t.cat != 'lux' || r.nextInt(4) == 0))
        .toList();
    final FsMatchPick? pk = widget.pick;
    final String opp = pk != null ? pk.teams[1] : clubs[r.nextInt(clubs.length)].id;
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
          : <int>[my.form, r.nextInt(kBmForms.length)],
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
    final String team = kBmTeams.any((BmTeam x) => x.id == t) ? t : (seat == 0 ? 'club0' : 'club1');
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

  Future<void> _loadMatchImages(BmConfig c) async {
    final BmFieldS f = kBmFields[bmFieldIndex(c.field)];
    final List<ui.Image?> r = await Future.wait(<Future<ui.Image?>>[
      _img(f.asset),
      f.builtInGoals ? Future<ui.Image?>.value(null) : _img('${_a}goals/${f.gs}.webp'),
      // v6: the classic ball is drawn by the 3D roller from its flat art (no sprite sheet)
      c.ball == kBmClassicBallIndex ? _img(kBmClassicBall) : Future<ui.Image?>.value(null),
      _img(bmTeam(c.teams[e.ct(0)]).asset, w: 192),
      _img(bmTeam(c.teams[e.ct(1)]).asset, w: 192),
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

  void _report({bool forfeit = false, int? sideLeft, bool leftTeam = false, int? holdMs}) {
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
            _armSetupFallback();
          } else if (mySeat > 1) {
            // team games: seats 0 and 1 pick their side's team / formation; the others wait for them.
            stage = 'waiting';
          }
        }
      }
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
    _setups[mySeat] = _Setup(GemShop.instance.usableTeam(my.team), my.form, my.field, my.ball);
    net.send(_setups[mySeat]!.toJson());
    stage = 'waiting';
    _maybeStartOnline();
    _armSetupFallback();
    setState(() {});
  }

  /// Seconds this phone waits, after sending its own setup, for the other side's (v5: both phones open the formation
  /// screen on the same logged team pick and it times out after 15 s; this covers a phone that left or never opened
  /// the picks). Was 75 with the v4 45 s team screen.
  static const int kOnlineSetupWaitSeconds = 25;

  void _armSetupFallback() {
    if (_setupFallback != null || mySeat > 1 || stage == 'match') return;
    _setupFallback = Timer(const Duration(seconds: kOnlineSetupWaitSeconds), () {
      final NetLink? net = launch.net;
      final int opp = 1 - mySeat;
      if (_disposed || net == null || stage == 'match' || _setups.containsKey(opp)) return;
      final _Setup d = (_roomPrefs != null ? _prefSetup(opp) : null) ??
          _Setup(opp == 0 ? 'club0' : 'club1', 0, my.field, my.ball);
      net.send(<String, dynamic>{...d.toJson(), 'for': opp});
    });
  }

  /// v4: the online team / formation screens (seats 0 and 1, before their setup is logged).
  bool get _onlinePicking =>
      online &&
      _netReady &&
      mySeat <= 1 &&
      ((stage == 'setup' && !_setups.containsKey(mySeat)) || (stage == 'waiting' && _pickShown));

  Widget _onlinePick() {
    _pickShown = true;
    final NetLink net = launch.net!;
    final int opp = 1 - mySeat;
    String nm(int s) => s < net.names.length && net.names[s].isNotEmpty ? net.names[s] : (s == mySeat ? 'من' : 'حریف');
    final ProfileService? pr = ProfileService.current;
    return FsOnlinePick(
      key: const ValueKey<String>('online-pick'),
      team: my.team,
      form: my.form,
      opponentTeam: _setups[opp]?.team ?? _teamPicks[opp] ?? (opp == 0 ? 'club0' : 'club1'),
      opponentTeamIn: _teamPicks.containsKey(opp) || _setups.containsKey(opp),
      onTeam: (String t) {
        final NetLink? n = launch.net;
        if (_disposed || n == null || _teamPicks.containsKey(mySeat) || _setups.containsKey(mySeat)) return;
        final String team = GemShop.instance.usableTeam(t);
        _teamPicks[mySeat] = team;
        n.send(<String, dynamic>{'a': 'tpick', 'team': team});
        if (mounted) setState(() {});
      },
      players: <FsSidePlayer>[
        FsSidePlayer(
            name: nm(mySeat),
            portrait: 'assets/ui/anix/avatars/${pr?.portrait ?? '01-vanguard'}.webp',
            badge: 'سطح ${fsFa(pr?.level ?? 1)}'),
        FsSidePlayer(name: nm(opp), portrait: 'assets/ui/anix/avatars/02-cyber-scout.webp', badge: 'حریف'),
      ],
      topLane: 50,
      onBar: () {},
      onDone: (String t, int f) {
        if (_disposed || stage != 'setup' || _setups.containsKey(mySeat)) return;
        my.team = GemShop.instance.usableTeam(t);
        my.form = f;
        unawaited(_savePrefs());
        _sendSetup();
      },
    );
  }

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

  @override
  void dispose() {
    _disposed = true;
    _setupFallback?.cancel();
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
    e.stop();
    super.dispose();
  }

  // ------------------------------------------------------------------ build
  @override
  Widget build(BuildContext context) {
    if (stage != 'match') {
      // v4: no menu soundtrack on the screen that only hands over to an auto-started match (offline intro), and
      // none during a match; it comes back on the setup screen after leaving a match.
      if (launch.soundOn && !_paused && _visible && !widget.autoStart) unawaited(audio.music(true));
      if (_onlinePicking) return _onlinePick();
      return _setupScreen(context);
    }
    final double dpr = math.min(MediaQuery.devicePixelRatioOf(context), 1.75);
    // Layout only: centre the pitch (goals included) in the space between the scoreboard and the
    // gesture bar, so neither the HUD nor the system bars cover it.
    final EdgeInsets pad = MediaQuery.paddingOf(context);
    view.insetTop = pad.top + kBmScoreboardHeight;
    view.insetBottom = pad.bottom + 8;
    final bool fancy = launch.fancyEffects && !launch.reducedMotion;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF03060D),
        child: Stack(children: <Widget>[
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (PointerDownEvent ev) {
                final Offset w = view.toWorld(ev.localPosition);
                e.pointerDown(w.dx, w.dy);
              },
              onPointerMove: (PointerMoveEvent ev) {
                final Offset w = view.toWorld(ev.localPosition);
                e.pointerMove(w.dx, w.dy);
              },
              onPointerUp: (_) => e.pointerUp(),
              onPointerCancel: (_) => e.pointerCancel(),
              child: CustomPaint(
                painter: BmPainter(e, im, view, () => _nowMs, dpr, fancy,
                    repaint: _frame),
                size: Size.infinite,
              ),
            ),
          ),
          // vignette (#vig)
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: .95,
                    colors: <Color>[
                      Color(0x00000000),
                      Color(0x00000000),
                      Color(0x94050316)
                    ],
                    stops: <double>[0, .52, 1],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
              left: 0, right: 0, top: 0, child: SafeArea(child: _scoreboard())),
          Positioned.fill(child: IgnorePointer(child: _overlays())),
          if (_tableT >= 0) Positioned.fill(child: _scoreTable()),
          Positioned(
            left: 0,
            bottom: 12 + MediaQuery.paddingOf(context).bottom,
            child: FsBarHandle(players: cfg?.names.length ?? 2, onTap: _pause),
          ),
          // v6 reference toast "یک دقیقه تا پایان بازی" (dark pill, ~3 s). v7: one row above the game bar, because
          // the formation button now sits beside the bar.
          Positioned(
            left: 6,
            right: 8,
            bottom: 12 + MediaQuery.paddingOf(context).bottom + kBmFormButtonRowLift,
            child: IgnorePointer(
              child: ValueListenableBuilder<int>(
                valueListenable: _frame,
                builder: (BuildContext context, int _, Widget? __) => _minuteT > 0 && _tableT < 0
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: BmMinuteToast(
                            text: launch.tx('یک دقیقه تا پایان بازی', 'One minute left'),
                            opacity: (_minuteT / .25).clamp(0.0, 1.0).toDouble()))
                    : const SizedBox.shrink(),
              ),
            ),
          ),
          // Reference in-match "تغییر ترکیب" button. v7 (owner request 2026-11-20): moved down to sit beside the game
          // bar handle, on the same row (it used to float one row above the handle). Always shown while the match
          // runs; only the end-of-match score table (match over) covers that corner.
          if (_tableT < 0)
          Positioned(
            left: kBmFormButtonLeft,
            bottom: 12 + MediaQuery.paddingOf(context).bottom + (kFsBarHandleHeight - kBmFormButtonHeight) / 2,
            child: BmChangeFormButton(label: launch.tx('تغییر ترکیب', 'Formation'), onTap: _changeFormation),
          ),
        ]),
      ),
    );
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

  Widget _scoreboard() {
    return ValueListenableBuilder<int>(
      valueListenable: _frame,
      builder: (BuildContext context, int _, Widget? __) {
        final NxThemeColors visual = NxThemeColors.of(context);
        final double screenWidth = MediaQuery.sizeOf(context).width;
        // A wide, shallow HUD gives names and scores room without covering the pitch.
        // The host's exit + ORACLE buttons (48dp at 6dp from each edge) sit in the top corners:
        // keep the scoreboard between them instead of under them.
        final double sw = math.max(0, math.min(screenWidth - 2 * kBmHostButtonLane, 620));
        final bool aim = e.phase == 'aim';
        String clock = '';
        // v6 reference banner: 0 = white plates / yellow clock, 1 = red; flashes over the last minute and stays red
        // once the time is up (and in golden goal).
        double red = 0;
        if (e.mt > 0) {
          if (e.sd) {
            clock = launch.tx('گل طلایی', 'GOLDEN');
            red = 1;
          } else {
            // v3 (owner request 2026-11-20): a natural match clock that counts the played time up in real
            // seconds (00:00 -> match length) instead of counting down.
            final int el = math.min(e.mt, math.max(0, (e.mt - e.mleft).floor()));
            clock = '${(el ~/ 60).toString().padLeft(2, '0')}:${(el % 60).toString().padLeft(2, '0')}';
            if (launch.isFa) clock = fsFa(clock);
            red = bmClockRed(e.mleft, e.mt);
          }
        }
        final int tl = math.max(0, e.tleft.ceil());

        Widget team(int t) {
          final bool on = aim && e.turn == t;
          final Color accent = t == 0 ? visual.accent : visual.accentSecondary;
          final Widget logo = Container(
            width: 26,
            height: 26,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: visual.background.withValues(alpha: .78),
              border: Border.all(
                  color: on ? accent : visual.border.withValues(alpha: .56),
                  width: on ? 1.6 : 1),
              boxShadow: on
                  ? <BoxShadow>[
                      BoxShadow(
                          color: accent.withValues(alpha: .42), blurRadius: 12)
                    ]
                  : null,
            ),
            child: ClipOval(
                child: Image.asset(bmTeam(e.sel[e.ct(t)]).asset,
                    cacheWidth: 96, fit: BoxFit.contain)),
          );
          final Widget identity = Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
                  t == 0 ? CrossAxisAlignment.start : CrossAxisAlignment.end,
              children: <Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (on && t == 0) _TurnDot(color: accent),
                    if (on && t == 0) const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        e.nm(t),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: t == 0 ? TextAlign.left : TextAlign.right,
                        style: TextStyle(
                            color: visual.text,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (on && t == 1) const SizedBox(width: 4),
                    if (on && t == 1) _TurnDot(color: accent),
                  ],
                ),
              ],
            ),
          );
          final List<Widget> children = t == 0
              ? <Widget>[logo, const SizedBox(width: 6), identity]
              : <Widget>[identity, const SizedBox(width: 6), logo];
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              decoration: BoxDecoration(
                color: on ? accent.withValues(alpha: .13) : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: on
                        ? accent.withValues(alpha: .72)
                        : Colors.transparent),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // v6: on a narrow phone the chip keeps the name (the crest is on every disc) so the banner fits.
                  LayoutBuilder(
                      builder: (BuildContext context, BoxConstraints box) =>
                          Row(children: box.maxWidth >= 84 ? children : <Widget>[identity])),
                  // Reference turn clock: an orange bar under each name, full while waiting, draining toward the
                  // left on the side whose turn it is.
                  if (e.tt > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .45),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: on ? (e.tleft / e.tt).clamp(0.0, 1.0).toDouble() : 1,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(2),
                              gradient: const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: <Color>[Color(0xFFFFC23A), Color(0xFFFF8A00)],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        }

        return Center(
          child: SizedBox(
            width: sw,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: visual.surface.withValues(alpha: .96),
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: visual.border.withValues(alpha: .78)),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                          color: Colors.black.withValues(alpha: .34),
                          blurRadius: 18,
                          offset: const Offset(0, 8)),
                      BoxShadow(
                          color: visual.accent.withValues(alpha: .10),
                          blurRadius: 20),
                    ],
                  ),
                  child: Row(
                    children: <Widget>[
                      team(0),
                      // v6: the reference's score banner (white score plates either side of a yellow clock).
                      BmScoreBanner(
                        left: launch.isFa ? fsFa(e.score[0]) : '${e.score[0]}',
                        right: launch.isFa ? fsFa(e.score[1]) : '${e.score[1]}',
                        clock: clock,
                        red: red,
                      ),
                      team(1),
                    ],
                  ),
                ),
                if (aim && e.tt > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: visual.surfaceRaised.withValues(alpha: .94),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                            color: (e.tleft < 5
                                    ? const Color(0xFFFF697A)
                                    : visual.border)
                                .withValues(alpha: .8)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            _TurnDot(
                                color: e.tleft < 5
                                    ? const Color(0xFFFF697A)
                                    : visual.accent),
                            const SizedBox(width: 5),
                            Text(
                              '${launch.tx('نوبت', 'TURN')} ${e.turn + 1}',
                              style: TextStyle(
                                  color: visual.muted,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: .5),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${tl}s',
                              style: TextStyle(
                                color: e.tleft < 5
                                    ? const Color(0xFFFF8794)
                                    : visual.text,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                fontFeatures: const <ui.FontFeature>[
                                  ui.FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Locked team: confirm + buy with gems (server-side deduct and unlock). True when the team is now owned.
  Future<bool> _buyTeam(BmTeam t) async {
    final GemShop shop = GemShop.instance;
    final int price = shop.teamPrice(t.id);
    final bool fa = Localizations.localeOf(context).languageCode == 'fa';
    final int bal = ProfileService.current?.gems ?? 0;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        backgroundColor: const Color(0xFF120A33),
        title: Row(children: <Widget>[
          SizedBox(width: 40, height: 40, child: Image.asset(t.asset, cacheWidth: 96)),
          const SizedBox(width: 10),
          Expanded(child: Text(t.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900))),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(AnixAssets.sceneArenaPortal, height: 110, width: double.infinity, fit: BoxFit.cover, cacheWidth: 600),
          ),
          const SizedBox(height: 10),
          Text(fa ? 'این تیم قفل است. با $price الماس بازش کن؟' : 'This team is locked. Unlock it for $price gems?',
              style: const TextStyle(color: Colors.white)),
          const SizedBox(height: 6),
          Row(children: <Widget>[
            const Icon(Icons.diamond_rounded, size: 16, color: Color(0xFF3BD0FF)),
            const SizedBox(width: 4),
            Text(fa ? 'موجودی: $bal' : 'Balance: $bal', style: const TextStyle(color: Color(0xFFBFB3E6))),
          ]),
        ]),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(fa ? 'انصراف' : 'Cancel')),
          FilledButton.icon(
            onPressed: bal >= price ? () => Navigator.pop(c, true) : null,
            icon: const Icon(Icons.diamond_rounded, size: 16),
            label: Text(fa ? 'خرید با $price' : 'Buy for $price'),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    final GemBuyResult r = await shop.buyTeam(t.id);
    if (!mounted) return r.ok;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(r.ok ? (fa ? '${t.name} باز شد ✓' : '${t.name} unlocked ✓') : gemErrorText(r.error, fa))));
    if (r.ok) setState(() {});
    return r.ok;
  }

  // ------------------------------------------------------------------ setup screen
  Widget _setupScreen(BuildContext context) {
    final bool waiting = stage == 'waiting' || (online && !_netReady);
    final bool chooseArena = !online || isHostSeat;
    final List<BmTeam> teams =
        kBmTeams.where((BmTeam t) => t.cat == kBmCats[_cat][0]).toList();
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
                          Text('ANIX  /  MATCH LOBBY',
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
                            final bool on = t.id == my.team;
                            final bool owned = GemShop.instance.ownsTeam(t.id);
                            return GestureDetector(
                              onTap: () async {
                                if (!owned && !await _buyTeam(t)) return;
                                if (!mounted) return;
                                setState(() {
                                  my.team = t.id;
                                  audio.sfx('ui');
                                  unawaited(_savePrefs());
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
                                            child: Image.asset(t.asset, cacheWidth: 128)),
                                        if (!owned)
                                          Positioned(
                                            bottom: 0,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: const Color(0xE60B1230),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: const Color(0xFF3BD0FF)),
                                              ),
                                              child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                                                const Icon(Icons.diamond_rounded, size: 10, color: Color(0xFF3BD0FF)),
                                                const SizedBox(width: 2),
                                                Text('${GemShop.instance.teamPrice(t.id)}',
                                                    style: const TextStyle(
                                                        color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w900)),
                                              ]),
                                            ),
                                          ),
                                        if (!owned)
                                          const Positioned(
                                              top: 0,
                                              right: 0,
                                              child: Icon(Icons.lock_rounded, size: 14, color: Color(0xFFE2B04A))),
                                      ],
                                    )),
                                    const SizedBox(height: 3),
                                    Text(t.name,
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
                                    on: my.form == i,
                                    selectLabel: launch.tx('انتخاب', 'Select'),
                                    selectedLabel: launch.tx('انتخاب شده', 'Selected'),
                                    onTap: () => setState(() {
                                      my.form = i;
                                      audio.sfx('ui');
                                      unawaited(_savePrefs());
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
                                          child: Text(kBmFields[i].name,
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
                              Text(
                                  launch.tx('در انتظار حریف…',
                                      'Waiting for the opponent…'),
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
                                ? launch.tx('آماده‌ام', 'READY')
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

/// v7 layout of the in-match formation button: on the game bar's row, just right of the bar handle
/// ([kFsBarHandleWidth] wide, at the left edge), vertically centred on it.
const double kBmFormButtonHeight = 36;
const double kBmFormButtonLeft = kFsBarHandleWidth + 8;
/// Lift of the "one minute left" toast: one row above the game bar (where the formation button used to be).
const double kBmFormButtonRowLift = 48;

/// The reference's in-match "تغییر ترکیب" button: a dark pill with the label and a small green pitch icon.
class BmChangeFormButton extends StatelessWidget {
  const BmChangeFormButton({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: kBmFormButtonHeight,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: const Color(0xE61C1E22),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white24),
            boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x66000000), blurRadius: 6, offset: Offset(0, 2))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            Container(
              width: 30,
              height: 22,
              decoration: BoxDecoration(
                color: const Color(0xFF2E9B32),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: const Color(0xFF9CFF7A)),
              ),
              child: const Icon(Icons.grid_view_rounded, size: 14, color: Colors.white),
            ),
          ]),
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
  const _Chip({required this.label, required this.on, required this.onTap});
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

class _TurnDot extends StatelessWidget {
  const _TurnDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[
            BoxShadow(color: color.withValues(alpha: .62), blurRadius: 6)
          ]),
    );
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

/// v6: the reference's in-match score banner: a white score plate on each side of a yellow hexagonal clock, all
/// turning red by [red] (last-minute pulse, solid red at the final whistle / golden goal).
class BmScoreBanner extends StatelessWidget {
  const BmScoreBanner({super.key, required this.left, required this.right, required this.clock, this.red = 0});
  final String left;
  final String right;
  final String clock;
  final double red;

  static const double kWidth = 122;
  static const double kHeight = 34;
  static const double kPlate = 30;

  @override
  Widget build(BuildContext context) {
    final double k = red.clamp(0.0, 1.0).toDouble();
    final Color score = Color.lerp(const Color(0xFF1E2230), const Color(0xFF240306), k)!;
    final Color clockInk = Color.lerp(const Color(0xFF3C3300), const Color(0xFFFFE9EC), k)!;
    TextStyle st(Color c, double size) => TextStyle(
      color: c,
      fontSize: size,
      height: 1,
      fontWeight: FontWeight.w900,
      fontFeatures: const <ui.FontFeature>[ui.FontFeature.tabularFigures()],
    );
    return SizedBox(
      width: kWidth,
      height: kHeight,
      child: CustomPaint(
        painter: _BannerPainter(k),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: kPlate,
              child: Padding(
                padding: const EdgeInsets.only(left: 5),
                child: Center(
                  child: FittedBox(child: Text(left, maxLines: 1, style: st(score, 19))),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(clock, maxLines: 1, style: st(clockInk, 14)),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: kPlate,
              child: Padding(
                padding: const EdgeInsets.only(right: 5),
                child: Center(
                  child: FittedBox(child: Text(right, maxLines: 1, style: st(score, 19))),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BannerPainter extends CustomPainter {
  _BannerPainter(this.k);
  final double k;

  Color _l(int a, int b) => Color.lerp(Color(a), Color(b), k)!;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width, h = size.height, p = BmScoreBanner.kPlate, n = 8;
    final Paint edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.black.withValues(alpha: .55);
    Paint fill(Rect r, int top, int bottom, int topR, int bottomR) => Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[_l(top, topR), _l(bottom, bottomR)],
      ).createShader(r);
    // score plates (pointed outward ends), behind the clock
    final Path lp = Path()
      ..moveTo(n, 0)
      ..lineTo(p + n, 0)
      ..lineTo(p + n, h)
      ..lineTo(n, h)
      ..lineTo(0, h / 2)
      ..close();
    final Path rp = Path()
      ..moveTo(w - n, 0)
      ..lineTo(w - p - n, 0)
      ..lineTo(w - p - n, h)
      ..lineTo(w - n, h)
      ..lineTo(w, h / 2)
      ..close();
    final Rect all = Offset.zero & size;
    for (final Path q in <Path>[lp, rp]) {
      canvas.drawPath(q, fill(all, 0xFFFFFFFF, 0xFFCFD3DA, 0xFFFFC2CA, 0xFFF0687A));
      canvas.drawPath(q, edge);
    }
    // clock hexagon
    final Path c = Path()
      ..moveTo(p + n, 0)
      ..lineTo(w - p - n, 0)
      ..lineTo(w - p, h / 2)
      ..lineTo(w - p - n, h)
      ..lineTo(p + n, h)
      ..lineTo(p, h / 2)
      ..close();
    canvas.drawShadow(c, Colors.black, 2, false);
    canvas.drawPath(c, fill(all, 0xFFFFF35A, 0xFFC9B400, 0xFFF0303A, 0xFFA50E16));
    // top gloss
    canvas.drawPath(
      Path()
        ..moveTo(p + n + 2, 2)
        ..lineTo(w - p - n - 2, 2)
        ..lineTo(w - p - n * .5 - 2, h * .42)
        ..lineTo(p + n * .5 + 2, h * .42)
        ..close(),
      Paint()..color = Colors.white.withValues(alpha: .22),
    );
    canvas.drawPath(c, edge);
  }

  @override
  bool shouldRepaint(_BannerPainter old) => old.k != k;
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
