// Online pre-match picks (v4, owner request 2026-11-20): the same team select and formation select screens as the
// offline intro, but each phone picks only its own side. The pick is sent to the other phone as the logged
// {'a': 'setup'} move (see BermudaView._sendSetup); the match starts when both sides' setups are in the log.
// Both screens run their own countdown (team 45 s, formation 15 s), so a player who does nothing still sends the
// team / formation shown (their saved pick or the room's) and a match never waits on an idle screen.
import 'package:flutter/material.dart';

import '../core/bm_engine.dart';
import 'fs_formation_select.dart';
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
    this.teamSeconds = 45,
    this.formSeconds = 15,
    this.freeze = false,
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

  @override
  State<FsOnlinePick> createState() => _FsOnlinePickState();
}

class _FsOnlinePickState extends State<FsOnlinePick> {
  late final List<String> _teams = <String>[widget.team, widget.opponentTeam];
  bool _form = false;
  bool _shop = false;

  @override
  void didUpdateWidget(FsOnlinePick old) {
    super.didUpdateWidget(old);
    _teams[1] = widget.opponentTeam;
  }

  @override
  Widget build(BuildContext context) {
    if (_form) {
      return FsFormationSelect(
        key: const ValueKey<String>('online-form'),
        discAsset: bmTeam(_teams[0]).asset,
        initial: widget.form,
        seconds: widget.formSeconds,
        freezeAt: widget.freeze ? 0 : null,
        topLane: widget.topLane,
        onDone: (int f) => widget.onDone(_teams[0], f.clamp(0, kBmForms.length - 1).toInt()),
        onBar: widget.onBar,
      );
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
      onReady: (List<String> t) => setState(() {
        _teams[0] = t[0];
        _form = true;
      }),
      onShop: () => setState(() => _shop = true),
      onBar: widget.onBar,
    );
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
