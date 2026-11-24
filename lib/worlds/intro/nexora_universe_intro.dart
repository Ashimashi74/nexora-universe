import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 3-step orbital introduction inspired by "NEXORA | A Universe Beyond Play".
class NexoraUniverseIntro extends StatefulWidget {
  const NexoraUniverseIntro({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<NexoraUniverseIntro> createState() => _NexoraUniverseIntroState();
}

class _NexoraUniverseIntroState extends State<NexoraUniverseIntro> with SingleTickerProviderStateMixin {
  int _step = 0;
  double _orbitYaw = 0.0;
  double _orbitPitch = 0.25;
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  )..repeat();

  static const List<({String tag, String title, String subtitle})> _steps = <({String tag, String title, String subtitle})>[
    (
      tag: '01 / 03 THE DEPARTURE',
      title: 'NEXORA.',
      subtitle: 'A universe beyond play. Explore new worlds, challenge the extraordinary, and find your people.',
    ),
    (
      tag: '02 / 03 THE ARENA',
      title: 'COMPETE.',
      subtitle: 'Real-time multiplayer arenas, tournaments, and voice rooms built for what comes next.',
    ),
    (
      tag: '03 / 03 YOUR ORBIT',
      title: 'CONNECT.',
      subtitle: 'Your identity, your crew, your rank — synchronized across every world in the universe.',
    ),
  ];

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  void _next() {
    if (_step < _steps.length - 1) {
      setState(() => _step++);
    } else {
      widget.onFinished();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ({String tag, String title, String subtitle}) current = _steps[_step];
    return Scaffold(
      backgroundColor: const Color(0xFF07090F),
      body: GestureDetector(
        onPanUpdate: (DragUpdateDetails d) {
          setState(() {
            _orbitYaw += d.delta.dx * 0.01;
            _orbitPitch = (_orbitPitch + d.delta.dy * 0.01).clamp(-0.9, 0.9);
          });
        },
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _spin,
                builder: (_, __) => CustomPaint(
                  painter: _OrbitalUniversePainter(
                    phase: _spin.value * math.pi * 2 + _orbitYaw,
                    pitch: _orbitPitch,
                    step: _step,
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        const Text(
                          'YOUR JOURNEY BEGINS HERE',
                          style: TextStyle(
                            color: Color(0xFFD9B872),
                            fontSize: 11,
                            letterSpacing: 2.2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextButton(
                          onPressed: widget.onFinished,
                          child: const Text(
                            'Skip introduction',
                            style: TextStyle(color: Colors.white54, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      current.tag,
                      style: const TextStyle(
                        color: Color(0xFFD9B872),
                        fontSize: 12,
                        letterSpacing: 2.0,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      current.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 44,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      current.subtitle,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _next,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD9B872),
                          foregroundColor: const Color(0xFF07090F),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          _step < _steps.length - 1 ? 'Continue journey' : 'Enter NEXORA',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.6),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Center(
                      child: Text(
                        'Drag to orbit',
                        style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1.2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrbitalUniversePainter extends CustomPainter {
  _OrbitalUniversePainter({required this.phase, required this.pitch, required this.step});

  final double phase;
  final double pitch;
  final int step;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width * 0.5, size.height * 0.36);
    final double baseR = math.min(size.width, size.height) * 0.28;

    // Core planet glow
    canvas.drawCircle(
      center,
      baseR * 1.45,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            const Color(0xFFD9B872).withValues(alpha: 0.22),
            const Color(0xFF1A2540).withValues(alpha: 0.08),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: center, radius: baseR * 1.45)),
    );

    // Core sphere
    canvas.drawCircle(
      center,
      baseR * 0.42,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.35, -0.35),
          colors: <Color>[Color(0xFFFFE09A), Color(0xFFD9B872), Color(0xFF2B2214)],
        ).createShader(Rect.fromCircle(center: center, radius: baseR * 0.42)),
    );

    // 3 orbital rings
    for (int i = 0; i < 3; i++) {
      final double r = baseR * (0.72 + i * 0.28);
      final double tilt = pitch + (i - 1) * 0.28;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.scale(1.0, math.cos(tilt).abs().clamp(0.25, 1.0));
      canvas.drawCircle(
        Offset.zero,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = i == step ? 1.8 : 0.9
          ..color = i == step ? const Color(0xFFD9B872).withValues(alpha: 0.75) : Colors.white12,
      );
      final double a = phase * (i.isEven ? 1 : -1) + i * 2.1;
      final Offset sat = Offset(math.cos(a) * r, math.sin(a) * r);
      canvas.drawCircle(sat, i == step ? 5.5 : 3.5, Paint()..color = const Color(0xFFFFC95C));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitalUniversePainter old) =>
      old.phase != phase || old.pitch != pitch || old.step != step;
}
