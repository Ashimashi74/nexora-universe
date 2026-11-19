import 'package:nexora/core/storage/local_store.dart';

/// The owner's ANIX wooden pucks (black / green / oak, six carvings). They are Carrom men and Backgammon checkers,
/// never finger-soccer discs. Sprites are 256 px with the rim at radius 120 (see tool/build_fs_assets.py).
class WoodPieceSet {
  const WoodPieceSet(this.id, this.nameFa, this.nameEn);
  final String id, nameFa, nameEn;
  String get dark => 'assets/games/shared/pieces/nx_${id}_dark.webp';
  String get light => 'assets/games/shared/pieces/nx_${id}_light.webp';
}

/// Rim radius / half sprite size of every piece sprite.
const double kWoodPieceFill = 120 / 128;

const List<WoodPieceSet> kWoodPieceSets = <WoodPieceSet>[
  WoodPieceSet('ring', 'حلقه‌ی سبز', 'Green ring'),
  WoodPieceSet('star', 'ستاره', 'Star'),
  WoodPieceSet('carved', 'کنده‌کاری', 'Carved'),
  WoodPieceSet('hex', 'شش‌ضلعی', 'Hex'),
  WoodPieceSet('carbon', 'کربن', 'Carbon'),
  WoodPieceSet('minimal', 'مینیمال', 'Minimal'),
];

/// Selected set for [game] ('carrom' / 'backgammon'), remembered on the device. [count] lets a game add its own
/// sets before the wooden ones (Backgammon keeps its classic checkers at index 0).
int woodPieceIndex(String game, {int count = 6}) {
  try {
    return (LocalStore.instance.getInt('$game.pieces') ?? 0) % count;
  } catch (_) {
    return 0;
  }
}

Future<void> setWoodPieceIndex(String game, int i) async {
  try {
    await LocalStore.instance.setInt('$game.pieces', i);
  } catch (_) {}
}
