import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/worlds/rooms/talk_room_page.dart';

void main() {
  test('room game limits: mafia and party games 12, team games 6', () {
    final dynamic s = _S();
    expect(s.max('mafia'), 12);
    expect(s.max('spy_mafia'), 12);
    expect(s.max('finger_soccer'), 6);
    expect(s.max('carrom'), 6);
    expect(s.min('mafia'), 6);
  });
}

class _S {
  int max(String g) => TalkRoomLimits.maxPlayersFor(g);
  int min(String g) => TalkRoomLimits.minPlayersFor(g);
}
