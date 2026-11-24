import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/online/room_capacity.dart';

void main() {
  group('game capacity table', () {
    // The same table the server uses (supabase/games/migrations/…_g_room_capacity_v5.sql, nx_game_bounds).
    const Map<String, (int, int)> expected = <String, (int, int)>{
      'finger_soccer': (2, 6),
      'carrom': (2, 2),
      'billiards': (2, 2),
      'pool8': (2, 2),
      'backgammon': (2, 2),
      'quiz': (2, 2),
      'ludo': (2, 4),
      'snakes_ladders': (2, 4),
      'uno': (2, 4),
      'mafia': (6, 12),
      'spy_mafia': (4, 8),
      'kart_racing': (2, 4),
      'obstacle_race': (2, 4),
      'bomb_arena': (2, 4),
      'mini_golf': (2, 4),
      'basketball_battle': (2, 4),
      // Games added to the arcade as real gameplay (they used to be lobby ids with no game).
      'endless_runner': (1, 1),
      'tetris_rush': (1, 1),
      'helix_jump': (1, 1),
      'fruit_ninja': (1, 1),
      'geo_dash': (1, 1),
      'traffic_racer': (1, 1),
      'stack_tower': (1, 1),
      'bubble_shooter': (1, 1),
      'knife_hit': (1, 1),
      'game_2048': (1, 1),
    };

    test('bounds match the server table', () {
      expected.forEach((String game, (int, int) bounds) {
        final GameCapacity c = capacityOf(game);
        expect(c.min, bounds.$1, reason: '$game min');
        expect(c.max, bounds.$2, reason: '$game max');
      });
    });

    test('categories decide the team rule', () {
      expect(categoryOf('finger_soccer'), RoomCategory.team);
      expect(categoryOf('mafia'), RoomCategory.social);
      expect(categoryOf('billiards'), RoomCategory.duel);
      expect(categoryOf('ludo'), RoomCategory.group);
    });

    test('clamp and options', () {
      final GameCapacity fs = capacityOf('finger_soccer');
      expect(fs.clamp(0), 2);
      expect(fs.clamp(9), 6);
      expect(fs.options, <int>[2, 4, 6]);
      expect(capacityOf('ludo').options, <int>[2, 3, 4]);
    });
  });

  group('room capacity rules', () {
    RoomCapacity room({int capacity = 4, int picked = 2, bool manager = true, String game = 'finger_soccer'}) =>
        RoomCapacity.fallback(game, capacity: capacity, selected: picked, isManager: manager);

    test('parses the server payload', () {
      final RoomCapacity c = RoomCapacity.fromRpc(<String, dynamic>{
        'game': 'mafia',
        'min_players': 6,
        'max_players': 12,
        'capacity': 9,
        'selected': 7,
        'audience': 14,
        'locked': true,
        'is_manager': true,
        'status': 'lobby',
      });
      expect(c.minPlayers, 6);
      expect(c.maxPlayers, 12);
      expect(c.capacity, 9);
      expect(c.selected, 7);
      expect(c.audience, 14, reason: 'audience is not capped by the board capacity');
      expect(c.locked, isTrue);
      expect(c.fromServer, isTrue);
      expect(c.freeSeats, 2);
    });

    test('a manager may not go below the game minimum or above its maximum', () {
      final RoomCapacity c = room();
      expect(c.checkCapacity(1), RoomRuleError.belowMinimum);
      expect(c.checkCapacity(7), RoomRuleError.aboveMaximum);
      expect(c.checkCapacity(2), isNull);
      expect(c.checkCapacity(6), isNull);
    });

    test('capacity can never drop below the players already picked', () {
      final RoomCapacity c = room(capacity: 6, picked: 4);
      expect(c.checkCapacity(3), RoomRuleError.belowSelected);
      expect(c.checkCapacity(4), isNull);
    });

    test('team games step in even sizes and refuse odd starts', () {
      final RoomCapacity c = room(capacity: 4, picked: 2);
      expect(c.step(1), 6);
      expect(c.step(-1), 2);
      expect(c.checkStart(3), RoomRuleError.notEvenTeams);
      expect(c.checkStart(4), isNull);
    });

    test('picks stop at the room capacity, not at the game maximum', () {
      final RoomCapacity c = room(capacity: 2, picked: 2);
      expect(c.checkPick(2), RoomRuleError.roomFull);
      expect(room(capacity: 4, picked: 2).checkPick(2), isNull);
    });

    test('spectators are never refused by the board rules', () {
      final RoomCapacity c = room(capacity: 2, picked: 2);
      expect(c.isFull, isTrue);
      expect(c.audience, 0);
      expect(c.copyWith(audience: 120).audience, 120);
    });

    test('only the manager can change anything, and not during a match', () {
      expect(room(manager: false).checkCapacity(4), RoomRuleError.notManager);
      final RoomCapacity playing = RoomCapacity.fallback('ludo', capacity: 4, isManager: true, status: 'playing');
      expect(playing.checkCapacity(4), RoomRuleError.roomPlaying);
      expect(playing.checkStart(2), RoomRuleError.roomPlaying);
    });

    test('local fallback clamps a stale room row into the game bounds', () {
      final RoomCapacity c = RoomCapacity.fallback('carrom', capacity: 6);
      expect(c.capacity, 2, reason: 'a carrom room can never offer 6 seats');
      expect(c.minPlayers, 2);
      expect(c.maxPlayers, 2);
    });
  });
}
