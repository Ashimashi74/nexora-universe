import 'dart:io';

// The app describes its own catalogue in user-facing copy: the Arcade world tagline, ORACLE's
// "what games do you have" answer and two achievement descriptions. All of those are const
// strings, so they cannot interpolate the registry — which is how the app ended up promising
// "9 games" and "all 20 new arcade games" while the registry held 26 and 17. This test is the
// guard that keeps the copy honest: adding or removing a game fails here until the copy follows.
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/profile/achievements.dart';
import 'package:nexora/games/arcade_kit/arcade_meta.dart';
import 'package:nexora/games/finger_soccer/core/bm_data.dart';
import 'package:nexora/games/finger_soccer/core/bm_engine.dart';
import 'package:nexora/games/finger_soccer/ui/bm_view.dart';
import 'package:nexora/games/game_registry.dart';
import 'package:nexora/worlds/oracle_core/core/oracle_knowledge.dart';
import 'package:nexora/worlds/world_registry.dart';

/// ASCII digits -> Persian digits, for the fa copy.
String faNum(int n) =>
    n.toString().split('').map((String d) => '۰۱۲۳۴۵۶۷۸۹'[int.parse(d)]).join();

/// A registry name without its parenthetical qualifier ('لودو (منچ)' -> 'لودو'), which is how
/// the prose refers to it.
String core(String name) => name.split(' (').first.trim();

void main() {
  group('catalogue size', () {
    test('the arcade is the nine originals plus seventeen expansion games', () {
      expect(kArcadeMultiIds.length, 7, reason: 'multiplayer arcade games');
      expect(kArcadeSoloIds.length, 10, reason: 'solo arcade games');
      expect(kArcadeIds.length, 17);
      expect(kGames.length, 26);
    });

    test('every expansion id resolves to a playable registry entry', () {
      for (final String id in kArcadeIds) {
        expect(gameById(id), isNotNull, reason: '$id is advertised but not in kGames');
      }
      // No duplicate ids: a duplicate would double-count every claim below.
      expect(kGames.map((GameInfo g) => g.id).toSet().length, kGames.length);
    });
  });

  group('user-facing copy matches the registry', () {
    test('the Arcade world tagline states the real game count', () {
      final NexoraWorld arcade =
          kWorlds.firstWhere((NexoraWorld w) => w.id == 'nexora_arcade');
      expect(arcade.taglineEn, contains('${kGames.length} games'));
      expect(arcade.taglineFa, contains(faNum(kGames.length)));
    });

    test('ORACLE lists every game it can actually open', () {
      final OracleFaq faq =
          kOracleFaq.firstWhere((OracleFaq f) => f.id == 'games_list');
      expect(faq.textEn, contains('${kGames.length} games'));
      expect(faq.textFa, contains(faNum(kGames.length)));
      for (final GameInfo g in kGames) {
        expect(faq.textEn, contains(core(g.nameEn)),
            reason: '${g.id}: ORACLE never mentions ${g.nameEn}');
        expect(faq.textFa, contains(core(g.nameFa)),
            reason: '${g.id}: ORACLE never mentions ${g.nameFa}');
      }
    });

    test('"Arcade Master" asks for every expansion game, no more and no less', () {
      final AchievementDef all =
          kAchievements.firstWhere((AchievementDef a) => a.id == 'arcade_all');
      expect(all.descEn, contains('${kArcadeIds.length}'));
      expect(all.descFa, contains(faNum(kArcadeIds.length)));
    });

    test('"Arcade Wings" does not claim to cover the whole catalogue', () {
      // Its rule is nine distinct games (stats.length >= 9), a subset of the 26 — so the copy
      // must say "different games", never "all".
      final AchievementDef wings =
          kAchievements.firstWhere((AchievementDef a) => a.id == 'all_games');
      expect(wings.descEn, contains('9 different games'));
      expect(wings.descEn.toLowerCase(), isNot(contains('all ')));
      expect(wings.descFa, isNot(contains('هر ۹')));
    });
  });

  // The finger soccer rules screen is the game's own instruction manual: it used to promise
  // 6 formations and 15-second online turns while the engine shipped 9 formations and a
  // 10-second clock (kBmOnlineTurnSeconds, and the server's turn-authority migration).
  group('finger soccer rules copy matches the engine', () {
    test('the rules name the real number of formations', () {
      final GameInfo fs = gameById('finger_soccer')!;
      expect(kBmForms.length, 9);
      expect(fs.rulesEn, contains('(${kBmForms.length} shapes)'));
      expect(fs.rulesFa, contains('${faNum(kBmForms.length)} ترکیب'));
    });

    test('the rules state the real online turn length', () {
      final GameInfo fs = gameById('finger_soccer')!;
      final int seconds = kBmOnlineTurnSeconds.toInt();
      expect(seconds, 10);
      expect(fs.rulesEn, contains('$seconds seconds'));
      expect(fs.rulesFa, contains('${faNum(seconds)} ثانیه'));
    });

    test('the catalogue the README advertises is the one that ships', () {
      // v10: 122 teams (Clubs 47, Nations 19, NX 12, Cars 24, Sport 12, Elite 6, Legends 2) from the owner's crest
      // archive, the owner's 5 pitches (v11), 18 balls.
      expect(kBmTeamDefs.length, 122);
      expect(kBmTeamDefs.where((BmTeamDef t) => t.cat == 'clubs').length, 47);
      expect(kBmTeamDefs.where((BmTeamDef t) => t.cat == 'nations').length, 19);
      expect(kBmTeamDefs.where((BmTeamDef t) => t.cat == 'nx').length, 12);
      expect(kBmTeamDefs.where((BmTeamDef t) => t.cat == 'cars').length, 24);
      expect(kBmTeamDefs.where((BmTeamDef t) => t.cat == 'sport').length, 12);
      expect(kBmTeamDefs.where((BmTeamDef t) => t.cat == 'elite').length, 6);
      expect(kBmTeamDefs.where((BmTeamDef t) => t.cat == 'legends').length, 2);
      expect(kBmFieldsRaw.length, 5);
      expect(kBmBallN.length, 4);
      final String readme = File('README.md').readAsStringSync();
      expect(readme, contains('122 teams'));
      expect(readme, contains('5 pitches'));
      expect(readme, contains('۱۲۲ تیم'));
    });
  });
}
