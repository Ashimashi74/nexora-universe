#!/usr/bin/env python3
"""Writes the catalogue section of lib/games/finger_soccer/core/bm_data.dart from tool/teams_v10.py.

Keeps one source of truth: edit the Python spec, run this script, and the Dart table (plus the SQL seed that
tool/gen_teams_sql.py builds from the same spec) always agree.
"""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from teams_v10 import CATS, TEAMS  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TARGET = os.path.join(REPO, 'lib', 'games', 'finger_soccer', 'core', 'bm_data.dart')
MARK_START = '/// v10 (owner art 2026-11-22): the catalogue is the owner'
MARK_END = 'class BmTrail {'


def dart_str(s: str) -> str:
    return s.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$')


def build() -> int:
    cats = ",\n".join(f"  <Object>['{c}', '{dart_str(en)}', '{dart_str(fa)}']" for c, en, fa in CATS)
    rows = []
    for tid, cat, en, fa, slug, p, a in TEAMS:
        folder = 'v9' if cat in ('cars', 'sport') else 'v10'
        rows.append(
            f"  BmTeamDef('{tid}', '{cat}', '{dart_str(en)}', '{dart_str(fa)}', 'discs/{folder}/{slug}', {p}, {a}),")
    counts = {}
    for t in TEAMS:
        counts[t[1]] = counts.get(t[1], 0) + 1
    summary = ', '.join(f'{k} {v}' for k, v in counts.items())
    block = f'''/// v10 (owner art 2026-11-22): the catalogue is the owner's full crest archive — {counts['clubs']} club badges,
/// {counts['nations']} national crests and {counts['nx']} NX faction coins, plus the {counts['elite']} elite "second finish" coins and the
/// {counts['legends']} bosses, cut one disc per coin by tool/build_fs_v10_assets.py ({summary}). The v9 car and sport
/// sets are kept as they are (same ids, same art on discs/v9). This table is generated: edit tool/teams_v10.py.
const List<List<Object>> kBmCats = <List<Object>>[
{cats},
];

/// One selectable piece set. [power] scales the shot impulse, [accuracy] narrows the aim spread (both 1..10).
class BmTeamDef {{
  const BmTeamDef(this.id, this.cat, this.name, this.faName, this.art, this.power, this.accuracy);
  final String id, cat, name;
  /// Persian name (shown when the UI is in Persian; the English name above is the canonical one).
  final String faName;
  /// Asset path relative to assets/games/bermuda/ (without .webp).
  final String art;
  final int power, accuracy;
}}

/// Shop catalogue ids: `club0..club31` and `nat20..nat23` are the v9 car / sport sets (their ids are the prices the
/// live nx_catalog already sells); everything else is a v10 id. Free teams: NX Core, NX Cyan, NX Mercury
/// (gem_shop.dart kFreeTeams), so a new player can always field a team.
const List<BmTeamDef> kBmTeamDefs = <BmTeamDef>[
{chr(10).join(rows)}
];
'''
    src = open(TARGET, encoding='utf-8').read()
    start = src.index(MARK_START)
    end = src.index(MARK_END)
    open(TARGET, 'w', encoding='utf-8').write(src[:start] + block + '\n' + src[end:])
    return len(TEAMS)


if __name__ == '__main__':
    print('wrote', build(), 'teams')
