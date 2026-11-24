#!/usr/bin/env python3
"""Offline static checks for the ANIX Flutter tree (lib/ + test/).

The repo is developed in an environment without the Flutter/Dart SDK (and without access to
storage.googleapis.com / pub.dev), so `flutter analyze` cannot run here. This script catches the
class of mistakes that survive hand edits: broken imports/exports/parts, duplicate public top-level
declarations that collide across directly imported libraries, unbalanced delimiters (with full Dart
string/raw-string/comment/`${...}` interpolation awareness), and references to design tokens that
are not declared on their owning class.

Usage: python3 tool/verify_static.py [--verbose]
Exit code 1 when a real problem is found.
"""
from __future__ import annotations

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.path.join(ROOT, 'lib')
TEST = os.path.join(ROOT, 'test')
PACKAGE = 'nexora'

DECL = re.compile(
    r'^(?:abstract\s+|sealed\s+|base\s+|final\s+|interface\s+)*'
    r'(class|enum|mixin|extension)\s+([A-Za-z_]\w*)',
    re.M,
)
DIRECTIVE_IMPORT = re.compile(
    r"""^\s*import\s+['"]([^'"]+)['"]([^;]*);""",
    re.M,
)
DIRECTIVE_EXPORT = re.compile(
    r"""^\s*export\s+['"]([^'"]+)['"]([^;]*);""",
    re.M,
)
PART = re.compile(r"""^\s*part\s+['"]([^'"]+)['"]\s*;""", re.M)
PART_OF = re.compile(r"""^\s*part\s+of\s+""", re.M)


def scan_dart(src: str) -> tuple[int, int, int, str]:
    """Lex Dart comments, strings (including raw and triple-quoted) and `${...}` interpolations.

    Returns `(paren_delta, brace_delta, bracket_delta, stripped_code)` where `stripped_code`
    replaces comments with spaces and string literal bodies with empty quotes (preserving newlines
    and interpolated expressions).
    """
    n = len(src)
    paren = brace = bracket = 0
    out: list[str] = []

    def walk_code(i: int, stop_on_brace: bool) -> int:
        nonlocal paren, brace, bracket
        brace_depth = 0
        while i < n:
            c = src[i]
            # Line comment
            if c == '/' and i + 1 < n and src[i + 1] == '/':
                j = src.find('\n', i + 2)
                if j < 0:
                    return n
                out.append('\n')
                i = j + 1
                continue
            # Block comment
            if c == '/' and i + 1 < n and src[i + 1] == '*':
                j = src.find('*/', i + 2)
                end = n if j < 0 else j + 2
                out.append('\n' * src.count('\n', i, end))
                i = end
                continue
            # Raw string: r'''...''', r"""...""", r'...', r"..."
            if c == 'r' and i + 1 < n and src[i + 1] in ("'", '"'):
                i = walk_string(i + 1, raw_str=True)
                continue
            # Normal string: '''...''', """...""", '...', "..."
            if c in ("'", '"'):
                i = walk_string(i, raw_str=False)
                continue
            if c == '(':
                paren += 1
                out.append(c)
            elif c == ')':
                paren -= 1
                out.append(c)
            elif c == '{':
                brace += 1
                brace_depth += 1
                out.append(c)
            elif c == '}':
                if stop_on_brace and brace_depth == 0:
                    return i + 1
                brace -= 1
                brace_depth -= 1
                out.append(c)
            elif c == '[':
                bracket += 1
                out.append(c)
            elif c == ']':
                bracket -= 1
                out.append(c)
            else:
                out.append(c)
            i += 1
        return i

    def walk_string(i: int, raw_str: bool) -> int:
        qchar = src[i]
        triple = src[i:i + 3] == qchar * 3
        delim = qchar * 3 if triple else qchar
        out.append(qchar)
        i += len(delim)
        while i < n:
            if src.startswith(delim, i):
                out.append(qchar)
                return i + len(delim)
            c = src[i]
            if not raw_str and c == '\\' and i + 1 < n:
                if src[i + 1] == '\n':
                    out.append('\n')
                i += 2
                continue
            if not raw_str and c == '$' and i + 1 < n and src[i + 1] == '{':
                out.append(' ')
                i = walk_code(i + 2, stop_on_brace=True)
                out.append(' ')
                continue
            if c == '\n':
                out.append('\n')
            i += 1
        out.append(qchar)
        return n

    walk_code(0, stop_on_brace=False)
    return paren, brace, bracket, ''.join(out)


def dart_files(roots: list[str]) -> list[str]:
    out = []
    for root in roots:
        if not os.path.isdir(root):
            continue
        for base, _dirs, files in os.walk(root):
            for f in files:
                if f.endswith('.dart'):
                    out.append(os.path.join(base, f))
    return sorted(out)


def resolve(target: str, src_path: str) -> str | None:
    if target.startswith(f'package:{PACKAGE}/'):
        rel_p = target[len(f'package:{PACKAGE}/'):]
        return os.path.normpath(os.path.join(LIB, rel_p))
    if target.startswith('dart:') or target.startswith('package:'):
        return 'external'
    base = os.path.dirname(src_path)
    return os.path.normpath(os.path.join(base, target))


def filter_combinators(names: set[str], clause: str) -> set[str]:
    """Apply `as prefix`, `show ...`, `hide ...` clauses on an import/export directive."""
    # Prefixed imports (`import '...' as foo;`) never collide with unqualified names.
    if re.search(r'\bas\s+[A-Za-z_]\w*', clause):
        return set()
    m_show = re.search(r'\bshow\s+([A-Za-z0-9_,\s]+)', clause)
    if m_show:
        shown = {w.strip() for w in m_show.group(1).split(',') if w.strip()}
        names = names & shown
    m_hide = re.search(r'\bhide\s+([A-Za-z0-9_,\s]+)', clause)
    if m_hide:
        hidden = {w.strip() for w in m_hide.group(1).split(',') if w.strip()}
        names = names - hidden
    return names


def rel(path: str) -> str:
    return os.path.relpath(path, ROOT)


def main() -> int:
    verbose = '--verbose' in sys.argv
    problems: list[str] = []
    files = dart_files([LIB, TEST])
    raw: dict[str, str] = {}
    srcs: dict[str, str] = {}

    # 3. scan & check balanced delimiters first
    for path in files:
        text = open(path, encoding='utf-8').read()
        raw[path] = text
        paren, brace, bracket, stripped = scan_dart(text)
        srcs[path] = stripped
        if paren:
            problems.append(f'{rel(path)}: unbalanced parens ({paren:+d})')
        if brace:
            problems.append(f'{rel(path)}: unbalanced braces ({brace:+d})')
        if bracket:
            problems.append(f'{rel(path)}: unbalanced brackets ({bracket:+d})')

    # 1. imports / exports / parts resolve
    for path, text in srcs.items():
        for target, _clause in DIRECTIVE_IMPORT.findall(text):
            dest = resolve(target, path)
            if dest == 'external':
                continue
            if dest is None or not os.path.isfile(dest):
                problems.append(f'{rel(path)}: unresolved import {target}')
        for target, _clause in DIRECTIVE_EXPORT.findall(text):
            dest = resolve(target, path)
            if dest == 'external':
                continue
            if dest is None or not os.path.isfile(dest):
                problems.append(f'{rel(path)}: unresolved export {target}')
        for target in PART.findall(text):
            dest = resolve(target, path)
            if dest is None or not os.path.isfile(dest):
                problems.append(f'{rel(path)}: unresolved part {target}')

    # 2. per-file declarations, and collisions between a library and its direct imports
    declared: dict[str, dict[str, str]] = {}
    for path, text in srcs.items():
        d: dict[str, str] = {}
        for kind, name in DECL.findall(text):
            d.setdefault(name, kind)
        declared[path] = d

    def exported_public(path: str, seen: set[str] | None = None) -> set[str]:
        """Public declarations exposed when `path` is imported (own + parts + transitive `export`s)."""
        seen = seen or set()
        if path in seen or path not in srcs:
            return set()
        seen.add(path)
        names = {n for n in declared.get(path, {}) if not n.startswith('_')}
        for target in PART.findall(srcs[path]):
            dest = resolve(target, path)
            if dest not in (None, 'external') and dest in declared:
                names |= {n for n in declared[dest] if not n.startswith('_')}
        for target, clause in DIRECTIVE_EXPORT.findall(srcs[path]):
            dest = resolve(target, path)
            if dest not in (None, 'external'):
                sub = exported_public(dest, seen)
                names |= filter_combinators(sub, clause)
        return names

    for path in files:
        if PART_OF.search(srcs[path]):
            continue
        own = {n: k for n, k in declared.get(path, {}).items() if not n.startswith('_')}
        imported_names: set[str] = set()
        for target, clause in DIRECTIVE_IMPORT.findall(srcs[path]):
            dest = resolve(target, path)
            if dest not in (None, 'external') and dest != path:
                sub = exported_public(dest, {path})
                imported_names |= filter_combinators(sub, clause)
        for name in sorted(set(own) & imported_names):
            problems.append(f'{rel(path)}: {own[name]} {name} collides with an imported declaration')

    # 4. design-token references must exist in the declaring library
    token_owner = {
        'Nx2': 'lib/core/ui2/nx2_widgets.dart',
        'Luxe': 'lib/core/ui2/luxe.dart',
        'LuxeSpace': 'lib/core/ui2/luxe.dart',
        'LuxeRadius': 'lib/core/ui2/luxe.dart',
        'Nx2Space': 'lib/core/ui2/nx2_widgets.dart',
        'NxColors': 'lib/core/theme/nx_theme.dart',
        'NxSpace': 'lib/core/theme/nx_theme.dart',
        'NxRadius': 'lib/core/theme/nx_theme.dart',
        'NxMotion': 'lib/core/theme/nx_theme.dart',
        'NxThemeColors': 'lib/core/theme/nx_theme.dart',
    }
    for cls, owner_rel in token_owner.items():
        owner = os.path.join(ROOT, owner_rel)
        if not os.path.isfile(owner):
            problems.append(f'token owner missing: {owner_rel}')
            continue
        body = srcs[owner]
        members = set(re.findall(
            r'\bstatic\s+(?:const|final|Color|double|int|List<[^>]+>|TextStyle|LinearGradient|BoxDecoration)\s+([a-zA-Z_]\w*)',
            body,
        ))
        members |= set(re.findall(r'\bstatic\s+const\s+\w+\s+([a-zA-Z_]\w*)\s*=', body))
        members |= set(re.findall(r'\bstatic\s+[^;{=()]*?\b([a-zA-Z_]\w*)\s*[(<]', body))
        members |= set(re.findall(r'\bstatic\s+[^;{=]*?\bget\s+([a-zA-Z_]\w*)', body))
        # Named constructors (`const NxThemeColors.foo(...)` or `factory Cls.bar(...)`)
        members |= set(re.findall(r'\b%s\.([a-zA-Z_]\w*)\s*\(' % cls, body))
        for path, text in srcs.items():
            if os.path.abspath(path) == os.path.abspath(owner):
                continue
            for used in re.findall(r'\b%s\.([a-zA-Z_]\w*)' % cls, text):
                if used not in members and used not in ('values', 'name', 'index', 'toString'):
                    problems.append(f'{rel(path)}: {cls}.{used} is not declared in {owner_rel}')

    # 5. named-argument verification on shared Luxe / Nx2 components & helpers
    kit_owners = {
        'LuxeCard': 'lib/core/ui2/luxe.dart',
        'LuxeButton': 'lib/core/ui2/luxe.dart',
        'LuxeIconButton': 'lib/core/ui2/luxe.dart',
        'LuxeSection': 'lib/core/ui2/luxe.dart',
        'LuxeStat': 'lib/core/ui2/luxe.dart',
        'LuxeListRow': 'lib/core/ui2/luxe.dart',
        'LuxeDivider': 'lib/core/ui2/luxe.dart',
        'LuxeEmpty': 'lib/core/ui2/luxe.dart',
        'LuxeLoading': 'lib/core/ui2/luxe.dart',
        'LuxeHeader': 'lib/core/ui2/luxe.dart',
        'showLuxeDialog': 'lib/core/ui2/luxe.dart',
        'showLuxeConfirm': 'lib/core/ui2/luxe.dart',
        'showLuxePrompt': 'lib/core/ui2/luxe.dart',
        'showLuxeSheet': 'lib/core/ui2/luxe.dart',
        'luxeToast': 'lib/core/ui2/luxe.dart',
        'Nx2SectionHeader': 'lib/core/ui2/nx2_widgets.dart',
        'Nx2Panel': 'lib/core/ui2/nx2_widgets.dart',
        'Nx2Button': 'lib/core/ui2/nx2_widgets.dart',
    }

    def top_level_named_args(arg_str: str) -> list[str]:
        depth_p = depth_b = depth_k = 0
        out_names: list[str] = []
        seg_start = 0
        for idx, ch in enumerate(arg_str + ','):
            if ch == '(':
                depth_p += 1
            elif ch == ')':
                depth_p = max(0, depth_p - 1)
            elif ch == '{':
                depth_b += 1
            elif ch == '}':
                depth_b = max(0, depth_b - 1)
            elif ch == '[':
                depth_k += 1
            elif ch == ']':
                depth_k = max(0, depth_k - 1)
            elif ch == ',' and depth_p == 0 and depth_b == 0 and depth_k == 0:
                seg = arg_str[seg_start:idx].strip()
                seg_start = idx + 1
                m_arg = re.match(r'^([A-Za-z_]\w*)\s*:', seg)
                if m_arg:
                    out_names.append(m_arg.group(1))
        return out_names

    def balanced_parens_slice(s: str, open_idx: int) -> str | None:
        depth = 0
        for idx in range(open_idx, len(s)):
            if s[idx] == '(':
                depth += 1
            elif s[idx] == ')':
                depth -= 1
                if depth == 0:
                    return s[open_idx + 1:idx]
        return None

    kit_params: dict[str, set[str]] = {}
    for sym, owner_rel in kit_owners.items():
        owner_body = srcs[os.path.join(ROOT, owner_rel)]
        # Match constructor `const Sym({...})` or function `sym<...>(..., {...})`
        m_sig = re.search(r'\b%s\s*(?:<[^>]*>)?\s*\(' % sym, owner_body)
        if not m_sig:
            problems.append(f'kit signature missing: {sym} in {owner_rel}')
            continue
        sig = balanced_parens_slice(owner_body, m_sig.end() - 1) or ''
        m_named = re.search(r'\{(.*)\}', sig, flags=re.S)
        params: set[str] = set()
        if m_named:
            for chunk in m_named.group(1).split(','):
                chunk = chunk.split('=')[0].strip()
                m_p = re.search(r'(?:this\.|super\.)?([A-Za-z_]\w*)\s*$', chunk)
                if m_p:
                    params.add(m_p.group(1))
        kit_params[sym] = params

    for path, text in srcs.items():
        for sym, allowed in kit_params.items():
            for m_call in re.finditer(r'\b%s\s*(?:<[^;{}()]*>)?\s*\(' % sym, text):
                # Skip declaration sites (`class Sym`, `const Sym({`, `Future<...> sym`)
                prefix = text[max(0, m_call.start() - 30):m_call.start()]
                if re.search(r'(?:const\s+$|Future<[^>]*>\s+$|void\s+$)', prefix):
                    body_check = balanced_parens_slice(text, m_call.end() - 1) or ''
                    if '{' in body_check and ('this.' in body_check or 'required ' in body_check):
                        continue
                arg_body = balanced_parens_slice(text, m_call.end() - 1)
                if arg_body is None:
                    continue
                for arg_name in top_level_named_args(arg_body):
                    if arg_name not in allowed:
                        problems.append(f'{rel(path)}: {sym}(...) has no named parameter `{arg_name}`')

    # 6. online capacity parity between the registry files and the test table. The solo arcade games are
    # single-player (SoloDef, not GameInfo) and have no room bounds: the table's (1, 1) rows for them are the
    # test's own statement that they can never open a room, so both sides are compared after dropping them.
    reg_bounds: dict[str, tuple[int, int]] = {}
    for reg_rel in ('lib/games/game_registry.dart', 'lib/games/arcade_registry.dart'):
        reg_txt = raw[os.path.join(ROOT, reg_rel)]
        for block in reg_txt.split('GameInfo(')[1:]:
            m_id = re.search(r"id:\s*'([^']+)'", block)
            m_min = re.search(r'minPlayers:\s*(\d+)', block)
            m_max = re.search(r'maxPlayers:\s*(\d+)', block)
            if not (m_id and m_min and m_max):
                continue
            m_omin = re.search(r'onlineMin:\s*(\d+)', block)
            m_omax = re.search(r'onlineMax:\s*(\d+)', block)
            lo = int(m_omin.group(1)) if m_omin else int(m_min.group(1))
            hi = int(m_omax.group(1)) if m_omax else int(m_max.group(1))
            reg_bounds[m_id.group(1)] = (lo, hi)

    test_cap = raw[os.path.join(ROOT, 'test/worlds/room_capacity_test.dart')]
    test_bounds = {
        k: (int(a), int(b))
        for k, a, b in re.findall(r"'([a-z0-9_]+)':\s*\((\d+),\s*(\d+)\)", test_cap)
    }
    solo_only = {k for k, v in test_bounds.items() if v == (1, 1) and k not in reg_bounds}
    test_bounds = {k: v for k, v in test_bounds.items() if k not in solo_only}
    if reg_bounds != test_bounds:
        problems.append(f'capacity mismatch between registry ({reg_bounds}) and room_capacity_test ({test_bounds})')

    if problems:
        uniq = list(dict.fromkeys(problems))
        for p in uniq:
            print('ERROR', p)
        print(f'\n{len(uniq)} problem(s) in {len(files)} files')
        return 1
    print(f'ok: {len(files)} files (lib + test), imports resolve, delimiters balanced, tokens declared')
    if verbose:
        for path in files:
            print(' ', rel(path))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
