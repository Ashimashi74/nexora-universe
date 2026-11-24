// Guard: the seat counts the registry (and therefore the room screen and the server's
// nx_game_bounds) offers must never exceed what each game's own rules engine really plays.
// A room that let a manager pick 6 players for a 4-seat board would start a broken match.
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/game_registry.dart';
import 'package:nexora/games/ludo/core/ludo_rules.dart';
import 'package:nexora/games/snakes_ladders/core/snl_rules.dart';
import 'package:nexora/games/uno/core/uno_engine.dart';
import 'package:nexora/games/uno/core/uno_models.dart';

void main() {
  GameInfo info(String id) {
    final GameInfo? g = gameById(id);
    expect(g, isNotNull, reason: id);
    return g!;
  }

  test('ludo: every offered seat count builds a board with exactly that many players', () {
    final GameInfo g = info('ludo');
    for (int n = g.onlineMinPlayers; n <= g.onlineMaxPlayers; n++) {
      expect(LudoState.initial(n).playerCount, n, reason: 'ludo $n');
    }
    for (int n = g.minPlayers; n <= g.maxPlayers; n++) {
      expect(LudoState.initial(n).playerCount, n, reason: 'ludo offline $n');
    }
  });

  test('snakes & ladders: every offered seat count is played as is (no silent clamp)', () {
    final GameInfo g = info('snakes_ladders');
    for (int n = g.onlineMinPlayers; n <= g.onlineMaxPlayers; n++) {
      expect(SnlEngine(playerCount: n, seed: 1).playerCount, n, reason: 'snl $n');
    }
    for (int n = g.minPlayers; n <= g.maxPlayers; n++) {
      expect(SnlEngine(playerCount: n, seed: 1).playerCount, n, reason: 'snl offline $n');
    }
  });

  test('NX Cards: every offered seat count deals a legal game', () {
    final GameInfo g = info('uno');
    // The engine itself supports 2..6; the registry (and the live server) stay at 2..4.
    expect(g.onlineMaxPlayers, lessThanOrEqualTo(6));
    expect(g.maxPlayers, lessThanOrEqualTo(6));
    for (int n = g.onlineMinPlayers; n <= g.onlineMaxPlayers; n++) {
      final UnoGame game = UnoGame(playerCount: n, seed: 7);
      expect(game.playerCount, n);
      expect(game.hands.length, n);
      for (final List<UnoCard> hand in game.hands) {
        expect(hand.length, 7, reason: 'uno $n seats');
      }
    }
  });

  test('duels stay duels and the social games keep their real table sizes', () {
    for (final String id in <String>['carrom', 'billiards', 'backgammon', 'quiz', 'pool8']) {
      final GameInfo g = info(id);
      expect(g.onlineMinPlayers, 2, reason: id);
      expect(g.onlineMaxPlayers, 2, reason: id);
    }
    expect(info('mafia').onlineMinPlayers, 6);
    expect(info('mafia').onlineMaxPlayers, 12);
    expect(info('spy_mafia').onlineMinPlayers, 4);
    expect(info('spy_mafia').onlineMaxPlayers, 8);
    // Team game: 1v1 / 2v2 / 3v3 online, one duel offline.
    expect(info('finger_soccer').onlineMaxPlayers, 6);
    expect(info('finger_soccer').maxPlayers, 2);
  });

  test('the four-seat arcade games never offer more seats than their four-corner layouts', () {
    for (final String id in <String>['kart_racing', 'obstacle_race', 'bomb_arena', 'mini_golf', 'basketball_battle']) {
      final GameInfo g = info(id);
      expect(g.onlineMinPlayers, 2, reason: id);
      expect(g.onlineMaxPlayers, lessThanOrEqualTo(4), reason: id);
    }
  });
}
