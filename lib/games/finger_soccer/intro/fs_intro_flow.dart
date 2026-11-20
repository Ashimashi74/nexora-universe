// Pre-match flow for offline finger soccer (vs bot / pass-and-play), as in the reference game:
// splash -> team select (team one / team two, ready countdown; shop on top) -> formation select -> the match.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nexora/core/economy/gem_shop.dart';
import 'package:nexora/core/profile/profile_service.dart';
import 'package:nexora/games/core/game_contract.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/bm_engine.dart';
import '../ui/bm_view.dart';
import 'fs_formation_select.dart';
import 'fs_game_bar.dart';
import 'fs_intro_data.dart';
import 'fs_shop.dart';
import 'fs_splash.dart';
import 'fs_team_select.dart';

/// Room for the game host's exit / ORACLE buttons over the top corners.
const double kFsHostLane = 50;

class FsIntroFlow extends StatefulWidget {
  const FsIntroFlow({super.key, required this.launch, this.topLane = kFsHostLane});
  final GameLaunch launch;
  final double topLane;
  @override
  State<FsIntroFlow> createState() => _FsIntroFlowState();
}

class _FsIntroFlowState extends State<FsIntroFlow> {
  String _stage = 'splash'; // splash | team | shop | form0 | form1 | match
  late final math.Random _r = math.Random(widget.launch.seed);
  late final List<String> _teams = <String>[kDefaultTeam, _randomTeam(kDefaultTeam)];
  final List<int> _forms = <int>[0, 0];
  final FsBarSettings _bar = FsBarSettings();
  int _side = 0;
  FsMatchPick? _pick;

  GameLaunch get launch => widget.launch;
  bool get _bot => launch.vsBot;

  String _randomTeam(String not) {
    final List<BmTeam> pool = kBmTeams.where((BmTeam t) => t.id != not && (t.cat != 'lux' || _r.nextInt(4) == 0)).toList();
    return pool.isEmpty ? kBmTeams.first.id : pool[_r.nextInt(pool.length)].id;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      final String t = p.getString('bm.team') ?? kDefaultTeam;
      final int f = p.getInt('bm.form') ?? 0;
      if (!mounted) return;
      setState(() {
        _teams[0] = GemShop.instance.usableTeam(kBmTeams.any((BmTeam x) => x.id == t) ? t : kDefaultTeam);
        if (_teams[1] == _teams[0]) _teams[1] = _randomTeam(_teams[0]);
        _forms[0] = f.clamp(0, math.max(0, kBmForms.length - 1)).toInt();
      });
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      await p.setString('bm.team', _teams[0]);
      await p.setInt('bm.form', _forms[0]);
    } catch (_) {}
  }

  List<FsSidePlayer> get _players {
    final ProfileService? pr = ProfileService.current;
    final String me = launch.playerName.isEmpty ? 'بازیکن ۱' : launch.playerName;
    return <FsSidePlayer>[
      FsSidePlayer(
          name: me,
          portrait: 'assets/ui/anix/avatars/${pr?.portrait ?? '01-vanguard'}.webp',
          badge: 'سطح ${fsFa(pr?.level ?? 1)}'),
      _bot
          ? const FsSidePlayer(name: 'ربات', portrait: 'assets/ui/anix/avatars/04-iron-warden.webp', badge: 'ربات')
          : const FsSidePlayer(name: 'بازیکن ۲', portrait: 'assets/ui/anix/avatars/02-cyber-scout.webp', badge: 'مهمان'),
    ];
  }

  void _openBar() {
    unawaited(FsGameBar.show(
      context,
      settings: _bar,
      players: _players.map((FsSidePlayer p) => p.name).toList(),
      onExit: () {
        final NavigatorState nav = Navigator.of(context);
        if (nav.canPop()) nav.pop();
      },
    ));
  }

  void _toForms(List<String> teams) {
    setState(() {
      _teams
        ..[0] = teams[0]
        ..[1] = teams[1];
      _stage = 'form0';
    });
  }

  void _formDone(int side, int f) {
    _forms[side] = f;
    if (side == 0 && !_bot) {
      setState(() => _stage = 'form1');
      return;
    }
    if (_bot) _forms[1] = kBmForms.isEmpty ? 0 : _r.nextInt(kBmForms.length);
    unawaited(_save());
    setState(() {
      _pick = FsMatchPick(teams: List<String>.of(_teams), forms: List<int>.of(_forms));
      _stage = 'match';
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget child = switch (_stage) {
      'splash' => FsSplash(key: const ValueKey<String>('splash'), onDone: () => setState(() => _stage = 'team')),
      'team' || 'shop' => Stack(key: const ValueKey<String>('teamstage'), fit: StackFit.expand, children: <Widget>[
          FsTeamSelect(
            key: const ValueKey<String>('team'),
            fa: true,
            teams: _teams,
            players: _players,
            side: _side,
            onSide: (int s) => _side = s,
            topLane: widget.topLane,
            onReady: _toForms,
            onShop: () => setState(() => _stage = 'shop'),
            onBar: _openBar,
          ),
          if (_stage == 'shop')
            FsShop(
              fa: true,
              team: _teams[0],
              topLane: widget.topLane,
              onTeam: (String t) => setState(() => _teams[0] = t),
              onBack: () => setState(() => _stage = 'team'),
            ),
        ]),
      'form0' || 'form1' => FsFormationSelect(
          key: ValueKey<String>(_stage),
          discAsset: bmTeam(_teams[_stage == 'form0' ? 0 : 1]).asset,
          initial: _forms[_stage == 'form0' ? 0 : 1],
          subtitle: _bot ? null : (_stage == 'form0' ? 'تیم یک' : 'تیم دو'),
          topLane: widget.topLane,
          onDone: (int f) => _formDone(_stage == 'form0' ? 0 : 1, f),
          onBar: _openBar,
        ),
      _ => BermudaView(key: const ValueKey<String>('match'), launch: launch, pick: _pick, autoStart: true),
    };
    return ColoredBox(color: Colors.black, child: AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: child));
  }
}
