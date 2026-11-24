import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/worlds/rooms/talk_room_page.dart';

void main() {
  // Room limits are the game's real online bounds (registry) and the games project mirrors them in
  // nx_game_bounds. The old copy had drifted: carrom said 6 (the board is a two-seat duel) and quiz 21
  // (the quiz engine is 1v1), which let the manager start matches no engine could run.
  test('room game limits follow the game mechanics', () {
    final dynamic s = _S();
    expect(s.max('mafia'), 12);
    expect(s.max('spy_mafia'), 8);
    expect(s.max('finger_soccer'), 6, reason: 'online finger soccer plays 1v1, 2v2 and 3v3');
    expect(s.max('carrom'), 2, reason: 'carrom is a two-seat duel (white vs black baseline)');
    expect(s.max('quiz'), 2, reason: 'quiz engine is 1v1');
    expect(s.max('uno'), 4);
    expect(s.max('ludo'), 4);
    expect(s.min('mafia'), 6);
    expect(s.min('spy_mafia'), 4);
    expect(s.min('finger_soccer'), 2);
  });
}

class _S {
  int max(String g) => TalkRoomLimits.maxPlayersFor(g);
  int min(String g) => TalkRoomLimits.minPlayersFor(g);
}
