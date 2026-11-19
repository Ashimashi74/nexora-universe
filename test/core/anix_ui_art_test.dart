import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/audio/sfx_service.dart';
import 'package:nexora/core/ui2/anix_kit.dart';
import 'package:nexora/games/game_registry.dart';

void main() {
  test('every painted icon, trophy and scene exists and is declared in pubspec', () {
    final String pub = File('pubspec.yaml').readAsStringSync();
    for (final String dir in <String>['icons', 'trophies', 'scenes']) {
      expect(pub.contains('assets/ui/anix/$dir/'), isTrue, reason: dir);
    }
    final List<String> paths = <String>[
      for (final String n in AnixAssets.iconNames) AnixAssets.icon(n),
      for (final String t in AnixAssets.trophyTiers) AnixAssets.trophy(t),
      AnixAssets.sceneVoiceStage,
      AnixAssets.sceneTrophyHall,
      AnixAssets.sceneHubPanorama,
      AnixAssets.scenePortalBlue,
      AnixAssets.scenePortalGold,
    ];
    for (final String p in paths) {
      expect(File(p).existsSync(), isTrue, reason: p);
    }
    for (final String route in <String>['/hub', '/tournaments', '/leaderboard', '/settings']) {
      expect(File(AnixAssets.iconForRoute(route)!).existsSync(), isTrue, reason: route);
    }
  });

  test('every online game has a pedestal', () {
    for (final GameInfo g in kGames.where((GameInfo g) => g.supportsOnline)) {
      expect(File('assets/arcade/pedestals/${g.id}.webp').existsSync(), isTrue, reason: g.id);
    }
  });

  test('every UI sound effect exists and is declared', () {
    expect(File('pubspec.yaml').readAsStringSync().contains('assets/sfx/ui/'), isTrue);
    for (final String n in NxSfx.names) {
      expect(File('assets/sfx/ui/$n.mp3').existsSync(), isTrue, reason: n);
    }
    NxSfx.instance.configure(enabled: true, volume: 0.5);
    NxSfx.instance.play('tick'); // no-op under tests, must not throw
  });
}
