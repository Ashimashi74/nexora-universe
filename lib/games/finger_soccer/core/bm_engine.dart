// ignore_for_file: constant_identifier_names, non_constant_identifier_names
// BERMUDA NXG disc-football engine: a 1:1 port of www/js/game.js (physics, rules, turn flow, AI, fx state).
// Formulas follow the JS; the friction / launch / restitution constants are calibrated on the owner's reference
// recording (2026-11-20, see the comments on each constant). Retune only from new measurements.
// World = the field image's own pixel space scaled by FS (see geo()).
import 'dart:math' as math;

import 'bm_data.dart';

// ---------------------------------------------------------------- constants (game.js line 4-6)
// PR / BR are the radii of the DRAWN disc and ball (rim of the normalised sprites, see kBmDiscArtFill /
// kBmBallArtFill): the collider is exactly what the player sees.
// Finger-soccer proportions (owner request 2026-11, v2): on the old 112-unit discs the pitch looked huge and the pieces
// tiny. Disc diameter is now 150 world units, about 1/6 of the playing width (880-945 on every pitch) like a real
// table set; the ball is half the disc diameter. The goal sprite grows with them (kBmGoalArtScale) so the mouth stays
// about 2.7 discs wide, and the view fits the whole world to any phone (BmView.layout).
// Reference proportions (owner request 2026-11-20, measured on his reference screenshot, pitch 620 px wide): disc
// ~75 px = 0.12 of the playing width, ball ~35 px = 0.056, goal mouth ~213 px = 0.34. On the 880-unit default pitch
// that is a 106-unit disc, a 50-unit ball and a 300-unit mouth.
const double K = 1.27, PR = 53.0, BR = 25.0, STEP = 1 / 240, LMAX = 320;
/// Ball spin / curve keeps the original tuning radius so the bigger collider does not change curl after bounces.
const double SPIN_R = 28.8;
/// Visual scale of the goal sprite (assets/games/bermuda/goals/white.webp, the only goal art): drawn at full size so
/// the mouth (inner width between the two side tubes) is about three discs wide. Posts, side nets and back net are
/// built from the drawn sprite.
const double kBmGoalArtScale = 0.92; // mouth = 0.34 of the playing width (reference)
/// v5 (owner request 2026-11-20): goal mouth 3.5% narrower. The goal sprite is drawn 3.5% narrower (its height and
/// net depth unchanged), and the posts / mouth / side nets are still built from the drawn sprite, so the colliders
/// keep matching the art. Before: 1.
const double kBmGoalMouthScale = 0.965;
/// Match balls: 0-3 the owner's animated balls (kBmAnimBalls), 4 the classic black / white ball of the reference
/// recordings (kBmClassicBall, v6), 5 NX Spin (v7 default) and 6 NX Star, the owner's GIF balls played with the
/// GIF's own frames and timing (kBmAnimBalls, gifTimed).
const int NB = 7;
/// Weighty pieces (owner request 2026-11): discs are heavy (mass 8) and the ball lighter (2.6) but not a ping-pong
/// ball. BKICK keeps a disc striking the ball launching it 5% harder than plain elastic transfer.
const double DISC_M = 8.0;
const double BALL_M = 2.6;
const double BKICK = 1.05;
/// Disc sliding friction (constant + speed-proportional part), disc<->disc restitution and the disc speed cap after
/// touching the ball: heavier felt so shots stop where they are aimed instead of skating around.
/// Anti-drift tuning (owner request 2026-11, v2): pieces skated too far and kept jittering after every shot. Felt
/// friction is ~60% higher (PF1 520 -> 840, PF2 1.1 -> 1.9) so a disc glides ~40% less, disc<->disc and rail bounces
/// are deader, and a slow disc snaps to rest sooner (kBmDiscStop). Launch speed (fire) is untouched, so shot power
/// and the ball's speed off a strike are exactly as before.
/// Reference calibration (2026-11-20, measured frame by frame on the owner's reference finger-soccer recording, 15 fps,
/// pitch 325 px wide => 1 px = 2.88 world units): after the launch glide (boost, unchanged .35 x friction for .22 s,
/// the recording shows ~0.2 s at almost constant speed) a disc slows by 123 px/s^2 + 5.1/s * v (joint fit of 5 shots;
/// a power-2 shot glides ~200 px and stops in ~0.8 s, simulated 202 px / 0.79 s). PF1 = 123 px/s^2 * 2.88 / K,
/// PV0 = the 80 px/s ramp.
/// Reference calibration v2 (2026-11-20, three recordings, frame-by-frame template tracking of 3 clean shot glides
/// and 4 discs struck by another body, positions fitted with the engine's own friction law): shot discs and struck
/// discs follow ONE law, a weak constant part (~20 px/s^2) + 3.5/s speed drag, with no launch glide (struck discs
/// never get the glide and still fit; with it the shot fits got worse). The old law (123 px/s^2 + 5.0/s, 0.22 s
/// glide) stopped struck discs ~40% short. PF1 = 20 px/s^2 * 2.88 / K. Old values: PF1 280, PF2 5.0, glide .22.
/// Reference calibration v4 (2026-11-20, owner: "disc friction exactly like the video"): the v2 set (3 shots + 4
/// struck discs) plus 3 fast glides (PSG 580, 1779, Adidas 1460; up to ~1700 px/s), every track fitted jointly with
/// the engine law (free launch speed per track, no glide). Best: NO constant part, 3.25/s drag (rms 6.05 px per
/// position over 10 tracks) vs v2's 20 px/s^2 + 3.5/s (rms 6.41 px) and v1's 123 + 5.1 (rms 10.3 px). A slide is
/// pure speed drag down to kBmDiscStop (~13 px/s), so a disc glides ~9% further and ~10% longer at the same launch;
/// kBmLaunch is unchanged (shot power untouched). Old values: PF1 45, PF2 3.5.
const double HV = 4, PF1 = 0, PF2 = 3.25, PV0 = 181, EPP = .22, PCAP = 190;
/// Launch glide (s at .35 x friction) given to a shot disc. 0 since calibration v2 (was .22).
const double kBmLaunchGlide = 0;
/// Ball striking a disc (ball faster than the disc): the disc takes the full mass-ratio impulse (1) instead of the
/// 1/HV quarter, so a hard ball shoves a resting disc visibly like the reference. A disc striking the ball keeps HV.
const double kBmBallHitDiscK = 1.0;
/// Impulse factor of the slower (struck) disc in a disc<->disc hit: 1 since calibration v2 (was .85, which capped
/// how far a struck disc could travel).
const double kBmStruckDiscK = 1.0;
/// Wall / post restitution of a disc (a heavy wooden puck loses most of its speed into the rail).
const double kBmDiscWallE = .48; // reference: .45 - .5 normal restitution off the rail (unused since v7, kept for docs)
/// Rail restitution (owner request 2026-11-20, v3): a bank shot keeps its power. Every body (ball and discs) comes
/// off the side rails, the end lines beside the goals and the round corners with this normal restitution and no
/// tangential loss. Before: ball .62-.72 (speed dependent), disc .48 (kBmDiscWallE).
/// v7 (owner request 2026-11-20): the goal posts and the inside of the goal (side nets and back net) rebound exactly
/// like the rails too, for the ball and every disc: same normal restitution [kBmRailE], no tangential loss. Only the
/// ball settling in the net after a goal (phase 'goal', play already stopped) keeps its soft damping.
const double kBmRailE = .9;
/// Ball curl per unit of spin (rad/s). v3: 0, the ball travels in straight lines (owner request 2026-11-20: no sudden
/// bends after a wall or a glancing hit). Spin is still kept and drawn (the ball still turns round in the corners).
/// Before: .034.
const double kBmBallCurve = 0;
/// Mass of a disc when the BALL strikes it (ball faster than the disc). v3: lighter pieces (owner request
/// 2026-11-20) so a hard ball knocks a disc back further. A disc striking the ball, and disc<->disc hits, keep
/// DISC_M, so shot power and the ball's speed off a strike are unchanged. Before: DISC_M (8).
const double kBmDiscLightM = 5.5;
/// Global playback rate of the simulation (owner request 2026-11-20, v3): the whole scene runs 5% slower. Only the
/// rate real time feeds the fixed-step accumulator changes; every step is the same STEP, so paths, distances and
/// outcomes are identical (and online phones still run the same steps), just 5% slower to watch. Before: 1.
/// v5 (owner request 2026-11-20): 85% speed (15% slower). Before: .95.
const double kBmSimRate = .85;
/// v5: spin a disc picks up from a glancing contact (rad/s per unit of tangential speed / radius) and its cap.
/// Render only: a disc's spin turns its sprite (bm_painter) and never feeds its motion, so paths are unchanged.
const double kBmDiscSpinK = .16, kBmDiscSpinMax = 22;
/// Below this speed (world units/s, times K) a sliding disc stops dead instead of creeping.
const double kBmDiscStop = 30; // reference discs stop dead below ~13 px/s

/// Largest aim error (radians, one side) at accuracy 1; accuracy 10 shoots exactly where the player aims.
const double kBmMaxAimError = 0.11;

/// Launch scale. v2: 1.87 -> 2.04 (x1.09) so that, with the lighter v2 friction, a shot disc still stops where the
/// reference shots stop (distance-matched over 700..5000 world/s launches: x1.06..1.10). A full pull at power 10 now
/// leaves at ~1875 px/s (5400 world/s), i.e. ~1670 px/s averaged over the first 1/15 s frame, as measured for the
/// reference's power-10 sides (PSG, Adidas). Team power scales it through strikeOf (see there).
/// v6 (owner request 2026-11-20, two new recordings where BOTH sides are power 10 / accuracy 10, see
/// docs/FS_V6_CALIBRATION.md): the hardest ball in the recordings averages 4.57 playing widths/s over its first
/// 0.2 s (1431 px/s on a 313 px pitch); a power-10 full pull now gives exactly that on screen (4.58 w/s from the
/// contact, kBmSimRate included; 2.04 gave 4.74 w/s, ~4% too hard). Every other power keeps its reference share of it
/// (strikeOf / powerShare).
const double kBmLaunch = 1.97;
/// Ball rolling friction: constant part (world/s^2 / K) and linear drag (1/s), see sim().
const double kBmBallF0 = 23, kBmBallDrag = 1.08;
/// Speed caps (world/s / K): the reference ball leaves a hard strike at up to ~1725 px/s (4970 world/s).
/// v2: the disc cap is above the strongest launch (power 10 full pull ~4250 world/s / K), so it never limits a
/// shot or a disc that is struck by another body (was 4200, just under the v2 launch).
const double kBmBallVMax = 4000, kBmDiscVMax = 4400;

/// v6 (reference recordings 2026-11-20): after a goal the "Goal!" banner holds ~2.0 s (pieces keep rolling), then
/// every piece glides back to its kickoff slot in ~1.0 s before the kickoff turn starts. The glide is render only
/// (the bodies already stand on their slots, see BmBody.gx / gy), so online phones stay in lock-step.
const double kBmGoalHold = 2.0, kBmResetGlide = 1.0;

/// Team powers shown in the reference game's team-select UI (قدرت bar) for the sides in the owner's recordings.
/// Reference speeds are divided by the side's strike (BmEngine.refStrikeOf) before calibrating kBmLaunch, so a
/// slow Japan (2) shot and a fast PSG (10) shot measure the same base launch. ANIX's own team stats (kBmTeamDefs)
/// are NOT these numbers and stay as they are (the "Japan 2 / PSG 10" table edit was reverted on purpose).
const Map<String, int> kBmRefPower = <String, int>{
  'Japan': 2, 'Starbucks': 15, 'Paris Saint-Germain': 10, 'Adidas': 10, 'Australia': 5, 'Kakero': 10, 'Oreo': 15,
};

/// Field size factor (game.js line 12).
const double FS = 1.12 * 1.215;

/// A field after the FS scale (game.js line 12: W,H,L,R,T,B,cs rounded, g = 169).
class BmFieldS {
  BmFieldS(BmField f)
      : id = f.id,
        name = f.name,
        gs = f.gs,
        W = _r(f.w0),
        H = _r(f.h0),
        L = _r(f.l0),
        R = _r(f.r0),
        T = _r(f.t0),
        B = _r(f.b0),
        cs = _r(f.cs0),
        g = 169,
        rc = f.rc,
        builtInGoals = f.builtInGoals,
        gh = f.gh0 * FS,
        gr = f.gr0 * FS,
        gd = f.gd0 * FS,
        asset = f.asset ?? 'assets/games/bermuda/fields/${f.id}.webp';
  static double _r(int v) => (v * FS).round().toDouble(); // Math.round on positive values
  final String id, name, gs;
  final double W, H, L, R, T, B, cs, g;
  /// Corner radius (world), built-in goal geometry (world): post-centre half width, post radius, net depth.
  final double rc, gh, gr, gd;
  final bool builtInGoals;
  final String asset;
}

final List<BmFieldS> kBmFields = kBmFieldsRaw.map(BmFieldS.new).toList(growable: false);

class BmTeam {
  const BmTeam(this.id, this.cat, this.name, this.asset, this.power, this.accuracy);
  final String id, cat, name, asset;
  /// 1..10: shot impulse multiplier (see [BmEngine.fire]) and aim precision.
  final int power, accuracy;
}

/// Every piece set, in picker order (see kBmTeamDefs: Club, National, Luxury).
final List<BmTeam> kBmTeams = kBmTeamDefs
    .map((BmTeamDef d) => BmTeam(d.id, d.cat, d.name, 'assets/games/bermuda/${d.art}.webp', d.power, d.accuracy))
    .toList(growable: false);

BmTeam bmTeam(String id) => kBmTeams.firstWhere((BmTeam t) => t.id == id, orElse: () => kBmTeams.first);

/// A team shape: five discs (the keeper first) as [x, d] in the team's own frame. x is the fraction of the playing
/// width, left to right as the team sees it from its own goal; d is the depth from its own goal line as a fraction of
/// the half pitch (0 = goal line, 1 = halfway line).
class BmFormation {
  const BmFormation(this.fa, this.en, this.slots);
  final String fa, en;
  final List<List<double>> slots;
  String get label => '$fa · $en';
}

/// The nine formations of the owner's reference game (formation-select screen of the 2026-11-20 recording, same
/// order and names). Read from its mini pitches (depth as drawn; the width is drawn ~1.3x stretched there, mapped
/// back with 0.77) and, for Nish and Oghab, measured directly on the reference kickoff frames.
const List<BmFormation> kBmForms = <BmFormation>[
  BmFormation('الماس', 'Almas · Diamond', <List<double>>[
    <double>[.500, .133], <double>[.270, .386], <double>[.730, .386], <double>[.418, .762], <double>[.582, .762]]),
  BmFormation('عقاب', 'Oghab · Eagle', <List<double>>[
    <double>[.500, .230], <double>[.210, .423], <double>[.790, .423], <double>[.500, .610], <double>[.500, .780]]),
  BmFormation('موج', 'Mowj · Wave', <List<double>>[
    <double>[.307, .299], <double>[.693, .299], <double>[.168, .595], <double>[.500, .595], <double>[.832, .595]]),
  BmFormation('ماه', 'Mah · Moon', <List<double>>[
    <double>[.500, .207], <double>[.270, .347], <double>[.730, .347], <double>[.170, .598], <double>[.830, .598]]),
  BmFormation('دیوانه', 'Divaneh · Crazy', <List<double>>[
    <double>[.500, .662], <double>[.190, .833], <double>[.336, .820], <double>[.632, .821], <double>[.792, .817]]),
  BmFormation('لبه', 'Labeh · Edge', <List<double>>[
    <double>[.500, .128], <double>[.500, .368], <double>[.500, .595], <double>[.257, .841], <double>[.743, .841]]),
  BmFormation('نیش', 'Nish · Sting', <List<double>>[
    <double>[.500, .126], <double>[.275, .516], <double>[.725, .516], <double>[.275, .898], <double>[.725, .898]]),
  BmFormation('بازو', 'Bazoo · Arm', <List<double>>[
    <double>[.500, .128], <double>[.250, .568], <double>[.500, .573], <double>[.760, .569], <double>[.760, .886]]),
  BmFormation('حمله همه جانبه', 'All-out attack', <List<double>>[
    <double>[.500, .128], <double>[.410, .785], <double>[.590, .785], <double>[.275, .890], <double>[.725, .890]]),
];

/// The slots of formation [fi] (clamped to the list, so an old saved index still loads).
List<List<double>> bmSlots(int fi) => kBmForms[fi.clamp(0, kBmForms.length - 1)].slots;

String bmBallName(int i) => '${kBmBallN[i]} Ball';

// ---------------------------------------------------------------- bodies
/// A goal: [x1]..[x2] is the open mouth between the posts' inner faces, [px1]/[px2] the post centres (circles of
/// radius [pr]), [y] the goal line and [d] the direction into the net (-1 top, +1 bottom).
class BmGoal {
  BmGoal(this.team, this.y, this.x1, this.x2, this.d, {double? px1, double? px2, this.pr = 5})
      : px1 = px1 ?? x1,
        px2 = px2 ?? x2;
  final int team;
  final double y, x1, x2, px1, px2, pr;
  final int d;
}

class BmTrailPt {
  BmTrailPt(this.x, this.y, this.v, {this.a = 1, this.h = false});
  final double x, y, v;
  double a;
  final bool h;
}

class BmBody {
  BmBody(this.x, this.y, this.team, this.r, this.m, {this.power = 0}) : im = 1 / m;
  double x, y, vx = 0, vy = 0;
  final double r, m, im;
  final int team;
  /// Per-piece strike rating (the team's power). 0 is reserved for the ball; player pieces are 1..10.
  int power;
  /// Aim precision 1..10 (the team's accuracy); 10 = no aim error.
  int accuracy = 10;
  double spin = 0, ang = 0, sq = 0, boost = 0;
  final List<double> R = <double>[1, 0, 0, 0, 1, 0, 0, 0, 1];
  int rv = 0;
  int cid = 0;
  /// v6: render-only offset (world units) from the kickoff slot back to where the piece stood when the goal was
  /// scored; drawn as gx * BmEngine.glideK so the piece glides home (see kBmResetGlide).
  double gx = 0, gy = 0;
  BmGoal? gout;
  final List<BmTrailPt> tr = <BmTrailPt>[];
}

class BmPart {
  BmPart(this.x, this.y, this.vx, this.vy, this.l, this.r, this.c, this.k, this.g, this.rot, {double? m}) : m = m ?? l;
  double x, y, vx, vy, l;
  final double m, r, g;
  final int c, k;
  double rot;
}

class BmRing {
  BmRing(this.x, this.y, this.r, this.l, this.w) : m = l;
  final double x, y, r, m, w;
  double l;
}

class BmDrag {
  BmDrag(this.b, this.sx, this.sy, this.cx, this.cy, {this.ai = false});
  final BmBody b;
  final double sx, sy;
  double cx, cy;
  final bool ai;
}

class BmAiPlan {
  BmAiPlan(this.b, this.dx, this.dy, this.l);
  final BmBody b;
  final double dx, dy, l;
  double t = 0;
}

/// Match config (game.js startMatch cfg).
class BmConfig {
  const BmConfig({
    required this.mode,
    required this.teams,
    required this.form,
    required this.names,
    required this.field,
    required this.ball,
    this.limit = 0,
    this.matchTime = 0,
    this.turnTime = 0,
    this.ai = false,
    this.aiLvl = 1,
    this.mirror = false,
    this.first = 0,
    this.perSide = 1,
  });

  /// Players per side online (1 = 1v1, 2 = 2v2, 3 = 3v3). Seats alternate sides (0,2,4 vs 1,3,5) and each side's
  /// players take its turns in rotation.
  final int perSide;
  final String mode; // 'local' | 'bot' | 'online'
  final List<String> teams; // global team ids
  final List<int> form; // global formations
  final List<String> names; // global names
  final int field, ball, limit, matchTime, first;
  final double turnTime;
  final bool ai, mirror;
  final int aiLvl;
}

/// Callbacks the engine fires (sound, haptics, toast, network, end).
abstract class BmHooks {
  void sfx(String k, [double v = 1]);
  void tone(String k);
  void vib(List<int> pattern);
  void toast(String text, bool big);
  void goalFx();
  void emit(String event, Map<String, dynamic> data);
}

const List<int> _goalCols = <int>[0xFFFFD23A, 0xFFFF4A7A, 0xFF3BD0FF, 0xFF7BFF5A, 0xFFFFFFFF];

class BmEngine {
  BmEngine(this.hooks, {math.Random? rng}) : rnd = rng ?? math.Random() {
    geo();
  }

  final BmHooks hooks;
  final math.Random rnd;
  double R_() => rnd.nextDouble();

  // SET (game.js line 13)
  int setLim = 5, setFld = 0, setBall = 0;

  // C
  String mode = 'local';
  List<String> names = <String>['', ''];
  bool mirror = false;
  int ai = -1, aiLvl = 1, mt = 0;
  double tt = 0;

  // geometry
  late double Fl, Fr, Ft, Fb, Fw, Fh, CX, CY, KY = 0, DEPTH = 112, RC = 70;
  late List<BmGoal> GOALS;
  /// Goal sprite placement (world): left x, drawn width, drawn height and the sprite's post-bottom fraction (the
  /// sprite is drawn so its posts end exactly on the goal line). GGw == 0 for fields with goals built into the art.
  late double GGw, GGh, GGx, GGleg = 1;
  /// Visual depth reserved behind each goal line (layout).
  double get goalVisualDepth => GGw > 0 ? GGh * GGleg : DEPTH;
  BmFieldS get field => kBmFields[setFld];

  List<String> sel = <String>['club0', 'club1'];
  List<int> form = <int>[0, 0];

  List<BmBody> bodies = <BmBody>[];
  BmBody? ball;
  List<int> score = <int>[0, 0];
  int turn = 0, kick = 0, shots = 0;
  String phase = 'aim';
  BmDrag? drag;
  double pause = 0, idle = 0, flash = 0, acc = 0, freeze = 0, slow = 0, cam = 0;
  final List<double> shake = <double>[0, 0];
  List<BmTrailPt> trail = <BmTrailPt>[];
  List<BmPart> parts = <BmPart>[];
  List<BmRing> rings = <BmRing>[];
  bool menuOpen = true, inMatch = false;
  double mleft = 0;
  bool sd = false;
  double aiT = 0;
  BmAiPlan? aiPlan;
  double tleft = 0;
  bool remote = false;
  double fxAcc = 0, fxAcc2 = 0;
  bool _endEmitted = false;

  int ct(int t) => mirror ? 1 - t : t;
  String nm(int t) => names[ct(t)].isNotEmpty ? names[ct(t)] : bmTeam(sel[ct(t)]).name;
  List<int> bcol() => kBmTR[setBall % kBmTR.length].c;

  void geo() {
    final BmFieldS f = field;
    Fl = f.L + 4;
    Fr = f.R - 4;
    Ft = f.T + 4;
    Fb = f.B - 4;
    Fw = Fr - Fl;
    Fh = Fb - Ft;
    CX = (Fl + Fr) / 2;
    CY = (Ft + Fb) / 2;
    KY = f.cs;
    RC = f.rc;
    if (f.builtInGoals) {
      // Goals drawn into the field art: posts, mouth and net depth measured on the art.
      GGw = 0;
      GGh = 0;
      GGx = CX;
      GGleg = 1;
      DEPTH = f.gd;
      final double pl = CX - f.gh, pr = CX + f.gh;
      GOALS = <BmGoal>[
        BmGoal(0, Ft, pl + f.gr, pr - f.gr, -1, px1: pl, px2: pr, pr: f.gr),
        BmGoal(1, Fb, pl + f.gr, pr - f.gr, 1, px1: pl, px2: pr, pr: f.gr),
      ];
      return;
    }
    // Separate goal sprite: [w, h, left post, right post, post half-width, back-bar inner edge, post bottom].
    final List<double> gi = kBmGS[f.gs]!;
    final double fullW = 2 * f.g / (gi[3] - gi[2]);
    GGw = fullW * kBmGoalArtScale * kBmGoalMouthScale;
    GGh = fullW * kBmGoalArtScale * gi[1] / gi[0] * 1.02; // goal depth +2% (owner request); v5: not narrowed
    GGleg = gi[6];
    GGx = CX - GGw * (gi[2] + gi[3]) / 2; // post centres symmetric about the centre line
    final double pl = GGx + gi[2] * GGw, pr = GGx + gi[3] * GGw, prad = gi[4] * GGw;
    // The sprite's post bottoms sit on the goal line; the back net is the inner edge of its back bar.
    DEPTH = GGh * (gi[6] - gi[5]);
    GOALS = <BmGoal>[
      BmGoal(0, Ft, pl + prad, pr - prad, -1, px1: pl, px2: pr, pr: prad),
      BmGoal(1, Fb, pl + prad, pr - prad, 1, px1: pl, px2: pr, pr: prad),
    ];
  }

  BmBody mk(double x, double y, int team, double r, double m, {int power = 0}) =>
      BmBody(x, y, team, r, m, power: power);

  /// v6: seconds left of the post-goal glide back to the kickoff slots (render only; input and the turn clock wait).
  double glide = 0;

  /// 1 -> 0 while the pieces glide home (smoothstep of the time left), 0 otherwise.
  double get glideK {
    if (glide <= 0) return 0;
    final double u = _mn(1, glide / kBmResetGlide);
    return u * u * (3 - 2 * u);
  }

  void reset(int k, {bool glideIn = false}) {
    final Map<int, List<double>> was = <int, List<double>>{
      if (glideIn)
        for (final BmBody b in bodies) b.cid: <double>[b.x, b.y],
    };
    bodies = <BmBody>[];
    trail = <BmTrailPt>[];
    parts = <BmPart>[];
    rings = <BmRing>[];
    freeze = 0;
    slow = 0;
    cam = 0;
    for (int cm = 0; cm < 2; cm++) {
      // Each side's formation laid out in that side's own frame: the top side is the bottom layout turned half a
      // circle, so its left is the screen's right. Indexed by cm like the piece ids (cid), so a mirrored phone lays
      // out every cid exactly where the host does (snapshots and remote shots are keyed by cid).
      final List<List<double>> sl = bmSlots(form[cm]);
      for (int i = 0; i < sl.length; i++) {
        final double nx = sl[i][0], nd = sl[i][1];
        double x = _mx(Fl + PR + 6, _mn(Fr - PR - 6, Fl + nx * Fw)), y = Fb - nd * Fh / 2;
        if (cm != 0) {
          x = 2 * CX - x;
          y = 2 * CY - y;
        }
        if (mirror) {
          x = 2 * CX - x;
          y = 2 * CY - y;
        }
        final BmTeam tm = bmTeam(sel[ct(cm)]);
        final BmBody b = mk(x, y, ct(cm), PR, DISC_M, power: tm.power)..accuracy = tm.accuracy;
        b.cid = cm * 20 + i;
        b.boost = 0;
        bodies.add(b);
      }
    }
    final BmBody bl = mk(CX, mirror ? 2 * CY - KY : KY, 2, BR, BALL_M);
    bl.cid = 99;
    ball = bl;
    bodies.add(bl);
    glide = 0;
    if (glideIn) {
      for (final BmBody b in bodies) {
        final List<double>? p = was[b.cid];
        if (p == null) continue;
        b.gx = p[0] - b.x;
        b.gy = p[1] - b.y;
        if (b.gx.abs() + b.gy.abs() > 1) glide = kBmResetGlide;
      }
    }
    turn = k;
    _turnStarted();
    phase = 'aim';
    drag = null;
    pause = 0;
    idle = 0;
    shots = 0;
    tleft = tt;
    remote = false;
    aiT = 0;
    aiPlan = null;
    hooks.emit('turn', <String, dynamic>{'turn': ct(turn), 'mine': turn == 0});
  }

  void toast(String t, [bool big = false]) => hooks.toast(t, big);

  void burst(double x, double y, int n, double sp, List<int> cols, double life, [int k = 0]) {
    if (parts.length > 360) return;
    for (int i = 0; i < n; i++) {
      final double a = R_() * 7, v = sp * (.3 + R_());
      parts.add(BmPart(x, y, math.cos(a) * v, math.sin(a) * v, life * (.6 + R_() * .6), 2 + R_() * 3.5, cols[i % cols.length], k, 0,
          R_() * 6,
          m: life));
    }
  }

  void wallFx(double x, double y, double vs) {
    final double q = _mn(1, vs / (1500 * K));
    burst(x, y, (4 + q * 10).round(), 180 + q * 380, <int>[0xFFFFFFFF, bcol()[0], 0xFFFFD86B], .3, 5);
    if (q > .35) {
      rings.add(BmRing(x, y, 10, .26, q * .7));
      cam = _mx(cam, q * .55);
    }
  }

  void spawn(double x, double y, double vx, double vy, double l, double r, int c, [int k = 0, double g = 0]) {
    if (parts.length > 360) return;
    parts.add(BmPart(x, y, vx, vy, l, r, c, k, g, R_() * 6));
  }

  void scored(int t, [bool fromRemote = false]) {
    final bool ng = shots <= 1;
    if (!fromRemote && mode == 'online') hooks.emit('goal', <String, dynamic>{'team': ct(t), 'nogoal': ng});
    if (ng) {
      phase = 'goal';
      pause = 1.4;
      kick = turn;
      toast('No goal');
      return;
    }
    score[t]++;
    pause = kBmGoalHold; // v6: was 1.8
    flash = 1;
    shake[t] = .6;
    phase = 'goal';
    kick = 1 - t;
    hooks.goalFx();
    final BmBody b = ball!;
    final List<int> bc = kBmTR[setBall % kBmTR.length].c;
    burst(b.x, GOALS[t].y, 70, 700, <int>[0xFFFFD23A, 0xFFFFFFFF, bc[0], bc[1]], 1.3);
    burst(b.x, GOALS[t].y, 46, 520, <int>[...bc, 0xFFFFFFFF], 1.6, 1);
    hooks.sfx('goal');
    hooks.vib(<int>[60, 40, 120]);
    slow = 1.1;
    cam = 1.4;
    rings.add(BmRing(b.x, GOALS[t].y, 20, .7, 1));
    for (int w = 0; w < 3; w++) {
      _later(.25 + w * .3, () {
        if (inMatch) {
          burst(Fl + R_() * (Fr - Fl), GOALS[t].y + (GOALS[t].d < 0 ? 60 : -60), 26, 420, _goalCols, 1.4, 3);
          burst(Fl + R_() * (Fr - Fl), GOALS[t].y, 18, 300, _goalCols, 1.2, 1);
        }
      });
    }
    hooks.emit('scored', <String, dynamic>{
      'team': ct(t),
      'score': <int>[score[ct(0)], score[ct(1)]],
      'mine': t == 0
    });
  }

  // setTimeout replacement driven by frame() (wall-clock seconds).
  final List<MapEntry<double, void Function()>> _timers = <MapEntry<double, void Function()>>[];
  double _clock = 0;
  void _later(double sec, void Function() f) => _timers.add(MapEntry<double, void Function()>(_clock + sec, f));


  void walls(BmBody b) {
    final bool bl = b == ball;
    if (!bl && b.gout != null) {
      final BmGoal g = b.gout!;
      final double dq = g.d * (b.y - g.y);
      if (dq > -b.r * 1.05) {
        b.vy = -g.d * 270 * K;
        b.vx *= .6;
      } else {
        b.vy = 0;
        b.vx *= .2;
        b.gout = null;
      }
    }
    final double r = b.r, vs = math.sqrt(b.vx * b.vx + b.vy * b.vy);
    if (b.x - r < Fl) {
      b.x = Fl + r;
      if (b.vx < 0) {
        if (bl && vs > 200) {
          hooks.sfx('wall', vs / 1800);
          wallFx(Fl, b.y, vs);
        }
        b.vx *= -kBmRailE;
        b.spin += b.vy / (bl ? SPIN_R : r) * .05;
      }
    }
    if (b.x + r > Fr) {
      b.x = Fr - r;
      if (b.vx > 0) {
        if (bl && vs > 200) {
          hooks.sfx('wall', vs / 1800);
          wallFx(Fr, b.y, vs);
        }
        b.vx *= -kBmRailE;
        b.spin -= b.vy / (bl ? SPIN_R : r) * .05;
      }
    }
    for (final BmGoal g in GOALS) {
      final double dp = g.d * (b.y - g.y);
      if (dp <= -r) continue;
      final double lo = g.x1 + (bl ? 0 : r), hi = g.x2 - (bl ? 0 : r);
      final bool inside = bl ? (b.x > g.x1 && b.x < g.x2) : (dp > 0 || (b.x >= lo && b.x <= hi));
      if (inside) {
        final bool gl = phase == 'goal' && bl;
        final double eb = gl ? .2 : kBmRailE, back = g.y + g.d * DEPTH;
        if (!bl && dp > r * .3 && vs < 150 * K && b.gout == null) b.gout = g;
        if (dp + r > DEPTH) {
          b.y = back - g.d * r;
          b.vy = -g.d * b.vy.abs() * eb;
          if (gl) b.vx *= .6;
        }
        if (dp > (bl ? r * .6 : 0)) {
          final double ee = gl ? .3 : kBmRailE;
          if (b.x < g.x1 + r) {
            b.x = g.x1 + r;
            if (b.vx < 0) b.vx *= -ee;
          }
          if (b.x > g.x2 - r) {
            b.x = g.x2 - r;
            if (b.vx > 0) b.vx *= -ee;
          }
        }
      } else {
        if (bl && vs > 200) {
          hooks.sfx('wall', vs / 1800);
          wallFx(b.x, g.y, vs);
        }
        b.y = g.y - g.d * r;
        if (g.d * b.vy > 0) b.vy = -g.d * b.vy.abs() * kBmRailE;
        b.spin += g.d * b.vx / (bl ? SPIN_R : r) * .05;
      }
    }
    for (final List<double> c in <List<double>>[
      <double>[Fl + RC, Ft + RC, 1, 1],
      <double>[Fr - RC, Ft + RC, -1, 1],
      <double>[Fl + RC, Fb - RC, 1, -1],
      <double>[Fr - RC, Fb - RC, -1, -1],
    ]) {
      final double cx = c[0], cy = c[1], sx = c[2], sy = c[3];
      if (RC <= r) continue; // corner tighter than the body: the straight walls already hold it
      if ((b.x - cx) * sx < 0 && (b.y - cy) * sy < 0) {
        final double dx = b.x - cx, dy = b.y - cy, d = math.sqrt(dx * dx + dy * dy), lim = RC - r;
        if (d > lim && d > 0) {
          final double nx = dx / d, ny = dy / d, vn = b.vx * nx + b.vy * ny;
          b.x = cx + nx * lim;
          b.y = cy + ny * lim;
          if (vn > 0) {
            const double ec = kBmRailE;
            b.vx -= (1 + ec) * vn * nx;
            b.vy -= (1 + ec) * vn * ny;
          }
        }
      }
    }
  }

  void post(BmBody b, double px, double py, double pr) {
    final double dx = b.x - px, dy = b.y - py, d = math.sqrt(dx * dx + dy * dy), m = b.r + pr;
    if (d >= m || d == 0) return;
    final double nx = dx / d, ny = dy / d, vn = b.vx * nx + b.vy * ny;
    b.x = px + nx * m;
    b.y = py + ny * m;
    if (vn < 0) {
      const double kp = 1 + kBmRailE; // v7: posts rebound like the rails (was ball 1.54-1.7, disc 1.48)
      b.vx -= kp * vn * nx;
      b.vy -= kp * vn * ny;
      if (b == ball) {
        hooks.sfx('post', -vn / 1800);
        if (-vn > 900 * K) {
          toast('Post!');
          burst(b.x, b.y, 16, 380, <int>[0xFFFFFFFF, 0xFFFFD86B], .4, 5);
          rings.add(BmRing(px, py, 10, .3, .8));
          cam = _mx(cam, .7);
        }
      }
      hooks.tone('post');
    }
  }

  void hit(BmBody a, BmBody b) {
    double dx = b.x - a.x, dy = b.y - a.y, d = math.sqrt(dx * dx + dy * dy);
    final double m = a.r + b.r;
    if (d >= m) return;
    if (d < 1e-4) {
      dx = 1;
      dy = 0;
      d = 1;
    }
    final BmBody bl = ball!;
    final double nx = dx / d, ny = dy / d;
    final bool isB = a == bl || b == bl;
    double ka = isB && a != bl ? 1 / HV : 1, kb = isB && b != bl ? 1 / HV : 1;
    // Calibration v2: when the ball is the faster body it is the ball that strikes the disc -> full push.
    final bool ballHits = isB &&
        (bl.vx * bl.vx + bl.vy * bl.vy) > (a == bl ? b.vx * b.vx + b.vy * b.vy : a.vx * a.vx + a.vy * a.vy);
    // v3: a disc the ball strikes reacts as a lighter piece (kBmDiscLightM); every other contact uses the body masses.
    final double ima = ballHits && a != bl ? 1 / kBmDiscLightM : a.im, imb = ballHits && b != bl ? 1 / kBmDiscLightM : b.im;
    final double sm = ima + imb;
    if (ballHits) {
      if (a == bl) {
        kb = kBmBallHitDiscK;
      } else {
        ka = kBmBallHitDiscK;
      }
    }
    if (!isB) {
      final double sa = math.sqrt(a.vx * a.vx + a.vy * a.vy), sb = math.sqrt(b.vx * b.vx + b.vy * b.vy);
      if (sa > sb) {
        kb = kBmStruckDiscK;
      } else {
        ka = kBmStruckDiscK;
      }
    }
    double wa = ima / sm * ka, wb = imb / sm * kb;
    if (isB) {
      if (a == bl) {
        wa = 1 - wb;
      } else {
        wb = 1 - wa;
      }
    }
    final double pen = _mx(m - d - .3, 0) * .9;
    a.x -= nx * pen * wa;
    a.y -= ny * pen * wa;
    b.x += nx * pen * wb;
    b.y += ny * pen * wb;
    final double vn = (b.vx - a.vx) * nx + (b.vy - a.vy) * ny;
    if (vn >= 0) return;
    // v5: discs pick up spin from the tangential part of the contact (same sign convention as the ball below).
    final double vt = -ny * (b.vx - a.vx) + nx * (b.vy - a.vy);
    if (a != bl) a.spin = _mx(-kBmDiscSpinMax, _mn(kBmDiscSpinMax, a.spin - vt / a.r * kBmDiscSpinK));
    if (b != bl) b.spin = _mx(-kBmDiscSpinMax, _mn(kBmDiscSpinMax, b.spin + vt / b.r * kBmDiscSpinK));
    final double e = vn < -40 * K ? (isB ? .55 - .12 * _mn(1, _mx(0, (-vn - 500 * K) / (1200 * K))) : EPP) : 0,
        j = -(1 + e) * vn / sm;
    final BmBody? pa = isB ? (a == bl ? b : a) : null;
    final double pre = pa != null ? math.sqrt(pa.vx * pa.vx + pa.vy * pa.vy) : 0;
    if (pa != null) {
      // disc strikes the ball (disc faster than ball): ball launch x1.05 overall (see BKICK).
      final double bs = math.sqrt(bl.vx * bl.vx + bl.vy * bl.vy);
      if (pre > bs) {
        if (a == bl) {
          ka *= BKICK;
        } else {
          kb *= BKICK;
        }
      }
    }
    a.vx -= j * nx * ima * ka;
    a.vy -= j * ny * ima * ka;
    b.vx += j * nx * imb * kb;
    b.vy += j * ny * imb * kb;
    // PCAP only limits a slow disc that pushes the ball, never a disc the ball struck (calibration v2).
    if (pa != null && pre < 260 * K && !ballHits) {
      final double ps = math.sqrt(pa.vx * pa.vx + pa.vy * pa.vy), cp = PCAP * K;
      if (ps > cp) {
        pa.vx *= cp / ps;
        pa.vy *= cp / ps;
      }
    }
    if (vn < -120 * K) {
      hooks.sfx(isB ? 'hitb' : 'hitp', -vn / 1900);
      if (vn < -420 * K) {
        final double q = _mn(1, -vn / (1500 * K));
        burst(a.x + nx * a.r, a.y + ny * a.r, (4 + q * 8).round(), 260 + q * 300, <int>[0xFFFFFFFF, 0xFF9FE0FF, 0xFFFFD86B], .3, 5);
        if (!isB) {
          a.sq = _mx(a.sq, q);
          b.sq = _mx(b.sq, q);
          rings.add(BmRing(a.x + nx * a.r, a.y + ny * a.r, 12, .3, q * .8));
          cam = _mx(cam, q * .6);
        }
        hooks.vib(<int>[12]);
      }
    }
    if (isB) {
      bl.spin += (bl == b ? 1 : -1) * (-ny * (b.vx - a.vx) + nx * (b.vy - a.vy)) / SPIN_R * .3;
      bl.spin = _mx(-34, _mn(34, bl.spin));
      final double pw = _mn(1, -vn / (1700 * K));
      if (pw > .2) {
        final BmBody o = bl == b ? a : b;
        final int sg = bl == b ? -1 : 1;
        bl.sq = _mx(bl.sq, pw);
        cam = _mx(cam, pw * .9);
        o.sq = _mx(o.sq, pw);
        if (pw > .75 && freeze <= 0) freeze = .04;
        rings.add(BmRing(bl.x, bl.y, bl.r, .34, pw));
        burst(bl.x + nx * sg * bl.r * .2, bl.y + ny * sg * bl.r * .2, (6 + pw * 18).round(), 260 + pw * 520,
            pw > .7 ? <int>[...bcol(), 0xFFFFFFFF] : bcol(), .32 + .2 * pw);
        hooks.vib(pw > .7 ? <int>[18, 14, 30] : <int>[16]);
      }
    }
  }

  // 3D ball rotation (game.js rot)
  final List<double> _M = List<double>.filled(9, 0);
  void rot(List<double> R, double wx, double wy, double wz, double dt) {
    final double w = math.sqrt(wx * wx + wy * wy + wz * wz), th = w * dt;
    if (th < 1e-7) return;
    final double nx = wx / w, ny = wy / w, nz = wz / w, c = math.cos(th), sn = math.sin(th), C = 1 - c;
    final List<double> M = _M;
    M[0] = c + nx * nx * C;
    M[1] = nx * ny * C - nz * sn;
    M[2] = nx * nz * C + ny * sn;
    M[3] = ny * nx * C + nz * sn;
    M[4] = c + ny * ny * C;
    M[5] = ny * nz * C - nx * sn;
    M[6] = nz * nx * C - ny * sn;
    M[7] = nz * ny * C + nx * sn;
    M[8] = c + nz * nz * C;
    for (int q = 0; q < 3; q++) {
      final double a = R[q], b = R[3 + q], d = R[6 + q];
      R[q] = M[0] * a + M[1] * b + M[2] * d;
      R[3 + q] = M[3] * a + M[4] * b + M[5] * d;
      R[6 + q] = M[6] * a + M[7] * b + M[8] * d;
    }
  }

  void sim(double dt) {
    final BmBody? bal = ball;
    for (final BmBody b in bodies) {
      b.x += b.vx * dt;
      b.y += b.vy * dt;
      final double sp = math.sqrt(b.vx * b.vx + b.vy * b.vy);
      final bool bl = b == bal;
      if (sp > 0) {
        if (bl) {
          // Reference: the ball rolls with ~1.08/s linear drag + ~13 px/s^2 (global fit over 14 free rolls, rms 3.8 px).
          final double f = kBmBallF0 * K * _mn(1, sp / (300 * K)) + sp * kBmBallDrag, ns = sp - f * dt;
          if (ns < 12 * K) {
            b.vx = 0;
            b.vy = 0;
          } else {
            final double m = _mx(-34, _mn(34, b.spin)) * kBmBallCurve * dt, cs = math.cos(m), sn = math.sin(m);
            final double vx = b.vx * cs - b.vy * sn, vy = b.vx * sn + b.vy * cs, k = _mn(ns, kBmBallVMax * K) / sp;
            b.vx = vx * k;
            b.vy = vy * k;
          }
        } else {
          final double fb = b.boost > 0 ? .35 : 1;
          if (b.boost > 0) b.boost -= dt;
          final double ns = sp - (PF1 * K * _mn(1, sp / (PV0 * K)) + sp * PF2) * fb * dt;
          if (ns < kBmDiscStop * K) {
            b.vx = 0;
            b.vy = 0;
          } else {
            final double k = _mn(ns, kBmDiscVMax * K) / sp;
            b.vx *= k;
            b.vy *= k;
          }
        }
      }
      if (bl) {
        final double sp2 = math.sqrt(b.vx * b.vx + b.vy * b.vy);
        b.spin *= 1 - (sp2 > 0 ? 1.05 : 3.2) * dt;
        if (b.spin.abs() < .02) b.spin = 0;
        b.sq *= 1 - 9 * dt;
        final double roll = .95 / b.r, wx = -b.vy * roll, wy = b.vx * roll, wz = b.spin * .55;
        if (sp2 > 0 || wz != 0) {
          rot(b.R, wx, wy, wz, dt);
          b.rv++;
        }
        b.ang += b.spin * dt;
      } else {
        b.spin *= 1 - 2.6 * dt;
        b.ang += b.spin * dt;
      }
      walls(b);
    }
    for (int i = 0; i < 2; i++) {
      for (int a = 0; a < bodies.length; a++) {
        for (int c = a + 1; c < bodies.length; c++) {
          hit(bodies[a], bodies[c]);
        }
      }
    }
    if (bal != null) {
      for (final BmGoal g in GOALS) {
        post(bal, g.px1, g.y, g.pr);
        post(bal, g.px2, g.y, g.pr);
      }
    }
    for (final BmBody b in bodies) {
      if (b != bal) {
        for (final BmGoal g in GOALS) {
          post(b, g.px1, g.y, g.pr);
          post(b, g.px2, g.y, g.pr);
        }
      }
      walls(b);
    }
    if (phase == 'move' && !remote && bal != null) {
      for (final BmGoal g in GOALS) {
        if (bal.x > g.x1 && bal.x < g.x2 && (g.d < 0 ? bal.y < g.y - bal.r * .8 : bal.y > g.y + bal.r * .8)) {
          scored(g.team);
        }
      }
    }
  }

  // ---------------------------------------------------------------- flow
  void end() {
    hooks.sfx('fin');
    phase = 'over';
    if (_endEmitted) return;
    _endEmitted = true;
    hooks.emit('end', <String, dynamic>{
      'score': <int>[score[ct(0)], score[ct(1)]],
      'local': List<int>.from(score),
    });
  }

  void restart(int k) {
    score = <int>[0, 0];
    _endEmitted = false;
    mleft = mt.toDouble();
    sd = false;
    reset(ct(k));
  }

  bool canCtl() =>
      !menuOpen &&
      phase == 'aim' &&
      glide <= 0 &&
      !remote &&
      turn != ai &&
      !(mode == 'online' && turn != 0) &&
      !(mode == 'online' && perSide > 1 && localSeat != null && controllerSeat(ct(turn)) != localSeat);

  // ---------------------------------------------------------------- team rotation (2v2 / 3v3)
  /// Players per side (from the config) and this phone's seat (online team games).
  int perSide = 1;
  int? localSeat;

  /// Turns each side (global side index) has started; the shooter rotates with it.
  final List<int> sideTurns = <int>[0, 0];

  void _turnStarted() => sideTurns[ct(turn)]++;

  /// Index (0..perSide-1) of the side's player whose turn it is.
  int shooterIndex(int side) => perSide <= 1 ? 0 : (math.max(1, sideTurns[side]) - 1) % perSide;

  /// Global seat of the side's current shooter (sides alternate seats: 0,2,4 / 1,3,5).
  int shooterSeat(int side) => side + 2 * shooterIndex(side);

  /// v5 (team games): seats that left the match (online forfeits). Their turns are played by the next teammate still
  /// in the match; the rotation counters (and so every phone's replay) are unchanged, only who may shoot moves.
  bool Function(int seat)? seatGone;

  /// Seat that shoots the side's current turn: the shooter, or when they left, the next teammate still playing.
  int controllerSeat(int side) {
    final int s = shooterSeat(side);
    final bool Function(int seat)? gone = seatGone;
    if (perSide <= 1 || gone == null || !gone(s)) return s;
    final int i0 = shooterIndex(side);
    for (int k = 1; k < perSide; k++) {
      final int c = side + 2 * ((i0 + k) % perSide);
      if (!gone(c)) return c;
    }
    return s;
  }

  /// Replay only: adopt the rotation counters carried in a settled snapshot.
  void applyRotation(Map<String, dynamic>? snap) {
    final List<dynamic>? r = snap?['rt'] as List<dynamic>?;
    if (r != null && r.length == 2) {
      sideTurns[0] = (r[0] as num).toInt();
      sideTurns[1] = (r[1] as num).toInt();
    }
  }

  /// Replay only: a logged timeout flipped the turn without finishTurn().
  void bumpRotation() => _turnStarted();

  void launch(BmBody b, double vx, double vy, bool fromRemote) {
    b.vx = vx;
    b.vy = vy;
    b.boost = kBmLaunchGlide;
    glide = 0; // v6: a shot (e.g. a remote one arriving early) ends any post-goal glide at once
    if (b.team != turn) turn = b.team;
    phase = 'move';
    idle = 0;
    shots++;
    remote = fromRemote;
    drag = null;
    hooks.tone('launch');
    burst(b.x, b.y, 10, 300, bcol(), .35);
    cam = _mx(cam, .25);
  }

  /// Shot multiplier of a power rating (unchanged ANIX tuning): 1 => 0.65x, 5 => 1.05x, 7 => 1.25x, 10 => 1.55x.
  /// Reference calibration: a power-2 side launches at ~0.40x the speed of a power-10 side (700 vs 1720 px/s).
  static double strikeOf(int power) => .39 + power.clamp(1, 10) * .116;

  /// v6: share of the calibrated power-10 shot (the reference recordings, 10 / 10 sides) that a power gets:
  /// 10 => 1, 9 => .925, 5 => .626, 2 => .401, 1 => .326 (the reference's own Japan 2 vs PSG 10 ratio, .40).
  static double powerShare(int power) => strikeOf(power) / strikeOf(10);

  /// Strike multiplier of a REFERENCE-game power (its scale goes past 10: Starbucks / Oreo show 15). Same linear law,
  /// unclamped; used only to normalise speeds measured on the reference recordings (see kBmRefPower).
  static double refStrikeOf(int power) => .39 + power * .116;

  /// Aim error (radians) of an accuracy rating for a uniform sample u in [-1, 1].
  static double aimErrorOf(int accuracy, double u) => (10 - accuracy.clamp(1, 10)) / 9 * kBmMaxAimError * u;

  void fire(BmBody b, double dx, double dy, double l) {
    final double p = _mn(l, LMAX) / LMAX;
    // Team stats are physical, applied before launch: power scales the impulse, accuracy bends the aimed direction by
    // a random error (triangular, so most shots stay near the aim). Online the resulting velocity is what is sent, so
    // both phones replay the same shot.
    final double v = (260 + 1085 * math.pow(p, .8).toDouble()) * K * kBmLaunch * strikeOf(b.power);
    final double err = aimErrorOf(b.accuracy, R_() - R_()), ca = math.cos(err), sa = math.sin(err);
    final double ux = dx / l, uy = dy / l;
    final double vx = (ux * ca - uy * sa) * v, vy = (ux * sa + uy * ca) * v;
    launch(b, vx, vy, false);
    final int sg = mirror ? -1 : 1;
    hooks.emit('shot', <String, dynamic>{'cid': b.cid, 'vx': vx * sg, 'vy': vy * sg, 'team': ct(b.team), 'power': b.power});
  }

  // ---------------------------------------------------------------- in-match formation change ("تغییر ترکیب")
  /// True when [side] (global side index) may re-form its discs right now: it is that side's turn, the aim phase,
  /// and no shot has been taken since the last kickoff (every disc still stands on its kickoff slot). Only the side to
  /// play can change immediately, so online the change and that side's first shot come from the same phone in order
  /// and can never race the opponent's shot.
  bool canReformNow(int side) => inMatch && phase == 'aim' && shots == 0 && ct(turn) == side;

  /// Changes [side]'s formation (global side index) to [fi] during a match. Applied at once when
  /// [canReformNow], otherwise stored for the next kickoff (reset() lays every side out from [form]).
  /// Deterministic: online both phones apply the same logged 'form' move to the same state. Returns true when the
  /// discs were moved now.
  bool changeForm(int side, int fi) {
    if (side < 0 || side > 1) return false;
    form[side] = fi.clamp(0, kBmForms.length - 1).toInt();
    if (!canReformNow(side)) return false;
    final List<List<double>> sl = bmSlots(form[side]);
    for (final BmBody b in bodies) {
      if (b == ball || b.cid ~/ 20 != side) continue;
      final int i = b.cid % 20;
      if (i >= sl.length) continue;
      // same layout as reset(): the side's own frame, top side turned half a circle, mirrored phones flipped
      double x = _mx(Fl + PR + 6, _mn(Fr - PR - 6, Fl + sl[i][0] * Fw)), y = Fb - sl[i][1] * Fh / 2;
      if (side != 0) {
        x = 2 * CX - x;
        y = 2 * CY - y;
      }
      if (mirror) {
        x = 2 * CX - x;
        y = 2 * CY - y;
      }
      b.x = x;
      b.y = y;
      b.vx = 0;
      b.vy = 0;
      b.tr.clear();
    }
    drag = null;
    return true;
  }

  void finishTurn(bool emitSnap) {
    turn = 1 - turn;
    _turnStarted();
    phase = 'aim';
    tleft = tt;
    remote = false;
    aiT = 0;
    aiPlan = null;
    if (emitSnap && mode == 'online') hooks.emit('settled', <String, dynamic>{'snap': snapshot(), 'mt': mleft});
    hooks.emit('turn', <String, dynamic>{'turn': ct(turn), 'mine': turn == 0});
  }

  void skipTurn() {
    if (phase != 'aim') return;
    drag = null;
    aiPlan = null;
    toast('Time up');
    finishTurn(false);
  }

  Map<String, dynamic> snapshot() {
    List<double> f(double x, double y) => mirror ? <double>[2 * CX - x, 2 * CY - y] : <double>[x, y];
    return <String, dynamic>{
      'b': bodies.map((BmBody b) {
        final List<double> p = f(b.x, b.y);
        return <num>[b.cid, double.parse(p[0].toStringAsFixed(1)), double.parse(p[1].toStringAsFixed(1))];
      }).toList(),
      'sc': <int>[score[ct(0)], score[ct(1)]],
      'tn': ct(turn),
      'rt': <int>[sideTurns[0], sideTurns[1]],
    };
  }

  void applySnapshot(Map<String, dynamic>? s) {
    if (s == null || s['b'] is! List) return;
    for (final dynamic e in s['b'] as List<dynamic>) {
      final List<dynamic> q = e as List<dynamic>;
      final int cid = (q[0] as num).toInt();
      final double x = (q[1] as num).toDouble(), y = (q[2] as num).toDouble();
      BmBody? b;
      for (final BmBody o in bodies) {
        if (o.cid == cid) b = o;
      }
      if (b == null) continue;
      b.x = mirror ? 2 * CX - x : x;
      b.y = mirror ? 2 * CY - y : y;
      b.vx = 0;
      b.vy = 0;
    }
  }

  // ---------------------------------------------------------------- remote API (game.js public API)
  void remoteShot(Map<String, dynamic> m) {
    final int cid = (m['cid'] as num).toInt();
    BmBody? b;
    for (final BmBody o in bodies) {
      if (o.cid == cid) b = o;
    }
    if (b == null) return;
    final int? power = (m['power'] as num?)?.toInt();
    if (power != null && power >= 1 && power <= 10) b.power = power;
    final int sg = mirror ? -1 : 1;
    launch(b, (m['vx'] as num).toDouble() * sg, (m['vy'] as num).toDouble() * sg, true);
  }

  void remoteSettled(Map<String, dynamic> m) {
    if (phase != 'move' && phase != 'aim') return;
    final Map<String, dynamic>? snap = (m['snap'] as Map?)?.cast<String, dynamic>();
    applySnapshot(snap);
    final num? mtv = m['mt'] as num?;
    if (mtv != null) syncClock(mtv.toDouble());
    // JS flips the turn here; when the local fallback (idle > 3 s) already flipped it, only adopt the snapshot.
    final num? tn = snap?['tn'] as num?;
    if (phase == 'aim' && tn != null && ct(turn) == tn.toInt()) return;
    finishTurn(false);
  }

  void remoteGoal(Map<String, dynamic> m) {
    if (phase == 'move' || phase == 'aim') scored(ct((m['team'] as num).toInt()), true);
  }

  void remoteTimeout(Map<String, dynamic> m) {
    final num? seat = m['seat'] as num?;
    if (seat != null && ct(turn) != seat.toInt()) return;
    skipTurn();
  }

  void syncClock(double sec) {
    if (mt > 0 && !sd && (mleft - sec).abs() > 1.2) mleft = _mx(0, sec);
  }

  // ---------------------------------------------------------------- timer + AI
  void timeCheck() {
    if (!(mt > 0) || sd || mleft > 0) return;
    if (score[0] != score[1]) {
      end();
    } else {
      sd = true;
      toast('Golden goal!');
      hooks.sfx('whs');
    }
  }

  void tick(double dt) {
    if (phase == 'aim') timeCheck();
    if (phase != 'aim') return;
    if (tt > 0) {
      tleft -= dt;
      if (tleft <= 0) {
        if (mode == 'online') {
          hooks.emit('timeout', <String, dynamic>{'team': ct(turn)});
          skipTurn();
        } else {
          skipTurn();
        }
        return;
      }
    }
    if (turn == ai) aiTick(dt);
  }

  void aiTick(double dt) {
    if (phase != 'aim') return;
    if (aiPlan == null) {
      aiT += dt;
      if (aiT < .7 + R_() * .7) return;
      final BmAiPlan? p = aiDecide();
      aiPlan = p;
      if (p == null) return;
      p.t = 0;
      drag = BmDrag(p.b, p.b.x, p.b.y, p.b.x, p.b.y, ai: true);
      return;
    }
    final BmAiPlan p = aiPlan!;
    p.t += dt;
    final double k = _mn(1, p.t / .75), e = k * k * (3 - 2 * k);
    drag?.cx = p.b.x - p.dx * p.l * e;
    drag?.cy = p.b.y - p.dy * p.l * e;
    if (k >= 1) {
      drag = null;
      aiPlan = null;
      fire(p.b, p.dx * p.l, p.dy * p.l, p.l);
    }
  }

  static double segDist(double px, double py, double ax, double ay, double bx, double by) {
    final double vx = bx - ax, vy = by - ay;
    double l2 = vx * vx + vy * vy;
    if (l2 == 0) l2 = 1;
    double t = ((px - ax) * vx + (py - ay) * vy) / l2;
    t = _mx(0, _mn(1, t));
    final double qx = px - (ax + vx * t), qy = py - (ay + vy * t);
    return math.sqrt(qx * qx + qy * qy);
  }

  double gauss() => (R_() + R_() + R_() - 1.5) * 1.15;

  BmAiPlan? aiDecide() {
    final int me = turn;
    final BmBody bal = ball!;
    final List<BmBody> mine = bodies.where((BmBody b) => b.team == me && b != bal).toList();
    final BmGoal tg = GOALS[me], og = GOALS[1 - me];
    final int lvl = aiLvl;
    final double sg = <double>[.14, .06, .016][lvl], gw = (tg.x2 - tg.x1) / 2;
    final List<_Cand> cands = <_Cand>[];
    bool clear(BmBody p, double x, double y) {
      for (final BmBody o in bodies) {
        if (o == p || o == bal) continue;
        if (segDist(o.x, o.y, p.x, p.y, x, y) < p.r + o.r - 6) return false;
      }
      return true;
    }

    for (final BmBody p in mine) {
      for (final double ox in <double>[-.55, 0, .55]) {
        final double Tx = CX + ox * gw, Ty = tg.y;
        double ux = Tx - bal.x, uy = Ty - bal.y;
        double ul = math.sqrt(ux * ux + uy * uy);
        if (ul == 0) ul = 1;
        ux /= ul;
        uy /= ul;
        final double cx = bal.x - ux * (p.r + bal.r + 1), cy = bal.y - uy * (p.r + bal.r + 1);
        double vx = cx - p.x, vy = cy - p.y;
        final double dist = math.sqrt(vx * vx + vy * vy);
        if (dist < 8) continue;
        vx /= dist;
        vy /= dist;
        final double al = vx * ux + vy * uy;
        if (al < .2) continue;
        if (!clear(p, cx, cy)) continue;
        int blk = 0;
        for (final BmBody o in bodies) {
          if (o.team == me || o == bal) continue;
          if (segDist(o.x, o.y, bal.x, bal.y, Tx, Ty) < bal.r + o.r + 6) blk++;
        }
        cands.add(_Cand(p, vx, vy, 100 * al - dist * .03 - blk * 28 + ((bal.y - Ty).abs() < 420 ? 25 : 0), dist, true));
      }
      double vx = bal.x - p.x, vy = bal.y - p.y;
      final double dist = math.sqrt(vx * vx + vy * vy);
      if (dist > 8) {
        vx /= dist;
        vy /= dist;
        if (clear(p, bal.x, bal.y)) {
          final double toOwn = (vy * (og.y - bal.y) > 0) ? vy.abs() : 0;
          cands.add(_Cand(p, vx, vy, 10 - dist * .04 - toOwn * 55, dist, false));
        }
      }
    }
    if (cands.isEmpty) {
      final List<BmBody> s = List<BmBody>.from(mine)
        ..sort((BmBody a, BmBody b) =>
            _h(a.x - bal.x, a.y - bal.y).compareTo(_h(b.x - bal.x, b.y - bal.y)));
      if (s.isEmpty) return null;
      final BmBody p = s.first;
      final double vx = bal.x - p.x, vy = bal.y - p.y;
      double d = _h(vx, vy);
      if (d == 0) d = 1;
      cands.add(_Cand(p, vx / d, vy / d, 0, d, false));
    }
    cands.sort((_Cand a, _Cand b) => b.sc.compareTo(a.sc));
    final List<_Cand> pool = cands.sublist(0, math.min<int>(cands.length, <int>[4, 2, 1][lvl]));
    final _Cand c = pool[(R_() * pool.length).floor()];
    final double ang = math.atan2(c.dy, c.dx) + gauss() * sg;
    double pw = lvl == 2 ? _mn(1, .66 + c.dist / 1000) : _mn(1, .5 + c.dist / 1100);
    if (lvl == 0) pw *= .7 + R_() * .3;
    if (c.atk && lvl > 0) pw = _mx(pw, .78);
    return BmAiPlan(c.p, math.cos(ang), math.sin(ang), _mx(.3, pw) * LMAX);
  }

  static double _h(double x, double y) => math.sqrt(x * x + y * y);

  // ---------------------------------------------------------------- fx state (game.js fx())
  void fx(double dt) {
    final BmBody? bal = ball;
    for (final BmBody b in bodies) {
      if (b == bal) continue;
      final double sp = _h(b.vx, b.vy);
      if (sp > 140 * K) {
        b.tr.add(BmTrailPt(b.x, b.y, sp));
      } else if (b.tr.isNotEmpty) {
        b.tr.removeAt(0);
      }
      if (b.tr.length > 14) b.tr.removeAt(0);
      if (sp > 420 * K && R_() < dt * 34 && parts.length < 300) {
        final double ux = b.vx / sp, uy = b.vy / sp, o = (R_() - .5) * b.r * 1.6;
        spawn(b.x - ux * b.r * .8 - uy * o, b.y - uy * b.r * .8 + ux * o, -ux * 260, -uy * 260, .22, 2.2,
            b.team != 0 ? 0xFFFF9A9A : 0xFF9FD0FF, 5);
      }
    }
    for (final BmBody b in bodies) {
      if (b != bal && b.sq != 0) b.sq = b.sq > .02 ? b.sq - dt * 5 : 0;
    }
    if (bal != null && phase != 'over') {
      final double sp = _h(bal.vx, bal.vy);
      if (sp > 350 * K) trail.add(BmTrailPt(bal.x, bal.y, sp, h: sp > 1250 * K));
      if (sp > 300 * K && !menuOpen) {
        final double f = _mn(1, sp / (2300 * K));
        final BmTrail st = kBmTR[setBall % kBmTR.length];
        final List<int> c = st.c;
        final BmFa fa = kBmFA[field.id] ?? kBmFA['stadium']!;
        final double bx = bal.x, by = bal.y, ux = bal.vx / sp, uy = bal.vy / sp;
        fxAcc += dt * (26 + 70 * f);
        while (fxAcc >= 1) {
          fxAcc--;
          final double o = (R_() - .5) * BR * 1.4, px = bx - ux * BR * .6 - uy * o, py = by - uy * BR * .6 + ux * o;
          final double sx = (R_() - .5) * 260 - ux * 120, sy = (R_() - .5) * 260 - uy * 120;
          switch (st.k) {
            case 'bolt':
              spawn(px, py, sx * 1.6, sy * 1.6, .28, 2.2, R_() < .5 ? c[1] : c[2], 5);
              break;
            case 'prism':
              spawn(px, py, sx * .4, sy * .4, .5, 4 + R_() * 3, bmHsl(R_() * 360, 65), 0);
              break;
            case 'wave':
              spawn(px, py, sx * .3, sy * .3 - 40, .6, 3 + R_() * 3, c[R_() < .5 ? 0 : 1], 4, -60);
              break;
            case 'star':
              spawn(px, py, sx * .4, sy * .4, .7, 5 + R_() * 6, R_() < .4 ? c[2] : c[1], 1);
              break;
            case 'smoke':
              break;
            case 'rainbow':
              spawn(px, py, sx * .5, sy * .5, .6, 3 + R_() * 3, bmHsl(R_() * 360, 62), 3, 60);
              break;
            case 'neon':
              spawn(px, py, sx * .5, sy * .5, .45, 3 + R_() * 3, R_() < .5 ? c[0] : c[1], 3);
              break;
            case 'yin':
              spawn(px, py, sx * .4, sy * .4, .55, 3 + R_() * 4, R_() < .5 ? 0xFFFFFFFF : 0xFFA066FF, 0);
              break;
            case 'fire':
              spawn(px, py, sx * .35, sy * .35 - 90, .55, 6 + R_() * 7, c[R_() < .5 ? 0 : 1], 2, -260);
              break;
            case 'blade':
              spawn(px, py, -ux * 600 + sx * .2, -uy * 600 + sy * .2, .22, 2.2, c[R_() < .5 ? 0 : 1], 5);
              break;
            case 'ghost':
              if (R_() < .3) spawn(px, py, sx * .2, sy * .2, .7, 4, c[1], 1);
              break;
            case 'ember':
              spawn(px, py, sx * .5, sy * .5 - 60, .8, 2.5 + R_() * 2.5, c[R_() < .5 ? 0 : 1], 0, -150);
              break;
            case 'plasma':
              final double a = R_() * 6.28;
              spawn(px + math.cos(a) * 12, py + math.sin(a) * 12, math.cos(a) * 90 + sx * .2, math.sin(a) * 90 + sy * .2, .45,
                  3 + R_() * 3, c[R_() < .5 ? 0 : 1], 0);
              break;
          }
        }
        fxAcc2 += dt * (14 + 44 * f);
        while (fxAcc2 >= 1) {
          fxAcc2--;
          final double o = (R_() - .5) * BR * 2.4, px = bx - ux * BR - uy * o, py = by - uy * BR + ux * o;
          spawn(px, py, (R_() - .5) * 150, (R_() - .5) * 150, .55 + R_() * .5, (fa.k == 0 ? 2.2 : 4) + R_() * 4,
              fa.c[(R_() * fa.c.length).floor()], fa.k, fa.g);
        }
      }
    }
  }

  // ---------------------------------------------------------------- main loop (game.js loop)
  void frame(double rawDt) {
    final double dt = _mn(rawDt <= 0 ? .016 : rawDt, .05);
    _clock += dt;
    if (_timers.isNotEmpty) {
      final List<MapEntry<double, void Function()>> due =
          _timers.where((MapEntry<double, void Function()> e) => e.key <= _clock).toList();
      _timers.removeWhere((MapEntry<double, void Function()> e) => e.key <= _clock);
      for (final MapEntry<double, void Function()> e in due) {
        e.value();
      }
    }
    if (!menuOpen && bodies.isNotEmpty) {
      // v3 match clock: runs on real elapsed time (not the 50 ms physics clamp, which made it lag on slow frames);
      // a frame gap over 1 s (app resumed) counts as 1 s.
      final double clk = rawDt <= 0 ? .016 : _mn(rawDt, 1.0);
      if (mt > 0 && !sd && phase != 'over' && mleft > 0) mleft = _mx(0, mleft - clk);
      double ts = 1;
      if (freeze > 0) {
        freeze -= dt;
        ts = 0;
      } else if (slow > 0) {
        slow -= dt;
        ts = .32 + .68 * math.pow(1 - _mx(0, slow) / 1.1, 2).toDouble();
      }
      acc += dt * ts * kBmSimRate;
      int n = 0;
      if (phase != 'over') {
        while (acc >= STEP && n++ < 14) {
          sim(STEP);
          acc -= STEP;
        }
        if (n > 14) acc = 0;
      }
      if (phase == 'move') {
        idle = bodies.any((BmBody b) => b.vx != 0 || b.vy != 0) ? 0 : idle + dt;
        if (idle > .25) {
          if (!remote) {
            finishTurn(true);
          } else if (idle > 3) {
            finishTurn(false);
          }
        }
      } else if (phase == 'aim') {
        if (glide > 0) {
          glide = _mx(0, glide - dt);
        } else {
          tick(dt);
        }
      } else if (phase == 'goal') {
        pause -= dt;
        if (pause <= 0) {
          if (mt > 0) {
            if (sd || (mleft <= 0 && score[0] != score[1])) {
              end();
            } else {
              if (mleft <= 0) sd = true;
              reset(kick, glideIn: true);
            }
          } else if (score[0] >= setLim || score[1] >= setLim) {
            end();
          } else {
            reset(kick, glideIn: true);
          }
        }
      }
      fx(dt);
    }
    flash = _mx(0, flash - dt * 2);
    cam = _mx(0, cam - dt * 3.2);
    for (final BmRing r in rings) {
      r.l -= dt;
    }
    rings.removeWhere((BmRing r) => r.l <= 0);
    shake[0] = _mx(0, shake[0] - dt);
    shake[1] = _mx(0, shake[1] - dt);
    for (final BmTrailPt p in trail) {
      p.a -= dt * 3;
    }
    trail.removeWhere((BmTrailPt p) => p.a <= 0);
    for (final BmPart p in parts) {
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vx *= .97;
      p.vy = p.vy * .97 + p.g * dt;
      p.rot += dt * 4;
      p.l -= dt;
    }
    parts.removeWhere((BmPart p) => p.l <= 0);
  }

  // ---------------------------------------------------------------- start
  void startMatch(BmConfig cfg) {
    _later(.25, () => hooks.sfx('whs'));
    mode = cfg.mode;
    names = List<String>.from(cfg.names);
    mirror = cfg.mirror;
    perSide = cfg.perSide < 1 ? 1 : cfg.perSide;
    sideTurns[0] = 0;
    sideTurns[1] = 0;
    ai = cfg.ai ? 1 : -1;
    aiLvl = cfg.aiLvl;
    tt = cfg.turnTime;
    mt = cfg.matchTime;
    mleft = mt.toDouble();
    sd = false;
    sel = List<String>.from(cfg.teams);
    form = List<int>.from(cfg.form);
    setFld = bmFieldIndex(cfg.field);
    setBall = bmBallIndex(cfg.ball);
    setLim = cfg.matchTime > 0 ? 9999 : (cfg.limit == 0 ? 5 : cfg.limit);
    geo();
    score = <int>[0, 0];
    _endEmitted = false;
    reset(ct(cfg.first));
    inMatch = true;
    menuOpen = false;
  }

  void stop() {
    inMatch = false;
    phase = 'over';
    bodies = <BmBody>[];
    menuOpen = true;
  }

  // ---------------------------------------------------------------- touch input (world coords)
  void pointerDown(double px, double py) {
    if (!canCtl()) return;
    BmBody? f;
    double bd = 1e9;
    for (final BmBody b in bodies) {
      if (b.team == turn && b != ball) {
        final double d = _h(px - b.x, py - b.y);
        if (d < b.r + 30 && d < bd) {
          f = b;
          bd = d;
        }
      }
    }
    if (f == null) return;
    drag = BmDrag(f, px, py, px, py);
  }

  void pointerMove(double px, double py) {
    final BmDrag? d = drag;
    if (d != null && !d.ai) {
      d.cx = px;
      d.cy = py;
    }
  }

  void pointerUp() {
    final BmDrag? d = drag;
    if (d == null || d.ai) return;
    final double dx = d.sx - d.cx, dy = d.sy - d.cy, l = _h(dx, dy);
    drag = null;
    if (l > 18) fire(d.b, dx, dy, l);
  }

  void pointerCancel() {
    if (drag != null && !drag!.ai) drag = null;
  }
}

class _Cand {
  _Cand(this.p, this.dx, this.dy, this.sc, this.dist, this.atk);
  final BmBody p;
  final double dx, dy, sc, dist;
  final bool atk;
}

/// hsl(h, 100%, l%) as ARGB (game.js hsl()).
int bmHsl(double h, [double l = 60]) => bmHslColor(((h % 360) + 360) % 360, 1, l / 100);

int bmHslColor(double h, double s, double l) {
  final double c = (1 - (2 * l - 1).abs()) * s, hp = (h.floorToDouble() % 360) / 60, x = c * (1 - (hp % 2 - 1).abs()), m = l - c / 2;
  double r = 0, g = 0, b = 0;
  if (hp < 1) {
    r = c;
    g = x;
  } else if (hp < 2) {
    r = x;
    g = c;
  } else if (hp < 3) {
    g = c;
    b = x;
  } else if (hp < 4) {
    g = x;
    b = c;
  } else if (hp < 5) {
    r = x;
    b = c;
  } else {
    r = c;
    b = x;
  }
  int q(double v) => ((v + m) * 255).round().clamp(0, 255).toInt();
  return 0xFF000000 | (q(r) << 16) | (q(g) << 8) | q(b);
}


double _mn(double a, double b) => a < b ? a : b;
double _mx(double a, double b) => a > b ? a : b;
