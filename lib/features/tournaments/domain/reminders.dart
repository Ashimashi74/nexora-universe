// Pure planning of the device-side tournament reminders (no Flutter imports), used by TournamentWatcher.
//
// The watcher schedules local notifications 10 minutes before (a) the start of every tournament the player is in
// and (b) every scheduled match of theirs. A reminder that no longer applies (withdrawn, removed, cancelled,
// already live, match moved or finished) has to be cancelled on the device, otherwise it fires for nothing.

/// One reminder the device should hold.
class TReminder {
  const TReminder({required this.key, required this.at, required this.tournamentId, required this.kind});

  /// Stable key (`soon:<tournament>` / `msoon:<match>`); the notification id is derived from it.
  final String key;

  /// When it fires (UTC).
  final DateTime at;
  final String tournamentId;

  /// 'start' | 'checkin' | 'match'.
  final String kind;

  String get payload => '/tournaments/$tournamentId';
}

/// Minimal tournament facts for planning.
class TRemTournament {
  const TRemTournament({required this.id, required this.status, required this.startAt, this.checkin = false});
  final String id;
  final String status;
  final DateTime startAt;
  final bool checkin;
}

/// Minimal match facts for planning.
class TRemMatch {
  const TRemMatch({required this.id, required this.tournamentId, required this.status, this.scheduledAt});
  final String id;
  final String tournamentId;
  final String status;
  final DateTime? scheduledAt;
}

class ReminderPlanner {
  const ReminderPlanner._();

  static const Duration lead = Duration(minutes: 10);

  /// Notification id for a key (fits a 32-bit Android id).
  static int idFor(String key) {
    // FNV-1a: stable across runs and isolates (String.hashCode is not guaranteed to be).
    int h = 0x811c9dc5;
    for (final int c in key.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h & 0x3fffffff;
  }

  /// Reminders the device should hold now. [myStatus]: tournament id → my entry status.
  static List<TReminder> plan({
    required DateTime nowUtc,
    required Iterable<TRemTournament> tournaments,
    required Map<String, String> myStatus,
    required Iterable<TRemMatch> myMatches,
  }) {
    final List<TReminder> out = <TReminder>[];
    final Map<String, TRemTournament> byId = <String, TRemTournament>{for (final TRemTournament t in tournaments) t.id: t};
    for (final TRemTournament t in tournaments) {
      final String? st = myStatus[t.id];
      if (st == null) continue;
      if (!const <String>{'scheduled', 'registering', 'closed', 'drawn'}.contains(t.status)) continue;
      // approved players are reminded of the start; with check-in also waitlisted ones (they may take a freed place)
      final bool wanted = st == 'approved' || (t.checkin && st == 'waitlist' && t.status != 'drawn');
      if (!wanted) continue;
      final DateTime at = t.startAt.toUtc().subtract(lead);
      if (!at.isAfter(nowUtc)) continue;
      out.add(TReminder(key: 'soon:${t.id}', at: at, tournamentId: t.id, kind: t.checkin && t.status != 'drawn' ? 'checkin' : 'start'));
    }
    for (final TRemMatch m in myMatches) {
      final DateTime? s = m.scheduledAt;
      if (m.status != 'scheduled' || s == null) continue;
      final TRemTournament? t = byId[m.tournamentId];
      if (t != null && (t.status == 'finished' || t.status == 'cancelled')) continue;
      final DateTime at = s.toUtc().subtract(lead);
      if (!at.isAfter(nowUtc)) continue;
      out.add(TReminder(key: 'msoon:${m.id}', at: at, tournamentId: m.tournamentId, kind: 'match'));
    }
    return out;
  }

  /// Pending tournament reminder ids on the device that are not in [plan] any more and must be cancelled.
  /// [pending]: id → payload of the device's pending notifications (only tournament payloads are considered).
  static Set<int> stale(Map<int, String?> pending, Iterable<TReminder> plan) {
    final Set<int> keep = <int>{for (final TReminder r in plan) idFor(r.key)};
    return <int>{
      for (final MapEntry<int, String?> e in pending.entries)
        if ((e.value ?? '').startsWith('/tournaments') && !keep.contains(e.key)) e.key,
    };
  }
}
