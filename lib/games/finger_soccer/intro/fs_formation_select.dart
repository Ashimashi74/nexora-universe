// Formation select (reference 18-36 s): "انتخاب ترکیب", a 3-column grid of mini half-pitches (own goal on the left,
// halfway circle on the right) with the formation's discs, its name and a green "انتخاب" button (the picked one is
// grey "انتخاب شده"), and the orange loading bar that runs until the match starts.
import 'dart:async';

import 'package:flutter/material.dart';

import 'fs_intro_data.dart';
import 'fs_intro_ui.dart';

class FsFormationSelect extends StatefulWidget {
  const FsFormationSelect({
    super.key,
    required this.discAsset,
    required this.initial,
    required this.onDone,
    required this.onBar,
    this.players = 2,
    this.subtitle,
    this.seconds = 15,
    this.freezeAt,
    this.onChat,
    this.topLane = 0,
  });

  /// Disc art drawn on the mini pitches (the side's team).
  final String discAsset;
  final int initial;
  final ValueChanged<int> onDone;
  final VoidCallback onBar;
  final VoidCallback? onChat;
  final int players;

  /// Local two-player matches pick twice: "تیم یک" / "تیم دو".
  final String? subtitle;
  final int seconds;

  /// Tests: hold the loading bar at this value instead of running.
  final double? freezeAt;
  final double topLane;

  @override
  State<FsFormationSelect> createState() => _FsFormationSelectState();
}

class _FsFormationSelectState extends State<FsFormationSelect> {
  late final List<FsFormation> _forms = fsFormations();
  late int _sel = widget.initial.clamp(0, _forms.isEmpty ? 0 : _forms.length - 1);
  bool _picked = false;
  double _p = 0;
  Timer? _t;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    if (widget.freezeAt != null) {
      _p = widget.freezeAt!;
      return;
    }
    const int tick = 50;
    _t = Timer.periodic(const Duration(milliseconds: tick), (_) {
      if (!mounted) return;
      final double step = _picked ? tick / 900 : tick / (widget.seconds * 1000);
      setState(() => _p = (_p + step).clamp(0.0, 1.0));
      if (_p >= 1) _finish();
    });
  }

  void _finish() {
    if (_done) return;
    _done = true;
    _t?.cancel();
    widget.onDone(_sel);
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  static const List<double> _cols = <double>[27, 129, 231];
  static const double _row0 = 153, _rowStep = 131, _pw = 80, _ph = 52;

  void _pick(int i) {
    if (_done) return;
    setState(() {
      _sel = i;
      _picked = true;
    });
  }

  Widget _cell(FsFormation f, int i) {
    final double left = _cols[i % 3], top = _row0 + (i ~/ 3) * _rowStep;
    final bool on = i == _sel;
    return Positioned(
      left: left,
      top: top,
      width: _pw,
      // The whole card (mini pitch, name, button) picks the formation, not only the small button.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _pick(i),
        child: Column(children: <Widget>[
        SizedBox(
          width: _pw,
          height: _ph,
          child: Stack(children: <Widget>[
            const Positioned.fill(child: CustomPaint(painter: FsMiniPitchPainter())),
            for (final List<double> s in f.slots)
              Positioned(
                left: (s[1] / .5).clamp(0.0, 1.0) * (_pw - 14) + 2,
                top: s[0].clamp(0.0, 1.0) * (_ph - 12) + 1,
                child: _MiniDisc(asset: widget.discAsset),
              ),
          ]),
        ),
        const SizedBox(height: 3),
        Container(
          width: _pw,
          height: 21,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            gradient: const LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: <Color>[Color(0xFF3A3A3A), Color(0xFF111111)]),
          ),
          child: Center(
            child: Text(f.name,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: fsText(10.5, weight: FontWeight.w900, height: 1)),
          ),
        ),
        const SizedBox(height: 8),
        FsPress(
          onTap: _done ? null : () => _pick(i),
          child: on && _picked ? fsGreyButton('انتخاب شده', _pw, 19, size: 10.5) : fsLimeButton('انتخاب', _pw, 19, size: 10.5),
        ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FsCanvas(dim: .38, bottomGradient: .85, topLane: widget.topLane, children: <Widget>[
        Positioned(
          left: 0,
          right: 0,
          top: 28,
          child: Column(children: <Widget>[
            Text('انتخاب ترکیب',
                style: fsText(21, weight: FontWeight.w900, shadows: const <Shadow>[Shadow(color: Color(0xAA000000), blurRadius: 4, offset: Offset(0, 2))])),
            if (widget.subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(widget.subtitle!, style: fsText(13, color: kFsYellow, weight: FontWeight.w900)),
              ),
          ]),
        ),
        for (int i = 0; i < _forms.length; i++) _cell(_forms[i], i),
        Positioned(left: 80, top: 646, child: FsLoadBar(value: _p)),
        Positioned(left: 0, top: 730, child: FsBarHandle(players: widget.players, onTap: widget.onBar)),
        Positioned(left: 270, top: 683, child: FsChatButton(onTap: widget.onChat)),
      ]);
}

class _MiniDisc extends StatelessWidget {
  const _MiniDisc({required this.asset});
  final String asset;
  @override
  Widget build(BuildContext context) => Container(
        width: 12,
        height: 12,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFFE23B2E),
          boxShadow: <BoxShadow>[BoxShadow(color: Color(0x99000000), blurRadius: 1.5, offset: Offset(0, 1.2))],
        ),
        child: ClipOval(child: Image.asset(asset, fit: BoxFit.cover, cacheWidth: 48, errorBuilder: (_, __, ___) => const SizedBox())),
      );
}

/// A half pitch lying on its side: own goal + box on the left, the halfway line and centre circle on the right.
class FsMiniPitchPainter extends CustomPainter {
  const FsMiniPitchPainter();
  @override
  void paint(Canvas c, Size s) {
    final double w = s.width, h = s.height;
    c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF7DC443));
    const int n = 8;
    for (int i = 0; i < n; i += 2) {
      c.drawRect(Rect.fromLTWH(w * i / n, 0, w / n, h), Paint()..color = const Color(0xFF6BB437));
    }
    final Paint line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = const Color(0xE6FFFFFF);
    c.drawRect(Rect.fromLTWH(1.5, 1.5, w - 3, h - 3), line);
    c.drawRect(Rect.fromLTWH(1.5, h * .22, w * .2, h * .56), line);
    c.drawRect(Rect.fromLTWH(1.5, h * .36, w * .08, h * .28), line);
    c.drawArc(Rect.fromCircle(center: Offset(w - 1.5, h / 2), radius: h * .26), 1.5708, 3.1416, false, line);
    c.drawArc(Rect.fromCircle(center: Offset(w * .2, h / 2), radius: h * .14), -1.2, 2.4, false, line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
