// Data adapters for the finger-soccer pre-match intro (splash -> team select -> formation select).
// Teams and formations come straight from the engine (kBmTeams, kBmForms / bmSlots); this file only adds the
// Persian display names and reads the formation list in whatever shape the engine defines it.
import '../core/bm_data.dart';
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

/// Every formation the engine defines, in its order. The name is the Persian label when the engine has one.
List<FsFormation> fsFormations({bool fa = true}) {
  final List<FsFormation> out = <FsFormation>[];
  for (int i = 0; i < kBmForms.length; i++) {
    // kBmForms holds BmFormation (fa / en names, slots as [x, d] with d = depth of the half pitch, 0 = own goal
    // line, 1 = halfway line); the formation screen wants y in 0..0.5 of the whole pitch.
    final BmFormation f = kBmForms[i];
    final String name = fa ? f.fa : f.en;
    final List<List<double>> slots =
        bmSlots(i).map((List<double> s) => <double>[s[0], s[1] * .5]).toList(growable: false);
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

String fsTeamName(BmTeam t, bool fa) => fa ? t.faName : t.name;

/// Localized label for the v10 team catalogue category shown in both the picker and shop.
String fsTeamCategoryName(String category, bool fa) {
  for (final List<Object> row in kBmCats) {
    if (row[0] == category) return row[fa ? 2 : 1] as String;
  }
  return category;
}

