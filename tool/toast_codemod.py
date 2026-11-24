#!/usr/bin/env python3
"""One-shot codemod: raw Material SnackBars -> the app's own luxeToast / luxeToastState.

Only converts call sites it fully understands (content: Text(<expr>), optional action /
duration). Anything richer is reported and left for a human, so the codemod can never
silently drop a widget.
"""
import os, re

ROOT = 'lib'
SKIP = {os.path.join('lib', 'core', 'ui2', 'luxe.dart')}
SHOW = 'showSnackBar('


def scan(s, i):
    """i points at an opening bracket; return the index just past its match."""
    close = {'(': ')', '[': ']', '{': '}'}[s[i]]
    depth = 0
    while i < len(s):
        c = s[i]
        if c in '\'"':
            q = c
            i += 1
            while i < len(s):
                if s[i] == '\\':
                    i += 2
                    continue
                if s[i] == q:
                    break
                i += 1
            i += 1
            continue
        if c == '/' and s[i + 1:i + 2] == '/':
            i = s.index('\n', i)
            continue
        if c == '/' and s[i + 1:i + 2] == '*':
            i = s.index('*/', i) + 2
            continue
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    raise ValueError('unbalanced bracket at %d' % i)


def split_args(s):
    out, depth, start, i = [], 0, 0, 0
    while i < len(s):
        c = s[i]
        if c in '\'"':
            q = c
            i += 1
            while i < len(s):
                if s[i] == '\\':
                    i += 2
                    continue
                if s[i] == q:
                    break
                i += 1
            i += 1
            continue
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
        elif c == ',' and depth == 0:
            out.append(s[start:i])
            start = i + 1
        i += 1
    out.append(s[start:])
    return [o.strip() for o in out if o.strip()]


def named(args):
    d, pos = {}, []
    for a in args:
        m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(.*)$', a, re.S)
        if m:
            d[m.group(1)] = m.group(2).strip()
        else:
            pos.append(a)
    if pos:
        d['_pos'] = pos
    return d


def unwrap_ctor(expr, ctor):
    """`Ctor(<args>)` -> the named/positional arg dict, else None."""
    e = expr.strip().rstrip(',').strip()
    if not (e.startswith(ctor + '(') and e.endswith(')')):
        return None
    inner = e[len(ctor) + 1:-1]
    end = scan('(' + inner + ')', 0)
    if end != len(inner) + 2:      # trailing junk after the ctor
        return None
    return named(split_args(inner))


def unwrap_text(expr):
    d = unwrap_ctor(expr, 'Text')
    if d is None or '_pos' not in d or len(d['_pos']) != 1:
        return None
    first = d['_pos'][0]
    if 'TextSpan' in first:
        return None
    return first.strip()


RECV_CTX = re.compile(
    r'ScaffoldMessenger\.(?:of|maybeOf)\((?P<ctx>[A-Za-z_][\w\.]*)\)\s*\??\s*'
    r'(?:\.\.\s*hideCurrentSnackBar\(\)\s*)?\.\.?\s*$')
RECV_VAR = re.compile(
    r'(?<![\w.])(?P<v>[A-Za-z_]\w*)\s*(?:\.\.\s*hideCurrentSnackBar\(\)\s*)?\.\.?\s*$')


def receiver(pre):
    """-> ('ctx', context_expr, start_offset_in_pre) | ('var', name, start) | None"""
    m = RECV_CTX.search(pre)
    if m:
        return ('ctx', m.group('ctx'), m.start())
    m = RECV_VAR.search(pre)
    if m:
        return ('var', m.group('v'), m.start())
    return None


def squash(s):
    return re.sub(r'\s+', ' ', s).strip()


converted, report, manual = 0, [], []

for dirpath, _, files in os.walk(ROOT):
    for fn in sorted(files):
        if not fn.endswith('.dart'):
            continue
        path = os.path.join(dirpath, fn)
        if path in SKIP:
            continue
        src = open(path).read()
        if SHOW not in src:
            continue
        out, pos, changed = [], 0, False
        while True:
            idx = src.find(SHOW, pos)
            if idx < 0:
                out.append(src[pos:])
                break
            end = scan(src, idx + len(SHOW) - 1)
            pre = src[max(0, idx - 300):idx]
            inner = src[idx + len(SHOW):end - 1].strip()

            def bail(why):
                manual.append((path, idx, why))
                out.append(src[pos:end])
                return end

            bar = unwrap_ctor(inner, 'SnackBar')
            if bar is None:
                pos = bail('not a literal SnackBar(...)')
                continue
            msg = unwrap_text(bar['content']) if 'content' in bar else None
            if msg is None:
                pos = bail('rich content (not a plain Text): ' + squash(bar.get('content', '?'))[:90])
                continue
            r = receiver(pre)
            if r is None:
                pos = bail('unrecognised receiver: ' + squash(pre)[-70:])
                continue
            kind, name, rstart = r

            parts = [msg]
            if 'action' in bar:
                act = unwrap_ctor(bar['action'], 'SnackBarAction')
                if act is None or 'label' not in act or 'onPressed' not in act:
                    pos = bail('unsupported action: ' + squash(bar['action'])[:90])
                    continue
                parts += ['actionLabel: %s' % act['label'], 'onAction: %s' % act['onPressed']]
            if 'duration' in bar:
                parts.append('duration: %s' % bar['duration'])

            call = ('luxeToast(%s, %s)' % (name, ', '.join(parts)) if kind == 'ctx'
                    else 'luxeToastState(%s, %s)' % (name, ', '.join(parts)))
            # absolute index where the receiver expression starts (never before what we
            # already emitted, or a nearby previous conversion would be overwritten)
            abs_start = max(max(0, idx - 300) + rstart, pos)
            out.append(src[pos:abs_start])
            out.append(call)
            pos = end
            changed = True
            converted += 1
            report.append('%-58s %s' % (path, squash(call)[:96]))
        if changed:
            new = ''.join(out)
            if 'ui2/luxe.dart' not in new:
                rel = os.path.relpath('lib/core/ui2/luxe.dart', os.path.dirname(path))
                lines = new.split('\n')
                last = max(i for i, l in enumerate(lines) if l.startswith('import '))
                lines.insert(last + 1, "import '%s';" % rel)
                new = '\n'.join(lines)
            open(path, 'w').write(new)

print('CONVERTED %d call sites' % converted)
for r in report:
    print('  ' + r)
print('\nLEFT FOR MANUAL REVIEW: %d' % len(manual))
for p, i, why in manual:
    print('  %s\n      %s' % (p, why))
