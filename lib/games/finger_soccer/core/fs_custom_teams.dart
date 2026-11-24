// Shared finger-soccer custom teams (تیم‌های اختصاصی), owner spec 2026-11-24.
//
// A player who bought `fs_custom_team` (1000 gems) uploads a photo; the app cuts it to a round crest
// (fsCropRoundCrest, same 256px disc as the shipped crests) and the server creates the team
// (RPC fs_create_custom_team, table public.fs_custom_teams, supabase/migrations/20261124200000_nx_fs_shared_custom_teams.sql).
// Every authenticated player reads the shared list; each team is `cx_<uuid hex>` with power / accuracy 10 and its own
// 250-gem catalog row `fs_team:cx_<hex>` that nx_buy_with_gems sells. The owner fields it free.
//
// This file holds the client list. [FsCustomTeams.apply] appends / updates the teams in kBmTeams (category
// 'custom'), so every picker and bmTeam() lookup sees them; teams are never removed mid-session (indexes stay valid).
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'bm_engine.dart';

/// Gem price another player pays for someone's custom team (the server row wins).
const int kFsCustomTeamBuyPrice = 250;

/// Max custom team name length (server check).
const int kFsCustomTeamNameMax = 24;

/// Team id of the fs_custom_teams row [uuid] (`cx_` + the uuid without dashes; the table's generated team_id).
String fsCustomTeamIdOf(String uuid) => '$kBmCustomTeamPrefix${uuid.replaceAll('-', '').toLowerCase()}';

class FsCustomTeam {
  const FsCustomTeam({
    required this.teamId,
    required this.ownerId,
    required this.name,
    required this.crestUrl,
    this.price = kFsCustomTeamBuyPrice,
  });

  /// `cx_<hex>`.
  final String teamId;
  final String ownerId;
  final String name;
  final String crestUrl;
  final int price;

  /// A fs_custom_teams row (or the `team` object an RPC returns). Null when it is not a usable team.
  static FsCustomTeam? fromRow(Map<String, dynamic> m) {
    final String id = '${m['team_id'] ?? (m['id'] != null ? fsCustomTeamIdOf('${m['id']}') : '')}';
    final String owner = '${m['owner_id'] ?? ''}';
    final String url = '${m['crest_url'] ?? ''}';
    if (!bmIsCustomTeamId(id) || owner.isEmpty || !url.startsWith('https://')) return null;
    if (m['active'] == false) return null;
    String name = '${m['name'] ?? ''}'.trim();
    if (name.isEmpty) name = 'Custom Team';
    return FsCustomTeam(
        teamId: id, ownerId: owner, name: name, crestUrl: url, price: (m['price'] as num?)?.toInt() ?? kFsCustomTeamBuyPrice);
  }

  /// The engine team: category 'custom', power / accuracy 10, network crest with the fallback disc.
  BmTeam toBmTeam() => BmTeam(teamId, 'custom', name, name, kBmCustomTeamFallbackAsset, kBmCustomTeamStat,
      kBmCustomTeamStat, crestUrl: crestUrl);
}

/// The shared custom-team list (loaded with the gem shop, see GemShop.refresh).
class FsCustomTeams extends ChangeNotifier {
  FsCustomTeams._();
  static final FsCustomTeams instance = FsCustomTeams._();

  final Map<String, FsCustomTeam> _byId = <String, FsCustomTeam>{};
  bool loaded = false;

  List<FsCustomTeam> get teams => List<FsCustomTeam>.unmodifiable(_byId.values);

  FsCustomTeam? byTeamId(String teamId) => _byId[teamId];

  /// The custom team [uid] created (one per account), if any.
  FsCustomTeam? ownedBy(String? uid) {
    if (uid == null || uid.isEmpty) return null;
    for (final FsCustomTeam t in _byId.values) {
      if (t.ownerId == uid) return t;
    }
    return null;
  }

  bool isOwner(String teamId, String? uid) => uid != null && _byId[teamId]?.ownerId == uid;

  /// Adds / updates teams (and their kBmTeams entries). Returns true when anything changed.
  bool apply(Iterable<FsCustomTeam> list) {
    bool changed = false;
    for (final FsCustomTeam t in list) {
      final FsCustomTeam? old = _byId[t.teamId];
      if (old != null && old.name == t.name && old.crestUrl == t.crestUrl && old.price == t.price) continue;
      _byId[t.teamId] = t;
      final BmTeam bt = t.toBmTeam();
      final int at = kBmTeams.indexWhere((BmTeam x) => x.id == t.teamId);
      if (at >= 0) {
        kBmTeams[at] = bt;
      } else {
        kBmTeams.add(bt);
      }
      changed = true;
    }
    if (changed) notifyListeners();
    return changed;
  }

  /// Parses rows and [apply]s them.
  bool applyRows(Iterable<dynamic> rows) {
    final List<FsCustomTeam> list = <FsCustomTeam>[];
    for (final dynamic r in rows) {
      final FsCustomTeam? t = r is Map ? FsCustomTeam.fromRow(Map<String, dynamic>.from(r)) : null;
      if (t != null) list.add(t);
    }
    return apply(list);
  }

  /// Loads every active team (RLS: authenticated players read active rows).
  Future<void> load(SupabaseClient c) async {
    try {
      final List<dynamic> rows = await c
          .from('fs_custom_teams')
          .select('id, team_id, owner_id, name, crest_url, price, active')
          .eq('active', true)
          .order('created_at');
      applyRows(rows);
      loaded = true;
    } catch (e) {
      debugPrint('fs_custom_teams: $e');
    }
  }

  /// Makes sure [teamId] (e.g. an online opponent's team) is known: fetches that one row when it is not.
  Future<FsCustomTeam?> ensure(SupabaseClient? c, String teamId) async {
    final FsCustomTeam? have = _byId[teamId];
    if (have != null || c == null || !bmIsCustomTeamId(teamId)) return have;
    try {
      final dynamic row = await c
          .from('fs_custom_teams')
          .select('id, team_id, owner_id, name, crest_url, price, active')
          .eq('team_id', teamId)
          .maybeSingle();
      if (row is Map) applyRows(<dynamic>[row]);
    } catch (e) {
      debugPrint('fs_custom_teams ensure $teamId: $e');
    }
    return _byId[teamId];
  }

  @visibleForTesting
  void resetForTest() {
    _byId.clear();
    kBmTeams.removeWhere((BmTeam t) => bmIsCustomTeamId(t.id));
    loaded = false;
  }
}

/// Side of a custom crest in px (the shipped crests are 256 x 256 discs).
const int kFsCrestSize = 256;

/// Rim radius of the crest disc inside its square: the shipped discs put the rim at 120 of 128 (kBmDiscArtFill).
const double kFsCrestRimFill = 120 / 128;

/// Cuts [bytes] (any image the platform decodes) into a clean round crest: centre square crop (cover), scaled to
/// [size] px, a disc of radius size/2 * [kFsCrestRimFill] with a soft white rim, fully transparent outside. PNG.
Future<Uint8List> fsCropRoundCrest(Uint8List bytes, {int size = kFsCrestSize}) async {
  final ui.Codec codec = await ui.instantiateImageCodec(bytes);
  final ui.FrameInfo frame = await codec.getNextFrame();
  final ui.Image src = frame.image;
  try {
    final double side = (src.width < src.height ? src.width : src.height).toDouble();
    final ui.Rect from = ui.Rect.fromLTWH((src.width - side) / 2, (src.height - side) / 2, side, side);
    final double c = size / 2;
    final double r = c * kFsCrestRimFill;
    final ui.Rect disc = ui.Rect.fromCircle(center: ui.Offset(c, c), radius: r);
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(rec);
    canvas.save();
    canvas.clipPath(ui.Path()..addOval(disc), doAntiAlias: true);
    canvas.drawImageRect(src, from, disc, ui.Paint()..filterQuality = ui.FilterQuality.high);
    canvas.restore();
    final double rim = size / 64;
    canvas.drawCircle(
        ui.Offset(c, c),
        r - rim / 2,
        ui.Paint()
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = rim
          ..isAntiAlias = true
          ..color = const ui.Color(0xD9FFFFFF));
    final ui.Image out = await rec.endRecording().toImage(size, size);
    try {
      final ByteData? png = await out.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) throw StateError('crest_encode_failed');
      return png.buffer.asUint8List();
    } finally {
      out.dispose();
    }
  } finally {
    src.dispose();
  }
}
