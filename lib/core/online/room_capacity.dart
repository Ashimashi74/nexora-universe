import '../../games/game_registry.dart';

/// ===================== ROOM CAPACITY =====================
/// One place for "how many people fit in this room".
///
/// Three numbers matter and they are deliberately different:
///  * **audience** — everyone inside a talk room (speakers + listeners). There is no
///    application-wide cap: the server stores `NULL` capacities for a room and never
///    refuses a listener. Only the room's own admission settings apply.
///  * **capacity** — how many of those people the manager puts on the *board*
///    (`nx_rooms.seats`). The manager chooses it; it can never exceed the game's
///    real mechanics ([GameCapacity.max]).
///  * **selected** — players actually picked for the next match.
///
/// The values mirror the server (`nx_game_bounds` on the games project). The server is
/// the authority: [RoomCapacity.fromRpc] reads the live numbers and every mutation
/// (capacity, pick, kick, start) is validated again in SQL. This class only mirrors them
/// for the UI, and [RoomCapacity.fallback] keeps the room usable when the RPC is not
/// deployed yet.
enum RoomCategory {
  /// Board / party games: 2–4 seats around one table.
  group,

  /// Team games: sides of equal size (finger soccer 1v1, 2v2, 3v3).
  team,

  /// One-against-one duels (billiards, backgammon, carrom, quiz…).
  duel,

  /// Social deduction: mafia & spy — many players, hidden roles.
  social,
}

/// Active-player bounds of one game, as the gameplay code actually implements them.
class GameCapacity {
  const GameCapacity(this.min, this.max, this.category);

  final int min;
  final int max;
  final RoomCategory category;

  /// Every legal capacity the manager can pick (team games only offer even sizes).
  List<int> get options => <int>[
        for (int n = min; n <= max; n++)
          if (category != RoomCategory.team || n.isEven) n,
      ];

  int clamp(int n) => n < min ? min : (n > max ? max : n);

  bool allows(int n) => n >= min && n <= max;

  /// Team games need two equally sized sides.
  bool isLegalTeamCount(int n) => n.isEven;

  @override
  String toString() => 'GameCapacity($min..$max, ${category.name})';
}

/// Category per game id. Kept next to the registry lookup so a new game can never be
/// added without a capacity decision: unknown ids fall back to the registry's own bounds.
RoomCategory categoryOf(String gameId) => switch (gameId) {
      'finger_soccer' => RoomCategory.team,
      'mafia' || 'spy_mafia' => RoomCategory.social,
      'carrom' || 'billiards' || 'backgammon' || 'quiz' || 'pool8' => RoomCategory.duel,
      _ => RoomCategory.group,
    };

/// Bounds derived from the game registry (which the server mirrors in `nx_game_bounds`).
GameCapacity capacityOf(String gameId) {
  final GameInfo? g = gameById(gameId);
  final int min = g?.onlineMinPlayers ?? 2;
  final int max = g?.onlineMaxPlayers ?? 2;
  return GameCapacity(min, max < min ? min : max, categoryOf(gameId));
}

/// Mirrors the server's `_nx_room_seat_limit`: the hard ceiling for picked players.
int roomSeatLimit(String gameId) => capacityOf(gameId).max;

/// Mirrors the server's `nx_game_bounds(...).min_seats`.
int roomMinPlayers(String gameId) => capacityOf(gameId).min;

/// Why a capacity / pick / start request is refused. The same rules run in SQL, so a
/// modified client can never widen them.
enum RoomRuleError {
  belowMinimum,
  aboveMaximum,
  belowSelected,
  notEvenTeams,
  roomPlaying,
  notManager,
  roomFull,
  noPickedPlayers,
}

extension RoomRuleErrorText on RoomRuleError {
  String message(bool fa, {int? value}) => switch (this) {
        RoomRuleError.belowMinimum => fa ? 'حداقل ${value ?? 2} بازیکن لازم است' : 'At least ${value ?? 2} players are needed',
        RoomRuleError.aboveMaximum => fa ? 'این بازی حداکثر ${value ?? 0} بازیکن دارد' : 'This game takes at most ${value ?? 0} players',
        RoomRuleError.belowSelected =>
          fa ? 'اول بازیکن‌ها را کم کن، بعد ظرفیت را' : 'Remove players before lowering the capacity',
        RoomRuleError.notEvenTeams => fa ? 'بازی تیمی به دو طرف برابر نیاز دارد' : 'Team games need two equal sides',
        RoomRuleError.roomPlaying => fa ? 'بازی شروع شده است' : 'The match has already started',
        RoomRuleError.notManager => fa ? 'فقط مدیر اتاق' : 'The room manager only',
        RoomRuleError.roomFull => fa ? 'ظرفیت بازیکن‌ها پر است' : 'The player capacity is full',
        RoomRuleError.noPickedPlayers => fa ? 'هیچ بازیکنی انتخاب نشده' : 'No players were picked',
      };
}

/// A room's live capacity state (server truth, with a local fallback).
class RoomCapacity {
  const RoomCapacity({
    required this.gameId,
    required this.minPlayers,
    required this.maxPlayers,
    required this.capacity,
    this.selected = 0,
    this.audience = 0,
    this.locked = false,
    this.isManager = false,
    this.status = 'lobby',
    this.fromServer = false,
  });

  /// Local mirror when the capacity RPC is unavailable (older server): game bounds from
  /// the registry, capacity from the room row.
  factory RoomCapacity.fallback(String gameId, {int? capacity, int selected = 0, int audience = 0, bool locked = false, bool isManager = false, String status = 'lobby'}) {
    final GameCapacity b = capacityOf(gameId);
    final int cap = b.clamp(capacity ?? b.max);
    return RoomCapacity(
      gameId: gameId,
      minPlayers: b.min,
      maxPlayers: b.max,
      capacity: cap < selected ? selected : cap,
      selected: selected,
      audience: audience,
      locked: locked,
      isManager: isManager,
      status: status,
    );
  }

  /// `nx_room_capacity(p_room)` payload (jsonb).
  factory RoomCapacity.fromRpc(Map<String, dynamic> raw) {
    int i(String k, int d) => (raw[k] as num?)?.toInt() ?? d;
    final String game = '${raw['game'] ?? raw['selected_game'] ?? 'finger_soccer'}';
    final GameCapacity b = capacityOf(game);
    final int min = i('min_players', b.min);
    final int max = i('max_players', b.max);
    final int selected = i('selected', 0);
    final int cap = i('capacity', max);
    return RoomCapacity(
      gameId: game,
      minPlayers: min,
      maxPlayers: max < min ? min : max,
      capacity: cap < selected ? selected : cap,
      selected: selected,
      audience: i('audience', 0),
      locked: raw['locked'] == true,
      isManager: raw['is_manager'] == true,
      status: '${raw['status'] ?? 'lobby'}',
      fromServer: true,
    );
  }

  final String gameId;
  final int minPlayers;
  final int maxPlayers;

  /// Active-player capacity of this room (server: `nx_rooms.seats`).
  final int capacity;

  /// Players already picked for the next match.
  final int selected;

  /// Everyone inside the room (speakers + listeners). Unlimited.
  final int audience;

  /// Manager switched admission off: new people need to be let in.
  final bool locked;
  final bool isManager;
  final String status;

  /// True when the numbers came from the server RPC (not the local fallback).
  final bool fromServer;

  GameCapacity get bounds => GameCapacity(minPlayers, maxPlayers, categoryOf(gameId));

  bool get playing => status == 'playing';
  bool get isFull => selected >= capacity;
  int get freeSeats => capacity - selected;
  bool get canManage => isManager && !playing;

  /// Capacities the manager may choose: the game's real range, but never below what is
  /// already picked.
  List<int> get capacityOptions {
    final List<int> all = bounds.options;
    final List<int> ok = all.where((int n) => n >= selected).toList();
    return ok.isEmpty ? <int>[selected] : ok;
  }

  /// Rounds a capacity to a legal team size for team games (even numbers), otherwise
  /// clamps into the game's range. Used by the +/- stepper.
  int step(int delta) {
    int next = capacity + delta;
    if (bounds.category == RoomCategory.team && next.isOdd) next += delta.sign;
    return bounds.clamp(next < selected ? selected : next);
  }

  /// Validates the manager's new capacity before it goes to the server.
  RoomRuleError? checkCapacity(int next) {
    if (!isManager) return RoomRuleError.notManager;
    if (playing) return RoomRuleError.roomPlaying;
    if (next < minPlayers) return RoomRuleError.belowMinimum;
    if (next > maxPlayers) return RoomRuleError.aboveMaximum;
    if (next < selected) return RoomRuleError.belowSelected;
    if (bounds.category == RoomCategory.team && next.isOdd) return RoomRuleError.notEvenTeams;
    return null;
  }

  /// Validates a start request with the players currently picked.
  RoomRuleError? checkStart(int picked) {
    if (!isManager) return RoomRuleError.notManager;
    if (playing) return RoomRuleError.roomPlaying;
    if (picked < minPlayers) return RoomRuleError.belowMinimum;
    if (picked > capacity) return RoomRuleError.aboveMaximum;
    if (bounds.category == RoomCategory.team && picked.isOdd) return RoomRuleError.notEvenTeams;
    return null;
  }

  /// Validates adding one more picked player.
  RoomRuleError? checkPick(int picked) {
    if (picked >= capacity) return RoomRuleError.roomFull;
    if (picked >= maxPlayers) return RoomRuleError.aboveMaximum;
    return null;
  }

  RoomCapacity copyWith({int? capacity, int? selected, int? audience, bool? locked, bool? isManager, String? status, bool? fromServer}) =>
      RoomCapacity(
        gameId: gameId,
        minPlayers: minPlayers,
        maxPlayers: maxPlayers,
        capacity: capacity ?? this.capacity,
        selected: selected ?? this.selected,
        audience: audience ?? this.audience,
        locked: locked ?? this.locked,
        isManager: isManager ?? this.isManager,
        status: status ?? this.status,
        fromServer: fromServer ?? this.fromServer,
      );
}
