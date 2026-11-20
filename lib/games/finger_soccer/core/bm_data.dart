// GENERATED from BERMUDA_NXG www/js/game.js — do not retune. Values are copied 1:1.
// ignore_for_file: lines_longer_than_80_chars

class BmField {
  const BmField(this.id, this.name, this.w0, this.h0, this.l0, this.r0, this.t0, this.b0, this.cs0, this.g0, this.gs,
      {this.rc = 70, this.gh0 = 0, this.gr0 = 0, this.gd0 = 0, this.asset});
  final String id, name, gs;
  /// Raw image-space values (before FS scale). l0/r0/t0/b0 = the drawn boundary the ball bounces on (measured on the
  /// art: the touch line, or the barrier's inner edge where the art has no line in front of it).
  final int w0, h0, l0, r0, t0, b0, cs0, g0;
  /// Corner radius of the drawn boundary, in world units (measured per field on the art).
  final double rc;
  /// Fields whose art has the goals built in (gs == 'none'): post-centre half width, post radius and net depth,
  /// image px measured on the art. Unused for fields that draw a separate goal sprite.
  final double gh0, gr0, gd0;
  /// Field image (defaults to `assets/games/bermuda/fields/<id>.webp`).
  final String? asset;
  bool get builtInGoals => gs == 'none';
}

const List<BmField> kBmFieldsRaw = <BmField>[
  // Owner-provided default pitch (697x1280). Bounds match its red inner
  // frame; kickoff matches the visible centre spot.
  BmField('nexora_green', 'ANIX Green', 697, 1280, 25, 672, 81, 1197, 640, 115, 'white', rc: 22),
  BmField('forest', 'Forest', 1086, 1448, 195, 890, 127, 1311, 702, 130, 'white', rc: 70),
  BmField('ice', 'Ice', 1086, 1448, 190, 895, 134, 1308, 700, 132, 'white', rc: 110),
  BmField('ocean', 'Ocean', 1086, 1448, 191, 897, 108, 1313, 701, 132, 'white', rc: 150),
  BmField('street', 'Street', 1086, 1448, 182, 902, 157, 1313, 706, 134, 'white', rc: 110),
  BmField('streetarena', 'Street Arena', 1086, 1448, 194, 888, 117, 1309, 702, 130, 'white', rc: 150),
  BmField('lava', 'Lava', 1086, 1448, 200, 884, 127, 1305, 699, 128, 'white', rc: 150),
  BmField('stadium', 'Stadium', 1086, 1448, 196, 888, 115, 1311, 701, 129, 'white', rc: 150),
  BmField('checker', 'Checker', 1086, 1448, 193, 890, 102, 1353, 704, 130, 'white', rc: 50),
  BmField('futsal', 'Futsal', 1086, 1448, 190, 895, 104, 1318, 697, 132, 'white', rc: 110),
  BmField('arena', 'Arena', 1086, 1448, 199, 884, 118, 1313, 694, 128, 'white', rc: 90),
  BmField('arena2', 'Grand Arena', 1086, 1448, 164, 921, 135, 1302, 703, 134, 'white', rc: 110),
  BmField('desert', 'Desert', 1086, 1448, 163, 920, 84, 1315, 694, 134, 'white', rc: 150),
  BmField('grove', 'Grove', 1086, 1448, 172, 918, 108, 1320, 695, 134, 'white', rc: 110),
  BmField('pool', 'Pool', 1086, 1448, 160, 925, 98, 1312, 697, 134, 'white', rc: 150),
  BmField('neon', 'Neon Tech', 1024, 1536, 141, 883, 131, 1385, 745, 139, 'white', rc: 110),
  BmField('royal', 'Royal', 1024, 1536, 148, 877, 147, 1350, 730, 136, 'white', rc: 110),
  BmField('mahogany', 'Mahogany', 1024, 1536, 97, 925, 90, 1393, 729, 155, 'white', rc: 150),
  BmField('leather', 'Leather', 1024, 1536, 99, 925, 99, 1405, 730, 154, 'white', rc: 150),
  BmField('aqua', 'Aquarium', 1024, 1536, 122, 905, 122, 1390, 742, 146, 'white', rc: 110),
  BmField('asphalt', 'Asphalt', 1024, 1536, 97, 925, 113, 1417, 742, 155, 'white', rc: 110),
  BmField('court', 'Court', 1024, 1536, 118, 907, 115, 1377, 715, 148, 'white', rc: 50),
  BmField('cyberbox', 'Cyber Box', 1024, 1536, 118, 906, 108, 1378, 706, 147, 'white', rc: 110),
  BmField('realmadrid', 'Real Madrid', 1086, 1448, 195, 889, 100, 1330, 722, 130, 'white', rc: 110),
  BmField('psg', 'Paris SG', 1086, 1448, 204, 881, 115, 1296, 666, 130, 'white', rc: 70),
  BmField('acmilan', 'AC Milan', 1086, 1448, 195, 889, 100, 1330, 722, 130, 'white', rc: 110),
  BmField('barcelona', 'FC Barcelona', 1086, 1448, 194, 889, 101, 1329, 721, 130, 'white', rc: 110),
  BmField('persepolis', 'Persepolis', 1152, 1536, 207, 943, 105, 1410, 770, 130, 'white', rc: 150),
  BmField('esteghlal', 'Esteghlal', 1086, 1448, 195, 890, 100, 1322, 690, 130, 'white', rc: 110),
  BmField('mancity', 'Man City', 1086, 1448, 195, 889, 102, 1329, 719, 130, 'white', rc: 110),
  // v7 (owner request 2026-11-20): the six owner art pack pitches (Neon Cup, Street Cage, Sockerbox, Gold Leather,
  // Neon Grass, Royal Gold) were removed. They were the last six entries, so every saved index below 30 still
  // names the same pitch; a saved / synced index that no longer exists falls back to the default pitch
  // (bmFieldIndex).
];

/// Ids of pitches removed from the game (v7). Kept only so tests can check they never come back.
const List<String> kBmRemovedFieldIds = <String>[
  'neon_cup', 'street_cage', 'sockerbox', 'gold_leather', 'neon_grass', 'royal_gold',
];

/// A saved / synced pitch index -> a valid one: anything missing or out of range (e.g. a removed v6 pitch) is the
/// default pitch 0 (ANIX Green).
int bmFieldIndex(int? i) => (i == null || i < 0 || i >= kBmFieldsRaw.length) ? 0 : i;

/// Goal art measured on each sprite (alpha): [width, height, left post centre, right post centre, post half-width,
/// inner edge of the back bar, bottom of the posts] - x values are fractions of the width, y values of the height.
/// The engine builds the posts, the side nets and the back net from these numbers, so the drawn goal is the collider.
const Map<String, List<double>> kBmGS = <String, List<double>>{
  // The only goal art (owner asset goalpost_139462.png: white tubular frame, hexagonal net, front view).
  'white': <double>[840, 307, 0.0470, 0.9548, 0.0167, 0.0945, 0.9967],
};

/// Team categories: Club (باشگاهی), National (ملی), Luxury (لاکچری). The old car / brand / sports pieces are luxury.
/// The black / green / oak ANIX wooden pucks are NOT soccer discs: they are the Carrom men and Backgammon checkers
/// (assets/games/carrom/pieces, assets/games/backgammon/pieces).
const List<List<Object>> kBmCats = <List<Object>>[
  <Object>['club', 'Club', 'باشگاهی'],
  <Object>['nat', 'National', 'ملی'],
  <Object>['lux', 'Luxury', 'لاکچری'],
];

/// One selectable piece set. [power] scales the shot impulse, [accuracy] narrows the aim spread (both 1..10).
/// Club / National values are hand-set by real-world strength; every Luxury piece is 10 / 10.
class BmTeamDef {
  const BmTeamDef(this.id, this.cat, this.name, this.art, this.power, this.accuracy);
  final String id, cat, name;
  /// Asset path relative to assets/games/bermuda/ (without .webp).
  final String art;
  final int power, accuracy;
}

const List<BmTeamDef> kBmTeamDefs = <BmTeamDef>[
  BmTeamDef('club0', 'club', 'Real Madrid', 'discs/real_madrid', 9, 9),
  BmTeamDef('club1', 'club', 'Barcelona', 'discs/barcelona', 9, 9),
  BmTeamDef('club2', 'club', 'Manchester City', 'discs/man_city', 9, 9),
  BmTeamDef('club3', 'club', 'Manchester United', 'discs/man_united', 8, 7),
  BmTeamDef('club4', 'club', 'Liverpool', 'discs/liverpool', 9, 8),
  BmTeamDef('club5', 'club', 'Arsenal', 'discs/arsenal', 8, 8),
  BmTeamDef('club6', 'club', 'Chelsea', 'discs/chelsea', 8, 7),
  BmTeamDef('club7', 'club', 'Bayern Munich', 'discs/bayern', 9, 8),
  BmTeamDef('club8', 'club', 'Borussia Dortmund', 'discs/dortmund', 8, 7),
  BmTeamDef('club9', 'club', 'Paris Saint-Germain', 'discs/psg', 9, 8),
  BmTeamDef('club10', 'club', 'Inter Milan', 'discs/inter', 8, 8),
  BmTeamDef('club11', 'club', 'AC Milan', 'discs/ac_milan', 8, 7),
  BmTeamDef('club12', 'club', 'Juventus', 'discs/juventus', 8, 8),
  BmTeamDef('club13', 'club', 'Atletico Madrid', 'discs/atletico', 8, 8),
  BmTeamDef('club14', 'club', 'Ajax', 'discs/ajax', 7, 7),
  BmTeamDef('club15', 'club', 'Benfica', 'teams/club15', 7, 7),
  BmTeamDef('club16', 'club', 'Porto', 'teams/club16', 7, 6),
  BmTeamDef('club17', 'club', 'Boca Juniors', 'teams/club17', 7, 6),
  BmTeamDef('club18', 'club', 'River Plate', 'teams/club18', 7, 7),
  BmTeamDef('club19', 'club', 'Flamengo', 'teams/club19', 7, 6),
  BmTeamDef('club20', 'club', 'Al Nassr', 'discs/al_nassr', 7, 6),
  BmTeamDef('club21', 'club', 'Al Hilal', 'discs/al_hilal', 7, 7),
  BmTeamDef('club22', 'club', 'Roma', 'discs/roma', 7, 7),
  BmTeamDef('club23', 'club', 'Besiktas', 'teams/club23', 6, 6),
  BmTeamDef('club24', 'club', 'Tottenham', 'discs/tottenham', 8, 7),
  BmTeamDef('club25', 'club', 'Marseille', 'discs/marseille', 7, 6),
  BmTeamDef('club26', 'club', 'Napoli', 'teams/club26', 8, 7),
  BmTeamDef('club27', 'club', 'Sporting CP', 'teams/club27', 7, 7),
  BmTeamDef('club28', 'club', 'Sevilla', 'teams/club28', 7, 6),
  BmTeamDef('club29', 'club', 'Valencia', 'teams/club29', 6, 6),
  BmTeamDef('club30', 'club', 'PSV', 'teams/club30', 7, 6),
  BmTeamDef('club31', 'club', 'Newcastle', 'discs/newcastle', 8, 7),
  BmTeamDef('club32', 'club', 'Persepolis', 'discs/persepolis', 6, 7),
  BmTeamDef('club33', 'club', 'Esteghlal', 'discs/esteghlal', 6, 6),
  BmTeamDef('club34', 'club', 'Inter Miami', 'discs/inter_miami', 7, 6),
  BmTeamDef('club35', 'club', 'Wolfsburg', 'discs/wolfsburg', 6, 6),
  BmTeamDef('club36', 'club', 'Shakhtar Donetsk', 'discs/shakhtar', 6, 7),
  BmTeamDef('club37', 'club', 'Celtic', 'discs/celtic', 6, 6),
  BmTeamDef('club38', 'club', 'Rangers', 'discs/rangers', 6, 5),
  BmTeamDef('club39', 'club', 'Monaco', 'discs/monaco', 7, 6),
  BmTeamDef('nat0', 'nat', 'Argentina', 'discs/argentina', 9, 9),
  BmTeamDef('nat1', 'nat', 'Brazil', 'discs/brazil', 9, 8),
  BmTeamDef('nat2', 'nat', 'France', 'discs/france', 9, 9),
  BmTeamDef('nat3', 'nat', 'Germany', 'discs/germany', 8, 9),
  BmTeamDef('nat4', 'nat', 'Portugal', 'discs/portugal', 9, 8),
  BmTeamDef('nat5', 'nat', 'Spain', 'discs/spain', 9, 9),
  BmTeamDef('nat6', 'nat', 'Italy', 'discs/italy', 8, 8),
  BmTeamDef('nat7', 'nat', 'England', 'teams/nat07', 9, 8),
  BmTeamDef('nat8', 'nat', 'Netherlands', 'teams/nat08', 8, 8),
  BmTeamDef('nat9', 'nat', 'Belgium', 'teams/nat09', 8, 7),
  BmTeamDef('nat10', 'nat', 'Uruguay', 'teams/nat10', 8, 7),
  BmTeamDef('nat11', 'nat', 'Sweden', 'teams/nat11', 6, 7),
  BmTeamDef('nat12', 'nat', 'Poland', 'teams/nat12', 7, 6),
  BmTeamDef('nat13', 'nat', 'Denmark', 'teams/nat13', 7, 7),
  BmTeamDef('nat14', 'nat', 'Croatia', 'teams/nat14', 8, 8),
  BmTeamDef('nat15', 'nat', 'Switzerland', 'teams/nat15', 7, 7),
  BmTeamDef('nat16', 'nat', 'Mexico', 'teams/nat16', 7, 6),
  BmTeamDef('nat17', 'nat', 'USA', 'teams/nat17', 7, 6),
  BmTeamDef('nat18', 'nat', 'Japan', 'teams/nat18', 7, 8),
  BmTeamDef('nat19', 'nat', 'South Korea', 'teams/nat19', 7, 7),
  BmTeamDef('nat20', 'nat', 'Australia', 'teams/nat20', 6, 6),
  BmTeamDef('nat21', 'nat', 'Senegal', 'teams/nat21', 7, 6),
  BmTeamDef('nat22', 'nat', 'Morocco', 'teams/nat22', 8, 7),
  BmTeamDef('nat23', 'nat', 'Tunisia', 'teams/nat23', 6, 6),
  BmTeamDef('nat24', 'nat', 'Egypt', 'teams/nat24', 6, 6),
  BmTeamDef('nat25', 'nat', 'Iceland', 'teams/nat25', 5, 6),
  BmTeamDef('nat26', 'nat', 'Iran', 'discs/iran', 7, 7),
  BmTeamDef('nat27', 'nat', 'Qatar', 'discs/qatar', 5, 6),
  BmTeamDef('nat28', 'nat', 'Saudi Arabia', 'teams/nat28', 6, 5),
  BmTeamDef('nat29', 'nat', 'Colombia', 'teams/nat29', 8, 7),
  BmTeamDef('nat30', 'nat', 'Lebanon', 'discs/lebanon', 4, 5),
  BmTeamDef('lux0', 'lux', 'Louis Vuitton', 'teams/lux00', 10, 10),
  BmTeamDef('lux1', 'lux', 'Chanel', 'teams/lux01', 10, 10),
  BmTeamDef('lux2', 'lux', 'Gucci', 'teams/lux02', 10, 10),
  BmTeamDef('lux3', 'lux', 'Hermes', 'teams/lux03', 10, 10),
  BmTeamDef('lux4', 'lux', 'Prada', 'teams/lux04', 10, 10),
  BmTeamDef('lux5', 'lux', 'Dior', 'teams/lux05', 10, 10),
  BmTeamDef('lux6', 'lux', 'Versace', 'teams/lux06', 10, 10),
  BmTeamDef('lux7', 'lux', 'Rolex', 'teams/lux07', 10, 10),
  BmTeamDef('lux8', 'lux', 'Cartier', 'teams/lux08', 10, 10),
  BmTeamDef('lux9', 'lux', 'Fendi', 'teams/lux09', 10, 10),
  BmTeamDef('lux10', 'lux', 'Valentino', 'teams/lux10', 10, 10),
  BmTeamDef('lux11', 'lux', 'Burberry', 'teams/lux11', 10, 10),
  BmTeamDef('lux12', 'lux', 'Saint Laurent', 'teams/lux12', 10, 10),
  BmTeamDef('lux13', 'lux', 'Swarovski', 'teams/lux13', 10, 10),
  BmTeamDef('car0', 'lux', 'Lamborghini', 'teams/car00', 10, 10),
  BmTeamDef('car1', 'lux', 'Ferrari', 'teams/car01', 10, 10),
  BmTeamDef('car2', 'lux', 'Rolls-Royce', 'teams/car02', 10, 10),
  BmTeamDef('car3', 'lux', 'Mercedes-Benz', 'teams/car03', 10, 10),
  BmTeamDef('car4', 'lux', 'BMW', 'teams/car04', 10, 10),
  BmTeamDef('car5', 'lux', 'Porsche', 'teams/car05', 10, 10),
  BmTeamDef('car6', 'lux', 'Maserati', 'teams/car06', 10, 10),
  BmTeamDef('car7', 'lux', 'Aston Martin', 'teams/car07', 10, 10),
  BmTeamDef('car8', 'lux', 'Bentley', 'teams/car08', 10, 10),
  BmTeamDef('car9', 'lux', 'Bugatti', 'teams/car09', 10, 10),
  BmTeamDef('car10', 'lux', 'Lexus', 'teams/car10', 10, 10),
  BmTeamDef('car11', 'lux', 'Cadillac', 'teams/car11', 10, 10),
  BmTeamDef('car12', 'lux', 'McLaren', 'teams/car12', 10, 10),
  BmTeamDef('car13', 'lux', 'Tesla', 'teams/car13', 10, 10),
  BmTeamDef('spt0', 'lux', 'Nike', 'teams/spt00', 10, 10),
  BmTeamDef('spt1', 'lux', 'Adidas', 'teams/spt01', 10, 10),
  BmTeamDef('spt2', 'lux', 'Puma', 'teams/spt02', 10, 10),
  BmTeamDef('spt3', 'lux', 'Under Armour', 'teams/spt03', 10, 10),
  BmTeamDef('spt4', 'lux', 'New Balance', 'teams/spt04', 10, 10),
  BmTeamDef('spt5', 'lux', 'Reebok', 'teams/spt05', 10, 10),
  BmTeamDef('spt6', 'lux', 'Jordan', 'teams/spt06', 10, 10),
  BmTeamDef('spt7', 'lux', 'Asics', 'teams/spt07', 10, 10),
  BmTeamDef('spt8', 'lux', 'Wilson', 'teams/spt08', 10, 10),
  BmTeamDef('spt9', 'lux', 'Speedo', 'teams/spt09', 10, 10),
  BmTeamDef('spt10', 'lux', 'Converse', 'teams/spt10', 10, 10),
  BmTeamDef('spt11', 'lux', 'Vans', 'teams/spt11', 10, 10),
  BmTeamDef('spt12', 'lux', 'NBA', 'teams/spt12', 10, 10),
  BmTeamDef('spt13', 'lux', 'Umbro', 'teams/spt13', 10, 10),
  BmTeamDef('barca_gold', 'lux', 'Barcelona Gold', 'discs/barcelona_gold', 10, 10),
];

class BmTrail {
  const BmTrail(this.k, this.c);
  final String k;
  final List<int> c;
}

const List<BmTrail> kBmTR = <BmTrail>[
  BmTrail('bolt', <int>[0xFF19B4FF,0xFF8FE6FF,0xFFFFFFFF]),
  BmTrail('prism', <int>[0xFFFF7BD5,0xFF7BD7FF,0xFFFFFFFF]),
  BmTrail('wave', <int>[0xFF2FE0D0,0xFF9FF7EF,0xFFFFFFFF]),
  BmTrail('star', <int>[0xFF5CB6FF,0xFFBFE3FF,0xFFFFFFFF]),
  BmTrail('smoke', <int>[0xFFE8ECF2,0xFF9AA3B0,0xFFFFFFFF]),
  BmTrail('rainbow', <int>[0xFFFF5B5B,0xFFFFD23A,0xFF5BFF8A,0xFF5BD0FF,0xFFC05BFF]),
  BmTrail('neon', <int>[0xFF4DFF2A,0xFFB6FF9A,0xFFFFFFFF]),
  BmTrail('yin', <int>[0xFFFFFFFF,0xFF9B5CFF,0xFF000000]),
  BmTrail('fire', <int>[0xFFFF8A1F,0xFFFFD24A,0xFFFFF3C4]),
  BmTrail('blade', <int>[0xFFFF2B3A,0xFFFF8A92,0xFFFFFFFF]),
  BmTrail('ghost', <int>[0xFFDBE7FF,0xFF8FB0FF,0xFFFFFFFF]),
  BmTrail('ember', <int>[0xFFFF6A1F,0xFFFFB347,0xFFFFF0C8]),
  BmTrail('plasma', <int>[0xFF2F8BFF,0xFF7FC6FF,0xFFFFFFFF]),
  BmTrail('ghost', <int>[0xFFD9915B,0xFFF2C9A0,0xFFFFF4E6]),
  BmTrail('star', <int>[0xFF2F7BFF,0xFF8FD0FF,0xFFFFFFFF]),
  BmTrail('wave', <int>[0xFF9B5CFF,0xFFE0B8FF,0xFFFFFFFF]),
  BmTrail('fire', <int>[0xFFE0A82E,0xFFFFE08A,0xFFFFF7D6]),
  BmTrail('bolt', <int>[0xFF2F6BFF,0xFF7FB4FF,0xFFFFFFFF]),
  BmTrail('neon', <int>[0xFF2F8BFF,0xFFE8B84A,0xFFFFFFFF]),
  BmTrail('prism', <int>[0xFF1FD6A0,0xFF3B9BFF,0xFFFFFFFF]),
  BmTrail('blade', <int>[0xFFFF2B3A,0xFFFF8A92,0xFFFFFFFF]),
  BmTrail('plasma', <int>[0xFF18D8C0,0xFF9FF5E6,0xFFFFFFFF]),
  BmTrail('ember', <int>[0xFF2F5BFF,0xFFFFC83A,0xFFFFF3C4]),
  BmTrail('yin', <int>[0xFFFFFFFF,0xFFE0A82E,0xFF000000]),
  BmTrail('smoke', <int>[0xFFFF4A4A,0xFF9AA3B0,0xFFFFFFFF]),
  BmTrail('star', <int>[0xFFE0A82E,0xFFFFF0B0,0xFFFFFFFF]),
  BmTrail('plasma', <int>[0xFF2F8BFF,0xFFC0C8D8,0xFFFFFFFF]),
  BmTrail('ghost', <int>[0xFF9B5CFF,0xFFFFFFFF,0xFFFFFFFF]),
  BmTrail('neon', <int>[0xFF4DFF2A,0xFFC0C8D8,0xFFFFFFFF]),
  BmTrail('blade', <int>[0xFFE8B84A,0xFF2F6BFF,0xFFFFFFFF]),
  BmTrail('fire', <int>[0xFFFF2B3A,0xFFFF8A92,0xFFFFFFFF]),
  BmTrail('ember', <int>[0xFFFF8A1F,0xFFFFD24A,0xFFFFFFFF]),
  BmTrail('wave', <int>[0xFF3B9BFF,0xFF2FE08A,0xFFFFFFFF]),
  BmTrail('prism', <int>[0xFFFF4A7A,0xFF9B5CFF,0xFFFFFFFF]),
  BmTrail('bolt', <int>[0xFF2F6BFF,0xFFFFFFFF,0xFFFFFFFF]),
  BmTrail('star', <int>[0xFFFFD56B,0xFFFFFFFF,0xFFFFFFFF]),
];

const List<String> kBmTRN = <String>["Bolt", "Prism", "Wave", "Starlight", "Smoke", "Rainbow", "Neon", "Yin", "Fire", "Blade", "Ghost", "Ember", "Plasma", "Copper Ghost", "Stardust", "Twilight", "Gold Flame", "Thunder", "Cobalt Neon", "Aurora", "Crimson Blade", "Teal Storm", "Royal Ember", "Gold Yin", "Red Smoke", "Gilded Star", "Noir Chrome", "Violet Strike", "Emerald Edge", "Royal Blue Gold", "Crimson Noir", "Blaze Orange", "Aqua Wave", "Sunset Pro", "Elite Cobalt", "Crown Luxury"];

/// Match balls (owner rotation sprites, 16 frames side by side, frame width = sheet width / 16). Every sheet is
/// normalised by tool/build_fs_assets.py so the ball's radius is exactly [kBmBallArtFill] of half a frame.
const List<String> kBmBallN = <String>['ANIX Gold Spin', 'ANIX Green', 'ANIX Blue', 'NX Electron', 'Classic', 'NX Spin', 'NX Star'];
const List<String> kBmBallFa = <String>['انیکس طلایی', 'انیکس سبز', 'انیکس آبی', 'الکترون NX', 'کلاسیک', 'NX چرخان', 'NX ستاره'];

/// v6 (owner request 2026-11-20): the classic black / white ball of the reference recordings (owner's art, 111 px,
/// fills its square). It is not a sprite sheet: the 3D ball renderer (BmBallRenderer, flat studio light) rolls it
/// with the ball's real motion, one turn per 2*pi*r rolled, like the reference. It is the default match ball.
const int kBmClassicBallIndex = 4;
const String kBmClassicBall = 'assets/games/bermuda/balls/classic.png';
/// v7 (owner request 2026-11-20): the owner's "NX ball fixed center spin" GIF (24 frames, 90 ms) is the main ball.
const int kBmNxSpinBallIndex = 5;
/// v7: the owner's "NX football" GIF (16 frames, 90 ms; star panels + NX logo), cropped to the ball.
const int kBmNxStarBallIndex = 6;
const int kBmDefaultBall = kBmNxSpinBallIndex;

/// Preference key of the player's match ball. v7 uses a new key so every player (new and existing) starts on the
/// new main ball once: the old 'bm.ball.v6' value was also written automatically at every match start, so an
/// explicit choice could not be told apart from the old default. Picking a ball in the shop / setup writes this key.
const String kBmBallPref = 'bm.ball.v7';

/// A saved / synced ball index -> a valid one (missing or unknown = the default ball).
int bmBallIndex(int? i) => (i == null || i < 0 || i >= kBmBallN.length) ? kBmDefaultBall : i;

/// Picker / shop thumbnail of a ball.
String bmBallThumb(int i) => kBmAnimBalls[i]?.thumb ?? kBmClassicBall;

class BmAnimBall {
  const BmAnimBall(this.sheet, this.frames, this.frameMs, this.thumb, {this.gifTimed = false});
  final String sheet;
  final int frames;
  final int frameMs;
  final String thumb;
  /// v7 GIF balls: the strip is the GIF's frames in the GIF's order, each re-centred on the ball (no wobble), and
  /// they play at exactly [frameMs] per frame while the ball moves (held on the current frame while it rests), with
  /// no extra sprite rotation: the only rotation shown is the GIF's own. Older balls roll with distance instead.
  final bool gifTimed;

  /// Frame shown after [ms] of playback (GIF order, [frameMs] each, looping).
  int frameAt(double ms) => (ms / frameMs).floor() % frames;
}

const Map<int, BmAnimBall> kBmAnimBalls = <int, BmAnimBall>{
  0: BmAnimBall('assets/games/bermuda/balls/anix_spin_16.webp', 16, 100, 'assets/games/bermuda/balls/anix_spin_thumb.webp'),
  1: BmAnimBall('assets/games/bermuda/balls/anix_green_16.webp', 16, 100, 'assets/games/bermuda/balls/anix_green_thumb.webp'),
  2: BmAnimBall('assets/games/bermuda/balls/anix_blue_16.webp', 16, 100, 'assets/games/bermuda/balls/anix_blue_thumb.webp'),
  3: BmAnimBall('assets/games/bermuda/balls/nx_electron_16.webp', 16, 90, 'assets/games/bermuda/balls/nx_electron_thumb.webp'),
  // v7: built by tool/build_fs_nx_balls.py from the owner's GIFs (tool/ball_src/).
  5: BmAnimBall('assets/games/bermuda/balls/nx_spin_24.webp', 24, 90, 'assets/games/bermuda/balls/nx_spin_thumb.webp',
      gifTimed: true),
  6: BmAnimBall('assets/games/bermuda/balls/nx_star_16.webp', 16, 90, 'assets/games/bermuda/balls/nx_star_thumb.webp',
      gifTimed: true),
};

/// Art fills (tool/build_fs_assets.py): disc rim radius / half sprite size, ball radius / half frame size.
/// The painter draws every sprite so the rim lands exactly on the physics radius.
const double kBmDiscArtFill = 120 / 128;
const double kBmBallArtFill = 76 / 80;

class BmFa {
  const BmFa(this.k, this.c, this.g);
  final int k;
  final List<int> c;
  final double g;
}

const Map<String, BmFa> kBmFA = <String, BmFa>{
  'forest': BmFa(2, <int>[0xFF6FD36B,0xFFB8F5A0,0xFF2E8B3A], 130),
  'ice': BmFa(1, <int>[0xFFE8FBFF,0xFF9FE8FF,0xFFFFFFFF], 30),
  'ocean': BmFa(4, <int>[0xFFBFF3FF,0xFF5CD0FF,0xFFFFFFFF], -140),
  'street': BmFa(5, <int>[0xFFFF2BD6,0xFFFFE14A,0xFF2BF0FF], 0),
  'streetarena': BmFa(5, <int>[0xFFFFB02B,0xFFFF3B6B,0xFFFFFFFF], 0),
  'lava': BmFa(0, <int>[0xFFFF5A1F,0xFFFFB347,0xFFFFE08A], -220),
  'stadium': BmFa(1, <int>[0xFFFFD86B,0xFFFFFFFF,0xFFFFE9A8], 0),
  'checker': BmFa(3, <int>[0xFFFFFFFF,0xFF9AA3B0,0xFFFF4040], 0),
  'futsal': BmFa(5, <int>[0xFFFFCF8A,0xFFFFFFFF,0xFFFFA14A], 0),
  'arena': BmFa(5, <int>[0xFF7FB8FF,0xFFFFFFFF,0xFF3B7BFF], 0),
  'arena2': BmFa(1, <int>[0xFFC79BFF,0xFFFFFFFF,0xFF7B4BFF], 0),
  'desert': BmFa(0, <int>[0xFFE8C689,0xFFC99A54,0xFFFFF0C8], 60),
  'grove': BmFa(0, <int>[0xFFD8FF6A,0xFFFFFFA0,0xFF9CF06A], -30),
  'pool': BmFa(0, <int>[0xFF9FE9FF,0xFFE6FBFF,0xFF4CC7FF], 380),
  'neon': BmFa(5, <int>[0xFF7DFF3A,0xFFD6FF9A,0xFFFFFFFF], 0),
  'royal': BmFa(1, <int>[0xFFFFD86B,0xFFFFF3C4,0xFFFF9A3A], 0),
  'mahogany': BmFa(1, <int>[0xFFFFCF8A,0xFFFFF0C8,0xFFD9923A], -20),
  'leather': BmFa(0, <int>[0xFFD9A066,0xFFFFD9A0,0xFF8A5A2A], -30),
  'aqua': BmFa(4, <int>[0xFFBFF3FF,0xFF5CD0FF,0xFFFFFFFF], -150),
  'asphalt': BmFa(5, <int>[0xFFFFE14A,0xFFFFFFFF,0xFFFFB02B], 0),
  'court': BmFa(5, <int>[0xFFFFFFFF,0xFFFFCF8A,0xFF4AA8FF], 0),
  'cyberbox': BmFa(5, <int>[0xFFFF3B3B,0xFF3B8BFF,0xFFFFFFFF], 0),
  'realmadrid': BmFa(1, <int>[0xFFFFFFFF,0xFFFFD86B,0xFF3B6BFF], 0),
  'psg': BmFa(5, <int>[0xFFFF2B3A,0xFF3B6BFF,0xFFFFFFFF], 0),
  'acmilan': BmFa(5, <int>[0xFFFF2B3A,0xFFFFFFFF,0xFF111111], 0),
  'barcelona': BmFa(5, <int>[0xFFFF2B5A,0xFF3B6BFF,0xFFFFD86B], 0),
  'persepolis': BmFa(5, <int>[0xFFFF2B3A,0xFFFFD86B,0xFFFFFFFF], 0),
  'esteghlal': BmFa(1, <int>[0xFF3B8BFF,0xFFFFFFFF,0xFFFFD86B], 0),
  'mancity': BmFa(1, <int>[0xFF7FD0FF,0xFFFFFFFF,0xFF3B8BFF], 0),
};
