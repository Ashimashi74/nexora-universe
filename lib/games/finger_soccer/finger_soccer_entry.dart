import 'package:flutter/widgets.dart';

import 'package:nexora/games/core/game_contract.dart';
import 'intro/fs_intro_flow.dart';
import 'ui/bm_view.dart';

/// ANIX Arcade entry for Finger Soccer: the BERMUDA NXG disc-football game (1:1 port of its JS engine).
/// Pure engine in core/ (bm_engine.dart, bm_data.dart), rendering + UI + online wiring in ui/.
/// Offline matches (vs bot, pass-and-play) open with the reference pre-match intro (intro/: splash, team select,
/// formation select); online matches open BermudaView, which shows the same team / formation screens for this
/// phone's own side (intro/fs_online_pick.dart) and starts when both sides' logged 'setup' moves are in.
Widget buildFingerSoccerGame(GameLaunch launch) =>
    launch.online ? BermudaView(launch: launch) : FsIntroFlow(launch: launch);
