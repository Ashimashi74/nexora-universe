// Data adapters for the finger-soccer pre-match intro (splash -> team select -> formation select).
// Teams and formations come straight from the engine (kBmTeams, kBmForms / bmSlots); this file only adds the
// Persian display names and reads the formation list in whatever shape the engine defines it.
import '../core/bm_engine.dart';

/// What the intro hands to the match: one team id and one formation index per side (side 0 = bottom / team one).
class FsMatchPick {
  const FsMatchPick({required this.teams, required this.forms});
  final List<String> teams;
  final List<int> forms;
}

/// One formation as the formation screen draws it: its name and the disc slots of the own half
/// ([x] 0..1 across the pitch, [y] 0..0.5 from the own goal line to the halfway line).
class FsFormation {
  const FsFormation(this.index, this.name, this.slots);
  final int index;
  final String name;
  final List<List<double>> slots;
}

final RegExp _fa = RegExp('[\u0600-\u06FF]');

/// Every formation the engine defines, in its order. The name is the Persian label when the engine has one.
List<FsFormation> fsFormations({bool fa = true}) {
  final List<FsFormation> out = <FsFormation>[];
  for (int i = 0; i < kBmForms.length; i++) {
    final List<Object> f = kBmForms[i];
    final List<String> names = f.whereType<String>().toList();
    String name = names.isEmpty ? '${i + 1}' : (names.length > 1 ? names[1] : names[0]);
    if (fa) {
      for (final String s in names) {
        if (_fa.hasMatch(s)) {
          name = s;
          break;
        }
      }
    }
    List<List<double>> slots;
    try {
      slots = bmSlots(i);
    } catch (_) {
      slots = const <List<double>>[];
    }
    out.add(FsFormation(i, name, slots));
  }
  return out;
}

/// Turn time is not a per-team value in the engine (every team gets the same turn clock), so the "time" bar shows
/// the team's overall rating, the mean of power and aim, until a real per-team time stat exists.
int fsTimeStat(BmTeam t) => ((t.power + t.accuracy) / 2).round();

const List<String> _faDigits = <String>['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];

/// Western digits -> Persian digits.
String fsFa(Object v) => '$v'.replaceAllMapped(RegExp('[0-9]'), (Match m) => _faDigits[int.parse(m[0]!)]);

String fsTeamName(BmTeam t, bool fa) => fa ? (kFsTeamFa[t.name] ?? t.name) : t.name;

/// Persian names of the engine's teams (by their English name in kBmTeamDefs).
const Map<String, String> kFsTeamFa = <String, String>{
  'Real Madrid': 'رئال مادرید',
  'Barcelona': 'بارسلونا',
  'Manchester City': 'منچستر سیتی',
  'Manchester United': 'منچستر یونایتد',
  'Liverpool': 'لیورپول',
  'Arsenal': 'آرسنال',
  'Chelsea': 'چلسی',
  'Bayern Munich': 'بایرن مونیخ',
  'Borussia Dortmund': 'دورتموند',
  'Paris Saint-Germain': 'پاری سن ژرمن',
  'Inter Milan': 'اینتر',
  'AC Milan': 'میلان',
  'Juventus': 'یوونتوس',
  'Atletico Madrid': 'اتلتیکو مادرید',
  'Ajax': 'آژاکس',
  'Benfica': 'بنفیکا',
  'Porto': 'پورتو',
  'Boca Juniors': 'بوکا جونیورز',
  'River Plate': 'ریورپلاته',
  'Flamengo': 'فلامینگو',
  'Al Nassr': 'النصر',
  'Al Hilal': 'الهلال',
  'Roma': 'رم',
  'Besiktas': 'بشیکتاش',
  'Tottenham': 'تاتنهام',
  'Marseille': 'مارسی',
  'Napoli': 'ناپولی',
  'Sporting CP': 'اسپورتینگ',
  'Sevilla': 'سویا',
  'Valencia': 'والنسیا',
  'PSV': 'پی‌اس‌وی',
  'Newcastle': 'نیوکاسل',
  'Persepolis': 'پرسپولیس',
  'Esteghlal': 'استقلال',
  'Inter Miami': 'اینتر میامی',
  'Wolfsburg': 'ولفسبورگ',
  'Shakhtar Donetsk': 'شاختار',
  'Celtic': 'سلتیک',
  'Rangers': 'رنجرز',
  'Monaco': 'موناکو',
  'Argentina': 'آرژانتین',
  'Brazil': 'برزیل',
  'France': 'فرانسه',
  'Germany': 'آلمان',
  'Portugal': 'پرتغال',
  'Spain': 'اسپانیا',
  'Italy': 'ایتالیا',
  'England': 'انگلیس',
  'Netherlands': 'هلند',
  'Belgium': 'بلژیک',
  'Uruguay': 'اروگوئه',
  'Sweden': 'سوئد',
  'Poland': 'لهستان',
  'Denmark': 'دانمارک',
  'Croatia': 'کرواسی',
  'Switzerland': 'سوئیس',
  'Mexico': 'مکزیک',
  'USA': 'آمریکا',
  'Japan': 'ژاپن',
  'South Korea': 'کره جنوبی',
  'Morocco': 'مراکش',
  'Senegal': 'سنگال',
  'Australia': 'استرالیا',
  'Tunisia': 'تونس',
  'Nigeria': 'نیجریه',
  'Cameroon': 'کامرون',
  'Ghana': 'غنا',
  'Egypt': 'مصر',
  'Iceland': 'ایسلند',
  'Iran': 'ایران',
  'Qatar': 'قطر',
  'Saudi Arabia': 'عربستان',
  'Colombia': 'کلمبیا',
  'Lebanon': 'لبنان',
  'Louis Vuitton': 'لویی ویتون',
  'Chanel': 'شنل',
  'Gucci': 'گوچی',
  'Hermes': 'هرمس',
  'Prada': 'پرادا',
  'Dior': 'دیور',
  'Versace': 'ورساچه',
  'Rolex': 'رولکس',
  'Cartier': 'کارتیه',
  'Fendi': 'فندی',
  'Valentino': 'والنتینو',
  'Burberry': 'باربری',
  'Saint Laurent': 'سن لوران',
  'Swarovski': 'سواروسکی',
  'Lamborghini': 'لامبورگینی',
  'Ferrari': 'فراری',
  'Rolls-Royce': 'رولز رویس',
  'Mercedes-Benz': 'مرسدس بنز',
  'BMW': 'بی‌ام‌و',
  'Porsche': 'پورشه',
  'Maserati': 'مازراتی',
  'Aston Martin': 'استون مارتین',
  'Bentley': 'بنتلی',
  'Bugatti': 'بوگاتی',
  'Lexus': 'لکسوس',
  'Cadillac': 'کادیلاک',
  'McLaren': 'مک‌لارن',
  'Tesla': 'تسلا',
  'Nike': 'نایکی',
  'Adidas': 'آدیداس',
  'Puma': 'پوما',
  'Under Armour': 'آندر آرمور',
  'New Balance': 'نیوبالانس',
  'Reebok': 'ریباک',
  'Jordan': 'جردن',
  'Asics': 'اسیکس',
  'Wilson': 'ویلسون',
  'Speedo': 'اسپیدو',
  'Converse': 'کانورس',
  'Vans': 'ونس',
  'NBA': 'ان‌بی‌ای',
  'Umbro': 'آمبرو',
  'Barcelona Gold': 'بارسلونا طلایی',
};
