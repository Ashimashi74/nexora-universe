import 'package:flutter/widgets.dart';

import 'package:nexora/games/core/game_contract.dart';
import 'intro/fs_intro_flow.dart';
import 'ui/bm_view.dart';

/// ANIX Arcade entry for Finger Soccer: the BERMUDA NXG disc-football game (1:1 port of its JS engine).
/// Pure engine in core/ (bm_engine.dart, bm_data.dart), rendering + UI + online wiring in ui/.
/// Offline matches (vs bot, pass-and-play) open with the reference pre-match intro (intro/: splash, team select,
/// formation select); online matches keep the room / lobby setup of [BermudaView].
Widget buildFingerSoccerGame(GameLaunch launch) =>
    launch.online ? BermudaView(launch: launch) : FsIntroFlow(launch: launch);
