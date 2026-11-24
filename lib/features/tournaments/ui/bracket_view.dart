import 'package:flutter/material.dart';

import '../../../core/settings/app_settings.dart';
import '../../../core/ui2/anix_kit.dart';
import '../../../core/theme/nx_theme.dart';
import '../data/models.dart';
import 't_common.dart';

/// Live elimination bracket: columns of rounds with connector lines, pan + pinch zoom (InteractiveViewer).
/// Painting is one CustomPaint for the lines + lightweight positioned cards, so 64-player brackets stay smooth.
/// Art: the ANIX bracket kit (assets/ui/anix/bracket: gold / silver / blue match pills, status badges, champion crest
/// over the podium). It opens zoomed to fit the screen (it used to open as a tiny line drawing on black).
class BracketView extends StatefulWidget {
  const BracketView({
    super.key,
    required this.matches,
    required this.names,
    required this.me,
    this.onTap,
  });

  final List<TMatch> matches;
  final Map<String, String> names;
  final String? me;
  final void Function(TMatch m)? onTap;

  static const double cardW = 200;
  static const double cardH = 72;
  static const double colGap = 54;
  static const double rowGap = 18;

  @override
  State<BracketView> createState() => _BracketViewState();
}

class _BracketViewState extends State<BracketView> {
  final TransformationController _tc = TransformationController();
  Size? _fittedFor;

  List<TMatch> get matches => widget.matches;
  Map<String, String> get names => widget.names;
  String? get me => widget.me;
  void Function(TMatch m)? get onTap => widget.onTap;

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double cardW = BracketView.cardW, cardH = BracketView.cardH, colGap = BracketView.colGap,
        rowGap = BracketView.rowGap;
    final List<TMatch> w =
        matches.where((TMatch m) => m.bracket == 'W').toList();
    final List<TMatch> l =
        matches.where((TMatch m) => m.bracket == 'L').toList();
    final List<TMatch> finals = matches
        .where((TMatch m) =>
            m.bracket == 'GF' || m.bracket == 'GF2' || m.bracket == 'P3')
        .toList();
    if (w.isEmpty && l.isEmpty) {
      return Center(
          child: Text(
              context.tx('براکت بعد از قرعه‌کشی ساخته می‌شود',
                  'The bracket appears after the draw'),
              style: const TextStyle(color: NxColors.textDim)));
    }
    final _Layout winners = _Layout.build(w, 0, 0);
    final _Layout losers = _Layout.build(l, 0, winners.height + 40);
    final Map<String, Offset> pos = <String, Offset>{
      ...winners.pos,
      ...losers.pos
    };
    double width = winners.width > losers.width ? winners.width : losers.width;
    double height = losers.height > 0
        ? winners.height + 40 + losers.height
        : winners.height;
    // finals column on the right
    double fy = 0;
    final double fx = width + colGap;
    for (final TMatch m in finals) {
      final Offset? feed = m.bracket == 'GF' ? winners.lastPos : null;
      pos[m.id] = Offset(fx, feed?.dy ?? fy);
      fy = (feed?.dy ?? fy) + cardH + rowGap * 3;
    }
    if (finals.isNotEmpty) width = fx + cardW;
    if (fy > height) height = fy;
    final int lastW = w.isEmpty
        ? 1
        : w.map((TMatch m) => m.round).reduce((int a, int b) => a > b ? a : b);
    final int firstW = w.isEmpty
        ? 1
        : w.map((TMatch m) => m.round).reduce((int a, int b) => a < b ? a : b);
    final Map<String, TMatch> byId = <String, TMatch>{
      for (final TMatch m in matches) m.id: m
    };

    final double crest = finals.isNotEmpty ? 150 : 0;
    final double totalW = width + 48, totalH = height + 80 + crest;
    final Offset? gf = finals.isNotEmpty ? pos[finals.first.id] : null;
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints box) {
      final Size view = box.biggest;
      if (_fittedFor != view && view.width.isFinite && view.height.isFinite) {
        _fittedFor = view;
        // Fit the whole bracket (never smaller than 0.55 so names stay readable; pan for the rest).
        final double k = (view.width / totalW).clamp(0.55, 1.4).toDouble();
        final double k2 = (view.height / totalH).clamp(0.55, 1.4).toDouble();
        final double sc = k < k2 ? k : k2;
        final double dx = totalW * sc < view.width ? (view.width - totalW * sc) / 2 : 0;
        final double dy = totalH * sc < view.height ? (view.height - totalH * sc) / 2 : 0;
        _tc.value = Matrix4.identity()
          ..translateByDouble(dx, dy, 0, 1)
          ..scaleByDouble(sc, sc, 1, 1);
      }
      return Stack(children: <Widget>[
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -.2),
                radius: 1.1,
                colors: <Color>[const Color(0xFF1A1440), NxThemeColors.of(context).background],
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            child: Opacity(
              opacity: .35,
              child: Image.asset(AnixAssets.sceneArenaPodium, fit: BoxFit.fitWidth, cacheWidth: 900),
            ),
          ),
        ),
        InteractiveViewer(
      transformationController: _tc,
      constrained: false,
      minScale: 0.3,
      maxScale: 2.5,
      boundaryMargin: const EdgeInsets.all(240),
      child: SizedBox(
        width: totalW,
        height: totalH,
        child: Stack(children: <Widget>[
          if (gf != null)
            Positioned(
              left: 24 + gf.dx + (cardW - 120) / 2,
              top: 28 + gf.dy - 140 < 0 ? 0 : 28 + gf.dy - 140,
              width: 120,
              height: 132,
              child: Image.asset(AnixAssets.bracket('crest_champion'), fit: BoxFit.contain, cacheWidth: 300),
            ),
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _LinesPainter(
                  matches: matches,
                  pos: pos,
                  byId: byId,
                  accent: tAccent(context),
                  border: NxThemeColors.of(context).border,
                ),
              ),
            ),
          ),
          // round headers
          for (final MapEntry<int, double> e in winners.colX.entries)
            Positioned(
              left: 24 + e.value,
              top: 4,
              width: cardW,
              child: Text(
                roundName(context, w.firstWhere((TMatch m) => m.round == e.key),
                    lastW, firstW),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: tAccent(context),
                    fontWeight: FontWeight.w800,
                    fontSize: 12),
              ),
            ),
          if (losers.colX.isNotEmpty)
            Positioned(
              left: 24,
              top: winners.height + 40,
              child: Text(context.tx('براکت بازنده‌ها', 'Losers bracket'),
                  style: TextStyle(
                      color: tAccentSecondary(context),
                      fontWeight: FontWeight.w800,
                      fontSize: 12)),
            ),
          for (final TMatch m in matches)
            if (pos[m.id] != null)
              Positioned(
                left: 24 + pos[m.id]!.dx,
                top: 28 + pos[m.id]!.dy,
                width: cardW,
                height: cardH,
                child: _MatchCard(
                  m: m,
                  names: names,
                  me: me,
                  title: m.bracket == 'GF' ||
                          m.bracket == 'GF2' ||
                          m.bracket == 'P3'
                      ? roundName(context, m, lastW, firstW)
                      : null,
                  onTap: onTap == null ? null : () => onTap!(m),
                ),
              ),
        ]),
      ),
    ),
      ]);
    });
  }
}

class _Layout {
  _Layout(this.pos, this.colX, this.width, this.height, this.lastPos);
  final Map<String, Offset> pos;
  final Map<int, double> colX;
  final double width;
  final double height;
  final Offset? lastPos;

  /// Round r column; matches of round r+1 sit centred between their two feeders.
  static _Layout build(List<TMatch> ms, double x0, double y0) {
    final Map<String, Offset> pos = <String, Offset>{};
    final Map<int, double> colX = <int, double>{};
    if (ms.isEmpty) return _Layout(pos, colX, 0, 0, null);
    final List<int> rounds = ms.map((TMatch m) => m.round).toSet().toList()
      ..sort();
    final Map<int, List<TMatch>> byRound = <int, List<TMatch>>{
      for (final int r in rounds)
        r: (ms.where((TMatch m) => m.round == r).toList()
          ..sort((TMatch a, TMatch b) => a.idx.compareTo(b.idx))),
    };
    double maxY = 0;
    Offset? last;
    for (int c = 0; c < rounds.length; c++) {
      final int r = rounds[c];
      final double x = x0 + c * (BracketView.cardW + BracketView.colGap);
      colX[r] = x;
      final List<TMatch> list = byRound[r]!;
      final List<TMatch>? prev = c > 0 ? byRound[rounds[c - 1]] : null;
      for (int i = 0; i < list.length; i++) {
        double y;
        if (prev != null && prev.length == list.length * 2) {
          final Offset a = pos[prev[2 * i].id]!;
          final Offset b = pos[prev[2 * i + 1].id]!;
          y = (a.dy + b.dy) / 2;
        } else if (prev != null && prev.length == list.length) {
          y = pos[prev[i].id]!.dy;
        } else {
          y = y0 + i * (BracketView.cardH + BracketView.rowGap);
        }
        pos[list[i].id] = Offset(x, y);
        if (y + BracketView.cardH > maxY) maxY = y + BracketView.cardH;
        last = Offset(x, y);
      }
    }
    final double width = colX.values.isEmpty
        ? 0
        : colX.values.reduce((double a, double b) => a > b ? a : b) +
            BracketView.cardW;
    return _Layout(pos, colX, width, maxY - y0, last);
  }
}

class _LinesPainter extends CustomPainter {
  _LinesPainter(
      {required this.matches,
      required this.pos,
      required this.byId,
      required this.accent,
      required this.border});
  final List<TMatch> matches;
  final Map<String, Offset> pos;
  final Map<String, TMatch> byId;
  final Color accent;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = border.withValues(alpha: 0.72)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    final Paint hot = Paint()
      ..color = accent.withValues(alpha: 0.85)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (final TMatch m in matches) {
      final String? to = m.winTo;
      if (to == null) continue;
      final Offset? a = pos[m.id];
      final Offset? b = pos[to];
      if (a == null || b == null) continue;
      final Offset start = Offset(
          24 + a.dx + BracketView.cardW, 28 + a.dy + BracketView.cardH / 2);
      final Offset end = Offset(24 + b.dx, 28 + b.dy + BracketView.cardH / 2);
      final double mid = (start.dx + end.dx) / 2;
      final Path path = Path()
        ..moveTo(start.dx, start.dy)
        ..lineTo(mid, start.dy)
        ..lineTo(mid, end.dy)
        ..lineTo(end.dx, end.dy);
      canvas.drawPath(path, m.winner != null && m.isFinal ? hot : p);
    }
  }

  @override
  bool shouldRepaint(covariant _LinesPainter old) =>
      old.matches != matches || old.accent != accent || old.border != border;
}

class _MatchCard extends StatelessWidget {
  const _MatchCard(
      {required this.m,
      required this.names,
      required this.me,
      this.title,
      this.onTap});
  final TMatch m;
  final Map<String, String> names;
  final String? me;
  final String? title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool mine = m.involves(me);
    final Color accent = tAccent(context);
    final Color accentSecondary = tAccentSecondary(context);
    final bool live = m.status == 'playing' || m.status == 'ready_check';
    final (int s1, int s2) = m.shownScore;
    Widget row(String? uid, bool set, int score, bool won) {
      final String name =
          uid == null ? (set ? 'BYE' : '—') : (names[uid] ?? '…');
      return Row(children: <Widget>[
        Expanded(
          child: Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: won ? FontWeight.w900 : FontWeight.w600,
                color: uid == null
                    ? NxColors.textDim
                    : (uid == me ? accent : NxColors.ink),
              )),
        ),
        if (m.isFinal || m.games > 0)
          Text('$score',
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12.5,
                  color: won ? tAccent(context) : NxColors.textDim)),
      ]);
    }

    final bool done = m.winner != null;
    final String badge = live ? 'ic_play' : (done ? 'ic_check' : (m.p1 == null || m.p2 == null ? 'flat_lock' : 'ic_clock'));
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(30, 6, 10, 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: <Color>[
              (mine ? const Color(0xFF0E2A5A) : const Color(0xFF15122E)).withValues(alpha: .96),
              const Color(0xFF0B0A1C).withValues(alpha: .96),
            ]),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: mine
                  ? const Color(0xFF3B8CFF)
                  : (live ? accentSecondary : (done ? const Color(0xFFE2B04A) : const Color(0xFF8A8FA6))),
              width: mine || live ? 2 : 1.4,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                  color: (mine ? const Color(0xFF3B8CFF) : (done ? const Color(0xFFE2B04A) : Colors.black))
                      .withValues(alpha: .28),
                  blurRadius: 10),
            ],
          ),
          child: Stack(clipBehavior: Clip.none, children: <Widget>[
            Positioned(
              left: -28,
              top: 0,
              bottom: 0,
              child: Center(
                  child: Image.asset(AnixAssets.bracket(badge), width: 22, height: 22, cacheWidth: 64)),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (title != null)
                  Text(title!,
                      maxLines: 1,
                      style: TextStyle(
                          fontSize: 9.5,
                          color: accent,
                          fontWeight: FontWeight.w800)),
                row(m.p1, m.p1Set, s1, m.winner != null && m.winner == m.p1),
                const Divider(height: 6, thickness: 0.6),
                row(m.p2, m.p2Set, s2, m.winner != null && m.winner == m.p2),
              ]),
          ]),
        ),
      ),
    );
  }
}
