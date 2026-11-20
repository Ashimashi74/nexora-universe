// Splash: stadium at dusk, orange title, studio + version, black loading bar with a 0..100 counter.
import 'dart:async';

import 'package:flutter/material.dart';

import 'fs_intro_data.dart';
import 'fs_intro_ui.dart';

const String kFsTitle = 'گل کوچیک';
const String kFsStudio = 'نکسورا گیمز';
const String kFsVersion = '1.0.0';

class FsSplash extends StatefulWidget {
  const FsSplash({super.key, required this.onDone, this.duration = const Duration(milliseconds: 2600), this.freezeAt});
  final VoidCallback onDone;
  final Duration duration;

  /// Tests: hold the counter at this value instead of running.
  final int? freezeAt;
  @override
  State<FsSplash> createState() => _FsSplashState();
}

class _FsSplashState extends State<FsSplash> {
  Timer? _t;
  int _n = 0;

  @override
  void initState() {
    super.initState();
    if (widget.freezeAt != null) {
      _n = widget.freezeAt!;
      return;
    }
    final int step = (widget.duration.inMilliseconds / 100).round().clamp(5, 200);
    _t = Timer.periodic(Duration(milliseconds: step), (Timer t) {
      if (!mounted) return;
      if (_n >= 100) {
        t.cancel();
        widget.onDone();
        return;
      }
      setState(() => _n++);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  TextStyle _orange(double size) => TextStyle(
        fontFamily: 'Lalezar',
        fontSize: size,
        height: 1.1,
        decoration: TextDecoration.none,
        foreground: Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0xFFFF9A2E), Color(0xFFFF5A12)],
          ).createShader(Rect.fromLTWH(0, 0, 10, size * 1.1)),
      );

  Widget _line(String s, double top, double size) => Positioned(
        left: 0,
        right: 0,
        top: top,
        child: Center(
          child: FsOutlined(s,
              style: _orange(size), stroke: 2.2, strokeColor: const Color(0xFFDCD6E8)),
        ),
      );

  @override
  Widget build(BuildContext context) => FsCanvas(children: <Widget>[
        _line(kFsTitle, 52, 34),
        _line(kFsStudio, 124, 24),
        _line(fsFa(kFsVersion), 166, 24),
        Positioned(left: 80, top: 646, child: FsLoadBar(value: _n / 100, counter: fsFa(_n), fill: false)),
      ]);
}
