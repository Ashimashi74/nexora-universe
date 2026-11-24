#!/usr/bin/env python3
"""Team catalogue v10 (owner art 2026-11-22) — the single source for bm_data.dart and the SQL seed.

Categories and counts (127 teams):
  clubs     46  the owner's league crests, one per club (la Liga / PL / Serie A / L1 / Bundesliga / Liga Portugal /
                Eredivisie / Brazil / Argentina / Saudi / Iran / Turkey / Scotland / Ukraine / MLS / Belgium)
  nations   24  the owner's national crests
  nx        12  the NX house / faction coins (metal, gloss, arena)
  cars      24  kept from v9 (the owner's car badge sheet) — same ids, same art, now under "cars_v10"
  sport     12  kept from v9 (the owner's sport-brand sheet)
  elite      6  the owner's "second finish" coins: alternative art for six of the biggest clubs
  legends    2  the owner's original final-boss discs, Merciless and Capo
  = 46+24+12+24+12+6+2 = 126

Every entry: (id, category, English name, Persian name, art slug under discs/v10, power, accuracy).
Ids never change once shipped: the gem shop catalogue, player inventories and saved setups reference them.
"""
from __future__ import annotations

CATS = [
    # id,      English tab, Persian tab
    ('clubs',   'Clubs',   'باشگاهی'),
    ('nations', 'Nations', 'ملی'),
    ('nx',      'NX',      'انیکس'),
    ('cars',    'Cars',    'خودرو'),
    ('sport',   'Sport',   'ورزشی'),
    ('elite',   'Elite',   'ویژه'),
    ('legends', 'Legends', 'افسانه‌ای'),
]

TEAMS = [
    # ---------------------------------------------------------------- clubs (46)
    ('realmadrid',   'clubs', 'Real Madrid',        'رئال مادرید',      'realmadrid',      10, 10),
    ('barcelona',    'clubs', 'Barcelona',          'بارسلونا',         'barcelona',       10, 9),
    ('bayern',       'clubs', 'Bayern München',     'بایرن مونیخ',      'bayern',          9, 10),
    ('mancity',      'clubs', 'Manchester City',    'منچستر سیتی',      'mancity',         9, 10),
    ('liverpool',    'clubs', 'Liverpool',          'لیورپول',          'liverpool',       10, 8),
    ('manunited',    'clubs', 'Manchester United',  'منچستر یونایتد',   'manunited',       8, 9),
    ('arsenal',      'clubs', 'Arsenal',            'آرسنال',           'arsenal',         8, 9),
    ('chelsea',      'clubs', 'Chelsea',            'چلسی',             'chelsea',         8, 9),
    ('tottenham',    'clubs', 'Tottenham Hotspur',  'تاتنهام',          'tottenham',       8, 8),
    ('newcastle',    'clubs', 'Newcastle United',   'نیوکاسل',          'newcastle',       8, 8),
    ('astonvilla',   'clubs', 'Aston Villa',        'استون ویلا',       'astonvilla',      8, 8),
    ('westham',      'clubs', 'West Ham United',    'وستهام',          'westham',         7, 8),
    ('everton',      'clubs', 'Everton',            'اورتون',           'everton',         7, 7),
    ('leipzig',      'clubs', 'RB Leipzig',         'لایپزیگ',          'leipzig',         8, 8),
    ('dortmund',     'clubs', 'Borussia Dortmund',  'دورتموند',         'dortmund',        9, 8),
    ('leverkusen',   'clubs', 'Bayer Leverkusen',   'بایر لورکوزن',     'leverkusen',      8, 8),
    ('wolfsburg',    'clubs', 'VfL Wolfsburg',      'وولفسبورگ',        'wolfsburg',       7, 8),
    ('inter',        'clubs', 'Inter',              'اینتر',            'inter',           9, 8),
    ('acmilan',      'clubs', 'AC Milan',           'آ.ث. میلان',       'acmilan',         9, 8),
    ('juventus',     'clubs', 'Juventus',           'یوونتوس',          'juventus',        9, 8),
    ('napoli',       'clubs', 'Napoli',             'ناپولی',           'napoli',          8, 9),
    ('roma',         'clubs', 'Roma',               'آ.اس. رم',         'roma',            7, 8),
    ('lazio',        'clubs', 'Lazio',              'لاتزیو',           'lazio',           8, 8),
    ('fiorentina',   'clubs', 'Fiorentina',         'فیورنتینا',        'fiorentina',      7, 8),
    ('psg',          'clubs', 'Paris Saint-Germain','پاری سن ژرمن',     'psg',             10, 9),
    ('marseille',    'clubs', 'Olympique Marseille','مارسی',            'marseille',       8, 8),
    ('lyon',         'clubs', 'Olympique Lyonnais', 'لیون',             'lyon',            8, 8),
    ('galatasaray',  'clubs', 'Galatasaray',        'گالاتاسرای',       'galatasaray',     8, 8),
    ('fenerbahce',   'clubs', 'Fenerbahçe',         'فنرباغچه',         'fenerbahce',      8, 8),
    ('benfica',      'clubs', 'Benfica',            'بنفیکا',           'benfica',         8, 9),
    ('sporting',     'clubs', 'Sporting CP',        'اسپورتینگ',        'sporting',        8, 8),
    ('ajax',         'clubs', 'Ajax',               'آژاکس',            'ajax',            8, 9),
    ('sevilla',      'clubs', 'Sevilla',            'سویا',             'sevilla',         8, 8),
    ('valencia',     'clubs', 'Valencia',           'والنسیا',          'valencia',        7, 8),
    ('villarreal',   'clubs', 'Villarreal',         'ویارئال',          'villarreal',      7, 8),
    ('atletico',     'clubs', 'Atlético Madrid',    'اتلتیکو مادرید',   'atletico',        9, 9),
    ('flamengo',     'clubs', 'Flamengo',           'فلامینگو',         'flamengo',        8, 8),
    ('riverplate',   'clubs', 'River Plate',        'ریور پلاته',       'riverplate',      8, 8),
    ('boca',         'clubs', 'Boca Juniors',       'بوکا جونیورز',     'boca',            8, 8),
    ('corinthians',  'clubs', 'Corinthians',        'کورینتیانس',       'corinthians',     7, 8),
    ('shakhtar',     'clubs', 'Shakhtar Donetsk',   'شاختار دونتسک',    'shakhtar',        8, 7),
    ('intermiami',   'clubs', 'Inter Miami',        'اینتر میامی',      'intermiami',      9, 9),
    ('alhilal',      'clubs', 'Al Hilal',           'الهلال',           'alhilal',         9, 8),
    ('alnassr',      'clubs', 'Al Nassr',           'النصر',            'alnassr',         9, 8),
    ('losc',         'clubs', 'Lille LOSC',          'لیل',              'losc',            8, 8),
    ('persepolis',   'clubs', 'Persepolis',          'پرسپولیس',         'persepolis',      9, 8),
    ('esteghlal',    'clubs', 'Esteghlal',           'استقلال',          'esteghlal',       9, 8),
    # ---------------------------------------------------------------- nations (24)
    ('argentina',    'nations', 'Argentina',        'آرژانتین',         'argentina',       10, 10),
    ('brazil',       'nations', 'Brazil',           'برزیل',            'brazil',          10, 9),
    ('france',       'nations', 'France',           'فرانسه',           'france',          9, 9),
    ('germany',      'nations', 'Germany',          'آلمان',            'germany',         9, 9),
    ('spain',        'nations', 'Spain',            'اسپانیا',          'spain',           9, 9),
    ('italy',        'nations', 'Italy',            'ایتالیا',          'italy',           8, 9),
    ('england',      'nations', 'England',          'انگلیس',           'england',         9, 8),
    ('portugal',     'nations', 'Portugal',         'پرتغال',           'portugal',        9, 8),
    ('netherlands',  'nations', 'Netherlands',      'هلند',             'netherlands',     9, 8),
    ('belgium',      'nations', 'Belgium',          'بلژیک',            'belgium',         8, 8),
    ('croatia',      'nations', 'Croatia',          'کرواسی',           'croatia',         8, 8),
    ('uruguay',      'nations', 'Uruguay',          'اروگوئه',          'uruguay',         8, 8),
    ('japan',        'nations', 'Japan',            'ژاپن',             'japan',           7, 8),
    # second finishes of the same crests (the owner's other national sheets), kept as their own pick
    ('argentina_ii', 'nations', 'Argentina 1978',   'آرژانتین ۱۹۷۸',    'argentina_ii',    10, 9),
    ('germany_ii',   'nations', 'Germany 1954',     'آلمان ۱۹۵۴',       'germany_ii',      9, 8),
    ('brazil_ii',    'nations', 'Brazil 1970',      'برزیل ۱۹۷۰',       'brazil_ii',       10, 9),
    ('italy_ii',     'nations', 'Italy 1982',       'ایتالیا ۱۹۸۲',     'italy_ii',        8, 9),
    ('france_ii',    'nations', 'France 1998',      'فرانسه ۱۹۹۸',      'france_ii',       9, 9),
    ('spain_ii',     'nations', 'Spain 2010',       'اسپانیا ۲۰۱۰',     'spain_ii',        9, 9),
    # ---------------------------------------------------------------- NX house / faction coins (12)
    ('nx_core',      'nx', 'NX Core',       'NX هسته',      'nx_core_green',    6, 6),
    ('nx_cyan',      'nx', 'NX Cyan',       'NX فیروزه',    'nx_cyan',          7, 7),
    ('nx_frost',     'nx', 'NX Frost',      'NX یخ',        'nx_frost',         10, 10),
    ('nx_frost_blue','nx', 'NX Glacier',    'NX یخچال',     'nx_frost_blue',    9, 9),
    ('nx_dragon',    'nx', 'NX Dragon',     'NX اژدها',     'nx_dragon_gold',   10, 9),
    ('nx_dragon2',   'nx', 'NX Wyrm',       'NX اژدهای شعله','nx_dragon_gloss', 9, 9),
    ('nx_phoenix',   'nx', 'NX Phoenix',    'NX ققنوس',     'nx_phoenix_violet', 9, 10),
    ('nx_phoenix2',  'nx', 'NX Ember',      'NX ققنوس ارغوانی','nx_phoenix_purple', 9, 9),
    ('nx_lion',      'nx', 'NX Lion',       'NX شیر',       'nx_lion_gold',     9, 9),
    ('nx_lion2',     'nx', 'NX Crimson',    'NX شیر سرخ',   'nx_lion_red',      9, 8),
    ('nx_eagle',     'nx', 'NX Eagle',      'NX عقاب',      'nx_eagle_gold',    8, 9),
    ('nx_eagle2',    'nx', 'NX Valkyrie',   'NX والکیری',   'nx_eagle_white',   8, 9),
    # ---------------------------------------------------------------- cars (24) — v9 art, unchanged
    ('club0',  'cars', 'BMW',            'بی‌ام‌و',        'bmw',          9, 9),
    ('club1',  'cars', 'Mercedes-Benz',  'مرسدس بنز',     'mercedes',     9, 9),
    ('club2',  'cars', 'Audi',           'آئودی',         'audi',         8, 9),
    ('club3',  'cars', 'Bugatti',        'بوگاتی',        'bugatti',     10, 9),
    ('club4',  'cars', 'Ferrari',        'فراری',         'ferrari',     10, 9),
    ('club5',  'cars', 'Porsche',        'پورشه',         'porsche',      9, 10),
    ('club6',  'cars', 'McLaren',        'مک‌لارن',       'mclaren',     10, 8),
    ('club7',  'cars', 'Aston Martin',   'استون مارتین',  'aston_martin', 8, 9),
    ('club8',  'cars', 'Volkswagen',     'فولکس‌واگن',    'volkswagen',   7, 8),
    ('club9',  'cars', 'Lamborghini',    'لامبورگینی',    'lamborghini', 10, 8),
    ('club10', 'cars', 'Toyota',         'تویوتا',        'toyota',       7, 9),
    ('club11', 'cars', 'Nissan',         'نیسان',         'nissan',       7, 8),
    ('club12', 'cars', 'BMW II',         'بی‌ام‌و ۲',      'bmw_ii',       9, 9),
    ('club13', 'cars', 'Mercedes-Benz II','مرسدس بنز ۲',  'mercedes_ii',  9, 9),
    ('club14', 'cars', 'Audi II',        'آئودی ۲',       'audi_ii',      8, 9),
    ('club15', 'cars', 'Toyota II',      'تویوتا ۲',      'toyota_ii',    7, 9),
    ('club16', 'cars', 'Ferrari II',     'فراری ۲',       'ferrari_ii',  10, 9),
    ('club17', 'cars', 'Porsche II',     'پورشه ۲',       'porsche_ii',   9, 10),
    ('club18', 'cars', 'Honda',          'هوندا',         'honda',        7, 8),
    ('club19', 'cars', 'Ford',           'فورد',          'ford',         8, 7),
    ('club20', 'cars', 'Volkswagen II',  'فولکس‌واگن ۲',  'volkswagen_ii', 7, 8),
    ('club21', 'cars', 'Lamborghini II', 'لامبورگینی ۲',  'lamborghini_ii', 10, 8),
    ('club22', 'cars', 'Chevrolet',      'شورلت',         'chevrolet',    8, 7),
    ('club23', 'cars', 'Nissan II',      'نیسان ۲',       'nissan_ii',    7, 8),
    # ---------------------------------------------------------------- sport (12) — v9 art, unchanged
    ('club24', 'sport', 'Nike',          'نایکی',         'nike',             9, 8),
    ('club25', 'sport', 'Adidas',        'آدیداس',        'adidas',           8, 9),
    ('club26', 'sport', 'Puma',          'پوما',          'puma',             8, 8),
    ('club27', 'sport', 'Under Armour',  'آندر آرمور',    'under_armour',     8, 7),
    ('club28', 'sport', 'Reebok',        'ریباک',         'reebok',           7, 7),
    ('club29', 'sport', 'New Balance',   'نیوبالانس',     'new_balance',      7, 8),
    ('club30', 'sport', 'Nike II',       'نایکی ۲',       'nike_ii',          9, 8),
    ('club31', 'sport', 'Adidas II',     'آدیداس ۲',      'adidas_ii',        8, 9),
    ('nat20',  'sport', 'Puma II',       'پوما ۲',        'puma_ii',          8, 8),
    ('nat21',  'sport', 'Under Armour II','آندر آرمور ۲', 'under_armour_ii',  8, 7),
    ('nat22',  'sport', 'New Balance II','نیوبالانس ۲',   'new_balance_ii',   7, 8),
    ('nat23',  'sport', 'Reebok II',     'ریباک ۲',       'reebok_ii',        7, 7),
    # ---------------------------------------------------------------- elite (6) — the owner's second finishes
    ('elite_realmadrid', 'elite', 'Real Madrid Gold',  'رئال مادرید طلایی', 'realmadrid_ii',  10, 10),
    ('elite_barcelona',  'elite', 'Barcelona Prism',   'بارسلونا منشوری',   'barcelona_ii',   10, 10),
    ('elite_bayern',     'elite', 'Bayern Redline',    'بایرن سرخ',         'bayern_ii',      10, 9),
    ('elite_psg',        'elite', 'Paris Noir',        'پاریس شب',          'psg_ii',         9, 10),
    ('elite_chelsea',    'elite', 'Chelsea Cobalt',    'چلسی کبالت',        'chelsea',        9, 10),
    ('elite_dortmund',   'elite', 'Dortmund Amber',    'دورتموند کهربایی',  'dortmund_ii',    10, 9),
    # ---------------------------------------------------------------- legends (2) — the original bosses
    ('nx_merciless', 'legends', 'Merciless',  'بی‌رحم',  'arena_golem',  10, 10),
    ('nx_capo',      'legends', 'Capo',       'کاپو',    'arena_dragon', 10, 10),
]

# The v9 discs stay on disk (v9 ids unchanged); a team whose art slug lives there resolves to discs/v9.
V9_ONLY = {t[0] for t in TEAMS if t[1] in ('cars', 'sport')}

if __name__ == '__main__':
    ids = [t[0] for t in TEAMS]
    assert len(ids) == len(set(ids)), 'duplicate id'
    by = {}
    for t in TEAMS:
        by[t[1]] = by.get(t[1], 0) + 1
    print('teams', len(TEAMS), by)
    for cid, _, _ in CATS:
        assert cid in by, cid
    for t in TEAMS:
        assert len(t) == 7, t
        assert t[5] in range(1, 11) and t[6] in range(1, 11), t
        assert "'" not in t[3], t
    print('ids ok')
