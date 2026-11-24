import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../games/core/net_link.dart';

/// Final state of a match as stored on the server.
class MatchEnd {
  const MatchEnd({required this.winners, required this.reason, this.scores});
  final List<int> winners;
  final String reason;
  final List<int>? scores;
  bool get isForfeit => reason.startsWith('forfeit');

  /// Called off before it began (nx_quick_cancel): no result, no rewards.
  bool get isAbandoned => reason == 'abandoned';
  int? get forfeitSeat => isForfeit ? int.tryParse(reason.split(':').last) : null;
}

/// The match's server log, behind a seam so the link logic can be tested with an in-memory server.
abstract class MatchBackend {
  /// nx_push_move: `{ok: true}` or `{ok: false, reason: 'seq' | ...}`.
  Future<dynamic> pushMove(int seq, String kind, Map<String, dynamic> move, String? hash, int seat);

  /// Rows of the move log with seq > [after], ordered (seq, seat, kind, move, hash, by_user).
  Future<List<Map<String, dynamic>>> fetchMoves(int after);

  /// status, winner_seats, reason, scores of the match row (null when unknown).
  Future<Map<String, dynamic>?> fetchStatus();
}

class _SupabaseBackend implements MatchBackend {
  _SupabaseBackend(this._c, this._match);
  final SupabaseClient _c;
  final String _match;

  @override
  Future<dynamic> pushMove(int seq, String kind, Map<String, dynamic> move, String? hash, int seat) =>
      _c.rpc('nx_push_move', params: <String, dynamic>{
        'p_match': _match,
        'p_seq': seq,
        'p_kind': kind,
        'p_move': move,
        'p_hash': hash,
        'p_seat': seat,
      });

  @override
  Future<List<Map<String, dynamic>>> fetchMoves(int after) async {
    final List<dynamic> rows = await _c
        .from('nx_match_moves')
        .select('seq, seat, kind, move, hash, by_user')
        .eq('match_id', _match)
        .gt('seq', after)
        .order('seq');
    return <Map<String, dynamic>>[for (final dynamic r in rows) Map<String, dynamic>.from(r as Map)];
  }

  @override
  Future<Map<String, dynamic>?> fetchStatus() =>
      _c.from('nx_matches').select('status, winner_seats, reason, scores').eq('id', _match).maybeSingle();
}

/// Kinds the server log stores as 'system' so they never meet the turn clock of 20261117350000_g_turn_authority
/// (that nx_push_move rotated the server turn on EVERY move and rejected moves 10 s after the last one, so the
/// pre-match team / formation picks, the shooter's 'settled' snapshot and 'goal' were refused: room matches hung on
/// "waiting for the other players" and quick matches drifted apart). The real kind rides in the move as '_k' and is
/// restored on read, so games see exactly what was sent. Works on both the old and the fixed server function.
const Set<String> kWireWrapped = <String>{'move', 'timeout'};

/// The seat that acts as the match authority (posts snapshots, files timeouts, forfeits absent players).
///
/// It is the lowest non-forfeited seat that is connected. Until Realtime presence has synced at least once
/// ([presenceKnown] false) every seat is assumed connected: otherwise every phone sees only itself during the first
/// seconds of a match, each one thinks it is the authority, and they all post snapshots / defaults / timeouts at once.
@visibleForTesting
int authoritySeat({
  required int seatCount,
  required int mySeat,
  required Set<int> connected,
  required Set<int> forfeited,
  required bool presenceKnown,
}) {
  for (int s = 0; s < seatCount; s++) {
    if (forfeited.contains(s)) continue;
    if (!presenceKnown || s == mySeat || connected.contains(s)) return s;
  }
  return mySeat >= 0 ? mySeat : 0;
}

/// Seconds a seat may stay disconnected before the authority forfeits it. Tournament games carry
/// settings.grace_sec; lobby games give the player on turn 40 s and a waiting player 90 s.
@visibleForTesting
int absenceLimitSec({required bool onTurn, int? graceSec}) => graceSec ?? (onTurn ? 40 : 90);

/// Supabase implementation of [NetLink].
///
/// * Ordered log: table nx_match_moves (insert through RPC nx_push_move, seq = last+1).
/// * Delivery: Realtime postgres_changes + a catch-up poll (never misses a move).
/// * Presence + ephemeral 'live' messages: Realtime channel `nxm:<matchId>`.
class SupabaseMatchLink extends ChangeNotifier implements NetLink {
  SupabaseMatchLink._(this._c, this.matchId, this._uid, Map<String, dynamic> m, {MatchBackend? backend})
      : _b = backend ?? _SupabaseBackend(_c!, matchId) {
    _players = (m['players'] as List<dynamic>).map((dynamic e) => '$e').toList();
    names = ((m['names'] as List<dynamic>?) ?? const <dynamic>[]).map((dynamic e) => '$e').toList();
    while (names.length < _players.length) {
      names.add('Pilot ${names.length + 1}');
    }
    seed = (m['seed'] as num).toInt();
    game = '${m['game']}';
    roomId = m['room_id'] as String?;
    settings = Map<String, dynamic>.from((m['settings'] as Map?) ?? const <String, dynamic>{});
    mySeat = _players.indexOf(_uid);
    _status = '${m['status']}';
    if (_status != 'playing') _end = _endFrom(m);
  }

  /// [c] = games-project client; [uid] = the signed-in user (from the auth project's session).
  static Future<SupabaseMatchLink> open(SupabaseClient c, String matchId, {required String uid}) async {
    final Map<String, dynamic> m = await c.from('nx_matches').select().eq('id', matchId).single();
    final SupabaseMatchLink link = SupabaseMatchLink._(c, matchId, uid, m);
    link._connect();
    return link;
  }

  /// Tests: a link on an in-memory [backend] (no Realtime; the catch-up poll delivers moves).
  @visibleForTesting
  factory SupabaseMatchLink.test(MatchBackend backend, String matchId, String uid, Map<String, dynamic> m,
      {Duration poll = const Duration(milliseconds: 50)}) {
    final SupabaseMatchLink link = SupabaseMatchLink._(null, matchId, uid, m, backend: backend);
    link._poll = Timer.periodic(poll, (_) => unawaited(link._catchUp()));
    return link;
  }

  final SupabaseClient? _c;
  final MatchBackend _b;
  final String _uid;
  @override
  final String matchId;
  late final List<String> _players;
  @override
  late final List<String> names;
  @override
  late final int seed;
  late final String game;
  String? roomId;
  @override
  late final Map<String, dynamic> settings;
  @override
  late final int mySeat;

  String _status = 'playing';
  MatchEnd? _end;
  MatchEnd? get end => _end;
  bool get isOver => _status != 'playing';

  RealtimeChannel? _ch;
  Timer? _poll;
  Timer? _watch;
  Timer? _heartbeat;
  bool _disposed = false;

  final Map<int, NetMove> _rows = <int, NetMove>{};
  final Map<int, String> _rowUser = <int, String>{};
  final Set<int> _server = <int>{}; // seqs confirmed by the server log
  int _delivered = 0; // highest seq handed to the current listener (or sent by us)
  final Set<int> _ownSeqs = <int>{};
  final Set<int> _floating = <int>{}; // in-flight seqs of order-independent moves (kNetFloat)
  void Function(NetMove)? _listener;
  bool _replaying = false;
  Future<void> _sendChain = Future<void>.value();

  final Set<int> _connected = <int>{};
  final Set<int> _forfeited = <int>{};
  final Map<int, DateTime> _absentSince = <int, DateTime>{};
  final StreamController<NetLiveMessage> _live = StreamController<NetLiveMessage>.broadcast();
  int? _turnSeat;
  int _desyncs = 0;

  /// Fires when this phone's view diverged from the log (e.g. a send lost a race): rebuild + replay.
  final ValueNotifier<int> resyncRequests = ValueNotifier<int>(0);

  @override
  int get seatCount => _players.length;
  @override
  Set<int> get connectedSeats => Set<int>.unmodifiable(_connected);
  @override
  Set<int> get forfeitedSeats => Set<int>.unmodifiable(_forfeited);
  @override
  Listenable get changes => this;
  @override
  bool get replaying => _replaying;
  @override
  Stream<NetLiveMessage> get live => _live.stream;
  @override
  int get desyncs => _desyncs;
  @override
  set turnSeat(int? seat) => _turnSeat = seat;

  bool _presenceKnown = false;

  @override
  bool get isAuthority =>
      authoritySeat(
        seatCount: seatCount,
        mySeat: mySeat,
        connected: _connected,
        forfeited: _forfeited,
        presenceKnown: _presenceKnown || _c == null,
      ) ==
      mySeat;

  MatchEnd _endFrom(Map<String, dynamic> m) => MatchEnd(
        winners: ((m['winner_seats'] as List<dynamic>?) ?? const <dynamic>[]).map((dynamic e) => (e as num).toInt()).toList(),
        reason: '${m['reason'] ?? 'finished'}',
        scores: (m['scores'] as List<dynamic>?)?.map((dynamic e) => (e as num).toInt()).toList(),
      );

  void _connect() {
    final RealtimeChannel ch = _c!.channel('nxm:$matchId', opts: RealtimeChannelConfig(key: '$mySeat', self: false));
    ch
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'nx_match_moves',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'match_id', value: matchId),
          callback: (PostgresChangePayload p) => _onRow(p.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'nx_matches',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: matchId),
          callback: (PostgresChangePayload p) => _onMatch(p.newRecord),
        )
        .onBroadcast(
          event: 'live',
          callback: (Map<String, dynamic> p) {
            final dynamic payload = p['payload'] ?? p;
            if (payload is Map) {
              final Map<String, dynamic> d = Map<String, dynamic>.from(payload);
              _live.add(NetLiveMessage((d['s'] as num?)?.toInt() ?? -1, '${d['e']}',
                  Map<String, dynamic>.from((d['d'] as Map?) ?? const <String, dynamic>{})));
            }
          },
        )
        .onPresenceSync((_) => _syncPresence())
        .onPresenceJoin((_) => _syncPresence())
        .onPresenceLeave((_) => _syncPresence())
        .subscribe((RealtimeSubscribeStatus status, Object? error) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            unawaited(ch.track(<String, dynamic>{'seat': mySeat, 'uid': _uid}));
            unawaited(_catchUp());
          }
        });
    _ch = ch;
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => unawaited(_catchUp()));
    _watch = Timer.periodic(const Duration(seconds: 5), (_) => _watchAbsent());
    unawaited(_ping());
    _heartbeat = Timer.periodic(const Duration(seconds: 10), (_) => unawaited(_ping()));
  }

  bool _pingSupported = true;

  /// Match heartbeat (nx_match_ping, 20261123100000_g_online_multiplayer_v7): the server forfeits another seat or
  /// treats a player as gone only when this heartbeat has stopped. Silently off on a server without the function.
  Future<void> _ping() async {
    final SupabaseClient? c = _c;
    if (c == null || !_pingSupported || _disposed || isOver) return;
    try {
      final dynamic r = await c.rpc('nx_match_ping', params: <String, dynamic>{'p_match': matchId});
      if (r is Map && r['status'] is String && r['status'] != 'playing' && !_disposed) unawaited(_catchUp());
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' || e.message.contains('nx_match_ping')) _pingSupported = false;
    } catch (_) {}
  }

  void _syncPresence() {
    final RealtimeChannel? ch = _ch;
    if (ch == null) return;
    final Set<int> now = <int>{};
    for (final SinglePresenceState st in ch.presenceState()) {
      for (final Presence p in st.presences) {
        final dynamic s = p.payload['seat'];
        if (s is num) now.add(s.toInt());
      }
    }
    now.add(mySeat);
    final bool first = !_presenceKnown;
    _presenceKnown = true;
    if (first || !setEquals(now, _connected)) {
      _connected
        ..clear()
        ..addAll(now);
      for (final int s in now) {
        _absentSince.remove(s);
      }
      if (!_disposed) notifyListeners();
    }
  }

  void _watchAbsent() {
    if (isOver || !_presenceKnown || !isAuthority) return;
    final DateTime now = DateTime.now();
    for (int s = 0; s < seatCount; s++) {
      if (s == mySeat || _forfeited.contains(s) || _connected.contains(s)) continue;
      final DateTime since = _absentSince.putIfAbsent(s, () => now);
      final int limit =
          absenceLimitSec(onTurn: s == _turnSeat, graceSec: (settings['grace_sec'] as num?)?.toInt());
      if (now.difference(since).inSeconds >= limit) {
        _absentSince.remove(s);
        unawaited(_forfeitSeat(s));
      }
    }
  }

  Future<void> _forfeitSeat(int seat) async {
    try {
      final dynamic r = await _c?.rpc('nx_forfeit', params: <String, dynamic>{'p_match': matchId, 'p_seat': seat});
      // The server refuses when it still sees the seat (heartbeat / recent move): restart its absence clock.
      if (r is Map && r['ok'] == false && r['reason'] == 'active') _absentSince.remove(seat);
      await _catchUp();
    } catch (e) {
      debugPrint('forfeit seat $seat failed: $e');
    }
  }

  void _onMatch(Map<String, dynamic> m) {
    final String st = '${m['status']}';
    if (st != 'playing' && _status == 'playing') {
      _status = st;
      _end = _endFrom(m);
      if (!_disposed) notifyListeners();
    }
  }

  void _onRow(Map<String, dynamic> r) {
    final int seq = (r['seq'] as num).toInt();
    if (_rows.containsKey(seq) && !_ownSeqs.contains(seq)) return;
    String kind = '${r['kind']}';
    Map<String, dynamic> data = Map<String, dynamic>.from((r['move'] as Map?) ?? const <String, dynamic>{});
    if (kind == 'system' && data['_k'] is String) {
      kind = data['_k'] as String;
      data = Map<String, dynamic>.from(data)..remove('_k');
    }
    final NetMove m = NetMove(
      seq: seq,
      seat: (r['seat'] as num).toInt(),
      kind: kind,
      data: data,
      hash: r['hash'] as String?,
    );
    if (_floating.contains(seq) && r['by_user'] != _uid) {
      // An order-independent move of ours lost this seq: take the other row as normal; ours is re-posted later.
      _floating.remove(seq);
      _ownSeqs.remove(seq);
      if (_delivered >= seq) _delivered = seq - 1;
      _rows[seq] = m;
      _rowUser[seq] = '${r['by_user']}';
      _server.add(seq);
      _drain();
      return;
    }
    if (_ownSeqs.contains(seq) && r['by_user'] != _uid) {
      // Our optimistic seq was taken by someone else: the phone must resync.
      _rows[seq] = m;
      _rowUser[seq] = '${r['by_user']}';
      _server.add(seq);
      _requestResync();
      return;
    }
    _rows[seq] = m;
    _rowUser[seq] = '${r['by_user']}';
    _server.add(seq);
    if (m.isForfeit) {
      final int s = (m.data['seat'] as num?)?.toInt() ?? m.seat;
      if (_forfeited.add(s) && !_disposed) notifyListeners();
    }
    _drain();
  }

  void _drain() {
    if (_replaying) return;
    while (_rows.containsKey(_delivered + 1)) {
      _delivered++;
      if (_ownSeqs.contains(_delivered)) continue;
      final NetMove m = _rows[_delivered]!;
      _listener?.call(m);
    }
  }

  Future<void> _catchUp() async {
    if (_disposed) return;
    try {
      int from = 0;
      while (_server.contains(from + 1)) {
        from++;
      }
      final List<Map<String, dynamic>> rows = await _b.fetchMoves(from);
      if (_disposed) return;
      for (final Map<String, dynamic> r in rows) {
        _onRow(r);
      }
      if (_status == 'playing') {
        final Map<String, dynamic>? m = await _b.fetchStatus();
        if (m != null && !_disposed) _onMatch(m);
      }
    } catch (e) {
      debugPrint('catch-up failed: $e');
    }
  }

  void _requestResync() {
    _ownSeqs.clear();
    _floating.clear();
    // Optimistic rows that never reached the server log must not be replayed into the rebuilt game.
    _rows.removeWhere((int seq, _) => !_server.contains(seq));
    _rowUser.removeWhere((int seq, _) => !_server.contains(seq));
    // ...and the next post must take the seq after the real log, even before the game has rebuilt.
    int head = 0;
    while (_server.contains(head + 1)) {
      head++;
    }
    if (_delivered > head) _delivered = head;
    resyncRequests.value = resyncRequests.value + 1;
  }

  @override
  void listen(void Function(NetMove move) onMove, {VoidCallback? onReplayDone}) {
    _listener = onMove;
    _delivered = 0;
    _ownSeqs.clear();
    _replaying = true;
    unawaited(() async {
      await _catchUp();
      int seq = 1;
      while (_rows.containsKey(seq)) {
        final NetMove r = _rows[seq]!;
        if (_listener != onMove) return; // replaced by a newer game instance
        onMove(NetMove(seq: r.seq, seat: r.seat, kind: r.kind, data: r.data, hash: r.hash, replay: true));
        _delivered = seq;
        seq++;
      }
      _replaying = false;
      onReplayDone?.call();
      _drain();
    }());
  }

  @override
  Future<bool> send(Map<String, dynamic> data, {String kind = 'move', String? hash, int? asSeat}) {
    if (isOver) return Future<bool>.value(false);
    final int seat = asSeat ?? mySeat;
    if (data[kNetFloat] == true) return _sendFloating(data, kind, hash, seat);
    final int seq = _delivered + 1;
    _delivered = seq;
    _ownSeqs.add(seq);
    _rows[seq] = NetMove(seq: seq, seat: seat, kind: kind, data: data, hash: hash);
    _rowUser[seq] = _uid;
    final Completer<bool> done = Completer<bool>();
    _sendChain = _sendChain.then((_) async {
      bool ok = false;
      for (int attempt = 0; attempt < 3 && !ok; attempt++) {
        try {
          final dynamic r = await _push(seq, kind, data, hash, seat);
          if (r is Map && r['ok'] == true) {
            ok = true;
            _server.add(seq);
          } else {
            // 'seq': someone else's move landed first (e.g. a timeout); 'seat' / 'forfeited' / ...: refused.
            if (r is! Map || r['reason'] != 'seq') debugPrint('push move $seq refused: $r');
            break;
          }
        } catch (e) {
          debugPrint('push move $seq failed (try $attempt): $e');
          await Future<void>.delayed(Duration(milliseconds: 600 * (attempt + 1)));
        }
      }
      if (!ok && !isOver && !_disposed) {
        await _catchUp();
        if (_server.contains(seq) && _rowUser[seq] == _uid) {
          ok = true; // an earlier attempt landed, only its answer was lost
        } else {
          // Our optimistic move is not in the log (refused, lost, or its seq went to another phone): every later
          // seq this phone would post is off by one, so rebuild from the server log.
          _requestResync();
        }
      }
      done.complete(ok);
    });
    return done.future;
  }

  Future<dynamic> _push(int seq, String kind, Map<String, dynamic> data, String? hash, int seat) {
    final bool wrap = kWireWrapped.contains(kind);
    return _b.pushMove(seq, wrap ? 'system' : kind, wrap ? <String, dynamic>{...data, '_k': kind} : data, hash, seat);
  }

  /// Order-independent move (kNetFloat): its seq is taken when it is actually posted; when another phone's row wins
  /// that seq, the row is delivered and this move is re-posted at the next free seq. Never forces a resync.
  Future<bool> _sendFloating(Map<String, dynamic> data, String kind, String? hash, int seat) {
    final Completer<bool> done = Completer<bool>();
    _sendChain = _sendChain.then((_) async {
      bool ok = false;
      for (int attempt = 0; attempt < 12 && !ok && !_disposed && !isOver; attempt++) {
        int seq = _delivered + 1;
        while (_ownSeqs.contains(seq) || _rows.containsKey(seq)) {
          seq++;
        }
        if (seq != _delivered + 1) {
          await _catchUp();
          await Future<void>.delayed(const Duration(milliseconds: 200));
          continue;
        }
        _delivered = seq;
        _ownSeqs.add(seq);
        _floating.add(seq);
        _rows[seq] = NetMove(seq: seq, seat: seat, kind: kind, data: data, hash: hash);
        _rowUser[seq] = _uid;
        try {
          final dynamic r = await _push(seq, kind, data, hash, seat);
          if (r is Map && r['ok'] == true) {
            ok = true;
            _floating.remove(seq);
            _server.add(seq);
            break;
          }
          if (r is Map && r['reason'] != 'seq') debugPrint('push float $seq refused: $r');
          if (r is Map && r['reason'] == 'over') {
            _floating.remove(seq);
            break;
          }
        } catch (e) {
          debugPrint('push float $seq failed (try $attempt): $e');
          await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
        }
        // lost the seq (or failed): give it back, learn the log, try again at the next free seq
        _floating.remove(seq);
        if (_rowUser[seq] == _uid && !_server.contains(seq)) {
          _rows.remove(seq);
          _rowUser.remove(seq);
          _ownSeqs.remove(seq);
          if (_delivered >= seq) _delivered = seq - 1;
        }
        await _catchUp();
      }
      done.complete(ok);
    });
    return done.future;
  }

  /// Tests: where [sendLive] goes without a Realtime channel.
  void Function(NetLiveMessage m)? _testLive;
  @visibleForTesting
  set testLiveSink(void Function(NetLiveMessage m)? f) => _testLive = f;
  @visibleForTesting
  void injectLive(NetLiveMessage m) => _live.add(m);

  @override
  void sendLive(String event, Map<String, dynamic> data) {
    final RealtimeChannel? ch = _ch;
    if (ch == null) {
      _testLive?.call(NetLiveMessage(mySeat, event, data));
      return;
    }
    unawaited(ch.sendBroadcastMessage(event: 'live', payload: <String, dynamic>{'s': mySeat, 'e': event, 'd': data}));
  }

  @override
  Future<void> putSecret(int seat, String slot, Map<String, dynamic> data) async {
    if (seat < 0 || seat >= seatCount) return;
    await _c?.rpc('nx_put_secret', params: <String, dynamic>{
      'p_match': matchId,
      'p_user': _players[seat],
      'p_slot': slot,
      'p_data': data,
    });
  }

  @override
  Future<Map<String, dynamic>?> readSecret(String slot) async {
    try {
      final Map<String, dynamic>? r = await _c!
          .from('nx_match_secrets')
          .select('data')
          .eq('match_id', matchId)
          .eq('user_id', _uid)
          .eq('slot', slot)
          .maybeSingle();
      final dynamic d = r?['data'];
      return d is Map ? Map<String, dynamic>.from(d) : null;
    } catch (_) {
      return null;
    }
  }

  @override
  void verify(int seq, String? expected, String actual) {
    if (expected == null || expected == actual) return;
    _desyncs++;
    debugPrint('ANIX desync at seq $seq: expected $expected got $actual');
  }

  /// Report the final result. The server finalizes only when every player's report agrees (or the others are gone);
  /// until then it answers `{ok: true, pending: true}` and this waits (re-reporting now and then) for the final row.
  /// Conflicting reports end the match as 'disputed' (no rewards).
  Future<MatchEnd?> report(List<int> winners, List<int>? scores, {String? hash}) async {
    final Map<String, dynamic> params = <String, dynamic>{
      'p_match': matchId,
      'p_winners': winners,
      'p_scores': scores,
      'p_hash': hash,
      'p_reason': 'finished',
    };
    final SupabaseClient? c = _c;
    if (c == null) return _end;
    try {
      dynamic r = await c.rpc('nx_finish_match', params: params);
      for (int i = 0; i < 9 && !_disposed && r is Map && r['pending'] == true; i++) {
        await Future<void>.delayed(const Duration(seconds: 5));
        if (_disposed) break;
        final Map<String, dynamic>? m =
            await c.from('nx_matches').select('status').eq('id', matchId).maybeSingle();
        if (m != null && '${m['status']}' != 'playing') break;
        if (i.isOdd) r = await c.rpc('nx_finish_match', params: params);
      }
      final Map<String, dynamic>? m =
          await c.from('nx_matches').select('status, winner_seats, reason, scores').eq('id', matchId).maybeSingle();
      if (m != null && '${m['status']}' != 'playing') {
        _status = '${m['status']}';
        _end = _endFrom(m);
      }
      return _end;
    } catch (e) {
      debugPrint('report failed: $e');
      return null;
    }
  }

  /// Leave the running match (counts as forfeit).
  Future<void> forfeit() async {
    if (isOver) return;
    try {
      await _c?.rpc('nx_forfeit', params: <String, dynamic>{'p_match': matchId});
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _listener = null;
    _poll?.cancel();
    _watch?.cancel();
    _heartbeat?.cancel();
    final RealtimeChannel? ch = _ch;
    if (ch != null) unawaited(_c?.removeChannel(ch));
    unawaited(_live.close());
    resyncRequests.dispose();
    super.dispose();
  }
}
