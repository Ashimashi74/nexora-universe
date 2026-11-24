import 'package:flutter/widgets.dart';

import 'package:nexora/games/core/game_contract.dart';
import 'ui/bm_view.dart';

/// ANIX Arcade entry for Finger Soccer: the BERMUDA NXG disc-football game (1:1 port of its JS engine).
/// Pure engine in core/ (bm_engine.dart, bm_data.dart), rendering + UI + online wiring in ui/.
/// 2026-11-24 (owner request): every match, offline (vs bot, pass-and-play) and online, opens on the app's own
/// black-gold match lobby inside BermudaView (team incl. locked / custom teams, formation, pitch, ball). The
/// reference-game intro screens (intro/fs_intro_flow.dart and friends) are no longer used as the entry.
Widget buildFingerSoccerGame(GameLaunch launch) => BermudaView(launch: launch);
