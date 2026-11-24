import 'package:flutter/material.dart';

import '../core/game_contract.dart';
import 'solo_kit.dart';
import 'ui/action_boards.dart';
import 'ui/puzzle_boards.dart';

/// ===================== SOLO ARCADE REGISTRY =====================
/// The ten single-player arcade games, registered like every other ANIX game so they get
/// the same lobby cards, player stats, medals, daily challenge, global score board and
/// host result screen. Order here is the order they appear in the Arcade lobby group.
/// ==============================================================

final List<SoloDef> kSoloDefs = <SoloDef>[
  SoloDef(
    id: 'endless_runner',
    titleFa: 'دونده‌ی بی‌پایان',
    titleEn: 'Endless Runner',
    hintFa: 'با دکمه‌های چپ و راست بین سه مسیر جابه‌جا شو و از موانع رد شو. سرعت مدام بیشتر می‌شود.',
    hintEn: 'Hop between three lanes with the arrows and clear the barriers. The road keeps speeding up.',
    control: SoloControl.dpad,
    accent: const Color(0xFF42D9FF),
    board: (BuildContext c, SoloRun r) => RunnerBoard(run: r),
  ),
  SoloDef(
    id: 'geo_dash',
    titleFa: 'جئو دش',
    titleEn: 'Geo Dash',
    hintFa: 'لمس کن تا بپری و نگه دار تا بالاتر بمانی؛ از تیغه‌ها و بلوک‌های پرنده رد شو.',
    hintEn: 'Tap to jump, hold to fly higher, and thread the spikes and flying blocks.',
    control: SoloControl.tap,
    accent: const Color(0xFFB8F05A),
    board: (BuildContext c, SoloRun r) => DashBoard(run: r),
  ),
  SoloDef(
    id: 'traffic_racer',
    titleFa: 'مسابقه‌ی ترافیک',
    titleEn: 'Traffic Racer',
    hintFa: 'با فلش‌ها یا کشیدن انگشت بین سه لاین جابه‌جا شو و از ترافیک جلو بزن.',
    hintEn: 'Swap lanes with the arrows or a swipe and weave through the traffic.',
    control: SoloControl.dpad,
    accent: const Color(0xFFFF6B75),
    board: (BuildContext c, SoloRun r) => TrafficBoard(run: r),
  ),
  SoloDef(
    id: 'fruit_ninja',
    titleFa: 'میوه‌بُر',
    titleEn: 'Fruit Ninja',
    hintFa: 'انگشتت را روی میوه‌ها بکش و آن‌ها را دو نیم کن. بمب‌ها بازی را تمام می‌کنند.',
    hintEn: 'Drag across the fruit to slice it. Bombs end the run instantly.',
    control: SoloControl.drag,
    accent: const Color(0xFFFFB547),
    board: (BuildContext c, SoloRun r) => FruitBoard(run: r),
  ),
  SoloDef(
    id: 'knife_hit',
    titleFa: 'چاقو زدن',
    titleEn: 'Knife Hit',
    hintFa: 'چاقو را در کنده‌ی چرخان پرتاب کن؛ به چاقوهای قبلی نخور. هر ۵ پرتاب سریع‌تر می‌شود.',
    hintEn: 'Throw knives into the spinning log without hitting your own. Every 5 throws it speeds up.',
    control: SoloControl.tap,
    accent: const Color(0xFF9A82FF),
    board: (BuildContext c, SoloRun r) => KnifeBoard(run: r),
  ),
  SoloDef(
    id: 'helix_jump',
    titleFa: 'پرش مارپیچ',
    titleEn: 'Helix Jump',
    hintFa: 'با کشیدن افقی برج را بچرخان و از شکاف حلقه‌ها پایین بیا؛ حلقه‌های قرمز مرگبارند.',
    hintEn: 'Drag sideways to spin the tower, fall through the ring gaps and avoid the red ones.',
    control: SoloControl.drag,
    accent: const Color(0xFFB282FF),
    board: (BuildContext c, SoloRun r) => HelixBoard(run: r),
  ),
  SoloDef(
    id: 'bubble_shooter',
    titleFa: 'حباب‌زن',
    titleEn: 'Bubble Shooter',
    hintFa: 'نشانه بگیر و شلیک کن؛ سه حباب هم‌رنگ یا بیشتر می‌ترکد. همه‌ی حباب‌ها را پاک کن.',
    hintEn: 'Aim and fire; three or more matching bubbles pop. Clear the whole wall.',
    control: SoloControl.drag,
    accent: const Color(0xFF53CFFF),
    board: (BuildContext c, SoloRun r) => BubbleBoard(run: r),
  ),
  SoloDef(
    id: 'stack_tower',
    titleFa: 'برج بلوک',
    titleEn: 'Stack Tower',
    hintFa: 'بلوک را دقیقاً روی برج رها کن. خانه‌ی کامل جایزه‌ی کمبو دارد؛ خطا برج را باریک می‌کند.',
    hintEn: 'Drop each block precisely on the tower. Perfect drops build a combo; misses widen the gap.',
    control: SoloControl.tap,
    accent: const Color(0xFF84E1B1),
    board: (BuildContext c, SoloRun r) => StackBoard(run: r),
  ),
  SoloDef(
    id: 'tetris_rush',
    titleFa: 'تتریس راش',
    titleEn: 'Tetris Rush',
    hintFa: 'قطعه‌ها را بچرخان و بچین؛ هر خط کامل پاک می‌شود. با هر ۱۰ خط سرعت بیشتر می‌شود.',
    hintEn: 'Rotate and place the pieces, clear full lines, and survive the accelerating fall.',
    control: SoloControl.dpad,
    accent: const Color(0xFF8D8CFF),
    board: (BuildContext c, SoloRun r) => TetrisBoard(run: r),
  ),
  SoloDef(
    id: 'game_2048',
    titleFa: '۲۰۴۸',
    titleEn: 'NX 2048',
    hintFa: 'با فلش‌ها حرکت کن؛ دو خانه‌ی مساوی با هم جمع می‌شوند. عدد ۲۰۴۸ را بساز.',
    hintEn: 'Slide with the arrows; equal tiles merge. Reach 2048.',
    control: SoloControl.dpad,
    accent: const Color(0xFFFF8FD1),
    board: (BuildContext c, SoloRun r) => World2048Board(run: r),
  ),
];

SoloDef? soloDef(String id) {
  for (final SoloDef d in kSoloDefs) {
    if (d.id == id) return d;
  }
  return null;
}

/// Registry entries for `kGames` (mirrors the numbers in `nx_arcade_limits` on the server).
List<GameInfo> buildSoloGameInfos() => <GameInfo>[
      for (final SoloDef d in kSoloDefs)
        GameInfo(
          id: d.id,
          nameFa: d.titleFa,
          nameEn: d.titleEn,
          taglineFa: d.hintFa.split('؛').first.split('.').first,
          taglineEn: d.hintEn.split('.').first,
          rulesFa: d.hintFa,
          rulesEn: d.hintEn,
          minPlayers: 1,
          maxPlayers: 1,
          defaultPlayers: 1,
          supportsLocal: false,
          supportsOnline: false,
          solo: true,
          group: 5,
          accent: d.accent,
          builder: (GameLaunch launch) => buildSoloGame(d, launch),
        ),
    ];
