#!/bin/bash
# Rendered UI walk on Xvfb :99 (start it with tests/xvfb.sh). Usage: tests/render.sh 1080x1920 [safe] [outdir]
RES=${1:-1080x1920}; SAFE=$2; OUT=${3:-/workspace/work/nexgodot/shots}
cd /workspace/work/nexgodot
mkdir -p $OUT; touch $OUT/.gdignore
LOG=/tmp/render_$RES.log
env DISPLAY=:99 NX_WALK=1 NX_SHOTS=$OUT ${SAFE:+NX_SAFE=$SAFE} nohup timeout 240 /workspace/tools/godot --rendering-driver opengl3 --resolution $RES --path . res://src/main.tscn > $LOG 2>&1 &
echo "started -> $LOG"
