import 'package:flutter/widgets.dart';

import '../core/game_contract.dart';
import 'ui/obstacle_game.dart';

/// ANIX Obstacle Race: race to the finish over a seeded obstacle course with checkpoints, respawns and a
/// qualifying cut-off (bots offline, real-time online).
Widget buildObstacleRaceGame(GameLaunch launch) => ObstacleGame(launch: launch);
