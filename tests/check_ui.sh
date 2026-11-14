#!/bin/bash
# --check-only every UI-owned script
cd /workspace/work/nexgodot
fail=0
for f in src/main.gd src/core/nav.gd src/ui/*.gd src/screens/{intro,home,team,play,shop,profile,settings,setup,daily,chest}.gd tests/ui_walk.gd; do
  [ -f "$f" ] || continue
  out=$(timeout 60 /workspace/tools/godot --headless --path /workspace/work/nexgodot --check-only --script res://$f 2>&1 | grep -E "SCRIPT ERROR|Parse Error|ERROR" | grep -v "theme.tres" | grep -v -E "Identifier not found: (Nav|Data|Store|Sfx|Supa|Voice)\b|Failed to load script")
  if [ -n "$out" ]; then echo "== $f"; echo "$out" | head -12; fail=1; fi
done
[ $fail = 0 ] && echo "ALL OK"
