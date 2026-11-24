// Shared finger-soccer custom teams (تیم‌های اختصاصی): list model, engine registration, prices / ownership without a
// signed-in profile, and the round crest cut.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/economy/gem_shop.dart';
import 'package:nexora/games/finger_soccer/core/bm_engine.dart';
import 'package:nexora/games/finger_soccer/core/fs_custom_teams.dart';

Map<String, dynamic> _row({String id = '6c9f54ca-7b49-4e0c-bcaf-a635429f207c', String name = 'Lions', bool active = true}) =>
    <String, dynamic>{
      'id': id,
      'owner_id': '11111111-aaaa-4aaa-8aaa-000000000001',
      'name': name,
      'crest_url': 'https://example.supabase.co/storage/v1/object/public/nx-media/u/fs_custom_team.png?v=1',
      'price': 250,
      'active': active,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FsCustomTeams.instance.resetForTest());
  tearDown(() => FsCustomTeams.instance.resetForTest());

  test('team id is cx_ + the row uuid without dashes', () {
    expect(fsCustomTeamIdOf('6C9F54CA-7b49-4e0c-bcaf-a635429f207c'), 'cx_6c9f54ca7b494e0cbcafa635429f207c');
    expect(bmIsCustomTeamId('cx_6c9f54ca7b494e0cbcafa635429f207c'), isTrue);
    expect(bmIsCustomTeamId('cx_'), isFalse);
    expect(bmIsCustomTeamId(kCustomTeamId), isFalse);
    expect(bmIsCustomTeamId('realmadrid'), isFalse);
  });

  test('rows parse; inactive / non-https rows are rejected', () {
    final FsCustomTeam? t = FsCustomTeam.fromRow(_row());
    expect(t, isNotNull);
    expect(t!.teamId, 'cx_6c9f54ca7b494e0cbcafa635429f207c');
    expect(t.price, 250);
    expect(FsCustomTeam.fromRow(_row(active: false)), isNull);
    expect(FsCustomTeam.fromRow(_row()..['crest_url'] = 'http://x/y.png'), isNull);
    expect(FsCustomTeam.fromRow(<String, dynamic>{..._row(), 'team_id': 'cx_abc'})!.teamId, 'cx_abc');
  });

  test('applied teams join kBmTeams in the custom category at power / accuracy 10', () {
    final int before = kBmTeams.length;
    expect(FsCustomTeams.instance.applyRows(<dynamic>[_row(), _row(id: '00000000-0000-4000-8000-000000000002', name: 'B')]),
        isTrue);
    expect(kBmTeams.length, before + 2);
    final BmTeam t = bmTeam('cx_6c9f54ca7b494e0cbcafa635429f207c');
    expect(t.cat, 'custom');
    expect(t.name, 'Lions');
    expect(t.power, 10);
    expect(t.accuracy, 10);
    expect(t.crestUrl, startsWith('https://'));
    expect(kBmTeams.map((BmTeam t) => t.id).toSet().length, kBmTeams.length);

    // an update replaces the entry in place (no duplicate, indexes stay valid)
    final int at = kBmTeams.indexWhere((BmTeam x) => x.id == t.id);
    expect(FsCustomTeams.instance.applyRows(<dynamic>[_row(name: 'Tigers')]), isTrue);
    expect(kBmTeams.length, before + 2);
    expect(kBmTeams[at].name, 'Tigers');
    expect(FsCustomTeams.instance.applyRows(<dynamic>[_row(name: 'Tigers')]), isFalse);
  });

  test('an unknown custom id plays as a 10 / 10 custom team with the fallback disc', () {
    final BmTeam t = bmTeam('cx_ffffffffffffffffffffffffffffffff');
    expect(t.id, 'cx_ffffffffffffffffffffffffffffffff');
    expect(t.power, kBmCustomTeamStat);
    expect(t.accuracy, kBmCustomTeamStat);
    expect(t.asset, kBmCustomTeamFallbackAsset);
    expect(bmTeam('no_such_team').id, kBmTeams.first.id);
  });

  test('without a signed-in profile someone else\'s custom team costs 250 and is not usable', () {
    FsCustomTeams.instance.applyRows(<dynamic>[_row()]);
    const String id = 'cx_6c9f54ca7b494e0cbcafa635429f207c';
    expect(GemShop.instance.teamPrice(id), 250);
    expect(GemShop.instance.ownsTeam(id), isFalse);
    expect(GemShop.instance.usableTeam(id), kDefaultTeam);
    expect(GemShop.instance.usableTeam(kCustomTeamId), kDefaultTeam);
    expect(GemShop.instance.customTeamPrice, 1000);
    expect(teamItemId(id), 'fs_team:$id');
  });

  testWidgets('photos are cut to a round 256px crest, transparent outside the disc', (WidgetTester tester) async {
    await tester.runAsync(() async {
      final ui.PictureRecorder rec = ui.PictureRecorder();
      ui.Canvas(rec).drawRect(const ui.Rect.fromLTWH(0, 0, 300, 200), ui.Paint()..color = const ui.Color(0xFFFF0000));
      final ui.Image src = await rec.endRecording().toImage(300, 200);
      final ByteData? png = await src.toByteData(format: ui.ImageByteFormat.png);
      src.dispose();
      final Uint8List crest = await fsCropRoundCrest(png!.buffer.asUint8List());
      final ui.Codec codec = await ui.instantiateImageCodec(crest);
      final ui.Image out = (await codec.getNextFrame()).image;
      expect(out.width, kFsCrestSize);
      expect(out.height, kFsCrestSize);
      final ByteData rgba = (await out.toByteData())!;
      int alpha(int x, int y) => rgba.getUint8((y * out.width + x) * 4 + 3);
      int red(int x, int y) => rgba.getUint8((y * out.width + x) * 4);
      expect(alpha(0, 0), 0);
      expect(alpha(255, 255), 0);
      expect(alpha(2, 128), 0); // outside the rim (radius 120 of 128)
      expect(alpha(128, 128), 255);
      expect(red(128, 128), greaterThan(200));
      out.dispose();
    });
  });
}
