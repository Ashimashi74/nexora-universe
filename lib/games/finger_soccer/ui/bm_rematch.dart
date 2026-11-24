// Finger soccer v13 (owner request 2026-11-24, "بازی مجدد"): rematch at the end of an ONLINE match.
//
// Flow (every message rides the match's existing Realtime channel as an ephemeral 'fs_rm' live message, so nothing
// is written to the finished match's move log):
//   1. A player taps "بازی مجدد" on the end-of-match score table -> {op: req}. The others see
//      "حریف درخواست بازی مجدد داد" with Accept / Decline ({op: acc} / {op: dec}).
//   2. No answer within [kFsRematchTimeoutMs] -> "حریف پاسخ نداد" ({op: cancel} clears the prompt on the other side).
//      Two players asking at the same time count as both accepting.
//   3. Everyone accepted -> a new match for the same room and players is created through the normal server path
//      (nx_start_match for lobby / quick rooms, nx_start_room_match for talk rooms; both return the room's running
//      match when it already exists, so several phones calling is harmless). Seat 0 calls at once, the others poll
//      the room row and take the 'go' message, and try the call themselves after a few seconds (room host on another
//      seat). Each phone then stores its own team / formation ([FsRematchCarry]) and leaves the finished match page;
//      the room page opens the new match as it does for every match, and the new match logs the carried setups at
//      once (host keeps pitch + ball, as in every match), so it starts with the same teams and a 0-0 score.
//   4. A player who left (presence gone / forfeited) -> "حریف از بازی خارج شد" and the button is disabled.
// Tournament games never offer a rematch (the bracket decides the next game).
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:nexora/core/online/match_link.dart';
import 'package:nexora/core/online/online_service.dart';
import 'package:nexora/games/core/net_link.dart';
import '../../../core/ui2/luxe.dart';

/// Live event name of every rematch message.
const String kFsRematchEvent = 'fs_rm';

/// How long a request waits for an answer (ms).
const int kFsRematchTimeoutMs = 20000;

/// How long the new match may take to appear once everyone accepted (ms).
const int kFsRematchStartMs = 15000;

enum FsRematchPhase {
  /// Nothing asked yet (or a request lapsed / was declined by this phone).
  idle,

  /// This phone asked (or accepted) and waits for the others.
  waiting,

  /// Another player asked: Accept / Decline.
  incoming,

  /// Everyone accepted: the new match is being created / opened.
  starting,

  /// Our request ran out ("حریف پاسخ نداد").
  noAnswer,

  /// The other player declined.
  declined,

  /// A player left: the button is disabled.
  opponentLeft,

  /// The new match could not be created.
  failed,
}

/// Pure rematch state machine (no I/O; tests drive it directly). Times are ms on any monotonic clock.
class FsRematchMachine {
  FsRematchMachine({required this.mySeat, required this.seatCount, this.timeoutMs = kFsRematchTimeoutMs});

  final int mySeat, seatCount, timeoutMs;
  FsRematchPhase phase = FsRematchPhase.idle;

  /// Seats that want the rematch in the current round.
  final Set<int> accepted = <int>{};

  /// Round id (the requester's random number), echoed by answers.
  int? nonce;
  double deadline = 0;

  /// Seat whose request is shown ([FsRematchPhase.incoming]).
  int? fromSeat;

  /// Id of the new match once known.
  String? matchId;

  bool get allAccepted => accepted.length >= seatCount;
  bool get canRequest => const <FsRematchPhase>{
        FsRematchPhase.idle,
        FsRematchPhase.noAnswer,
        FsRematchPhase.declined,
        FsRematchPhase.failed,
      }.contains(phase);

  /// A request / answer / start is in progress (the end screen stays up).
  bool get busy =>
      phase == FsRematchPhase.waiting || phase == FsRematchPhase.incoming || phase == FsRematchPhase.starting;

  void _toStarting(double now) {
    phase = FsRematchPhase.starting;
    deadline = now + kFsRematchStartMs;
  }

  /// This phone asks. Returns the message to send (null when it cannot ask now).
  Map<String, dynamic>? request(double now, int n) {
    if (!canRequest) return null;
    phase = FsRematchPhase.waiting;
    accepted
      ..clear()
      ..add(mySeat);
    nonce = n;
    fromSeat = mySeat;
    deadline = now + timeoutMs;
    return <String, dynamic>{'op': 'req', 'n': n};
  }

  /// This phone accepts the shown request.
  Map<String, dynamic>? accept(double now) {
    if (phase != FsRematchPhase.incoming) return null;
    accepted.add(mySeat);
    if (allAccepted) {
      _toStarting(now);
    } else {
      phase = FsRematchPhase.waiting;
      deadline = now + timeoutMs;
    }
    return <String, dynamic>{'op': 'acc', 'n': nonce};
  }

  /// This phone declines the shown request.
  Map<String, dynamic>? decline() {
    if (phase != FsRematchPhase.incoming) return null;
    final int? n = nonce;
    phase = FsRematchPhase.idle;
    accepted.clear();
    nonce = null;
    return <String, dynamic>{'op': 'dec', 'n': n};
  }

  /// A message from [seat]. Never answers by itself (the user does), so it returns nothing.
  void receive(int seat, Map<String, dynamic> d, double now) {
    if (seat == mySeat || seat < 0 || seat >= seatCount) return;
    final String op = '${d['op']}';
    final int? n = (d['n'] as num?)?.toInt();
    switch (op) {
      case 'req':
        if (phase == FsRematchPhase.starting || phase == FsRematchPhase.opponentLeft) return;
        if (phase == FsRematchPhase.waiting) {
          // both asked (crossing requests) or another seat of a team game joined in: that player accepts too
          accepted.add(seat);
          if (allAccepted) _toStarting(now);
          return;
        }
        phase = FsRematchPhase.incoming;
        nonce = n;
        fromSeat = seat;
        accepted
          ..clear()
          ..add(seat);
        deadline = now + timeoutMs;
        return;
      case 'acc':
        if (phase != FsRematchPhase.waiting && phase != FsRematchPhase.incoming) return;
        accepted.add(seat);
        if (phase == FsRematchPhase.waiting && allAccepted) _toStarting(now);
        return;
      case 'dec':
        if ((phase == FsRematchPhase.waiting || phase == FsRematchPhase.incoming) && (n == null || n == nonce)) {
          phase = phase == FsRematchPhase.waiting ? FsRematchPhase.declined : FsRematchPhase.idle;
          accepted.clear();
        }
        return;
      case 'cancel':
        if (phase == FsRematchPhase.incoming && (n == null || n == nonce)) {
          phase = FsRematchPhase.idle;
          accepted.clear();
        }
        return;
      case 'go':
        final dynamic m = d['m'];
        if (m is String && m.isNotEmpty && phase != FsRematchPhase.opponentLeft) {
          matchId = m;
          if (phase != FsRematchPhase.starting) _toStarting(now);
        }
        return;
    }
  }

  /// Timeouts. Returns a message to send (the requester's 'cancel'), or null.
  Map<String, dynamic>? tick(double now) {
    if (now <= deadline) return null;
    switch (phase) {
      case FsRematchPhase.waiting:
        phase = FsRematchPhase.noAnswer;
        accepted.clear();
        return <String, dynamic>{'op': 'cancel', 'n': nonce};
      case FsRematchPhase.incoming:
        phase = FsRematchPhase.idle;
        accepted.clear();
        return null;
      case FsRematchPhase.starting:
        if (matchId == null) phase = FsRematchPhase.failed;
        return null;
      default:
        return null;
    }
  }

  /// Presence: [present] = seats still in the match (connected and not forfeited). While the new match is starting a
  /// player leaving the old page is expected and ignored.
  void presence(Set<int> present) {
    if (phase == FsRematchPhase.starting) return;
    bool gone = false;
    for (int s = 0; s < seatCount; s++) {
      if (s != mySeat && !present.contains(s)) gone = true;
    }
    if (gone) {
      phase = FsRematchPhase.opponentLeft;
      accepted.clear();
    } else if (phase == FsRematchPhase.opponentLeft) {
      phase = FsRematchPhase.idle; // back after a brief disconnect
    }
  }
}

/// The team / formation (and the host's pitch / ball) a phone carries into the rematch, read by the new match's view.
class FsRematchCarry {
  FsRematchCarry._(this.fromMatch, this.names, this.setup, this.at);
  final String fromMatch;
  final List<String> names;

  /// This phone's own setup move ({'a': 'setup', team, form, field, ball}).
  final Map<String, dynamic> setup;
  final DateTime at;

  static FsRematchCarry? _pending;

  static void put(String fromMatch, List<String> names, Map<String, dynamic> setup) =>
      _pending = FsRematchCarry._(fromMatch, List<String>.from(names), Map<String, dynamic>.from(setup), DateTime.now());

  /// The carried setup for a newly opened match with the same players (once; null when there is none).
  static Map<String, dynamic>? take(NetLink net) {
    final FsRematchCarry? c = _pending;
    if (c == null) return null;
    if (DateTime.now().difference(c.at) > const Duration(minutes: 2)) {
      _pending = null;
      return null;
    }
    if (net.matchId == c.fromMatch || !_same(net.names, c.names)) return null;
    _pending = null;
    return c.setup;
  }

  static bool _same(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @visibleForTesting
  static void clear() => _pending = null;
}

/// Creates the next match of the room (null when this phone may not / could not).
typedef FsRematchStarter = Future<String?> Function();

/// Reads the room's running match id when it is a new one (null when not yet).
typedef FsRematchRoomPoll = Future<String?> Function();

/// Wires [FsRematchMachine] to the match link (live messages, presence) and the server.
class FsRematchController extends ChangeNotifier {
  FsRematchController({
    required this.net,
    required this.starter,
    required this.roomPoll,
    required this.onGo,
    double Function()? clock,
    math.Random? rnd,
  })  : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch.toDouble()),
        _rnd = rnd ?? math.Random(),
        m = FsRematchMachine(mySeat: net.mySeat, seatCount: net.seatCount) {
    _sub = net.live.listen(_onLive, onError: (Object _) {});
    net.changes.addListener(_onPresence);
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    _onPresence();
  }

  /// A controller for a live Supabase match, or null when a rematch is not offered (tournament game, no room).
  static FsRematchController? forLink(NetLink? net, {required String? tournamentMatchId, required void Function(String) onGo}) {
    if (net is! SupabaseMatchLink || tournamentMatchId != null) return null;
    if (!fsRematchAllowed(net.settings, roomId: net.roomId)) return null;
    final SupabaseClient? c = OnlineService.current?.games;
    if (c == null) return null;
    final String room = net.roomId!;
    final String old = net.matchId;
    final String fn = net.settings.containsKey('room_prefs') ? 'nx_start_room_match' : 'nx_start_match';
    return FsRematchController(
      net: net,
      starter: () => fsRematchStart(c, fn, room, old),
      roomPoll: () => fsRematchPollRoom(c, room, old),
      onGo: onGo,
    );
  }

  final NetLink net;
  final FsRematchStarter starter;
  final FsRematchRoomPoll roomPoll;
  final void Function(String matchId) onGo;
  final double Function() _clock;
  final math.Random _rnd;
  final FsRematchMachine m;
  StreamSubscription<NetLiveMessage>? _sub;
  Timer? _timer;
  bool _disposed = false;
  bool _starting = false;
  bool _went = false;
  bool _tableDone = false;
  final Completer<void> _hold = Completer<void>();

  FsRematchPhase get phase => m.phase;

  /// Completes once the end screen may give way to the host's result overlay (table over and nothing pending).
  Future<void> get released => _hold.future;

  void _send(Map<String, dynamic>? msg) {
    if (msg == null) return;
    try {
      net.sendLive(kFsRematchEvent, msg);
    } catch (_) {}
  }

  void request() {
    _send(m.request(_clock(), 1 + _rnd.nextInt(1 << 30)));
    _changed();
  }

  void accept() {
    _send(m.accept(_clock()));
    _changed();
  }

  void decline() {
    _send(m.decline());
    _changed();
  }

  /// The score table's countdown is over.
  void tableDone() {
    _tableDone = true;
    _checkHold();
  }

  void _onLive(NetLiveMessage msg) {
    if (_disposed || msg.event != kFsRematchEvent) return;
    m.receive(msg.seat, msg.data, _clock());
    _changed();
  }

  void _onPresence() {
    if (_disposed) return;
    final Set<int> present = <int>{
      for (final int s in net.connectedSeats)
        if (!net.forfeitedSeats.contains(s)) s
    };
    final FsRematchPhase was = m.phase;
    m.presence(present);
    if (was != m.phase) _changed();
  }

  void _tick() {
    if (_disposed) return;
    final FsRematchPhase was = m.phase;
    _send(m.tick(_clock()));
    if (was != m.phase) _changed();
  }

  void _changed() {
    if (_disposed) return;
    if (m.phase == FsRematchPhase.starting) {
      final String? id = m.matchId;
      if (id != null) {
        _go(id);
      } else if (!_starting) {
        unawaited(_start());
      }
    }
    _checkHold();
    notifyListeners();
  }

  /// Everyone accepted: create (seat 0 at once, the others after a few seconds) or find the new match.
  Future<void> _start() async {
    _starting = true;
    final double t0 = _clock();
    bool tried = false;
    if (net.mySeat == 0) {
      tried = true;
      final String? id = await starter();
      if (id != null) {
        _send(<String, dynamic>{'op': 'go', 'm': id});
        _go(id);
        return;
      }
    }
    while (!_disposed && !_went && m.phase == FsRematchPhase.starting) {
      final String? id = await roomPoll();
      if (id != null) {
        _go(id);
        return;
      }
      if (!tried && _clock() - t0 > 5000) {
        tried = true;
        final String? s = await starter();
        if (s != null) {
          _send(<String, dynamic>{'op': 'go', 'm': s});
          _go(s);
          return;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    }
  }

  void _go(String id) {
    if (_went || _disposed) return;
    _went = true;
    m.matchId = id;
    onGo(id);
  }

  void _checkHold() {
    if (_hold.isCompleted) return;
    if (_tableDone && !m.busy) _hold.complete();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_sub?.cancel());
    net.changes.removeListener(_onPresence);
    if (!_hold.isCompleted) _hold.complete();
    super.dispose();
  }
}

/// A rematch is offered for room matches that are not tournament games.
bool fsRematchAllowed(Map<String, dynamic> settings, {required String? roomId}) =>
    roomId != null && !settings.containsKey('tournament') && !settings.containsKey('tmatch');

/// Starts the room's next match ([fn] = nx_start_match / nx_start_room_match). While the server still has the
/// finished match as the room's running one (its result is being booked) it returns that id: retried for a few
/// seconds until a new one comes back. Null when this phone may not start it (not the room's host / manager) or it
/// failed.
Future<String?> fsRematchStart(SupabaseClient c, String fn, String room, String oldMatch) async {
  for (int i = 0; i < 6; i++) {
    try {
      final dynamic r = await c.rpc(fn, params: <String, dynamic>{'p_room': room});
      final String? mid = r is Map ? r['match_id'] as String? : null;
      if (mid != null && mid != oldMatch) return mid;
    } on PostgrestException catch (e) {
      final String msg = e.message.toLowerCase();
      if (msg.contains('host only') || msg.contains('manager only') || msg.contains('need')) return null;
    } catch (_) {}
    await Future<void>.delayed(Duration(milliseconds: 700 * (i + 1)));
  }
  return null;
}

/// The room's running match when it is a new one.
Future<String?> fsRematchPollRoom(SupabaseClient c, String room, String oldMatch) async {
  try {
    final Map<String, dynamic>? r =
        await c.from('nx_rooms').select('status, match_id').eq('id', room).maybeSingle();
    final String? mid = r?['match_id'] as String?;
    if (r != null && r['status'] == 'playing' && mid != null && mid != oldMatch) return mid;
  } catch (_) {}
  return null;
}

/// The rematch strip on the end-of-match score table (black-gold Luxe look like the lobby).
class FsRematchPanel extends StatelessWidget {
  const FsRematchPanel({super.key, required this.c, required this.fa});
  final FsRematchController c;
  final bool fa;

  String _t(String f, String e) => fa ? f : e;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (BuildContext context, _) {
        final FsRematchPhase p = c.phase;
        final List<Widget> kids = <Widget>[];
        String? note;
        Color noteColor = Luxe.mute;
        switch (p) {
          case FsRematchPhase.incoming:
            note = _t('حریف درخواست بازی مجدد داد', 'Your opponent wants a rematch');
            noteColor = Luxe.gold2;
            kids.add(Row(children: <Widget>[
              Expanded(
                child: LuxeButton(
                  label: _t('رد', 'Decline'),
                  kind: LuxeButtonKind.ghost,
                  height: 44,
                  uppercase: false,
                  onTap: c.decline,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: LuxeButton(
                  label: _t('قبول', 'Accept'),
                  icon: Icons.check_rounded,
                  height: 44,
                  uppercase: false,
                  onTap: c.accept,
                ),
              ),
            ]));
            break;
          case FsRematchPhase.waiting:
            note = _t('در انتظار پاسخ حریف…', 'Waiting for your opponent…');
            kids.add(LuxeButton(label: _t('بازی مجدد', 'Rematch'), height: 44, uppercase: false, loading: true, onTap: () {}));
            break;
          case FsRematchPhase.starting:
            note = _t('بازی مجدد شروع می‌شود…', 'Starting the rematch…');
            noteColor = Luxe.gold2;
            kids.add(LuxeButton(label: _t('بازی مجدد', 'Rematch'), height: 44, uppercase: false, loading: true, onTap: () {}));
            break;
          case FsRematchPhase.opponentLeft:
            note = _t('حریف از بازی خارج شد', 'Your opponent left');
            noteColor = const Color(0xFFFF8A9A);
            kids.add(LuxeButton(
                label: _t('بازی مجدد', 'Rematch'), icon: Icons.replay_rounded, height: 44, uppercase: false, onTap: null));
            break;
          case FsRematchPhase.idle:
          case FsRematchPhase.noAnswer:
          case FsRematchPhase.declined:
          case FsRematchPhase.failed:
            if (p == FsRematchPhase.noAnswer) note = _t('حریف پاسخ نداد', 'No answer from your opponent');
            if (p == FsRematchPhase.declined) note = _t('حریف بازی مجدد را رد کرد', 'Your opponent declined');
            if (p == FsRematchPhase.failed) note = _t('شروع بازی مجدد ممکن نشد', 'Could not start the rematch');
            kids.add(LuxeButton(
                label: _t('بازی مجدد', 'Rematch'),
                icon: Icons.replay_rounded,
                height: 44,
                uppercase: false,
                onTap: c.request));
            break;
        }
        return Directionality(
          textDirection: fa ? TextDirection.rtl : TextDirection.ltr,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            decoration: BoxDecoration(
              color: Luxe.panel.withValues(alpha: .92),
              borderRadius: BorderRadius.circular(LuxeRadius.md),
              border: Border.all(color: Luxe.gold3),
              boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x99000000), blurRadius: 14, offset: Offset(0, 4))],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              if (note != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(note,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: noteColor, fontWeight: FontWeight.w800, fontSize: 14)),
                ),
              ...kids,
            ]),
          ),
        );
      },
    );
  }
}
