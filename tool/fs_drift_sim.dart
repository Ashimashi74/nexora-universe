// Quick physics check (dart run tool/fs_drift_sim.dart): how far a lone disc slides after a full-power shot, how long
// it takes to stop, and the launch speed (unchanged by the anti-drift tuning).
import 'dart:math' as math;

import 'package:nexora/games/finger_soccer/core/bm_engine.dart';

class _H implements BmHooks {
  @override
  void sfx(String k, [double v = 1]) {}
  @override
  void tone(String k) {}
  @override
  void vib(List<int> pattern) {}
  @override
  void toast(String text, bool big) {}
  @override
  void goalFx() {}
  @override
  void emit(String event, Map<String, dynamic> data) {}
}

void main() {
  final BmEngine e = BmEngine(_H(), rng: math.Random(1));
  e.startMatch(BmConfig(mode: 'local', teams: const <String>['club0', 'club1'], form: const <int>[0, 0],
      names: const <String>['A', 'B'], field: 6, ball: 0, matchTime: 300, ai: false, aiLvl: 1));
  for (final double pw in <double>[.3, .6, 1]) {
    final BmBody b = e.bodies.firstWhere((BmBody x) => x != e.ball);
    for (final BmBody o in e.bodies) {
      if (o != b) { o.x = -9999; o.y = -9999; }
    }
    b.x = e.CX; b.y = e.Fb - 80; b.vx = 0; b.vy = 0;
    final double l = LMAX * pw;
    final double v0 = (260 + 1085 * math.pow(pw, .8).toDouble()) * K * 1.32 * BmEngine.strikeOf(b.power);
    b.vy = -v0;
    double t = 0; final double y0 = b.y;
    while ((b.vx != 0 || b.vy != 0) && t < 20) { e.sim(STEP); t += STEP; }
    print('power ${(pw * 100).round()}%: launch ${v0.round()} u/s, slid ${(y0 - b.y).round()} u (${((y0 - b.y) / (2 * PR)).toStringAsFixed(1)} discs) in ${t.toStringAsFixed(2)} s (l=$l)');
  }
}
