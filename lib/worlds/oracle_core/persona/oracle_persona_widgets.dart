import 'dart:async';

import 'package:flutter/material.dart';

import 'package:nexora/core/storage/local_store.dart';

import 'oracle_persona.dart';
import 'oracle_persona_store.dart';

/// Funny-but-accurate tutorial card shown at the start of a game (only for mechanics the player has not seen enough;
/// replayable from the game's ORACLE sheet). Never blocks input: it sits at the top and fades out by itself.
class OracleTutorialBanner extends StatefulWidget {
  const OracleTutorialBanner({super.key, required this.gameId, this.delay = const Duration(milliseconds: 1400)});
  final String gameId;
  final Duration delay;

  @override
  State<OracleTutorialBanner> createState() => _OracleTutorialBannerState();
}

class _OracleTutorialBannerState extends State<OracleTutorialBanner> {
  OracleTutorial? _t;
  Timer? _in, _out;

  @override
  void initState() {
    super.initState();
    // First time only (per game): later matches never show it again; the in-game help button replays it.
    if (gameTutorialSeen(widget.gameId)) return;
    _in = Timer(widget.delay, () {
      if (!mounted) return;
      final OracleTutorial? t = OraclePersona.instance.nextTutorial(widget.gameId, OraclePersonaStore.tutorialViews());
      unawaited(markGameTutorialSeen(widget.gameId));
      if (t == null) return;
      OraclePersonaStore.markTutorial(t);
      setState(() => _t = t);
      _out = Timer(const Duration(seconds: 9), _hide);
    });
  }

  void _hide() {
    if (mounted) setState(() => _t = null);
  }

  @override
  void dispose() {
    _in?.cancel();
    _out?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final OracleTutorial? t = _t;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      child: t == null
          ? const SizedBox.shrink()
          : GestureDetector(key: ValueKey<String>(t.key), onTap: _hide, child: OracleTutorialCard(tutorial: t)),
    );
  }
}

String _tutKey(String gameId) => 'tutorial.seen.$gameId';

/// True once the game's tutorial has been shown (persisted per game).
bool gameTutorialSeen(String gameId) {
  try {
    return LocalStore.instance.getBool(_tutKey(gameId)) ?? false;
  } catch (_) {
    return false;
  }
}

Future<void> markGameTutorialSeen(String gameId) async {
  try {
    await LocalStore.instance.setBool(_tutKey(gameId), true);
  } catch (_) {}
}

/// Help button: replays every tutorial card of [gameId] in a sheet (the only way to see it after the first match).
Future<void> showGameTutorial(BuildContext context, String gameId) {
  final List<OracleTutorial> all = OraclePersona.instance.tutorials(gameId);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xF20B1030),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (BuildContext c) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * .7),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(0, 14, 0, 18),
            children: <Widget>[
              const Center(
                  child: Text('راهنمای بازی',
                      style: TextStyle(color: Color(0xFFFFD86B), fontSize: 16, fontWeight: FontWeight.w900))),
              const SizedBox(height: 10),
              if (all.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('برای این بازی هنوز راهنمایی ثبت نشده است.',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
                ),
              for (final OracleTutorial t in all)
                Padding(padding: const EdgeInsets.only(bottom: 10), child: OracleTutorialCard(tutorial: t, margin: 14)),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Round "?" button that replays the game's tutorial.
class GameHelpButton extends StatelessWidget {
  const GameHelpButton({super.key, required this.gameId});
  final String gameId;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black.withValues(alpha: 0.35),
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: 'راهنما',
          icon: const Icon(Icons.help_outline_rounded, color: Color(0xFFFFD86B)),
          onPressed: () => showGameTutorial(context, gameId),
        ),
      );
}

class OracleTutorialCard extends StatelessWidget {
  const OracleTutorialCard({super.key, required this.tutorial, this.margin = 56});
  final OracleTutorial tutorial;
  final double margin;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: EdgeInsets.symmetric(horizontal: margin),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(colors: <Color>[Color(0xF2182A5E), Color(0xF22A1556)]),
            border: Border.all(color: const Color(0xFF39E6FF)),
            boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x6639E6FF), blurRadius: 18)],
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Image.asset('assets/characters/oracle/moods/laugh.webp',
                width: 40, height: 40, errorBuilder: (_, __, ___) => const Icon(Icons.smart_toy_rounded, color: Color(0xFF8FF3FF))),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: <Widget>[
                Text('ORACLE · ${tutorial.title}',
                    style: const TextStyle(color: Color(0xFF8FF3FF), fontSize: 11, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(tutorial.line,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800, height: 1.35)),
                const SizedBox(height: 4),
                Text(tutorial.how, style: const TextStyle(color: Color(0xFFC9D3FF), fontSize: 12, height: 1.35)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// ORACLE's reaction line on the result screen (computed from the real result).
class OracleResultLine extends StatelessWidget {
  const OracleResultLine({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Image.asset('assets/characters/oracle/moods/laugh.webp',
            width: 34, height: 34, errorBuilder: (_, __, ___) => const Icon(Icons.smart_toy_rounded, color: Color(0xFF8FF3FF))),
        const SizedBox(width: 8),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: const Color(0xCC1B2350),
              border: Border.all(color: const Color(0xFF39E6FF).withValues(alpha: .7)),
            ),
            child: Text(text,
                textDirection: TextDirection.rtl,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700, height: 1.4)),
          ),
        ),
      ]),
    );
  }
}
