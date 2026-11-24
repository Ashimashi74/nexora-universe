import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/economy/gem_shop.dart';
import 'package:nexora/games/finger_soccer/core/bm_data.dart';

void main() {
  test('team gem prices: three free teams, every other team 150..500, stronger teams cost more', () {
    expect(kFreeTeams.length, 3);
    expect(kFreeTeams.contains(kDefaultTeam), isTrue);
    for (final BmTeamDef t in kBmTeamDefs) {
      final int p = defaultTeamPrice(t.id);
      if (kFreeTeams.contains(t.id)) {
        expect(p, 0, reason: t.id);
      } else {
        expect(p, inInclusiveRange(150, 500), reason: t.id);
        expect(p % 10, 0, reason: t.id);
      }
    }
    expect(defaultTeamPrice('lux0'), 500);
    expect(defaultTeamPrice('realmadrid'), greaterThan(defaultTeamPrice('everton')));
    expect(teamItemId('club0'), 'fs_team:club0');
  });

  test('locked teams fall back to the default free team when signed out', () {
    expect(GemShop.instance.ownsTeam('nx_core'), isTrue);
    // a retired v9 starter (its art no longer ships) is never fielded, even if the server still lists it
    expect(GemShop.instance.usableTeam('club32'), kDefaultTeam);
    expect(GemShop.instance.ownsTeam('lux0'), isFalse);
    expect(GemShop.instance.usableTeam('lux0'), kDefaultTeam);
  });
}
