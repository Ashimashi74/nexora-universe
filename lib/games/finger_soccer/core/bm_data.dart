// GENERATED from BERMUDA_NXG www/js/game.js — do not retune. Values are copied 1:1.
// ignore_for_file: lines_longer_than_80_chars
import 'dart:ui' show Color;

class BmField {
  const BmField(this.id, this.name, this.w0, this.h0, this.l0, this.r0, this.t0, this.b0, this.cs0, this.g0, this.gs,
      {this.rc = 70,
      this.gh0 = 0,
      this.gr0 = 0,
      this.gd0 = 0,
      this.asset,
      this.score,
      this.faName = '',
      this.scoreLeft = kBmScoreLeft,
      this.scoreRight = const Color(0xFFFF3B30)});
  final String id, name, gs;
  /// Persian name (shown when the UI is in Persian; empty = use [name]).
  final String faName;
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
  /// v9: the score displays drawn into the art (null = none). The whole art is then fitted to the screen and the live
  /// score is drawn on these displays instead of a HUD scoreboard.
  final BmScoreDisplay? score;
  /// Colours of the live digits on the left-hand (bottom / home side) and right-hand displays, measured on the art's
  /// printed digits.
  final Color scoreLeft, scoreRight;
  bool get fullArt => score != null;
  bool get builtInGoals => gs == 'none';
}

/// Geometry of the two side score displays drawn into a pitch art (image px of the art, [artW] wide). Each display
/// stacks two seven-segment digit cells: tens on top, ones below. The left display shows the bottom / home side, the
/// right one the other side. v11: measured per art (the five owner arts place and size their displays differently).
class BmScoreDisplay {
  const BmScoreDisplay(this.artW, this.leftCx, this.rightCx, this.tensCy, this.onesCy, this.digitW, this.digitH);
  final double artW, leftCx, rightCx, tensCy, onesCy, digitW, digitH;
}

/// Default colour of the left (bottom / home side) display's digits.
const Color kBmScoreLeft = Color(0xFF2F86FF);

const List<BmField> kBmFieldsRaw = <BmField>[
  // v12 (owner upload 2026-11-24): the owner's eleven pitch arts replace the seven v11 arts. Raw values are measured on
  // each art's own touch lines (in the art's measuring frame: 1086 x 1448, 1216 x 1622 or 837 x 1536, the same aspect
  // as the file); the goals are the separate owner goal sprite ('white', kBmGS). Built by tool/build_fs_v12_assets.py.
  BmField('tropical', 'Tropical', 1086, 1448, 214, 874, 116, 1304, 698, 115, 'white', faName: 'استوایی'),
  BmField('psg', 'Paris SG', 1216, 1622, 228, 987, 129, 1452, 746, 135, 'white', faName: 'پاری سن ژرمن'),
  BmField('campnou', 'Camp Nou Night', 1086, 1448, 194, 892, 104, 1332, 715, 121, 'white', faName: 'شب نیوکمپ'),
  BmField('pitch', 'NEXORA Pitch', 837, 1536, 30, 805, 101, 1432, 768, 128, 'white', faName: 'زمین نکسورا'),
  BmField('checker', 'Checker', 1216, 1622, 216, 997, 114, 1515, 788, 135, 'white', faName: 'شطرنجی'),
  BmField('futsal', 'Futsal', 1216, 1622, 213, 1002, 116, 1476, 781, 137, 'white', faName: 'فوتسال'),
  BmField('arena', 'Arena', 1216, 1622, 223, 990, 132, 1471, 777, 133, 'white', faName: 'آرنا'),
  BmField('blackice', 'Black Ice', 1086, 1448, 206, 880, 114, 1304, 697, 117, 'white', faName: 'یخ سیاه'),
  BmField('autumn', 'Autumn', 1086, 1448, 210, 878, 116, 1304, 695, 116, 'white', faName: 'پاییز'),
  BmField('frost', 'Frost Arena', 1086, 1448, 198, 888, 100, 1336, 700, 120, 'white', faName: 'آرنای یخبندان'),
  BmField('glacier', 'Glacier', 1086, 1448, 208, 888, 116, 1304, 698, 118, 'white', faName: 'یخچال'),
];

/// Ids of pitches removed from the game (v7, v9, v11 and v12). Kept only so tests can check they never come back.
/// v12: 'checker', 'futsal', 'arena' and 'psg' are back (the owner picked them again).
const List<String> kBmRemovedFieldIds = <String>[
  'neon_cup', 'street_cage', 'sockerbox', 'gold_leather', 'neon_grass', 'royal_gold',
  // v9: every older pitch
  'nexora_green', 'forest', 'ice', 'ocean', 'street', 'streetarena', 'lava', 'stadium',
  'arena2', 'desert', 'grove', 'pool', 'neon', 'royal', 'mahogany', 'leather', 'aqua', 'asphalt', 'court', 'cyberbox',
  'realmadrid', 'acmilan', 'barcelona', 'persepolis', 'esteghlal', 'mancity',
  // v11: the three v9 Sockerbox arts
  'nx_neon_arena', 'nx_gold_checker', 'nx_gold_stripes',
  // v12: the seven v11 arts
  'nx_green_plain', 'nx_rings_green_new', 'nx_checker_green', 'nx_stripes_green', 'nx_stripes_teal', 'nx_ember_street',
  'nx_black_sockerbox',
];

/// A saved / synced pitch index -> a valid one: anything missing or out of range (e.g. a removed v6 pitch) is the
/// default pitch 0 (v12: Tropical).
int bmFieldIndex(int? i) => (i == null || i < 0 || i >= kBmFieldsRaw.length) ? 0 : i;

/// Local preference key of the chosen pitch. v11: new key, so an index saved for the old v9 pitches (`bm.field`) is
/// never read as one of the new pitches: every player starts on pitch 0 until they pick again.
const String kBmFieldPref = 'bm.field.v11';

/// Pitch [i]'s name in the UI language (Persian when [fa] and the pitch has one).
String bmFieldName(int i, bool fa) {
  final BmField f = kBmFieldsRaw[bmFieldIndex(i)];
  return fa && f.faName.isNotEmpty ? f.faName : f.name;
}

/// Goal art measured on each sprite (alpha): [width, height, left post centre, right post centre, post half-width,
/// inner edge of the back bar, bottom of the posts] - x values are fractions of the width, y values of the height.
/// The engine builds the posts, the side nets and the back net from these numbers, so the drawn goal is the collider.
const Map<String, List<double>> kBmGS = <String, List<double>>{
  // The only goal art. v12: the owner's new white.webp (1024 x 374, white tubular frame, hexagonal net), measured on
  // its alpha: post centres at the leg feet, leg half-width, inner edge of the back bar, foot of the legs.
  'white': <double>[1024, 374, 0.0488, 0.9517, 0.0151, 0.0936, 0.9973],
};

/// v10 (owner art 2026-11-22): the catalogue is the owner's full crest archive — 47 club badges,
/// 19 national crests and 12 NX faction coins, plus the 6 elite "second finish" coins and the
/// 2 bosses, cut one disc per coin by tool/build_fs_v10_assets.py (clubs 47, nations 19, nx 12, cars 24, sport 12, elite 6, legends 2). The v9 car and sport
/// sets are kept as they are (same ids, same art on discs/v9). This table is generated: edit tool/teams_v10.py.
const List<List<Object>> kBmCats = <List<Object>>[
  <Object>['clubs', 'Clubs', 'باشگاهی'],
  <Object>['nations', 'Nations', 'ملی'],
  <Object>['nx', 'NX', 'نیکسورا'],
  <Object>['cars', 'Cars', 'خودرو'],
  <Object>['sport', 'Sport', 'ورزشی'],
  <Object>['elite', 'Elite', 'ویژه'],
  <Object>['legends', 'Legends', 'افسانه‌ای'],
  <Object>['custom', 'Custom', 'اختصاصی'],
];

/// One selectable piece set. [power] scales the shot impulse, [accuracy] narrows the aim spread (both 1..10).
class BmTeamDef {
  const BmTeamDef(this.id, this.cat, this.name, this.faName, this.art, this.power, this.accuracy);
  final String id, cat, name;
  /// Persian name (shown when the UI is in Persian; the English name above is the canonical one).
  final String faName;
  /// Asset path relative to assets/games/bermuda/ (without .webp).
  final String art;
  final int power, accuracy;
}

/// Shop catalogue ids: `club0..club31` and `nat20..nat23` are the v9 car / sport sets (their ids are the prices the
/// live nx_catalog already sells); everything else is a v10 id. Free teams: NX Core, NX Cyan, NX Mercury
/// (gem_shop.dart kFreeTeams), so a new player can always field a team.
const List<BmTeamDef> kBmTeamDefs = <BmTeamDef>[
  BmTeamDef('realmadrid', 'clubs', 'Real Madrid', 'رئال مادرید', 'discs/v10/realmadrid', 10, 10),
  BmTeamDef('barcelona', 'clubs', 'Barcelona', 'بارسلونا', 'discs/v10/barcelona', 10, 9),
  BmTeamDef('bayern', 'clubs', 'Bayern München', 'بایرن مونیخ', 'discs/v10/bayern', 9, 10),
  BmTeamDef('mancity', 'clubs', 'Manchester City', 'منچستر سیتی', 'discs/v10/mancity', 9, 10),
  BmTeamDef('liverpool', 'clubs', 'Liverpool', 'لیورپول', 'discs/v10/liverpool', 10, 8),
  BmTeamDef('manunited', 'clubs', 'Manchester United', 'منچستر یونایتد', 'discs/v10/manunited', 8, 9),
  BmTeamDef('arsenal', 'clubs', 'Arsenal', 'آرسنال', 'discs/v10/arsenal', 8, 9),
  BmTeamDef('chelsea', 'clubs', 'Chelsea', 'چلسی', 'discs/v10/chelsea', 8, 9),
  BmTeamDef('tottenham', 'clubs', 'Tottenham Hotspur', 'تاتنهام', 'discs/v10/tottenham', 8, 8),
  BmTeamDef('newcastle', 'clubs', 'Newcastle United', 'نیوکاسل', 'discs/v10/newcastle', 8, 8),
  BmTeamDef('astonvilla', 'clubs', 'Aston Villa', 'استون ویلا', 'discs/v10/astonvilla', 8, 8),
  BmTeamDef('westham', 'clubs', 'West Ham United', 'وستهام', 'discs/v10/westham', 7, 8),
  BmTeamDef('everton', 'clubs', 'Everton', 'اورتون', 'discs/v10/everton', 7, 7),
  BmTeamDef('leipzig', 'clubs', 'RB Leipzig', 'لایپزیگ', 'discs/v10/leipzig', 8, 8),
  BmTeamDef('dortmund', 'clubs', 'Borussia Dortmund', 'دورتموند', 'discs/v10/dortmund', 9, 8),
  BmTeamDef('leverkusen', 'clubs', 'Bayer Leverkusen', 'بایر لورکوزن', 'discs/v10/leverkusen', 8, 8),
  BmTeamDef('wolfsburg', 'clubs', 'VfL Wolfsburg', 'وولفسبورگ', 'discs/v10/wolfsburg', 7, 8),
  BmTeamDef('inter', 'clubs', 'Inter', 'اینتر', 'discs/v10/inter', 9, 8),
  BmTeamDef('acmilan', 'clubs', 'AC Milan', 'آ.ث. میلان', 'discs/v10/acmilan', 9, 8),
  BmTeamDef('juventus', 'clubs', 'Juventus', 'یوونتوس', 'discs/v10/juventus', 9, 8),
  BmTeamDef('napoli', 'clubs', 'Napoli', 'ناپولی', 'discs/v10/napoli', 8, 9),
  BmTeamDef('roma', 'clubs', 'Roma', 'آ.اس. رم', 'discs/v10/roma', 7, 8),
  BmTeamDef('lazio', 'clubs', 'Lazio', 'لاتزیو', 'discs/v10/lazio', 8, 8),
  BmTeamDef('fiorentina', 'clubs', 'Fiorentina', 'فیورنتینا', 'discs/v10/fiorentina', 7, 8),
  BmTeamDef('psg', 'clubs', 'Paris Saint-Germain', 'پاری سن ژرمن', 'discs/v10/psg', 10, 9),
  BmTeamDef('marseille', 'clubs', 'Olympique Marseille', 'مارسی', 'discs/v10/marseille', 8, 8),
  BmTeamDef('lyon', 'clubs', 'Olympique Lyonnais', 'لیون', 'discs/v10/lyon', 8, 8),
  BmTeamDef('galatasaray', 'clubs', 'Galatasaray', 'گالاتاسرای', 'discs/v10/galatasaray', 8, 8),
  BmTeamDef('fenerbahce', 'clubs', 'Fenerbahçe', 'فنرباغچه', 'discs/v10/fenerbahce', 8, 8),
  BmTeamDef('benfica', 'clubs', 'Benfica', 'بنفیکا', 'discs/v10/benfica', 8, 9),
  BmTeamDef('sporting', 'clubs', 'Sporting CP', 'اسپورتینگ', 'discs/v10/sporting', 8, 8),
  BmTeamDef('ajax', 'clubs', 'Ajax', 'آژاکس', 'discs/v10/ajax', 8, 9),
  BmTeamDef('sevilla', 'clubs', 'Sevilla', 'سویا', 'discs/v10/sevilla', 8, 8),
  BmTeamDef('valencia', 'clubs', 'Valencia', 'والنسیا', 'discs/v10/valencia', 7, 8),
  BmTeamDef('villarreal', 'clubs', 'Villarreal', 'ویارئال', 'discs/v10/villarreal', 7, 8),
  BmTeamDef('atletico', 'clubs', 'Atlético Madrid', 'اتلتیکو مادرید', 'discs/v10/atletico', 9, 9),
  BmTeamDef('flamengo', 'clubs', 'Flamengo', 'فلامینگو', 'discs/v10/flamengo', 8, 8),
  BmTeamDef('riverplate', 'clubs', 'River Plate', 'ریور پلاته', 'discs/v10/riverplate', 8, 8),
  BmTeamDef('boca', 'clubs', 'Boca Juniors', 'بوکا جونیورز', 'discs/v10/boca', 8, 8),
  BmTeamDef('corinthians', 'clubs', 'Corinthians', 'کورینتیانس', 'discs/v10/corinthians', 7, 8),
  BmTeamDef('shakhtar', 'clubs', 'Shakhtar Donetsk', 'شاختار دونتسک', 'discs/v10/shakhtar', 8, 7),
  BmTeamDef('intermiami', 'clubs', 'Inter Miami', 'اینتر میامی', 'discs/v10/intermiami', 9, 9),
  BmTeamDef('alhilal', 'clubs', 'Al Hilal', 'الهلال', 'discs/v10/alhilal', 9, 8),
  BmTeamDef('alnassr', 'clubs', 'Al Nassr', 'النصر', 'discs/v10/alnassr', 9, 8),
  BmTeamDef('losc', 'clubs', 'Lille LOSC', 'لیل', 'discs/v10/losc', 8, 8),
  BmTeamDef('persepolis', 'clubs', 'Persepolis', 'پرسپولیس', 'discs/v10/persepolis', 9, 8),
  BmTeamDef('esteghlal', 'clubs', 'Esteghlal', 'استقلال', 'discs/v10/esteghlal', 9, 8),
  BmTeamDef('argentina', 'nations', 'Argentina', 'آرژانتین', 'discs/v10/argentina', 10, 10),
  BmTeamDef('brazil', 'nations', 'Brazil', 'برزیل', 'discs/v10/brazil', 10, 9),
  BmTeamDef('france', 'nations', 'France', 'فرانسه', 'discs/v10/france', 9, 9),
  BmTeamDef('germany', 'nations', 'Germany', 'آلمان', 'discs/v10/germany', 9, 9),
  BmTeamDef('spain', 'nations', 'Spain', 'اسپانیا', 'discs/v10/spain', 9, 9),
  BmTeamDef('italy', 'nations', 'Italy', 'ایتالیا', 'discs/v10/italy', 8, 9),
  BmTeamDef('england', 'nations', 'England', 'انگلیس', 'discs/v10/england', 9, 8),
  BmTeamDef('portugal', 'nations', 'Portugal', 'پرتغال', 'discs/v10/portugal', 9, 8),
  BmTeamDef('netherlands', 'nations', 'Netherlands', 'هلند', 'discs/v10/netherlands', 9, 8),
  BmTeamDef('belgium', 'nations', 'Belgium', 'بلژیک', 'discs/v10/belgium', 8, 8),
  BmTeamDef('croatia', 'nations', 'Croatia', 'کرواسی', 'discs/v10/croatia', 8, 8),
  BmTeamDef('uruguay', 'nations', 'Uruguay', 'اروگوئه', 'discs/v10/uruguay', 8, 8),
  BmTeamDef('japan', 'nations', 'Japan', 'ژاپن', 'discs/v10/japan', 7, 8),
  BmTeamDef('argentina_ii', 'nations', 'Argentina 1978', 'آرژانتین ۱۹۷۸', 'discs/v10/argentina_ii', 10, 9),
  BmTeamDef('germany_ii', 'nations', 'Germany 1954', 'آلمان ۱۹۵۴', 'discs/v10/germany_ii', 9, 8),
  BmTeamDef('brazil_ii', 'nations', 'Brazil 1970', 'برزیل ۱۹۷۰', 'discs/v10/brazil_ii', 10, 9),
  BmTeamDef('italy_ii', 'nations', 'Italy 1982', 'ایتالیا ۱۹۸۲', 'discs/v10/italy_ii', 8, 9),
  BmTeamDef('france_ii', 'nations', 'France 1998', 'فرانسه ۱۹۹۸', 'discs/v10/france_ii', 9, 9),
  BmTeamDef('spain_ii', 'nations', 'Spain 2010', 'اسپانیا ۲۰۱۰', 'discs/v10/spain_ii', 9, 9),
  BmTeamDef('nx_core', 'nx', 'NX Core', 'NX هسته', 'discs/v10/nx_core_green', 6, 6),
  BmTeamDef('nx_cyan', 'nx', 'NX Cyan', 'NX فیروزه', 'discs/v10/nx_cyan', 7, 7),
  BmTeamDef('nx_frost', 'nx', 'NX Frost', 'NX یخ', 'discs/v10/nx_frost', 10, 10),
  BmTeamDef('nx_frost_blue', 'nx', 'NX Glacier', 'NX یخچال', 'discs/v10/nx_frost_blue', 9, 9),
  BmTeamDef('nx_dragon', 'nx', 'NX Dragon', 'NX اژدها', 'discs/v10/nx_dragon_gold', 10, 9),
  BmTeamDef('nx_dragon2', 'nx', 'NX Wyrm', 'NX اژدهای شعله', 'discs/v10/nx_dragon_gloss', 9, 9),
  BmTeamDef('nx_phoenix', 'nx', 'NX Phoenix', 'NX ققنوس', 'discs/v10/nx_phoenix_violet', 9, 10),
  BmTeamDef('nx_phoenix2', 'nx', 'NX Ember', 'NX ققنوس ارغوانی', 'discs/v10/nx_phoenix_purple', 9, 9),
  BmTeamDef('nx_lion', 'nx', 'NX Lion', 'NX شیر', 'discs/v10/nx_lion_gold', 9, 9),
  BmTeamDef('nx_lion2', 'nx', 'NX Crimson', 'NX شیر سرخ', 'discs/v10/nx_lion_red', 9, 8),
  BmTeamDef('nx_eagle', 'nx', 'NX Eagle', 'NX عقاب', 'discs/v10/nx_eagle_gold', 8, 9),
  BmTeamDef('nx_eagle2', 'nx', 'NX Valkyrie', 'NX والکیری', 'discs/v10/nx_eagle_white', 8, 9),
  BmTeamDef('club0', 'cars', 'BMW', 'بی‌ام‌و', 'discs/v9/bmw', 9, 9),
  BmTeamDef('club1', 'cars', 'Mercedes-Benz', 'مرسدس بنز', 'discs/v9/mercedes', 9, 9),
  BmTeamDef('club2', 'cars', 'Audi', 'آئودی', 'discs/v9/audi', 8, 9),
  BmTeamDef('club3', 'cars', 'Bugatti', 'بوگاتی', 'discs/v9/bugatti', 10, 9),
  BmTeamDef('club4', 'cars', 'Ferrari', 'فراری', 'discs/v9/ferrari', 10, 9),
  BmTeamDef('club5', 'cars', 'Porsche', 'پورشه', 'discs/v9/porsche', 9, 10),
  BmTeamDef('club6', 'cars', 'McLaren', 'مک‌لارن', 'discs/v9/mclaren', 10, 8),
  BmTeamDef('club7', 'cars', 'Aston Martin', 'استون مارتین', 'discs/v9/aston_martin', 8, 9),
  BmTeamDef('club8', 'cars', 'Volkswagen', 'فولکس‌واگن', 'discs/v9/volkswagen', 7, 8),
  BmTeamDef('club9', 'cars', 'Lamborghini', 'لامبورگینی', 'discs/v9/lamborghini', 10, 8),
  BmTeamDef('club10', 'cars', 'Toyota', 'تویوتا', 'discs/v9/toyota', 7, 9),
  BmTeamDef('club11', 'cars', 'Nissan', 'نیسان', 'discs/v9/nissan', 7, 8),
  BmTeamDef('club12', 'cars', 'BMW II', 'بی‌ام‌و ۲', 'discs/v9/bmw_ii', 9, 9),
  BmTeamDef('club13', 'cars', 'Mercedes-Benz II', 'مرسدس بنز ۲', 'discs/v9/mercedes_ii', 9, 9),
  BmTeamDef('club14', 'cars', 'Audi II', 'آئودی ۲', 'discs/v9/audi_ii', 8, 9),
  BmTeamDef('club15', 'cars', 'Toyota II', 'تویوتا ۲', 'discs/v9/toyota_ii', 7, 9),
  BmTeamDef('club16', 'cars', 'Ferrari II', 'فراری ۲', 'discs/v9/ferrari_ii', 10, 9),
  BmTeamDef('club17', 'cars', 'Porsche II', 'پورشه ۲', 'discs/v9/porsche_ii', 9, 10),
  BmTeamDef('club18', 'cars', 'Honda', 'هوندا', 'discs/v9/honda', 7, 8),
  BmTeamDef('club19', 'cars', 'Ford', 'فورد', 'discs/v9/ford', 8, 7),
  BmTeamDef('club20', 'cars', 'Volkswagen II', 'فولکس‌واگن ۲', 'discs/v9/volkswagen_ii', 7, 8),
  BmTeamDef('club21', 'cars', 'Lamborghini II', 'لامبورگینی ۲', 'discs/v9/lamborghini_ii', 10, 8),
  BmTeamDef('club22', 'cars', 'Chevrolet', 'شورلت', 'discs/v9/chevrolet', 8, 7),
  BmTeamDef('club23', 'cars', 'Nissan II', 'نیسان ۲', 'discs/v9/nissan_ii', 7, 8),
  BmTeamDef('club24', 'sport', 'Nike', 'نایکی', 'discs/v9/nike', 9, 8),
  BmTeamDef('club25', 'sport', 'Adidas', 'آدیداس', 'discs/v9/adidas', 8, 9),
  BmTeamDef('club26', 'sport', 'Puma', 'پوما', 'discs/v9/puma', 8, 8),
  BmTeamDef('club27', 'sport', 'Under Armour', 'آندر آرمور', 'discs/v9/under_armour', 8, 7),
  BmTeamDef('club28', 'sport', 'Reebok', 'ریباک', 'discs/v9/reebok', 7, 7),
  BmTeamDef('club29', 'sport', 'New Balance', 'نیوبالانس', 'discs/v9/new_balance', 7, 8),
  BmTeamDef('club30', 'sport', 'Nike II', 'نایکی ۲', 'discs/v9/nike_ii', 9, 8),
  BmTeamDef('club31', 'sport', 'Adidas II', 'آدیداس ۲', 'discs/v9/adidas_ii', 8, 9),
  BmTeamDef('nat20', 'sport', 'Puma II', 'پوما ۲', 'discs/v9/puma_ii', 8, 8),
  BmTeamDef('nat21', 'sport', 'Under Armour II', 'آندر آرمور ۲', 'discs/v9/under_armour_ii', 8, 7),
  BmTeamDef('nat22', 'sport', 'New Balance II', 'نیوبالانس ۲', 'discs/v9/new_balance_ii', 7, 8),
  BmTeamDef('nat23', 'sport', 'Reebok II', 'ریباک ۲', 'discs/v9/reebok_ii', 7, 7),
  BmTeamDef('elite_realmadrid', 'elite', 'Real Madrid Gold', 'رئال مادرید طلایی', 'discs/v10/realmadrid_ii', 10, 10),
  BmTeamDef('elite_barcelona', 'elite', 'Barcelona Prism', 'بارسلونا منشوری', 'discs/v10/barcelona_ii', 10, 10),
  BmTeamDef('elite_bayern', 'elite', 'Bayern Redline', 'بایرن سرخ', 'discs/v10/bayern_ii', 10, 9),
  BmTeamDef('elite_psg', 'elite', 'Paris Noir', 'پاریس شب', 'discs/v10/psg_ii', 9, 10),
  BmTeamDef('elite_chelsea', 'elite', 'Chelsea Cobalt', 'چلسی کبالت', 'discs/v10/chelsea', 9, 10),
  BmTeamDef('elite_dortmund', 'elite', 'Dortmund Amber', 'دورتموند کهربایی', 'discs/v10/dortmund_ii', 10, 9),
  BmTeamDef('nx_merciless', 'legends', 'Merciless', 'بی‌رحم', 'discs/v10/arena_golem', 10, 10),
  BmTeamDef('nx_capo', 'legends', 'Capo', 'کاپو', 'discs/v10/arena_dragon', 10, 10),
  // Not a team: the lobby's "create your custom team" tile (1000 gems, then a photo). The shared custom teams
  // themselves (cx_<hex>, power 10) are appended to kBmTeams at runtime by FsCustomTeams.
  BmTeamDef('custom_team', 'custom', 'Create Custom Team', 'ساخت تیم اختصاصی', 'discs/v10/nx_core_green', 10, 10),
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

/// v12 (owner upload 2026-11-24): the match balls are the owner's 18 new balls (six single arts and two sheets), each
/// cut on its own detected circle, fully transparent outside it, by tool/build_fs_v12_assets.py into
/// `assets/games/bermuda/balls/v9/<slug>.webp` (256 x 256, the ball fills its square; the folder name is kept). The
/// 3D ball renderer (BmBallRenderer) rolls each flat art with the ball's real motion.
const List<String> kBmBallN = <String>[
  'NX Lime',
  'NX Blue',
  'NX Violet',
  'NX Orange',
  'Classic',
  'NX Blue Wave',
  'NX Blue Stripe',
  'NX Cobalt',
  'NX Red Hex',
  'NX Carbon',
  'NX White Strike',
  'NX Black Strike',
  'NX Red Strike',
  'NX Blue Strike',
  'NX Red Flash',
  'NX Blue Flash',
  'Pro Sky',
  'Pro Red',
  'Pro Lime',
  'Pro Violet',
  'Pro Orange',
  'Pro Teal',
];
const List<String> kBmBallFa = <String>[
  'NX لیمویی',
  'NX آبی',
  'NX بنفش',
  'NX نارنجی',
  'کلاسیک',
  'موج آبی',
  'نوار آبی',
  'کبالت',
  'شش‌ضلعی سرخ',
  'کربن',
  'صاعقه سفید',
  'صاعقه سیاه',
  'صاعقه سرخ',
  'صاعقه آبی',
  'آذرخش سرخ',
  'آذرخش آبی',
  'پرو آسمانی',
  'پرو سرخ',
  'پرو لیمویی',
  'پرو بنفش',
  'پرو نارنجی',
  'پرو فیروزه‌ای',
];
/// All 22 Finger Soccer balls in `assets/games/bermuda/balls/v9/` (4 NX v13 + 18 Pro/Strike v12).
const List<String> kBmBallSlug = <String>[
  'nx_lime',
  'nx_blue',
  'nx_violet',
  'nx_orange',
  'nx_red_classic',
  'nx_blue_wave',
  'nx_blue_stripe',
  'nx_cobalt',
  'nx_red_hex',
  'nx_carbon',
  'nx_white_strike',
  'nx_black_strike',
  'nx_red_strike',
  'nx_blue_strike',
  'nx_red_flash',
  'nx_blue_flash',
  'pro_sky',
  'pro_red',
  'pro_lime',
  'pro_violet',
  'pro_orange',
  'pro_teal',
];
const int kBmDefaultBall = 0;

/// Preference key of the player's match ball. v9 uses a new key: every saved index named an old ball.
const String kBmBallPref = 'bm.ball.v13';

/// A saved / synced ball index -> a valid one (missing or unknown = the default ball).
int bmBallIndex(int? i) => (i == null || i < 0 || i >= kBmBallN.length) ? kBmDefaultBall : i;

/// The art of ball [i] (also its picker / shop thumbnail).
String bmBallArt(int i) => 'assets/games/bermuda/balls/v9/${kBmBallSlug[bmBallIndex(i)]}.webp';
String bmBallThumb(int i) => bmBallArt(i);

class BmAnimBall {
  const BmAnimBall(this.sheet, this.frames, this.frameMs, this.thumb, {this.gifTimed = false});
  final String sheet;
  final int frames;
  final int frameMs;
  final String thumb;
  /// GIF balls: frames in the GIF's order at exactly [frameMs] each while the ball moves.
  final bool gifTimed;

  /// Frame shown after [ms] of playback (GIF order, [frameMs] each, looping).
  int frameAt(double ms) => (ms / frameMs).floor() % frames;
}

/// Animated sprite-sheet balls. v9: none (every ball is rolled by the 3D renderer); the painter keeps the sheet path
/// so a future animated ball only needs an entry here.
const Map<int, BmAnimBall> kBmAnimBalls = <int, BmAnimBall>{};

/// Art fills (tool/build_fs_v9_assets.py): disc rim radius / half sprite size, ball radius / half frame size.
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
  // v11 pitches: firework colours taken from each art's frame / display colours.
  'nx_checker_silver': BmFa(1, <int>[0xFFE8EEF6, 0xFF2F86FF, 0xFF5BD12A], 0),
  'nx_rings_green': BmFa(5, <int>[0xFF2AFF15, 0xFFB6FFA0, 0xFFFFFFFF], 0),
  'nx_street': BmFa(1, <int>[0xFFFFC21F, 0xFF35FF06, 0xFFFFFFFF], 0),
  'nx_neon_blue': BmFa(5, <int>[0xFF2F86FF, 0xFFFF3B30, 0xFFFFC94A], 0),
  'nx_royal_purple': BmFa(1, <int>[0xFFB04DFF, 0xFFFFC94A, 0xFFFFFFFF], 0),
  // v12 pitches: firework colours taken from each art's rails and lights.
  'tropical': BmFa(1, <int>[0xFF3BE0FF, 0xFFFFD27A, 0xFF7CFF4A], 0),
  'psg': BmFa(1, <int>[0xFF2F5BFF, 0xFFFF3B4A, 0xFFFFFFFF], 0),
  'campnou': BmFa(1, <int>[0xFFB0153A, 0xFF2F5BFF, 0xFFFFD86B], 0),
  'pitch': BmFa(1, <int>[0xFFFFFFFF, 0xFF7CFF4A, 0xFFFF4A4A], 0),
  'blackice': BmFa(5, <int>[0xFFBFE6FF, 0xFFFFFFFF, 0xFF6FA8FF], 0),
  'frost': BmFa(5, <int>[0xFFBFE6FF, 0xFFFFFFFF, 0xFF6FA8FF], 0),
  'glacier': BmFa(5, <int>[0xFF8FE8FF, 0xFFFFFFFF, 0xFF3B9BFF], 0),
  'autumn': BmFa(1, <int>[0xFFFF8A1F, 0xFFFFD24A, 0xFFFF4A2A], 0),
  'futsal': BmFa(1, <int>[0xFFFF3B4A, 0xFF2F86FF, 0xFFFFFFFF], 0),
  // fallback used by the engine for any id without its own entry
  'stadium': BmFa(1, <int>[0xFFFFD86B, 0xFFFFFFFF, 0xFFFFE9A8], 0),
};
