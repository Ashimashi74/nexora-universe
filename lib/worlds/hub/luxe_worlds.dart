import 'package:flutter/material.dart';

import '../../core/assets/app_assets.dart';
import '../../games/game_registry.dart';

/// One destination inside a Station world. Every item opens a real, existing screen
/// (no "coming soon" tiles): [route] is a go_router location, [action] a named in-app action.
class LuxeItem {
  const LuxeItem({
    required this.fa,
    required this.en,
    required this.tab,
    this.icon,
    this.image,
    this.route,
    this.action,
    this.rarity = 2,
  });
  final String fa;
  final String en;
  final int tab;
  final String? icon; // assets/luxe/icons/<icon>.webp
  final String? image; // full asset path (game pedestals)
  final String? route;
  final String? action; // 'daily' = claim today's reward
  final int rarity;
}

class LuxeWorld {
  const LuxeWorld({
    required this.k,
    required this.fa,
    required this.en,
    required this.icon,
    required this.color,
    required this.tagFa,
    required this.tagEn,
    required this.tabsFa,
    required this.tabsEn,
    required this.items,
  });
  final String k;
  final String fa;
  final String en;
  final String icon;
  final Color color;
  final String tagFa;
  final String tagEn;
  final List<String> tabsFa;
  final List<String> tabsEn;
  final List<LuxeItem> items;
}

const List<String> _sport = <String>[
  'finger_soccer', 'basketball_battle', 'mini_golf', 'kart_racing', 'obstacle_race', 'bomb_arena'
];
const List<String> _table = <String>['billiards', 'pool8', 'carrom', 'backgammon', 'ludo', 'snakes_ladders'];
const List<String> _party = <String>['uno', 'mafia', 'spy_mafia', 'quiz'];

List<LuxeItem> _gameItems() {
  final List<LuxeItem> out = <LuxeItem>[];
  final Set<String> placed = <String>{};
  void add(List<String> ids, int tab) {
    for (final String id in ids) {
      final GameInfo? g = gameById(id);
      if (g == null) continue;
      placed.add(id);
      out.add(LuxeItem(
          fa: g.nameFa,
          en: g.nameEn,
          tab: tab,
          image: AppAssets.pedestal(id),
          route: '/arcade/$id',
          rarity: g.supportsOnline ? 4 : 3));
    }
  }

  add(_sport, 0);
  add(_table, 1);
  add(_party, 2);
  // Any game registered later still shows up (never silently dropped from the menu).
  for (final GameInfo g in kGames) {
    if (placed.contains(g.id)) continue;
    out.add(LuxeItem(fa: g.nameFa, en: g.nameEn, tab: 2, image: AppAssets.pedestal(g.id), route: '/arcade/${g.id}'));
  }
  out.addAll(const <LuxeItem>[
    LuxeItem(fa: 'روم‌های بازی', en: 'Game rooms', tab: 3, icon: 'r3c1', route: '/rooms', rarity: 4),
    LuxeItem(fa: 'آرکید', en: 'Arcade', tab: 3, icon: 'r5c5', route: '/world/nexora_arcade', rarity: 3),
    LuxeItem(fa: 'رده‌بندی', en: 'Leaderboard', tab: 3, icon: 'r2c6', route: '/leaderboard', rarity: 3),
  ]);
  return out;
}

List<LuxeWorld> buildLuxeWorlds() => <LuxeWorld>[
      LuxeWorld(
        k: 'games',
        fa: 'بازی‌ها',
        en: 'GAMES',
        icon: 'r4c5',
        color: const Color(0xFFE2C27A),
        tagFa: 'همه‌ی بازی‌ها در یک جا',
        tagEn: 'Every game in one place',
        tabsFa: const <String>['ورزشی', 'میزی', 'کارتی و گروهی', 'آنلاین'],
        tabsEn: const <String>['Sports', 'Table', 'Cards & party', 'Online'],
        items: _gameItems(),
      ),
      const LuxeWorld(
        k: 'events',
        fa: 'رویدادها',
        en: 'EVENTS',
        icon: 'r3c5',
        color: Color(0xFF9FC3D9),
        tagFa: 'ماموریت‌ها و رویدادهای ویژه',
        tagEn: 'Missions and special events',
        tabsFa: <String>['ماموریت', 'رویداد'],
        tabsEn: <String>['Missions', 'Events'],
        items: <LuxeItem>[
          LuxeItem(fa: 'ماموریت‌ها', en: 'Missions', tab: 0, icon: 'r5c2', route: '/rewards', rarity: 3),
          LuxeItem(fa: 'جایزه‌ی روزانه', en: 'Daily reward', tab: 0, icon: 'r3c6', action: 'daily', rarity: 4),
          LuxeItem(fa: 'جامعه و رویدادها', en: 'Communities & events', tab: 1, icon: 'r3c5', route: '/world/social_station', rarity: 3),
          LuxeItem(fa: 'تورنمنت‌ها', en: 'Tournaments', tab: 1, icon: 'r2c5', route: '/tournaments', rarity: 4),
        ],
      ),
      const LuxeWorld(
        k: 'rewards',
        fa: 'جایزه‌ها',
        en: 'REWARDS',
        icon: 'r3c6',
        color: Color(0xFFE8B7A0),
        tagFa: 'هدیه، جایزه و مدال',
        tagEn: 'Gifts, rewards and medals',
        tabsFa: <String>['جایزه', 'افتخار'],
        tabsEn: <String>['Rewards', 'Honours'],
        items: <LuxeItem>[
          LuxeItem(fa: 'جایزه‌ی روزانه', en: 'Daily reward', tab: 0, icon: 'r3c6', action: 'daily', rarity: 4),
          LuxeItem(fa: 'جایزه و پک', en: 'Rewards & packs', tab: 0, icon: 'r5c6', route: '/rewards', rarity: 3),
          LuxeItem(fa: 'مدال‌ها و دستاوردها', en: 'Medals', tab: 1, icon: 'r4c3', route: '/rewards', rarity: 3),
          LuxeItem(fa: 'جام‌ها و رده‌بندی', en: 'Cups & ranks', tab: 1, icon: 'r5c4', route: '/leaderboard', rarity: 4),
        ],
      ),
      const LuxeWorld(
        k: 'oracle',
        fa: 'هوش مصنوعی',
        en: 'ORACLE AI',
        icon: 'r5c2',
        color: Color(0xFFC9B6F0),
        tagFa: 'راهنما، تحلیل و پیشنهاد',
        tagEn: 'Guide, analysis and tips',
        tabsFa: <String>['اوراکل'],
        tabsEn: <String>['ORACLE'],
        items: <LuxeItem>[
          LuxeItem(fa: 'گفتگو با اوراکل', en: 'Talk to ORACLE', tab: 0, icon: 'r5c2', route: '/oracle', rarity: 4),
          LuxeItem(fa: 'تحلیل بازی من', en: 'Analyse my play', tab: 0, icon: 'r2c6',
              route: '/oracle?q=%D8%A8%D8%A7%D8%B2%DB%8C%E2%80%8C%D9%87%D8%A7%DB%8C%20%D9%85%D9%86%20%D8%B1%D8%A7%20%D8%AA%D8%AD%D9%84%DB%8C%D9%84%20%DA%A9%D9%86',
              rarity: 3),
          LuxeItem(fa: 'پیشنهاد بازی', en: 'Suggest a game', tab: 0, icon: 'r5c6',
              route: '/oracle?q=%DB%8C%DA%A9%20%D8%A8%D8%A7%D8%B2%DB%8C%20%D8%A8%D9%87%D9%85%20%D9%BE%DB%8C%D8%B4%D9%86%D9%87%D8%A7%D8%AF%20%D8%A8%D8%AF%D9%87',
              rarity: 2),
        ],
      ),
      const LuxeWorld(
        k: 'chat',
        fa: 'چت',
        en: 'CHAT',
        icon: 'r3c3',
        color: Color(0xFFA8D8C0),
        tagFa: 'دوستان، پیام و روم صوتی',
        tagEn: 'Friends, messages and voice',
        tabsFa: <String>['پیام', 'صدا', 'جامعه'],
        tabsEn: <String>['Messages', 'Voice', 'Community'],
        items: <LuxeItem>[
          LuxeItem(fa: 'چت و رسانه', en: 'Chat & media', tab: 0, icon: 'r3c3', route: '/social', rarity: 3),
          LuxeItem(fa: 'پیام‌ها، گروه‌ها و کانال‌ها', en: 'Messages & groups', tab: 0, icon: 'r3c4', route: '/world/orbit_network', rarity: 3),
          LuxeItem(fa: 'روم صوتی', en: 'Voice rooms', tab: 1, icon: 'r3c1', route: '/rooms', rarity: 4),
          LuxeItem(fa: 'پست و استوری', en: 'Posts & stories', tab: 2, icon: 'r5c3', route: '/world/nova_gallery', rarity: 3),
          LuxeItem(fa: 'جامعه‌ها', en: 'Communities', tab: 2, icon: 'r3c4', route: '/world/social_station', rarity: 2),
        ],
      ),
      const LuxeWorld(
        k: 'shop',
        fa: 'فروشگاه',
        en: 'SHOP',
        icon: 'r4c1',
        color: Color(0xFFD9B872),
        tagFa: 'خرید، هدیه و ظاهر',
        tagEn: 'Buy, gift and style',
        tabsFa: <String>['خرید', 'ظاهر'],
        tabsEn: <String>['Shop', 'Style'],
        items: <LuxeItem>[
          LuxeItem(fa: 'فروشگاه', en: 'Exchange', tab: 0, icon: 'r4c1', route: '/world/nexora_exchange', rarity: 4),
          LuxeItem(fa: 'آواتار و فضای من', en: 'Avatar & space', tab: 1, icon: 'r4c4', route: '/world/personal_orbit', rarity: 3),
        ],
      ),
      const LuxeWorld(
        k: 'profile',
        fa: 'پروفایل',
        en: 'PROFILE',
        icon: 'r4c4',
        color: Color(0xFFD4C4A8),
        tagFa: 'حساب، جام‌ها و رده‌بندی',
        tagEn: 'Account, trophies and ranks',
        tabsFa: <String>['حساب', 'دستاورد'],
        tabsEn: <String>['Account', 'Records'],
        items: <LuxeItem>[
          LuxeItem(fa: 'فضای شخصی', en: 'Personal orbit', tab: 0, icon: 'r4c4', route: '/world/personal_orbit', rarity: 3),
          LuxeItem(fa: 'حساب من', en: 'My account', tab: 0, icon: 'r4c2', route: '/account', rarity: 2),
          LuxeItem(fa: 'تنظیمات', en: 'Settings', tab: 0, icon: 'r4c2', route: '/settings', rarity: 1),
          LuxeItem(fa: 'رده‌بندی', en: 'Ranking', tab: 1, icon: 'r2c6', route: '/leaderboard', rarity: 3),
          LuxeItem(fa: 'دستاوردها', en: 'Achievements', tab: 1, icon: 'r4c3', route: '/rewards', rarity: 3),
        ],
      ),
      const LuxeWorld(
        k: 'tournaments',
        fa: 'تورنمنت‌ها',
        en: 'TOURNAMENTS',
        icon: 'r2c5',
        color: Color(0xFFE2C27A),
        tagFa: 'مسابقه‌ها و لیگ‌ها',
        tagEn: 'Cups and leagues',
        tabsFa: <String>['فعال', 'مدیریت'],
        tabsEn: <String>['Live', 'Manage'],
        items: <LuxeItem>[
          LuxeItem(fa: 'تورنمنت‌ها', en: 'Tournaments', tab: 0, icon: 'r2c5', route: '/tournaments', rarity: 4),
          LuxeItem(fa: 'ورود با کد', en: 'Join with code', tab: 0, icon: 'r4c6', route: '/tournaments/join', rarity: 2),
          LuxeItem(fa: 'جدول رده‌بندی', en: 'Standings', tab: 0, icon: 'r2c6', route: '/leaderboard', rarity: 3),
          LuxeItem(fa: 'ساخت تورنمنت', en: 'Create', tab: 1, icon: 'r5c4', route: '/tournaments/new', rarity: 3),
          LuxeItem(fa: 'دعوت‌ها و اعلان‌ها', en: 'Inbox', tab: 1, icon: 'r5c3', route: '/tournaments/inbox', rarity: 2),
        ],
      ),
    ];

LuxeWorld? luxeWorld(String k) {
  for (final LuxeWorld w in buildLuxeWorlds()) {
    if (w.k == k) return w;
  }
  return null;
}
