#!/bin/bash
# Install + launch the APK on the running emulator, collect logcat + screenshots, fail on a crash.
# Phase 1: normal launch (splash -> intro -> tap -> menu). Phase 2: relaunch straight into a quick match
# vs the bot (--nx-start=quickmatch, read by src/main.gd) and let it play.
# usage: emu_test.sh <apk> <outdir>
set -u
APK="$1"; OUT="$2"; PKG=com.nexora.nx
mkdir -p "$OUT"
adb wait-for-device
{ adb shell getprop ro.build.version.sdk; adb shell getprop ro.product.cpu.abilist; } | tee "$OUT/device.txt"
adb logcat -c || true
echo "== install"
adb install -r "$APK" 2>&1 | tee "$OUT/install.txt"
if ! grep -q Success "$OUT/install.txt"; then echo "::error::adb install failed"; adb logcat -d > "$OUT/logcat_install.txt"; exit 1; fi
adb shell dumpsys package $PKG | grep -E "versionCode|versionName|primaryCpuAbi|flags=" | tee "$OUT/package.txt"
ACT=$(adb shell cmd package resolve-activity --brief $PKG 2>/dev/null | tr -d '\r' | tail -n 1)
case "$ACT" in */*) ;; *) ACT="$PKG/com.godot.game.GodotApp";; esac
echo "launcher activity: $ACT"

shot() { adb exec-out screencap -p > "$OUT/$1.png" 2>/dev/null || true; }
alive() { adb shell pidof $PKG | tr -d '\r'; }
fail=0
check_log() {  # $1 = logcat file, $2 = phase name
  # only crashes of OUR process count (emulator system apps such as YouTube Music crash on their own)
  grep -A1 "FATAL EXCEPTION" "$1" | grep -q "Process: $PKG" && { echo "::error::[$2] FATAL EXCEPTION in $PKG"; fail=1; }
  grep -E "Fatal signal|>>> .* <<<" "$1" | grep -q "$PKG" && { echo "::error::[$2] native crash signal in $PKG"; fail=1; }
  grep -A1 "FATAL EXCEPTION" "$1" | grep "Process:" | grep -v "$PKG" | sed 's/^/[ignored foreign crash] /' || true
  grep -E -q "SCRIPT ERROR|Parse Error|USER ERROR" "$1" && { echo "::error::[$2] Godot script/user errors in logcat"; fail=1; }
  echo "================ [$2] filtered logcat ================"
  grep -E -i "godot|nexora|NX_|AndroidRuntime|FATAL|DEBUG +:|libc +:|SIGSEGV|SIGABRT|livekit|ActivityManager.*(nexora|Process)|SCRIPT ERROR|USER ERROR|Parse Error|OpenGL|GLES|vulkan|crash" "$1" | grep -v chatty | tail -n 400
}

SIZE=$(adb shell wm size | tr -d '\r' | grep -o '[0-9]*x[0-9]*' | tail -n 1); W=${SIZE%x*}; H=${SIZE#*x}
TX=$((W/2)); TY=$((H*84/100))   # the intro's "tap to enter" button sits at ~84% height
echo "screen ${W}x${H}, tap at ${TX},${TY}"
echo "== phase 1: normal launch"
adb shell am start -W -n "$ACT"
sleep 4;  shot p1_04s_splash
sleep 6;  shot p1_10s
P=$(alive); echo "pid@10s=$P"
adb shell input tap $TX $TY || true
sleep 5;  shot p1_15s_after_tap
adb shell input tap $TX $TY || true
sleep 10; shot p1_25s_menu
P=$(alive); echo "pid@25s=$P"
[ -z "$P" ] && { echo "::error::[launch] process died within 25 s"; fail=1; }
adb shell dumpsys activity activities | grep -E "ResumedActivity" | tee "$OUT/p1_activity.txt" || true
adb logcat -d -v threadtime > "$OUT/logcat_launch.txt"
adb logcat -d -b crash > "$OUT/logcat_crash_launch.txt" 2>/dev/null || true
check_log "$OUT/logcat_launch.txt" launch

echo "== phase 2: quick match"
adb shell am force-stop $PKG; sleep 2; adb logcat -c || true
adb shell am start -W -n "$ACT" --esa command_line_params --nx-start=quickmatch
sleep 12; shot p2_12s_match
sleep 10; shot p2_22s_match
P=$(alive); echo "pid@match22s=$P"
[ -z "$P" ] && { echo "::error::[match] process died during the quick match"; fail=1; }
adb logcat -d -v threadtime > "$OUT/logcat_match.txt"
adb logcat -d -b crash > "$OUT/logcat_crash_match.txt" 2>/dev/null || true
grep -q "NX_TEST quick match started" "$OUT/logcat_match.txt" && echo "match hook reached" || echo "::warning::NX_TEST marker not found (cmdline extra not delivered?)"
check_log "$OUT/logcat_match.txt" match
echo "result: fail=$fail"
exit $fail
