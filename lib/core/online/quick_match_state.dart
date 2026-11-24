/// What the lobby screen does on each 4 s tick while it shows a room (pure, so the matchmaking loop is testable).
enum LobbyTick {
  /// Nothing to do (no room yet, or a match screen is open on top).
  idle,

  /// Waiting in a quick lobby: heartbeat + look for an older lobby to move into (nx_quick re-call).
  requeue,

  /// Waiting in a regular room: heartbeat only (nx_lobby_ping).
  ping,

  /// The quick lobby is gone under this player (closed, dropped as a silent seat after the app slept, or a match
  /// started without them): leave it and go back into matchmaking.
  rejoinQueue,

  /// The room's match is running and this player is in it: open the match screen.
  openMatch,
}

LobbyTick lobbyTick({
  required bool hasRoom,
  required bool quick,
  required String? status,
  required bool seated,
  required bool inMatch,
  required bool busy,
  String? matchId,
  String? lastMatchSeen,
}) {
  if (!hasRoom || inMatch) return LobbyTick.idle;
  if (status == 'playing' && seated && matchId != null && matchId != lastMatchSeen) return LobbyTick.openMatch;
  if (quick && !busy && (status == 'closed' || !seated)) return LobbyTick.rejoinQueue;
  if (status == 'lobby') return quick ? LobbyTick.requeue : LobbyTick.ping;
  return LobbyTick.idle;
}
