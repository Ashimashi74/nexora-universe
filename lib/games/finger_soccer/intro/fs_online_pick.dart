// Online pre-match picks (v4, owner request 2026-11-20): the same team select and formation select screens as the
// offline intro, but each phone picks only its own side. The pick is sent to the other phone as the logged
// {'a': 'setup'} move (see BermudaView._sendSetup); the match starts when both sides' setups are in the log.
// Both screens run their own countdown (team 45 s, formation 15 s), so a player who does nothing still sends the
// team / formation shown (their saved pick or the room's) and a match never waits on an idle screen.
// v5 (owner request 2026-11-20): team 15 s then formation 15 s on ONE shared countdown. The team pick is logged
// ({'a': 'tpick'}, onTeam); a side that picks early waits on its team screen (banner + the seconds left) until the
// other side's team pick is in (or the team time + a short grace is over), so both phones open the formation screen
// on the same logged event; after the formation pick the screen waits again until the match starts for everyone.
import 'dart:async';

import 'package:flutter/material.dart';

import '../core/bm_engine.dart';
import 'fs_formation_select.dart';
import 'fs_intro_data.dart' show fsFa;
import 'fs_intro_ui.dart' show fsText, kFsYellow;
import 'fs_shop.dart';
import 'fs_team_select.dart';

class FsOnlinePick extends StatefulWidget {
  const FsOnlinePick({
    super.key,
    required this.team,
    required this.form,
    required this.opponentTeam,
    required this.players,
    required this.onDone,
    required this.onBar,
    this.topLane = 0,
    this.teamSeconds = 15,
    this.formSeconds = 15,
    this.freeze = false,
    this.opponentTeamIn = true,
    this.onTeam,
    this.teamGrace = 3,
  });

  /// Starting pick (saved pick, or the room's pre-game choice).
  final String team;
  final int form;

  /// The opponent's team once their setup has arrived, else a placeholder shown on the "تیم دو" side.
  final String opponentTeam;

  /// [0] = this phone's side, [1] = the opponent.
  final List<FsSidePlayer> players;
  final void Function(String team, int form) onDone;
  final VoidCallback onBar;
  final double topLane;
  final int teamSeconds, formSeconds;

  /// Tests: no countdowns.
  final bool freeze;

  /// v5: the other side's team pick is in the log (their 'tpick' or 'setup'). Until it is, a side that picked its
  /// team early waits on the team screen; both phones then open the formation screen together.
  final bool opponentTeamIn;

  /// v5: this phone's team pick (the parent logs it as {'a': 'tpick'}).
  final ValueChanged<String>? onTeam;

  /// v5: seconds past the shared team time a side waits for an absent opponent's team pick before it moves on.
  final int teamGrace;

  @override
  State<FsOnlinePick> createState() => _FsOnlinePickState();
}

class _FsOnlinePickState extends State<FsOnlinePick> {
  late final List<String> _teams = <String>[widget.team, widget.opponentTeam];
  bool _form = false;
  bool _shop = false;

  /// v5 shared countdown: seconds left on the current screen (team, then formation), ticked once a second.
  late int _left = widget.teamSeconds;
  late int _grace = widget.teamGrace;

  /// This side picked its team / formation and waits for the others.
  bool _teamPicked = false, _formPicked = false, _teamWaitOver = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    if (!widget.freeze) _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void _onTick() {
    if (!mounted) return;
    setState(() {
      if (_left > 0) {
        _left--;
      } else if (!_form && _teamPicked && !_teamWaitOver && --_grace <= 0) {
        // the other side stayed silent past the team time: go on (their setup is filled in later if they left)
        _teamWaitOver = true;
        _maybeOpenForm();
      }
    });
  }

  @override
  void didUpdateWidget(FsOnlinePick old) {
    super.didUpdateWidget(old);
    _teams[1] = widget.opponentTeam;
    _maybeOpenForm();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// Both sides' team picks are in (or the other side stayed silent past the team time): open the formation screen.
  void _maybeOpenForm() {
    if (_form || !_teamPicked || !(widget.opponentTeamIn || _teamWaitOver)) return;
    _form = true;
    _left = widget.formSeconds;
  }

  void _teamReady(List<String> t) {
    if (_teamPicked) return;
    _teamPicked = true;
    _teams[0] = t[0];
    widget.onTeam?.call(t[0]);
    setState(_maybeOpenForm);
  }

  /// Seconds left on the shared clock of the current screen.
  int get _secondsLeft => _left;

  /// "Waiting for the others" banner over a screen this side has finished, with the shared seconds left.
  Widget _waiting(Widget screen) => Stack(fit: StackFit.expand, children: <Widget>[
        AbsorbPointer(child: screen),
        Positioned(
          left: 24,
          right: 24,
          top: 300,
          child: Container(
            key: const ValueKey<String>('online-pick-wait'),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xE6101418),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kFsYellow, width: 1.5),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              Text(_form ? 'منتظر بقیه‌ی بازیکن‌ها…' : 'منتظر انتخاب تیم حریف…',
                  textAlign: TextAlign.center, style: fsText(15, weight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(fsFa(_secondsLeft), style: fsText(26, color: kFsYellow, weight: FontWeight.w900, height: 1)),
            ]),
          ),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    if (_form) {
      final Widget form = FsFormationSelect(
        key: const ValueKey<String>('online-form'),
        discAsset: bmTeam(_teams[0]).asset,
        initial: widget.form,
        seconds: widget.formSeconds,
        freezeAt: widget.freeze ? 0 : null,
        topLane: widget.topLane,
        onDone: (int f) {
          if (_formPicked) return;
          setState(() => _formPicked = true);
          widget.onDone(_teams[0], f.clamp(0, kBmForms.length - 1).toInt());
        },
        onBar: widget.onBar,
      );
      return _formPicked ? _waiting(form) : form;
    }
    final Widget team = FsTeamSelect(
      key: const ValueKey<String>('online-team'),
      fa: true,
      teams: _teams,
      players: widget.players,
      side: 0,
      fixedSide: 0,
      countdown: widget.teamSeconds,
      freeze: widget.freeze,
      topLane: widget.topLane,
      onReady: _teamReady,
      onShop: () => setState(() => _shop = true),
      onBar: widget.onBar,
    );
    if (_teamPicked) return _waiting(team);
    if (!_shop) return team;
    return Stack(fit: StackFit.expand, children: <Widget>[
      team,
      FsShop(
        fa: true,
        team: _teams[0],
        topLane: widget.topLane,
        onTeam: (String t) => setState(() => _teams[0] = t),
        onBack: () => setState(() => _shop = false),
      ),
    ]);
  }
}
