#!/usr/bin/env python3
"""Re-wrap the long single-line luxeToast(...) calls the codemod produced."""
import os, re

LIMIT = 118
CALL = re.compile(r'^(?P<ind>\s*)(?P<fn>luxeToast(?:State)?\()(?P<rest>.*)\);\s*$')


def split_args(s):
    """Split a comma-separated argument list at top level (quote/bracket aware)."""
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


wrapped = 0
for dirpath, _, files in os.walk('lib'):
    for fn in sorted(files):
        if not fn.endswith('.dart'):
            continue
        path = os.path.join(dirpath, fn)
        lines = open(path).read().split('\n')
        out, changed = [], False
        for line in lines:
            m = CALL.match(line)
            if m is None or len(line) <= LIMIT:
                out.append(line)
                continue
            ind, fnn, rest = m.group('ind'), m.group('fn'), m.group('rest')
            args = split_args(rest)
            if len(args) < 2:
                out.append(line)
                continue
            out.append('%s%s' % (ind, fnn))
            out.append(',\n'.join('%s    %s' % (ind, a) for a in args) + ',')
            out.append('%s);' % ind)
            changed = True
            wrapped += 1
        if changed:
            open(path, 'w').write('\n'.join(out))
print('re-wrapped %d calls' % wrapped)
