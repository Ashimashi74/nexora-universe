import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../arcade_kit/arcade_skin.dart';
import '../core/solo_rules_c.dart';
import '../solo_kit.dart';

/// =====================================================================================
/// NX 2048 — a bespoke glass board: bevelled tiles with heat-mapped colours, embossed
/// numbers, merge pop, spawn scale-in, and a target meter that fills toward 2048.
/// =====================================================================================
class World2048Board extends SoloBoard {
  const World2048Board({super.key, required super.run});
  @override
  World2048BoardState createState() => World2048BoardState();
}

class World2048BoardState extends SoloBoardState<World2048Board> {
  late World2048Game world;
  final Map<int, double> _pop = <int, double>{};
  final Map<int, double> _spawn = <int, double>{};
  int _moves = 0;
  int _bestTile = 0;
  bool _wasOver = false;

  /// Tile ramp: keyed by log2(value) - 1.
  static const List<Color> _tileColours = <Color>[
    Color(0xFF2FD2F2), // 2    cyan
    Color(0xFF48C8E8), // 4
    Color(0xFF5FD6B8), // 8    teal
    Color(0xFF7CE58F), // 16
    Color(0xFFB6E864), // 32
    Color(0xFFEFE05C), // 64
    Color(0xFFFFC94A), // 128  gold
    Color(0xFFFF9F45), // 256
    Color(0xFFFF7A5C), // 512
    Color(0xFFFF5C86), // 1024
    Color(0xFFFF4FD1), // 2048
    Color(0xFFFB8DFF), // 4096+
  ];

  @override
  void reset() {
    world = World2048Game(seed: widget.run.seed);
    _pop.clear();
    _spawn.clear();
    _moves = 0;
    _bestTile = 0;
    _wasOver = false;
    widget.run.set(0);
  }

  @override
  void step(double dt) {
    for (final int k in _pop.keys.toList()) {
      _pop[k] = (_pop[k]! + dt * 5).clamp(0.0, 1.0);
    }
    for (final int k in _spawn.keys.toList()) {
      _spawn[k] = (_spawn[k]! + dt * 4).clamp(0.0, 1.0);
    }
  }

  void _move(int dir) {
    if (world.over || !simulating) return;
    final List<List<int>> before = <List<int>>[for (final List<int> r in world.board.cells) List<int>.of(r)];
    final int gained = world.move(dir);
    final Size size = viewport;
    final _Board board = _Board.of(playRect(size));
    if (gained == 0 && _same(before, world.board.cells)) return;
    _moves++;
    // Animation bookkeeping: merged/increased cells pop, new cells spawn in.
    for (int r = 0; r < 4; r++) {
      for (int c = 0; c < 4; c++) {
        final int after = world.board.cell(r, c);
        if (after != before[r][c] && after != 0) _pop[r * 4 + c] = 0;
        if (before[r][c] == 0 && after != 0) _spawn[r * 4 + c] = 0;
      }
    }
    if (world.board.maxTile > _bestTile) {
      _bestTile = world.board.maxTile;
      fx.flashScreen(_colour(_bestTile), 0.10);
    }
    if (gained > 0) {
      final Offset at = Offset(board.rect.center.dx, board.rect.center.dy);
      burst(playRect(size), at, _colour(_bestTile), count: 14, speed: 240);
      fx.text('+$gained', at, SoloArt.ink, size: 20);
    }
    widget.run.set(world.score);
    if (!_wasOver && world.over) {
      _wasOver = true;
      fx.shake(10);
      widget.run.gameOver();
    }
    setState(() {});
  }

  Color _colour(int v) {
    final int idx = v <= 0 ? 0 : (math.log(v) / math.ln2).round() - 1;
    return _tileColours[idx.clamp(0, _tileColours.length - 1).toInt()];
  }

  bool _same(List<List<int>> a, List<List<int>> b) {
    for (int r = 0; r < 4; r++) {
      for (int c = 0; c < 4; c++) {
        if (a[r][c] != b[r][c]) return false;
      }
    }
    return true;
  }

  @override
  void onPointer(Offset at, SoloGesture kind) {
    if (kind != SoloGesture.drag) return;
    // Swipe support: the delta since the last drag frame selects the dominant axis.
    if (_dragFrom == null) {
      _dragFrom = at;
      return;
    }
    final Offset d = at - _dragFrom!;
    if (d.distance < 22) return;
    _dragFrom = at;
    _move(d.dx.abs() > d.dy.abs() ? (d.dx > 0 ? 2 : 0) : (d.dy > 0 ? 3 : 1));
  }

  Offset? _dragFrom;

  @override
  void paint(Canvas canvas, Size size) {
    final ArcadeSkin skin = widget.run.skin;
    final Color accent = skin.accent;
    final Color accent2 = skin.accent2;
    final Rect play = playRect(size);
    final _Board board = _Board.of(play);
    final Rect area = board.rect;
    final double cell = board.cell;
    final double gap = board.gap;

    // ---------------------------------------------------------------- backdrop
    SoloArt.backdrop(canvas, size, skin: skin, time: clock, halo: 0.22, haloAt: area.center);
    // orbit rings behind the board
    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(
        area.center + Offset(0, 0),
        area.width * (0.62 + i * 0.14),
        SoloArt.stroke(SoloArt.a(accent, 0.06 + i * 0.012), 1),
      );
    }

    // ---------------------------------------------------------------- board frame
    SoloArt.panel(canvas, area.inflate(gap * 0.9), accent, radius: 24, glow: 0.6, border: 1.4);
    canvas.drawRRect(
      RRect.fromRectAndRadius(area.inflate(gap * 0.25), Radius.circular(18)),
      Paint()..color = const Color(0xB3020610),
    );

    // ---------------------------------------------------------------- tiles
    for (int r = 0; r < 4; r++) {
      for (int c = 0; c < 4; c++) {
        final int v = world.board.cell(r, c);
        final Rect slot = Rect.fromLTWH(area.left + gap + c * (cell + gap), area.top + gap + r * (cell + gap), cell, cell);
        // empty socket
        canvas.drawRRect(
          RRect.fromRectAndRadius(slot, Radius.circular(cell * 0.16)),
          Paint()..color = SoloArt.a(const Color(0xFF0B1424), 0.9),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(slot, Radius.circular(cell * 0.16)),
          SoloArt.stroke(SoloArt.a(const Color(0xFFFFFFFF), 0.05), 1),
        );
        if (v == 0) continue;
        final int key = r * 4 + c;
        final double pop = _pop[key] ?? 1;
        final double spawn = _spawn[key] ?? 1;
        double scale = 1;
        if (pop < 1) scale = 1 + 0.16 * math.sin(pop * math.pi);
        if (spawn < 1) scale *= 0.6 + 0.4 * SoloArt.easeOutBack(spawn);
        final Rect tile = Rect.fromCenter(center: slot.center, width: slot.width * scale, height: slot.height * scale);
        final Color tint = _colour(v);
        paintGlow(canvas, tile.center, cell * 1.2, tint, 0.14);
        SoloArt.cube(canvas, tile, tint, radius: cell * 0.16, depth: cell * 0.06, glow: 0.3,
            edge: SoloArt.a(const Color(0xFFFFFFFF), 0.45));
        final int digits = '$v'.length;
        SoloArt.label(
          canvas,
          '$v',
          tile.center + Offset(0, 1),
          size: cell * (digits >= 4 ? 0.30 : digits == 3 ? 0.36 : 0.42),
          color: v >= 128 ? const Color(0xFF180B1E) : const Color(0xFF03121E),
          weight: FontWeight.w900,
        );
      }
    }

    // ---------------------------------------------------------------- readouts
    SoloArt.chip(canvas, Offset(16, play.top + 16), 'SCORE ${world.score}', SoloArt.ink);
    SoloArt.chip(canvas, Offset(size.width - 16, play.top + 16), '$_moves MOVES', accent2, alignRight: true);
    // target meter: 2 → 2048 progress in log space
    final int maxTile = world.board.maxTile;
    final double progress = maxTile <= 0 ? 0 : ((math.log(maxTile) / math.ln2) - 1) / 10;
    final Rect meter = Rect.fromLTWH(area.left, area.top - 22, area.width, 6);
    SoloArt.meter(canvas, meter, progress, accent2);
    SoloArt.label(canvas, 'TARGET 2048', meter.topLeft - const Offset(0, 10), size: 10, center: false,
        color: SoloArt.a(SoloArt.mute, 0.95), weight: FontWeight.w700);
    if (world.won) {
      paintCallout(canvas, Offset(size.width / 2, area.top - 56), '2048 REACHED', accent, scale: 1);
    }
    if (world.over) {
      SoloArt.label(canvas, 'NO MOVES LEFT', Offset(size.width / 2, area.bottom + 26), size: 16,
          color: SoloArt.danger, glow: SoloArt.danger);
    }

    SoloArt.frame(canvas, size, accent);
    paintFx(canvas, size);
  }

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: <Widget>[
          super.build(context),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SoloStage(
              accent: widget.run.skin.accent,
              onLeft: () => _move(0),
              onRight: () => _move(2),
              leftIcon: Icons.west_rounded,
              rightIcon: Icons.east_rounded,
              extra: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SoloPad(icon: Icons.north_rounded, onTap: () => _move(1), size: 52, accent: widget.run.skin.accent),
                  const SizedBox(height: 6),
                  SoloPad(icon: Icons.south_rounded, onTap: () => _move(3), size: 52, accent: widget.run.skin.accent),
                ],
              ),
            ),
          ),
        ],
      );
}

/// Board geometry shared by the painter and the swipe handler.
class _Board {
  _Board({required this.rect, required this.cell, required this.gap});
  final Rect rect;
  final double cell;
  final double gap;

  static _Board of(Rect play) {
    final double side = math.min(play.width - 32, play.height * 0.74);
    final double gap = side * 0.026;
    final double cell = (side - gap * 5) / 4;
    return _Board(
      rect: Rect.fromCenter(center: Offset(play.center.dx, play.top + play.height * 0.52), width: side, height: side),
      cell: cell,
      gap: gap,
    );
  }
}
