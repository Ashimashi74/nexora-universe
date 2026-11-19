import 'package:flutter/material.dart';

import '../core/golf_core.dart';

/// Classic scorecard: one column per hole (par row on top), one row per player, total and +/- par.
class GolfScorecard extends StatelessWidget {
  const GolfScorecard({
    super.key,
    required this.match,
    required this.names,
    required this.colors,
    required this.isFa,
    this.highlightHole,
  });

  final GolfMatch match;
  final List<String> names;
  final List<Color> colors;
  final bool isFa;
  final int? highlightHole;

  String _tx(String fa, String en) => isFa ? fa : en;

  @override
  Widget build(BuildContext context) {
    final GolfMatch g = match;
    const TextStyle head = TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w800);
    const TextStyle cell = TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900);
    Widget box(Widget child, {double w = 26, Color? bg}) => Container(
          width: w,
          height: 26,
          alignment: Alignment.center,
          color: bg,
          child: child,
        );
    Color? scoreBg(int s, int par) {
      if (s > kMaxStrokes) return const Color(0x55FF2D55);
      if (s == 1) return const Color(0xAAFFD34E);
      if (s < par) return const Color(0x6639E1FF);
      if (s > par) return const Color(0x33FF8A3D);
      return null;
    }

    final List<Widget> rows = <Widget>[
      Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        box(Text(_tx('حفره', 'HOLE'), style: head), w: 74),
        for (int i = 0; i < g.course.length; i++)
          box(Text('${i + 1}', style: head), bg: highlightHole == i ? const Color(0x33FFFFFF) : null),
        box(Text(_tx('جمع', 'TOT'), style: head), w: 38),
        box(const Text('±', style: head), w: 32),
      ]),
      Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        box(Text(_tx('پار', 'PAR'), style: head), w: 74),
        for (int i = 0; i < g.course.length; i++) box(Text('${g.course[i].par}', style: head)),
        box(Text('${g.parTotal()}', style: head), w: 38),
        box(const SizedBox(), w: 32),
      ]),
      for (int p = 0; p < g.players; p++)
        Opacity(
          opacity: g.out.contains(p) ? 0.45 : 1,
          child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
            box(
                Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: colors[p % colors.length])),
                  const SizedBox(width: 4),
                  Flexible(child: Text(names[p], style: cell.copyWith(fontSize: 11), overflow: TextOverflow.ellipsis, maxLines: 1)),
                ]),
                w: 74),
            for (int i = 0; i < g.course.length; i++)
              box(
                Text(i < g.cards[p].length ? (g.cards[p][i] > kMaxStrokes ? 'X' : '${g.cards[p][i]}') : '·', style: cell),
                bg: i < g.cards[p].length ? scoreBg(g.cards[p][i], g.course[i].par) : null,
              ),
            box(Text('${g.total(p)}', style: cell), w: 38),
            box(
                Text(g.cards[p].isEmpty ? '–' : (g.toPar(p) > 0 ? '+${g.toPar(p)}' : (g.toPar(p) == 0 ? 'E' : '${g.toPar(p)}')),
                    style: cell),
                w: 32),
          ]),
        ),
    ];
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xE6081A10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x887CFF7A)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: rows),
        ),
      ),
    );
  }
}
