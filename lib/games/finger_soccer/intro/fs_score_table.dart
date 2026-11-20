// v6 (owner request 2026-11-20): the reference's end-of-match "جدول امتیازات" (score table). Shown right after the
// final whistle over the dusk stadium: the title, one bevelled row per side (winner first: lime row with a trophy
// tab, the other side yellow), each with its crest, name and a grey score pill, and "N ثانیه تا بازگشت به جمع"
// counting down (20 s in the recordings) before the host's own result screen takes over.
// v6.1: one row per player (team games: every seat, with its side's goals) showing the player's avatar like the
// reference; the crest is the fallback when an avatar is unknown.
import 'package:flutter/material.dart';
import 'package:nexora/core/widgets/user_avatar.dart';

import 'fs_intro_data.dart';
import 'fs_intro_ui.dart';

/// Seconds the score table stays up (reference recordings: 20 -> 0, then the host's result screen).
const int kFsScoreTableSeconds = 20;

class FsScoreRow {
  const FsScoreRow(
      {required this.name, required this.score, required this.crest, this.winner = false, this.avatar});
  final String name;

  /// Match points shown in the grey pill (the side's goals).
  final int score;

  /// Player avatar: an ANIX avatar id or a photo url (null: the crest is drawn instead).
  final String? avatar;

  /// Asset of the side's crest (drawn in the round avatar slot).
  final String crest;
  final bool winner;
}

class FsScoreTable extends StatelessWidget {
  const FsScoreTable({super.key, required this.rows, required this.seconds, this.fa = true, this.topLane = 0});

  /// Rows in display order (the caller puts the winner first).
  final List<FsScoreRow> rows;

  /// Seconds left on the "back to the room" countdown.
  final int seconds;
  final bool fa;
  final double topLane;

  @override
  Widget build(BuildContext context) {
    return FsCanvas(
      topLane: topLane,
      children: <Widget>[
        Positioned(
          left: 0,
          right: 0,
          top: 8,
          child: Center(
            child: Text(fa ? 'جدول امتیازات' : 'Scoreboard',
                style: fsText(31, weight: FontWeight.w900, shadows: const <Shadow>[
                  Shadow(color: Color(0x99000000), blurRadius: 6, offset: Offset(0, 2)),
                ])),
          ),
        ),
        for (int i = 0; i < rows.length; i++) ..._row(rows[i], 98.0 + i * (rows.length > 4 ? 72 : 84)),
        Positioned(
          left: 0,
          right: 0,
          bottom: 50,
          child: Center(
            child: Text(
              fa ? '${fsFa(seconds)} ثانیه تا بازگشت به جمع' : '$seconds s until back to the room',
              textDirection: fa ? TextDirection.rtl : TextDirection.ltr,
              style: fsText(19, weight: FontWeight.w700, shadows: const <Shadow>[
                Shadow(color: Color(0xAA000000), blurRadius: 4, offset: Offset(0, 1)),
              ]),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _row(FsScoreRow r, double top) {
    final Color hi = r.winner ? const Color(0xFFC8F53A) : const Color(0xFFFFE45A);
    final Color lo = r.winner ? const Color(0xFF7DCB12) : const Color(0xFFFFC21C);
    final Color lip = r.winner ? const Color(0xFF1DB7C4) : const Color(0xFFE5486F);
    return <Widget>[
      if (r.winner)
        Positioned(
          left: 256,
          top: top - 22,
          child: Container(
            width: 34,
            height: 24,
            decoration: const BoxDecoration(
              color: Color(0xFF8BD61C),
              borderRadius: BorderRadius.vertical(top: Radius.circular(5)),
            ),
            child: const Icon(Icons.emoji_events_rounded, size: 17, color: Color(0xFFFFD52E)),
          ),
        ),
      Positioned(
        left: 28,
        top: top,
        child: Container(
          width: 304,
          height: 56,
          decoration: BoxDecoration(
            color: lip,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x66000000), blurRadius: 6, offset: Offset(0, 3))],
          ),
          padding: const EdgeInsets.only(bottom: 7),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: .55), width: 1.2),
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: <Color>[hi, lo]),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(children: <Widget>[
              // rtl: crest at the right end, then the name, the score pill at the left end
              Container(
                width: 40,
                height: 40,
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF1C2038)),
                child: r.avatar != null
                    ? NxUserAvatar(avatar: r.avatar, name: r.name, size: 36)
                    : ClipOval(
                        child: Image.asset(r.crest, fit: BoxFit.contain, cacheWidth: 96,
                            errorBuilder: (_, __, ___) => const SizedBox()),
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(r.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: fsText(18, color: const Color(0xFF1F2533), weight: FontWeight.w800)),
              ),
              const SizedBox(width: 8),
              Container(
                width: 84,
                height: 24,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  gradient: const LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: <Color>[Color(0xFF9A9A9A), Color(0xFF6E6E6E)]),
                  border: Border.all(color: const Color(0xFF4A4A4A), width: 1),
                ),
                alignment: Alignment.center,
                child: Text(fa ? fsFa(r.score) : '${r.score}', style: fsText(15, weight: FontWeight.w800, height: 1.1)),
              ),
            ]),
          ),
        ),
      ),
    ];
  }
}
