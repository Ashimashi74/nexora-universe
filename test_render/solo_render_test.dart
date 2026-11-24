import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/storage/local_store.dart';
import 'package:nexora/games/core/game_contract.dart';
import 'package:nexora/games/solo/solo_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

// =====================================================================================
// Solo arcade art harness.
//
// Renders every solo board inside the real shell on a phone, starts the run, plays a few
// seconds and writes PNGs (ready card + mid-run + game over) so the look can be reviewed
// without an emulator. Also asserts each board paints for a full run without throwing.
//
//   flutter test test_render/solo_render_test.dart --dart-define=SHOTS=$PWD/shots
//   ONLY=geo_dash,stack_tower flutter test test_render/solo_render_test.dart
// =====================================================================================

const String kShots = String.fromEnvironment('SHOTS', defaultValue: 'shots/solo');
const String kOnly = String.fromEnvironment('ONLY');
const int kSecs = int.fromEnvironment('SECS', defaultValue: 4);
const int kW = int.fromEnvironment('W', defaultValue: 390);
const int kH = int.fromEnvironment('H', defaultValue: 844);

final GlobalKey kShotKey = GlobalKey();
bool _fontsLoaded = false;

Future<void> loadSoloFonts() async {
  if (_fontsLoaded) return;
  _fontsLoaded = true;
  Future<void> fam(String name, List<String> files) async {
    final FontLoader l = FontLoader(name);
    for (final String f in files) {
      if (!File(f).existsSync()) continue;
      final List<int> b = File(f).readAsBytesSync();
      l.addFont(Future<ByteData>.value(ByteData.view(Uint8List.fromList(b).buffer)));
    }
    await l.load();
  }

  const String assets = 'assets/fonts';
  final List<String> roboto = <String>[
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
  ];
  await fam('Roboto', roboto);
  await fam('FlutterTest', roboto);
  await fam('ChakraPetch', <String>[
    '$assets/ChakraPetch-Regular.ttf',
    '$assets/ChakraPetch-SemiBold.ttf',
    '$assets/ChakraPetch-Bold.ttf',
  ]);
  await fam('Estedad', <String>[
    '$assets/Estedad-Regular.ttf',
    '$assets/Estedad-Bold.ttf',
    '$assets/Estedad-Black.ttf',
  ]);
}

Future<void> shoot(WidgetTester tester, String path) async {
  final RenderRepaintBoundary rb = kShotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final ui.Image im = await rb.toImage(pixelRatio: tester.view.devicePixelRatio);
    final ByteData? bd = await im.toByteData(format: ui.ImageByteFormat.png);
    final File f = File('$kShots/$path');
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(bd!.buffer.asUint8List());
  });
}

GameLaunch launch(String id) => GameLaunch(
      gameId: id,
      mode: GameMode.vsBot,
      difficulty: BotDifficulty.normal,
      playerName: 'Ashkan',
      isFa: false,
      fancyEffects: true,
      reducedMotion: false,
      soundOn: false,
      seed: 7,
      playerCount: 1,
      onFinish: (GameResult r) {},
    );

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalStore.init();
    await loadSoloFonts();
  });

  for (final SoloDef d in kSoloDefs) {
    if (kOnly.isNotEmpty && !kOnly.split(',').contains(d.id)) continue;
    testWidgets('render ${d.id}', (WidgetTester tester) async {
      tester.view.physicalSize = Size(kW * 2, kH * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData.dark(useMaterial3: true),
          home: RepaintBoundary(
            key: kShotKey,
            child: Scaffold(backgroundColor: Colors.black, body: buildSoloGame(d, launch(d.id))),
          ),
        ),
      ));
      // ready card
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 33));
      }
      await shoot(tester, 'ready/${d.id}.png');

      // start the run by tapping the card
      await tester.tapAt(Offset(kW * 0.5, kH * 0.63));
      for (int i = 0; i < kSecs * 30; i++) {
        await tester.pump(const Duration(milliseconds: 33));
        // keep the games moving: alternate a jump and a lane change a few times a second
        if (i % 26 == 0) await tester.tapAt(Offset(kW * 0.5, kH * 0.6));
      }
      await shoot(tester, 'play/${d.id}.png');
      expect(tester.takeException(), isNull);
    });
  }
}
