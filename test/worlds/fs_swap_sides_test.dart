import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/worlds/rooms/talk_room_page.dart';

/// v5: the room manager swaps Team 1 and Team 2 (seats alternate sides: 0,2,4 / 1,3,5).
void main() {
  test('1v1, 2v2, 3v3: every player moves to the other side, turn order inside a side kept', () {
    expect(fsSwapSides(<String>['a', 'b']), <String>['b', 'a']);
    expect(fsSwapSides(<String>['a', 'b', 'c', 'd']), <String>['b', 'a', 'd', 'c']);
    final List<String> six = <String>['a', 'b', 'c', 'd', 'e', 'f'];
    final List<String> sw = fsSwapSides(six);
    expect(sw, <String>['b', 'a', 'd', 'c', 'f', 'e']);
    for (int s = 0; s < six.length; s++) {
      // a player who was on side (s % 2) is now on the other side
      expect(sw.indexOf(six[s]) % 2, 1 - s % 2);
    }
    expect(fsSwapSides(sw), six); // swapping twice restores the room
  });

  test('odd or tiny lists: the unpaired last seat stays', () {
    expect(fsSwapSides(<String>[]), isEmpty);
    expect(fsSwapSides(<String>['a']), <String>['a']);
    expect(fsSwapSides(<String>['a', 'b', 'c']), <String>['b', 'a', 'c']);
  });
}
