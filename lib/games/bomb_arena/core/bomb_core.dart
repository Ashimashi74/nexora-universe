import 'dart:collection';
import 'dart:math' as math;

/// Pure-Dart Bomb Arena (Bomberman style) for 2-4 players.
///
/// * [BombArena] is ONE round: bombs, chain reactions, destructible crates, power-ups (range, extra bomb, speed,
///   trap), stun traps, sudden death (blocks fall in a spiral) and a hard round timer. Last player standing wins
///   the round; players that die in the same simulation step as the last opponent make the round a draw.
/// * [BombMatch] is the series: first to [BombMatch.winsNeeded] round wins, a draw when the leaders are still tied
///   after [BombMatch.maxRounds].
///
/// Units are tiles. A player's position is the centre of its 1x1 collision box (tile centre = i + 0.5); the box
/// is always aligned with the grid on at least one axis, which is what makes Bomberman-style corner sliding exact.
/// A player is hit by fire when its centre tile burns. The simulation runs on a fixed 1/60 s step
/// ([BombArena.fixedDt]) fed by an accumulator, so the outcome does not depend on the frame rate.
/// Grid chars: '#' wall, 'c' crate, '.' floor.

enum Pu { range, bomb, speed, trap }

class BPlayer {
  BPlayer(this.seat, this.x, this.y);
  final int seat;
  double x, y; // tile units, centre of tile = i + 0.5
  /// Raw stick input (-1..1 per axis). The dominant axis drives, the other one is used to turn corners.
  double dx = 0, dy = 0;
  int range = BombArena.startRange;
  int maxBombs = 1;
  double speed = BombArena.baseSpeed;
  int traps = 0;
  bool alive = true;
  double stun = 0;
  int kills = 0;
  double outAt = 0;

  /// Simulation step of the knock-out (equal for simultaneous deaths), -1 while alive.
  int outStep = -1;

  /// Seat whose fire knocked this player out, [BombArena.crushed] for sudden death, -1 = alive / forfeit.
  int killedBy = -1;

  /// 0 up, 1 right, 2 down, 3 left (render hint).
  int facing = 2;
  bool moving = false;

  /// Max distance per step (bots use it to stop exactly on a tile centre).
  double limit = double.infinity;

  int get tx => x.floor();
  int get ty => y.floor();
  int get speedLevel => ((speed - BombArena.baseSpeed) / BombArena.speedStep).round() + 1;
}

class Bomb {
  Bomb(this.owner, this.tx, this.ty, this.range, {this.fuse = BombArena.fuseTime});
  final int owner;
  final int tx, ty, range;
  double fuse;

  /// Seats whose box overlapped the tile when the bomb was placed: they may walk off it, never back on.
  final Set<int> passable = <int>{};
}

class Flame {
  Flame(this.tx, this.ty, this.dir, {this.life = BombArena.flameLife, this.owner = -1, this.tip = false});
  final int tx, ty;
  int dir; // 0 centre / crossing, 1 horizontal, 2 vertical
  double life;
  int owner;
  bool tip; // end of a ray (render hint)
}

class Trap {
  Trap(this.owner, this.tx, this.ty);
  final int owner;
  final int tx, ty;
}

class BEvent {
  const BEvent(this.kind, this.x, this.y, [this.seat = -1]);

  /// place, boom, crate, pickup, out, trap, stun, hurry, drop, round, match
  final String kind;
  final double x, y;
  final int seat;
}

class BombArena {
  BombArena({required this.seed, required this.count, this.botSkill = const <double>[]}) {
    final math.Random r = math.Random(seed);
    grid = List<List<String>>.generate(h, (int y) => List<String>.generate(w, (int x) {
          if (isFixedWall(x, y)) return '#';
          return r.nextDouble() < 0.62 ? 'c' : '.';
        }));
    for (int i = 0; i < count; i++) {
      final int sx = spawns[i][0], sy = spawns[i][1];
      for (final List<int> d in const <List<int>>[
        <int>[0, 0], <int>[1, 0], <int>[-1, 0], <int>[0, 1], <int>[0, -1], <int>[2, 0], <int>[-2, 0], <int>[0, 2], <int>[0, -2]
      ]) {
        final int x = sx + d[0], y = sy + d[1];
        if (x > 0 && y > 0 && x < w - 1 && y < h - 1 && grid[y][x] == 'c') grid[y][x] = '.';
      }
      players.add(BPlayer(i, sx + 0.5, sy + 0.5));
    }
    _r = math.Random(seed ^ 0x1234567);
  }

  static const int w = 13, h = 11;
  static const List<List<int>> spawns = <List<int>>[<int>[1, 1], <int>[w - 2, h - 2], <int>[w - 2, 1], <int>[1, h - 2]];

  // ---- tuning (seconds / tiles)
  static const double fixedDt = 1 / 60;
  static const int maxStepsPerCall = 15; // 0.25 s: a long hitch is dropped, never tunnelled
  static const double fuseTime = 2.4;
  static const double flameLife = 0.55;
  static const double stunTime = 1.6;
  static const int startRange = 2, maxRange = 8, maxBombCap = 8, maxTraps = 3;
  static const double baseSpeed = 3.4, speedStep = 0.45, maxSpeed = 5.65;
  static const double timeLimit = 120; // round length; sudden death fills the arena before it runs out
  static const double suddenDeathAt = 88;
  static const double dropInterval = 0.38;
  static const double startCountdown = 3;
  static const int crushed = -2;
  static const double _eps = 1e-6;

  final int seed;
  final int count;
  final List<double> botSkill;
  late final List<List<String>> grid;
  late final math.Random _r;
  final List<BPlayer> players = <BPlayer>[];
  final List<Bomb> bombs = <Bomb>[];
  final List<Flame> flames = <Flame>[];
  final Map<int, Pu> powerups = <int, Pu>{};
  final List<Trap> traps = <Trap>[];
  final List<BEvent> events = <BEvent>[];
  final List<int> outOrder = <int>[];
  double time = 0;
  double countdown = startCountdown;
  int stepCount = 0;
  double _acc = 0;
  int _dropIndex = 0;
  bool _hurry = false;

  /// Round result once [over]: winning seat, or -1 for a draw.
  int winner = -1;

  static bool isFixedWall(int x, int y) => x == 0 || y == 0 || x == w - 1 || y == h - 1 || (x.isEven && y.isEven);

  bool isBot(int s) => s < botSkill.length && botSkill[s] > 0;
  int key(int x, int y) => y * w + x;
  int aliveCount() => players.where((BPlayer p) => p.alive).length;
  bool get over => _overNow();
  bool get draw => over && winner < 0;
  bool get suddenDeath => time >= suddenDeathAt;
  double get timeLeft => math.max(0, timeLimit - time);
  int get dropsDone => _dropIndex;

  bool _overNow() => (count > 1 ? aliveCount() <= 1 : aliveCount() == 0) || time >= timeLimit - _eps;

  bool inside(int x, int y) => x >= 0 && y >= 0 && x < w && y < h;

  bool solid(int x, int y, {int? forSeat}) {
    if (!inside(x, y)) return true;
    if (grid[y][x] != '.') return true;
    for (final Bomb b in bombs) {
      if (b.tx == x && b.ty == y && (forSeat == null || !b.passable.contains(forSeat))) return true;
    }
    return false;
  }

  Bomb? bombAt(int x, int y) {
    for (final Bomb b in bombs) {
      if (b.tx == x && b.ty == y) return b;
    }
    return null;
  }

  Flame? flameAt(int x, int y) {
    for (final Flame f in flames) {
      if (f.tx == x && f.ty == y) return f;
    }
    return null;
  }

  /// True when the player's 1x1 box overlaps tile (x, y).
  static bool overlaps(BPlayer p, int x, int y) =>
      p.x - 0.5 < x + 1 - _eps && p.x + 0.5 > x + _eps && p.y - 0.5 < y + 1 - _eps && p.y + 0.5 > y + _eps;

  /// Ranking best → worst: survivors (by kills), then knocked-out players, latest first.
  List<int> ranking() {
    final List<BPlayer> alive = players.where((BPlayer p) => p.alive).toList()
      ..sort((BPlayer a, BPlayer b) => b.kills != a.kills ? b.kills.compareTo(a.kills) : a.seat.compareTo(b.seat));
    return <int>[...alive.map((BPlayer p) => p.seat), ...outOrder.reversed];
  }

  void input(int seat, double dx, double dy) {
    final BPlayer p = players[seat];
    p.dx = dx.isFinite ? dx.clamp(-1.0, 1.0) : 0;
    p.dy = dy.isFinite ? dy.clamp(-1.0, 1.0) : 0;
  }

  bool placeBomb(int seat) {
    final BPlayer p = players[seat];
    if (!p.alive || p.stun > 0 || countdown > 0 || over) return false;
    if (bombs.where((Bomb b) => b.owner == seat).length >= p.maxBombs) return false;
    final int tx = p.tx, ty = p.ty;
    if (grid[ty][tx] != '.' || bombAt(tx, ty) != null) return false;
    final Bomb b = Bomb(seat, tx, ty, p.range);
    for (final BPlayer q in players) {
      if (q.alive && overlaps(q, tx, ty)) b.passable.add(q.seat);
    }
    bombs.add(b);
    events.add(BEvent('place', tx + 0.5, ty + 0.5, seat));
    return true;
  }

  bool placeTrap(int seat) {
    final BPlayer p = players[seat];
    if (!p.alive || p.traps <= 0 || p.stun > 0 || countdown > 0 || over) return false;
    if (traps.any((Trap t) => t.tx == p.tx && t.ty == p.ty) || bombAt(p.tx, p.ty) != null) return false;
    p.traps--;
    traps.add(Trap(seat, p.tx, p.ty));
    events.add(BEvent('trap', p.tx + 0.5, p.ty + 0.5, seat));
    return true;
  }

  /// Advances by a frame of [dt] seconds using fixed [fixedDt] steps. Returns the number of steps run.
  int step(double dt) {
    if (!dt.isFinite || dt <= 0) return 0;
    _acc += math.min(dt, maxStepsPerCall * fixedDt);
    int n = 0;
    while (_acc >= fixedDt - 1e-9 && n < maxStepsPerCall) {
      _acc -= fixedDt;
      fixedStep();
      n++;
    }
    if (_acc < 0) _acc = 0;
    return n;
  }

  /// One deterministic simulation step of [fixedDt].
  void fixedStep() {
    const double dt = fixedDt;
    if (countdown > 0) {
      countdown = math.max(0, countdown - dt);
      if (countdown < 1e-9) countdown = 0;
      return;
    }
    if (_overNow()) {
      _decayFlames(dt);
      return;
    }
    stepCount++;
    time += dt;
    _suddenDeath();
    for (final BPlayer p in players) {
      if (!p.alive) continue;
      if (isBot(p.seat)) _bot(p, dt);
      _move(p, dt);
    }
    for (final Bomb b in bombs) {
      b.passable.removeWhere((int s) => !players[s].alive || !overlaps(players[s], b.tx, b.ty));
      b.fuse -= dt;
    }
    _decayFlames(dt);
    final List<Bomb> due = bombs.where((Bomb b) => b.fuse <= _eps || flameAt(b.tx, b.ty) != null).toList();
    if (due.isNotEmpty) _detonate(due);
    // fire: everyone standing in it this step is out together (simultaneous knock-outs → possible draw)
    final List<BPlayer> hit = <BPlayer>[];
    for (final BPlayer p in players) {
      if (!p.alive) continue;
      final Flame? f = flameAt(p.tx, p.ty);
      if (f != null) {
        hit.add(p);
        p.killedBy = f.owner;
      }
    }
    for (final BPlayer p in hit) {
      if (p.killedBy >= 0 && p.killedBy != p.seat && p.killedBy < players.length) players[p.killedBy].kills++;
      _knockOut(p);
    }
    _settle();
  }

  void _settle() {
    if (!_overNow()) return;
    final List<BPlayer> alive = players.where((BPlayer p) => p.alive).toList();
    winner = alive.length == 1 && count > 1 ? alive.first.seat : -1;
  }

  void _decayFlames(double dt) {
    for (int i = flames.length - 1; i >= 0; i--) {
      flames[i].life -= dt;
      if (flames[i].life <= _eps) flames.removeAt(i);
    }
  }

  void _knockOut(BPlayer p) {
    p.alive = false;
    p.outAt = time;
    p.outStep = stepCount;
    p.moving = false;
    outOrder.add(p.seat);
    events.add(BEvent('out', p.x, p.y, p.seat));
  }

  /// Forfeit / disconnect.
  void eliminate(int seat) {
    final BPlayer p = players[seat];
    if (!p.alive) return;
    p.killedBy = -1;
    _knockOut(p);
    _settle();
  }

  // ------------------------------------------------------------------ explosions
  static const List<List<int>> dirs = <List<int>>[<int>[1, 0], <int>[-1, 0], <int>[0, 1], <int>[0, -1]];

  void _flame(int x, int y, int dir, int owner, {bool tip = false}) {
    final Flame? f = flameAt(x, y);
    if (f == null) {
      flames.add(Flame(x, y, dir, owner: owner, tip: tip));
      return;
    }
    f.life = flameLife;
    f.owner = owner;
    if (f.dir != dir) f.dir = 0;
    f.tip = f.tip && tip;
  }

  /// Detonates [first] and everything they chain into, all in this step.
  void _detonate(List<Bomb> first) {
    final Queue<Bomb> q = Queue<Bomb>.of(first);
    final Set<int> broken = <int>{}; // crates destroyed this step: later rays stop on them too
    while (q.isNotEmpty) {
      final Bomb b = q.removeFirst();
      if (!bombs.remove(b)) continue;
      events.add(BEvent('boom', b.tx + 0.5, b.ty + 0.5, b.owner));
      _flame(b.tx, b.ty, 0, b.owner);
      powerups.remove(key(b.tx, b.ty));
      for (final List<int> d in dirs) {
        final int fd = d[0] != 0 ? 1 : 2;
        for (int k = 1; k <= b.range; k++) {
          final int x = b.tx + d[0] * k, y = b.ty + d[1] * k;
          if (!inside(x, y) || grid[y][x] == '#') break;
          final int kk = key(x, y);
          if (grid[y][x] == 'c') {
            grid[y][x] = '.';
            broken.add(kk);
            events.add(BEvent('crate', x + 0.5, y + 0.5));
            final double roll = _r.nextDouble();
            if (roll < 0.36) {
              final double kind = _r.nextDouble();
              powerups[kk] = kind < 0.34 ? Pu.range : kind < 0.66 ? Pu.bomb : kind < 0.88 ? Pu.speed : Pu.trap;
            }
            _flame(x, y, fd, b.owner, tip: true);
            break;
          }
          if (broken.contains(kk)) {
            _flame(x, y, fd, b.owner, tip: true);
            break;
          }
          final Bomb? other = bombAt(x, y);
          if (other != null) {
            q.add(other); // chain reaction: it goes off now and its fire continues the line
            _flame(x, y, fd, b.owner, tip: true);
            break;
          }
          if (powerups.remove(kk) != null) events.add(BEvent('burn', x + 0.5, y + 0.5));
          traps.removeWhere((Trap t) => t.tx == x && t.ty == y);
          _flame(x, y, fd, b.owner, tip: k == b.range);
        }
      }
    }
  }

  // ------------------------------------------------------------------ sudden death
  static final List<int> dropOrder = _spiral();

  static List<int> _spiral() {
    final List<int> out = <int>[];
    int l = 1, t = 1, r = w - 2, b = h - 2;
    while (l <= r && t <= b) {
      for (int x = l; x <= r; x++) {
        out.add(t * w + x);
      }
      for (int y = t + 1; y <= b; y++) {
        out.add(y * w + r);
      }
      if (t < b) {
        for (int x = r - 1; x >= l; x--) {
          out.add(b * w + x);
        }
      }
      if (l < r) {
        for (int y = b - 1; y > t; y--) {
          out.add(y * w + l);
        }
      }
      l++;
      t++;
      r--;
      b--;
    }
    return out.where((int k) => !isFixedWall(k % w, k ~/ w)).toList();
  }

  /// Round time at which the i-th sudden-death block lands.
  static double dropTime(int i) => suddenDeathAt + i * dropInterval;

  void _suddenDeath() {
    if (!_hurry && time >= suddenDeathAt - 3) {
      _hurry = true;
      events.add(const BEvent('hurry', w / 2, h / 2));
    }
    while (_dropIndex < dropOrder.length && time >= dropTime(_dropIndex) - _eps) {
      final int k = dropOrder[_dropIndex++];
      final int x = k % w, y = k ~/ w;
      grid[y][x] = '#';
      bombs.removeWhere((Bomb b) => b.tx == x && b.ty == y);
      powerups.remove(k);
      traps.removeWhere((Trap t) => t.tx == x && t.ty == y);
      flames.removeWhere((Flame f) => f.tx == x && f.ty == y);
      events.add(BEvent('drop', x + 0.5, y + 0.5));
      final List<BPlayer> hit = <BPlayer>[];
      for (final BPlayer p in players) {
        if (!p.alive) continue;
        if (p.tx == x && p.ty == y) {
          hit.add(p);
        } else if (overlaps(p, x, y)) {
          // pushed back onto the centre of its own tile so the box never sits inside a wall
          p.x = p.tx + 0.5;
          p.y = p.ty + 0.5;
        }
      }
      for (final BPlayer p in hit) {
        p.killedBy = crushed;
        _knockOut(p);
      }
    }
  }

  // ------------------------------------------------------------------ movement
  bool _walk(BPlayer p, int x, int y) => !solid(x, y, forSeat: p.seat);

  void _move(BPlayer p, double dt) {
    p.moving = false;
    if (p.stun > 0) {
      p.stun = math.max(0, p.stun - dt);
      p.limit = double.infinity;
      return;
    }
    final double ix = p.dx, iy = p.dy;
    final double mag = math.max(ix.abs(), iy.abs());
    if (mag >= 0.2) {
      final double total = math.min(p.speed * dt, p.limit);
      final bool primH = ix.abs() >= iy.abs();
      final int ps = (primH ? ix : iy).sign.toInt();
      final double sec = primH ? iy : ix;
      final int ss = sec.abs() >= 0.38 * mag ? sec.sign.toInt() : 0;
      double used = _moveDir(p, primH, ps, total);
      if (used < total - _eps && ss != 0) used += _moveDir(p, !primH, ss, total - used);
      if (used > _eps) p.moving = true;
      p.facing = primH ? (ps > 0 ? 1 : 3) : (ps > 0 ? 2 : 0);
    }
    p.limit = double.infinity;
    final Pu? pu = powerups.remove(key(p.tx, p.ty));
    if (pu != null) {
      switch (pu) {
        case Pu.range:
          p.range = math.min(maxRange, p.range + 1);
        case Pu.bomb:
          p.maxBombs = math.min(maxBombCap, p.maxBombs + 1);
        case Pu.speed:
          p.speed = math.min(maxSpeed, p.speed + speedStep);
        case Pu.trap:
          p.traps = math.min(maxTraps, p.traps + 1);
      }
      events.add(BEvent('pickup', p.x, p.y, p.seat));
    }
    for (int i = traps.length - 1; i >= 0; i--) {
      final Trap t = traps[i];
      if (t.owner != p.seat && t.tx == p.tx && t.ty == p.ty) {
        traps.removeAt(i);
        p.stun = stunTime;
        p.moving = false;
        events.add(BEvent('stun', p.x, p.y, p.seat));
      }
    }
  }

  /// Moves [p] up to [dist] along one axis ([horizontal], direction [s] = ±1) and returns the distance used.
  /// When the box straddles two lanes it first slides onto the nearest lane whose next tile is open (corner
  /// sliding); along the lane it may always reach the centre of its tile and only goes further when the next
  /// tile is walkable.
  double _moveDir(BPlayer p, bool horizontal, int s, double dist) {
    if (s == 0 || dist <= _eps) return 0;
    double used = 0;
    double along = horizontal ? p.x : p.y;
    double cross = horizontal ? p.y : p.x;
    bool walk(int a, int c) => horizontal ? _walk(p, a, c) : _walk(p, c, a);
    final int aCell = along.floor();
    final int lane = cross.floor();
    final double off = cross - (lane + 0.5);
    if (off.abs() > _eps) {
      final int other = lane + (off > 0 ? 1 : -1);
      final List<(int, double)> cand = <(int, double)>[(lane, off.abs()), (other, 1 - off.abs())];
      (int, double)? pick;
      for (final (int, double) c in cand) {
        if (walk(aCell, c.$1) && walk(aCell + s, c.$1)) {
          pick = c;
          break;
        }
      }
      if (pick == null) return 0;
      final double target = pick.$1 + 0.5;
      final double m = math.min(dist, pick.$2);
      cross += (target - cross).sign * m;
      used += m;
      if ((target - cross).abs() <= _eps) cross = target;
      _set(p, horizontal, along, cross);
      if (cross != target) return used;
    }
    final int ln = cross.floor();
    final double centre = aCell + 0.5;
    final double toCentre = (centre - along) * s; // > 0: still before the centre of this tile
    final bool open = walk(aCell + s, ln);
    final double room = open ? double.infinity : math.max(0, toCentre);
    final double m = math.min(dist - used, room);
    if (m <= _eps) {
      if (!open && toCentre.abs() <= _eps) _set(p, horizontal, centre, cross);
      return used;
    }
    along += s * m;
    if (!open && (along - centre).abs() <= _eps) along = centre;
    _set(p, horizontal, along, cross);
    return used + m;
  }

  static void _set(BPlayer p, bool horizontal, double along, double cross) {
    if (horizontal) {
      p.x = along;
      p.y = cross;
    } else {
      p.y = along;
      p.x = cross;
    }
  }

  // ------------------------------------------------------------------ danger model (bots)
  /// Per tile: when fire first reaches it ([BDanger.start], ∞ = never) and when the last fire there ends.
  /// Chain reactions shorten fuses, rays stop at walls, crates and bombs, and the next sudden-death blocks
  /// count as permanent fire.
  BDanger dangerMap({Bomb? extra, bool Function(Bomb b)? visible}) {
    final BDanger d = BDanger(w * h);
    final List<Bomb> all = <Bomb>[
      for (final Bomb b in bombs)
        if (visible == null || visible(b)) b,
      if (extra != null) extra
    ];
    final List<double> det = <double>[
      for (final Bomb b in all) flameAt(b.tx, b.ty) != null ? 0 : math.max(0, b.fuse)
    ];
    final List<List<int>> reach = <List<int>>[];
    final List<List<int>> hits = <List<int>>[];
    for (final Bomb b in all) {
      final List<int> tiles = <int>[key(b.tx, b.ty)];
      final List<int> chain = <int>[];
      for (final List<int> dd in dirs) {
        for (int k = 1; k <= b.range; k++) {
          final int x = b.tx + dd[0] * k, y = b.ty + dd[1] * k;
          if (!inside(x, y) || grid[y][x] == '#') break;
          tiles.add(key(x, y));
          if (grid[y][x] == 'c') break;
          final int o = all.indexWhere((Bomb e) => e.tx == x && e.ty == y);
          if (o >= 0) {
            chain.add(o);
            break;
          }
        }
      }
      reach.add(tiles);
      hits.add(chain);
    }
    for (int it = 0; it < all.length; it++) {
      bool changed = false;
      for (int i = 0; i < all.length; i++) {
        for (final int o in hits[i]) {
          if (det[i] < det[o]) {
            det[o] = det[i];
            changed = true;
          }
        }
      }
      if (!changed) break;
    }
    for (int i = 0; i < all.length; i++) {
      for (final int k in reach[i]) {
        d.add(k, det[i], det[i] + flameLife);
      }
    }
    for (final Flame f in flames) {
      d.add(key(f.tx, f.ty), 0, f.life);
    }
    for (int i = _dropIndex; i < dropOrder.length; i++) {
      final double at = dropTime(i) - time;
      if (at > 5) break;
      d.add(dropOrder[i], math.max(0, at), double.infinity);
    }
    return d;
  }

  // ------------------------------------------------------------------ bots
  final Map<int, _BotState> _bots = <int, _BotState>{};

  /// Suicides (knocked out by own fire) so far this round.
  int get selfKnockouts => players.where((BPlayer p) => !p.alive && p.killedBy == p.seat).length;

  bool _trapFor(BPlayer p, int x, int y) => traps.any((Trap t) => t.owner != p.seat && t.tx == x && t.ty == y);

  static const double _slot = 0.1;

  /// Debug description of a bot's current route.
  String debugRoute(int seat) =>
      (_bots[seat]?.route ?? const <_Step>[]).map((_Step s) => '${s.k % w},${s.k ~/ w}@${(s.go - time).toStringAsFixed(2)}').join(' ');

  /// Time until the box centre crosses from its tile into the neighbour in direction (ddx, ddy), moving now.
  double _crossTime(BPlayer p, int ddx, int ddy, double v) {
    final double ox = p.x - p.tx - 0.5, oy = p.y - p.ty - 0.5;
    final double along = ox * ddx + oy * ddy;
    final double perp = ddx != 0 ? oy.abs() : ox.abs();
    return (perp + 0.5 - along) / v;
  }

  /// Time-expanded search (tile × 0.1 s slot): the bot may walk or wait, and a tile may only be occupied while
  /// it does not burn (± [margin]). [score] rates a tile at the time it is first reached (higher is better,
  /// null = not a goal); the result is the timed route to the best one.
  List<_Step>? _route(BPlayer p, BDanger dg, double? Function(int k, double t) score,
      {double margin = 0.12, double horizon = 6, double speedFactor = 1}) {
    final double v = p.speed * speedFactor;
    final double half = 0.5 / v;
    final int start = key(p.tx, p.ty);
    final double lag = ((p.x - p.tx - 0.5).abs() + (p.y - p.ty - 0.5).abs()) / v;
    final double stun = p.stun;
    final int hz = (horizon / _slot).ceil();
    final int n = w * h;
    final int ms = math.max(1, ((1 / v) / _slot - 1e-9).ceil());
    final Map<int, int> prev = <int, int>{}; // state (slot * n + tile) → previous state
    final Map<int, double> leave = <int, double>{}; // state → time the move into it started
    final List<bool> seen = List<bool>.filled(n, false);
    final List<List<int>> buckets = List<List<int>>.generate(hz + 4 * ms + 4, (_) => <int>[]);
    prev[start] = -1;
    buckets[0].add(start);
    int best = -1;
    double bestScore = double.negativeInfinity;
    for (int i = 0; i <= hz; i++) {
      final double t = i * _slot;
      for (final int st in buckets[i]) {
        final int c = st % n;
        if (!seen[c]) {
          seen[c] = true;
          final double? sc = score(c, t);
          if (sc != null && sc > bestScore + 1e-9) {
            bestScore = sc;
            best = st;
          }
        }
        final int ws = (i + 1) * n + c;
        if (!prev.containsKey(ws) && !dg.hits(c, t - margin, t + _slot + margin)) {
          prev[ws] = st;
          buckets[i + 1].add(ws);
        }
        final int cx = c % w, cy = c ~/ w;
        for (final List<int> d in dirs) {
          final int nx = cx + d[0], ny = cy + d[1];
          // a bomb tile can be left but never re-entered (passing over one's own bomb ends once off it)
          if (!inside(nx, ny) || grid[ny][nx] != '.' || bombAt(nx, ny) != null || _trapFor(p, nx, ny)) continue;
          // when the move starts and when the centre crosses into the next tile
          double go, cross;
          if (c == start && i * _slot < lag + stun + 1e-9) {
            go = math.max(t, stun);
            cross = go + _crossTime(p, d[0], d[1], v);
          } else {
            go = t;
            cross = t + half;
          }
          final int ni = math.max(i + 1, ((cross + half) / _slot - 1e-9).ceil());
          if (ni >= buckets.length) continue;
          final int nk = key(nx, ny);
          final int ns = ni * n + nk;
          if (prev.containsKey(ns)) continue;
          if (dg.hits(c, t - margin, cross + margin)) continue;
          if (dg.hits(nk, cross - margin, ni * _slot + margin)) continue;
          prev[ns] = st;
          leave[ns] = go;
          buckets[ni].add(ns);
        }
      }
    }
    if (best < 0) return null;
    final List<int> chain = <int>[];
    for (int k = best; k != -1; k = prev[k]!) {
      chain.add(k);
    }
    final List<int> states = chain.reversed.toList();
    final List<_Step> out = <_Step>[];
    for (int j = 1; j < states.length; j++) {
      final int a = states[j - 1] % n, b = states[j] % n;
      if (a != b) out.add(_Step(b, time + leave[states[j]]!));
    }
    return out;
  }

  /// Re-checks the remaining timed route against the current fire map.
  bool _routeOk(BPlayer p, _BotState st, BDanger dg) {
    final double v = p.speed;
    final double half = 0.5 / v;
    const double m = 0.03;
    final List<_Step> r = st.route;
    int k = key(p.tx, p.ty);
    if (r.isEmpty) return !st.safeGoal || dg.start[k].isInfinite;
    double from = 0;
    for (int j = 0; j < r.length; j++) {
      final _Step s = r[j];
      final int x = s.k % w, y = s.k ~/ w;
      final bool onIt = x == p.tx && y == p.ty;
      if (!onIt && (grid[y][x] != '.' || bombAt(x, y) != null || _trapFor(p, x, y))) return false;
      double cross;
      if (j == 0) {
        final int ddx = x - p.tx, ddy = y - p.ty;
        if (ddx.abs() + ddy.abs() != 1) {
          cross = 0; // already standing in it
        } else {
          cross = math.max(0, s.go - time) + _crossTime(p, ddx, ddy, v);
        }
      } else {
        cross = math.max(0, s.go - time) + half;
      }
      if (cross > 0 && dg.hits(k, from - m, cross + m)) return false;
      k = s.k;
      from = cross;
    }
    if (dg.hits(k, from - m, from + half + m)) return false;
    return !st.safeGoal || dg.start[k].isInfinite;
  }

  int _cratesInBlast(int x0, int y0, int range) {
    int n = 0;
    for (final List<int> d in dirs) {
      for (int k = 1; k <= range; k++) {
        final int x = x0 + d[0] * k, y = y0 + d[1] * k;
        if (!inside(x, y) || grid[y][x] == '#') break;
        if (grid[y][x] == 'c') {
          n++;
          break;
        }
        if (bombAt(x, y) != null) break;
      }
    }
    return n;
  }

  bool _enemyInBlast(BPlayer p, int x0, int y0, int range) {
    for (final BPlayer o in players) {
      if (o.alive && o.seat != p.seat && o.tx == x0 && o.ty == y0) return true;
    }
    for (final List<int> d in dirs) {
      for (int k = 1; k <= range; k++) {
        final int x = x0 + d[0] * k, y = y0 + d[1] * k;
        if (!inside(x, y) || grid[y][x] != '.') break;
        for (final BPlayer o in players) {
          if (o.alive && o.seat != p.seat && o.tx == x && o.ty == y) return true;
        }
        if (bombAt(x, y) != null) break;
      }
    }
    return false;
  }

  bool _powerupInBlast(int x0, int y0, int range) {
    for (final List<int> d in dirs) {
      for (int k = 1; k <= range; k++) {
        final int x = x0 + d[0] * k, y = y0 + d[1] * k;
        if (!inside(x, y) || grid[y][x] != '.') break;
        if (powerups.containsKey(key(x, y))) return true;
      }
    }
    return false;
  }

  /// How good tile [k], reached after [t] s, is to wait out a blast: near, not a dead end, away from opponents.
  double _shelter(BPlayer p, BDanger dg, int k, double t) {
    final int x = k % w, y = k ~/ w;
    int exits = 0;
    for (final List<int> dd in dirs) {
      final int nx = x + dd[0], ny = y + dd[1];
      if (inside(nx, ny) && _walk(p, nx, ny) && dg.start[key(nx, ny)].isInfinite) exits++;
    }
    double s = 1000.0 - t * 3 + exits * 0.8;
    if (exits == 0) s -= 2.5;
    for (final BPlayer o in players) {
      if (o.alive && o.seat != p.seat && (o.tx - x).abs() + (o.ty - y).abs() <= 2) s -= 1.2;
    }
    return s;
  }

  void _bot(BPlayer p, double dt) {
    final double skill = botSkill[p.seat].clamp(0.05, 1.0);
    final _BotState st = _bots.putIfAbsent(p.seat, () => _BotState());
    st.think -= dt;
    st.bombCooldown -= dt;
    if (p.stun > 0) {
      p.dx = 0;
      p.dy = 0;
      return;
    }
    // reaction time: a new opponent bomb is only taken into account a moment after it appears
    final double reaction = 0.1 + (1 - skill) * 0.3;
    st.noticed.removeWhere((Bomb b, double _) => !bombs.contains(b));
    final BDanger dg = dangerMap(
        visible: (Bomb b) => b.owner == p.seat || st.noticed.putIfAbsent(b, () => time + reaction) <= time + 1e-9);
    st.dg = dg;
    final bool inDanger = dg.start[key(p.tx, p.ty)].isFinite;
    final bool late = st.route.isNotEmpty && time > st.route.first.go + 1.5 / p.speed + 0.3;
    final bool atCentre = (p.x - p.tx - 0.5).abs() <= _eps && (p.y - p.ty - 0.5).abs() <= _eps;
    if (!_routeOk(p, st, dg) || late || (st.think <= 0 && (atCentre || st.route.isEmpty))) {
      _plan(p, st, dg, inDanger, skill);
    }
    _steer(p, st);
  }

  void _plan(BPlayer p, _BotState st, BDanger dg, bool inDanger, double skill) {
    st.think = 0.1 + (1 - skill) * 0.32 + _r.nextDouble() * 0.06;
    final int here = key(p.tx, p.ty);
    if (inDanger) {
      // run (or wait out the fire) to a tile that never burns; if there is none, survive as long as possible
      final List<_Step>? esc = _route(p, dg, (int k, double t) => dg.start[k].isInfinite ? _shelter(p, dg, k, t) : null);
      if (esc != null) {
        st.route = esc;
        st.safeGoal = true;
        return;
      }
      st.route = _route(p, dg, (int k, double t) {
            double sc = math.min(dg.start[k], 30) - t * 0.01;
            for (final BPlayer o in players) {
              // do not pile onto an opponent's tile: sharing the last tile only ends in a draw
              if (o.alive && o.seat != p.seat && key(o.tx, o.ty) == k) sc -= 0.6;
            }
            return sc;
          }, margin: 0.02) ??
          <_Step>[];
      st.safeGoal = false;
      return;
    }
    final int mine = bombs.where((Bomb b) => b.owner == p.seat).length;
    final bool canBomb = mine < p.maxBombs && bombAt(p.tx, p.ty) == null && st.bombCooldown <= 0;
    bool stuckHere = !canBomb;
    if (canBomb) {
      final int crates = _cratesInBlast(p.tx, p.ty, p.range);
      final bool spoils = _powerupInBlast(p.tx, p.ty, p.range);
      final bool late = time >= suddenDeathAt - 25;
      final List<BPlayer> near = players
          .where((BPlayer o) => o.alive && o.seat != p.seat && (o.tx - p.tx).abs() + (o.ty - p.ty).abs() <= p.range + 2)
          .toList();
      bool enemy = _enemyInBlast(p, p.tx, p.ty, p.range) && _r.nextDouble() < 0.35 + skill * 0.65;
      if (!enemy && near.isNotEmpty && _r.nextDouble() < skill * 0.35 + (late ? 0.25 : 0)) enemy = true;
      final bool useful = (crates > 0 && !spoils) || enemy;
      if (useful || near.isNotEmpty) {
        final Bomb hypo = Bomb(p.seat, p.tx, p.ty, p.range)..passable.add(p.seat);
        bombs.add(hypo);
        final BDanger d2 = dangerMap(visible: (Bomb b) => b == hypo || b.owner == p.seat || (st.noticed[b] ?? 1e9) <= time + 1e-9);
        bool lethal = false;
        for (final BPlayer o in near) {
          // kill shot: the opponent has no way out of this bomb plus everything already ticking
          if (d2.start[key(o.tx, o.ty)].isFinite &&
              _route(o, d2, (int k, double t) => d2.start[k].isInfinite ? 1.0 : null, margin: 0, horizon: 4) == null) {
            lethal = true;
          }
        }
        // own escape with extra slack: a bot must never bet its life on a tight dodge
        final List<_Step>? esc = (useful || lethal)
            ? _route(p, d2, (int k, double t) => d2.start[k].isInfinite ? _shelter(p, d2, k, t) : null,
                margin: 0.22, horizon: 4, speedFactor: 0.9)
            : null;
        bombs.remove(hypo);
        if (esc != null && esc.isNotEmpty && (useful || (lethal && _r.nextDouble() < 0.5 + skill * 0.5))) {
          placeBomb(p.seat);
          st.bombCooldown = 0.3;
          st.route = esc;
          st.safeGoal = true;
          st.trapAt = p.traps > 0 && _r.nextDouble() < 0.25 + skill * 0.3 ? esc.first.k : -1;
          st.think = 0.25;
          return;
        }
        if (useful) stuckHere = true; // worth a bomb but no safe way out: go somewhere else
      }
    }
    // pick a destination: power-ups, bombing spots for crates/enemies, otherwise close in on the nearest enemy
    final double aggro = 0.4 + skill * 1.2;
    final double jitter = (1 - skill) * 1.5;
    final List<BPlayer> foes = players.where((BPlayer o) => o.alive && o.seat != p.seat).toList();
    final List<_Step>? route = _route(p, dg, (int k, double t) {
      if (dg.start[k].isFinite) return null;
      final int x = k % w, y = k ~/ w;
      double s = 0;
      if (powerups.containsKey(k)) s += 9;
      if (bombAt(x, y) == null) {
        final int c = _cratesInBlast(x, y, p.range);
        if (c > 0) s += 2.5 + c * 1.2;
        if (_enemyInBlast(p, x, y, p.range)) s += 5 * aggro;
      }
      if (foes.isNotEmpty) {
        int nearest = 1 << 20;
        for (final BPlayer o in foes) {
          nearest = math.min(nearest, (o.tx - x).abs() + (o.ty - y).abs());
        }
        s += aggro * 2.5 / (1 + nearest);
      }
      if (s <= 0) return null;
      if (k == here && stuckHere) s -= 4;
      return s - t * 2.2 + _r.nextDouble() * jitter;
    }, horizon: 5);
    st.route = route ?? <_Step>[];
    st.safeGoal = true;
  }

  void _steer(BPlayer p, _BotState st) {
    final List<_Step> r = st.route;
    while (r.isNotEmpty) {
      final int k = r.first.k;
      if ((p.x - (k % w + 0.5)).abs() <= _eps && (p.y - (k ~/ w + 0.5)).abs() <= _eps) {
        r.removeAt(0);
        continue;
      }
      break;
    }
    if (st.trapAt >= 0 && p.traps > 0 && key(p.tx, p.ty) == st.trapAt && bombAt(p.tx, p.ty) == null) {
      placeTrap(p.seat);
      st.trapAt = -1;
    }
    if (r.isEmpty) {
      _aim(p, p.tx + 0.5, p.ty + 0.5); // settle on the centre of the current tile
      return;
    }
    if (time < r.first.go - 1e-9) {
      // waiting for the route's next departure: stay put, or finish reaching the tile centre unless already
      // leaning towards the next tile (going back and forth would only waste the margin)
      final int nx = r.first.k % w, ny = r.first.k ~/ w;
      final double ox = p.x - p.tx - 0.5, oy = p.y - p.ty - 0.5;
      final bool leaning = (ox.abs() > _eps && (nx - p.tx).sign == ox.sign && ny == p.ty) ||
          (oy.abs() > _eps && (ny - p.ty).sign == oy.sign && nx == p.tx);
      if (leaning) {
        p.dx = 0;
        p.dy = 0;
      } else {
        _aim(p, p.tx + 0.5, p.ty + 0.5);
      }
      return;
    }
    _aim(p, r.first.k % w + 0.5, r.first.k ~/ w + 0.5);
  }

  /// Points the stick at (cx, cy), unaligned axis first, and clamps the step so the bot stops exactly there.
  void _aim(BPlayer p, double cx, double cy) {
    final double ex = cx - p.x, ey = cy - p.y;
    p.dx = 0;
    p.dy = 0;
    final bool needX = ex.abs() > _eps, needY = ey.abs() > _eps;
    if (!needX && !needY) {
      p.x = cx;
      p.y = cy;
      return;
    }
    final bool xAligned = (p.x - p.tx - 0.5).abs() <= _eps;
    final bool horizontal = needX && needY ? !xAligned : needX;
    if (horizontal) {
      p.dx = ex.sign;
      p.limit = ex.abs();
    } else {
      p.dy = ey.sign;
      p.limit = ey.abs();
    }
  }

  // ------------------------------------------------------------------ network snapshot
  Map<String, dynamic> snapshot() => <String, dynamic>{
        'g': grid.map((List<String> r) => r.join()).join(),
        'p': <List<num>>[
          for (final BPlayer p in players)
            <num>[
              (p.x * 1000).round(), (p.y * 1000).round(), p.alive ? 1 : 0, (p.stun * 100).round(), p.range, p.maxBombs,
              p.traps, p.kills, (p.speed * 100).round(), p.facing, p.moving ? 1 : 0
            ]
        ],
        'b': <List<num>>[for (final Bomb b in bombs) <num>[b.tx, b.ty, (b.fuse * 100).round(), b.range, b.owner]],
        'f': <List<num>>[for (final Flame f in flames) <num>[f.tx, f.ty, f.dir, (f.life * 100).round(), f.owner, f.tip ? 1 : 0]],
        'u': <String, int>{for (final MapEntry<int, Pu> e in powerups.entries) '${e.key}': e.value.index},
        'tr': <List<num>>[for (final Trap t in traps) <num>[t.tx, t.ty, t.owner]],
        't': (time * 100).round(),
        'c': (countdown * 100).round(),
        'o': outOrder,
        'd': _dropIndex,
        'wn': winner,
      };

  void applySnapshot(Map<String, dynamic> s, {int? keepSeat}) {
    final String g = '${s['g']}';
    if (g.length == w * h) {
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final String c = g[y * w + x];
          if (grid[y][x] == 'c' && c == '.') events.add(BEvent('crate', x + 0.5, y + 0.5));
          if (grid[y][x] != '#' && c == '#') events.add(BEvent('drop', x + 0.5, y + 0.5));
          grid[y][x] = c;
        }
      }
    }
    final List<dynamic> ps = (s['p'] as List<dynamic>?) ?? const <dynamic>[];
    for (int i = 0; i < ps.length && i < players.length; i++) {
      final List<dynamic> v = ps[i] as List<dynamic>;
      final BPlayer p = players[i];
      final bool alive = v[2] == 1;
      if (p.alive && !alive) events.add(BEvent('out', p.x, p.y, p.seat));
      num at(int j, num dflt) => j < v.length ? v[j] as num : dflt;
      p
        ..x = at(0, 500) / 1000
        ..y = at(1, 500) / 1000
        ..alive = alive
        ..stun = at(3, 0) / 100
        ..range = at(4, startRange).toInt()
        ..maxBombs = at(5, 1).toInt()
        ..traps = at(6, 0).toInt()
        ..kills = at(7, 0).toInt()
        ..speed = at(8, baseSpeed * 100) / 100
        ..facing = at(9, 2).toInt()
        ..moving = at(10, 0) == 1;
    }
    final int before = bombs.length;
    bombs
      ..clear()
      ..addAll(((s['b'] as List<dynamic>?) ?? const <dynamic>[]).map((dynamic e) {
        final List<dynamic> v = e as List<dynamic>;
        return Bomb((v[4] as num).toInt(), (v[0] as num).toInt(), (v[1] as num).toInt(), (v[3] as num).toInt(),
            fuse: (v[2] as num) / 100);
      }));
    final List<dynamic> fs = (s['f'] as List<dynamic>?) ?? const <dynamic>[];
    if (fs.isNotEmpty && flames.isEmpty && before > 0) {
      final List<dynamic> c = fs.first as List<dynamic>;
      events.add(BEvent('boom', (c[0] as num) + 0.5, (c[1] as num) + 0.5));
    }
    flames
      ..clear()
      ..addAll(fs.map((dynamic e) {
        final List<dynamic> v = e as List<dynamic>;
        return Flame((v[0] as num).toInt(), (v[1] as num).toInt(), (v[2] as num).toInt(),
            life: (v[3] as num) / 100,
            owner: v.length > 4 ? (v[4] as num).toInt() : -1,
            tip: v.length > 5 && v[5] == 1);
      }));
    powerups
      ..clear()
      ..addAll(((s['u'] as Map?) ?? const <String, int>{})
          .map((dynamic k, dynamic v) => MapEntry<int, Pu>(int.parse('$k'), Pu.values[(v as num).toInt()])));
    traps
      ..clear()
      ..addAll(((s['tr'] as List<dynamic>?) ?? const <dynamic>[]).map((dynamic e) {
        final List<dynamic> v = e as List<dynamic>;
        return Trap((v[2] as num).toInt(), (v[0] as num).toInt(), (v[1] as num).toInt());
      }));
    time = ((s['t'] as num?) ?? 0) / 100;
    final num? c = s['c'] as num?;
    countdown = c != null ? c / 100 : (time > 0 ? 0 : countdown);
    _dropIndex = ((s['d'] as num?) ?? _dropIndex).toInt();
    _hurry = time >= suddenDeathAt - 3;
    winner = ((s['wn'] as num?) ?? -1).toInt();
    outOrder
      ..clear()
      ..addAll(((s['o'] as List?) ?? const <dynamic>[]).map((dynamic e) => (e as num).toInt()));
  }
}

/// Fire windows per tile for the bots: [start] earliest burn (∞ = safe), [end] latest end of fire.
class BDanger {
  BDanger(int n)
      : start = List<double>.filled(n, double.infinity),
        end = List<double>.filled(n, double.negativeInfinity);
  final List<double> start;
  final List<double> end;

  void add(int k, double from, double to) {
    if (from < start[k]) start[k] = from;
    if (to > end[k]) end[k] = to;
  }

  /// True when the interval [a, b] overlaps the fire window of tile [k].
  bool hits(int k, double a, double b) => start[k].isFinite && a < end[k] && b > start[k];
}

class _Step {
  _Step(this.k, this.go);

  /// Tile to step onto and the absolute round time to start moving towards it.
  final int k;
  final double go;
}

class _BotState {
  List<_Step> route = <_Step>[];
  final Map<Bomb, double> noticed = <Bomb, double>{};
  BDanger? dg;
  bool safeGoal = true;
  double think = 0;
  double bombCooldown = 0;
  int trapAt = -1;
}

// ====================================================================== match
class BombMatch {
  BombMatch({
    required this.seed,
    required this.count,
    this.botSkill = const <double>[],
    this.winsNeeded = 2,
    this.maxRounds = 5,
  })  : wins = List<int>.filled(count, 0),
        totalKills = List<int>.filled(count, 0) {
    arena = _newRound();
  }

  static const double intermissionTime = 3.2;

  final int seed;
  final int count;
  final List<double> botSkill;
  final int winsNeeded;
  final int maxRounds;
  final List<int> wins;
  final List<int> totalKills;

  /// Round winners so far (-1 = drawn round).
  final List<int> roundWinners = <int>[];

  /// Seats knocked out for good (forfeit / disconnect).
  final Set<int> forfeited = <int>{};
  final List<BEvent> events = <BEvent>[];
  late BombArena arena;
  int round = 1;
  double intermission = 0;
  bool over = false;
  double _acc = 0;

  int seedFor(int r) => seed + (r - 1) * 7919;

  BombArena _newRound() {
    final BombArena a = BombArena(seed: seedFor(round), count: count, botSkill: botSkill);
    if (round > 1) a.countdown = 1.5;
    for (final int s in forfeited) {
      a.eliminate(s);
    }
    a.events.clear();
    return a;
  }

  /// Seats with the most round wins (one = the champion, several = a drawn match). Valid once [over].
  List<int> get leaders {
    final int top = wins.reduce(math.max);
    return <int>[for (int i = 0; i < count; i++) if (wins[i] == top && !forfeited.contains(i)) i];
  }

  bool get isDraw => over && leaders.length != 1;
  int get winner => over && leaders.length == 1 ? leaders.first : -1;

  /// Match ranking best → worst: round wins, then knock-outs, then the last round's placing.
  List<int> ranking() {
    final List<int> last = arena.ranking();
    final List<int> seats = List<int>.generate(count, (int i) => i)
      ..sort((int a, int b) {
        final int fa = forfeited.contains(a) ? 1 : 0, fb = forfeited.contains(b) ? 1 : 0;
        if (fa != fb) return fa - fb;
        if (wins[a] != wins[b]) return wins[b] - wins[a];
        final int ka = totalKills[a] + arena.players[a].kills, kb = totalKills[b] + arena.players[b].kills;
        if (ka != kb) return kb - ka;
        return last.indexOf(a) - last.indexOf(b);
      });
    return seats;
  }

  void input(int seat, double dx, double dy) => arena.input(seat, dx, dy);
  bool placeBomb(int seat) => intermission <= 0 && !over && arena.placeBomb(seat);
  bool placeTrap(int seat) => intermission <= 0 && !over && arena.placeTrap(seat);

  void forfeit(int seat) {
    if (!forfeited.add(seat)) return;
    arena.eliminate(seat);
  }

  /// Frame update with fixed steps (same accumulator rules as [BombArena.step]).
  int step(double dt, {int speedUp = 1}) {
    if (!dt.isFinite || dt <= 0) return 0;
    _acc += math.min(dt, BombArena.maxStepsPerCall * BombArena.fixedDt) * speedUp;
    int n = 0;
    while (_acc >= BombArena.fixedDt - 1e-9 && n < BombArena.maxStepsPerCall * speedUp) {
      _acc -= BombArena.fixedDt;
      fixedStep();
      n++;
    }
    if (_acc < 0) _acc = 0;
    return n;
  }

  void fixedStep() {
    if (over) {
      arena.fixedStep();
      _pull();
      return;
    }
    if (intermission > 0) {
      arena.fixedStep();
      _pull();
      intermission -= BombArena.fixedDt;
      if (intermission <= 1e-9) {
        intermission = 0;
        for (final BPlayer p in arena.players) {
          totalKills[p.seat] += p.kills;
        }
        round++;
        arena = _newRound();
        events.add(BEvent('round', BombArena.w / 2, BombArena.h / 2, round));
      }
      return;
    }
    arena.fixedStep();
    _pull();
    if (arena.over) _endRound();
  }

  void _pull() {
    events.addAll(arena.events);
    arena.events.clear();
  }

  void _endRound() {
    final int wnr = arena.winner;
    roundWinners.add(wnr);
    if (wnr >= 0) wins[wnr]++;
    final int active = count - forfeited.length;
    final bool clinched = wnr >= 0 && wins[wnr] >= winsNeeded;
    final bool alone = active <= 1;
    if (clinched || alone || round >= maxRounds) {
      over = true;
      for (final BPlayer p in arena.players) {
        totalKills[p.seat] += p.kills;
        p.kills = 0;
      }
      events.add(BEvent('match', BombArena.w / 2, BombArena.h / 2, winner));
    } else {
      intermission = intermissionTime;
      events.add(BEvent('roundEnd', BombArena.w / 2, BombArena.h / 2, wnr));
    }
  }

  Map<String, dynamic> snapshot() => <String, dynamic>{
        ...arena.snapshot(),
        'R': round,
        'W': wins,
        'K': totalKills,
        'I': (intermission * 100).round(),
        'M': over ? 1 : 0,
        'RW': roundWinners,
        'F': forfeited.toList(),
      };

  void applySnapshot(Map<String, dynamic> s) {
    final int r = ((s['R'] as num?) ?? round).toInt();
    if (r != round) {
      round = r;
      arena = BombArena(seed: seedFor(round), count: count);
      events.add(BEvent('round', BombArena.w / 2, BombArena.h / 2, round));
    }
    final bool wasOver = arena.over;
    arena.applySnapshot(s);
    _pull();
    final List<dynamic> wl = (s['W'] as List<dynamic>?) ?? const <dynamic>[];
    for (int i = 0; i < wl.length && i < count; i++) {
      wins[i] = (wl[i] as num).toInt();
    }
    final List<dynamic> kl = (s['K'] as List<dynamic>?) ?? const <dynamic>[];
    for (int i = 0; i < kl.length && i < count; i++) {
      totalKills[i] = (kl[i] as num).toInt();
    }
    roundWinners
      ..clear()
      ..addAll(((s['RW'] as List<dynamic>?) ?? const <dynamic>[]).map((dynamic e) => (e as num).toInt()));
    forfeited
      ..clear()
      ..addAll(((s['F'] as List<dynamic>?) ?? const <dynamic>[]).map((dynamic e) => (e as num).toInt()));
    final double im = ((s['I'] as num?) ?? 0) / 100;
    final bool nowOver = s['M'] == 1;
    if (!wasOver && arena.over && !nowOver && im > 0) {
      events.add(BEvent('roundEnd', BombArena.w / 2, BombArena.h / 2, arena.winner));
    }
    intermission = im;
    if (nowOver && !over) events.add(BEvent('match', BombArena.w / 2, BombArena.h / 2, leaders.length == 1 ? leaders.first : -1));
    over = nowOver;
  }
}
