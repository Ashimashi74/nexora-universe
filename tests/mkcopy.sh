#!/bin/bash
# Build a throwaway copy of the project with stub autoloads where the real files are missing.
# assets/ is symlinked, .godot import cache copied once. Usage: tests/mkcopy.sh [/tmp/uitest]
set -e
SRC=/workspace/work/nexgodot
DST=${1:-/tmp/uitest}
mkdir -p $DST
rm -rf $DST/src $DST/tests $DST/addons $DST/android
cp -a $SRC/src $SRC/tests $SRC/project.godot $DST/
[ -d $SRC/addons ] && cp -a $SRC/addons $DST/ || true
[ -e $DST/assets ] || ln -s $SRC/assets $DST/assets
if [ ! -d $DST/.godot ] && [ -d $SRC/.godot ]; then cp -a $SRC/.godot $DST/.godot; fi
for pair in core/data.gd:data.gd core/store.gd:store.gd core/sfx.gd:sfx.gd net/supa.gd:supa.gd net/voice.gd:voice.gd; do
  f=${pair%%:*}; s=${pair##*:}
  if [ ! -f $SRC/src/$f ]; then mkdir -p $(dirname $DST/src/$f); cp $SRC/tests/stubs/$s $DST/src/$f; echo "stub: $f"; fi
done
