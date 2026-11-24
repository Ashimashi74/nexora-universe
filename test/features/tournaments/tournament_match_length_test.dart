import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tournaments/data/models.dart';
import 'package:nexora/features/tournaments/ui/t_common.dart';

Tournament _t(Map<String, dynamic> cfg) => Tournament(<String, dynamic>{'id': 't', 'config': cfg});

void main() {
  test('match length chip follows the server config (minutes / first to N goals)', () {
    expect(matchLengthShort(_t(<String, dynamic>{'match_minutes': 7})), '7′');
    expect(matchLengthShort(_t(<String, dynamic>{'match_minutes': 3})), '3′');
    expect(matchLengthShort(_t(<String, dynamic>{'match_minutes': 0})), '5′'); // game default
    expect(matchLengthShort(_t(<String, dynamic>{'goal_target': 3, 'match_minutes': 0})), '⚽3');
  });
}
