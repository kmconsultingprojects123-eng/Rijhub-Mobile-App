#!/bin/zsh
# Real screens and screen recordings from the Employi app, on a temporary
# iOS Simulator cloned from the project's dedicated one, so no simulator you
# work on (or its signed-in accounts) is ever touched.
#
#   sim.sh start                   clone the dedicated simulator's device and app into a temporary one, boot it headless, 9:41, launch
#   sim.sh go 'JSON'               open a screen with no taps: writes Documents/dev_launch.json, relaunches
#   sim.sh shot NAME               full-resolution screenshot -> $OUT/NAME.png
#   sim.sh record NAME             start a screen recording -> $OUT/NAME.mp4
#   sim.sh stop                    nudge the screen, then stop the recording (see below)
#   sim.sh tap X Y                 device points: a capture's pixels / 3 on a 3x iPhone
#   sim.sh swipe X1 Y1 X2 Y2       slow drag held before release: scrolls exactly that far
#   sim.sh flick X1 Y1 X2 Y2 [MS]  quick drag released moving: scrolls on with momentum, like a thumb
#   sim.sh finish                  delete the temporary simulator, quit Simulator if nothing else runs
#
# SIM names the dedicated simulator the app is copied from: default "RijHub
# Redesign", which has a debug build installed (`go` needs one). OUT
# defaults to ~/Downloads/employi-reel-captures. tap, swipe, flick and stop
# show the Simulator window and take the cursor for a moment, then put it
# back; don't type while one runs.
#
# The recorder only writes a frame when the screen changes, so a recording
# stopped on a still screen loses its last moments. `stop` makes a 40-point
# scroll first; don't use the frames after it.
set -e
BUNDLE=com.rijhub.app
SIM=${SIM:-RijHub Redesign}
NAME="Employi reel (temporary)"
OUT=${OUT:-$HOME/Downloads/employi-reel-captures}
HERE=${0:A:h}
STATE=${TMPDIR:-/tmp}/employi-reel-sim
BIN=${TMPDIR:-/tmp}/employi-reel-simtap

temp_udid() { [[ -f $STATE ]] && cat $STATE || { echo "no temporary simulator: run sim.sh start" >&2; exit 1; } }

source_udid() {
  # The dedicated simulator, by name: never "whichever has the app".
  local u
  u=$(xcrun simctl list devices -j | python3 -c "
import json, sys
for devs in json.load(sys.stdin)['devices'].values():
    for d in devs:
        if d['name'] == sys.argv[1] and d.get('isAvailable', True):
            print(d['udid']); sys.exit()" "$SIM")
  [[ -n $u ]] || { echo "no simulator named \"$SIM\": create it and install a debug build on it first" >&2; exit 1; }
  echo $u
}

source_app() {
  # the app bundle on the dedicated simulator, read from disk: it isn't booted
  for p in ~/Library/Developer/CoreSimulator/Devices/$1/data/Containers/Bundle/Application/*/*.app/Info.plist(N); do
    if [[ $(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$p" 2>/dev/null) == $BUNDLE ]]; then
      echo "${p:h}"; return
    fi
  done
  echo "\"$SIM\" doesn't have $BUNDLE installed: build and run the app on it first" >&2; exit 1
}

drive() {
  [[ -x $BIN && $BIN -nt $HERE/simtap.swift ]] || swiftc -O "$HERE/simtap.swift" -o "$BIN"
  # Stop here without a temporary simulator: opening Simulator with no device
  # named would bring up (and boot) whichever one it used last.
  local U
  U=$(temp_udid) && [[ -n $U ]] || return 1
  # Taps land wherever the screen point is, so show this device's window and
  # raise it by name. "window 1" can be another simulator's.
  open -a Simulator --args -CurrentDeviceUDID $U
  osascript -e 'tell application "Simulator" to activate'
  local F="" i
  for i in {1..20}; do                 # the window can take a moment to appear
    F=$(osascript -e "tell application \"System Events\" to tell process \"Simulator\"
      set w to first window whose name contains \"$NAME\"
      perform action \"AXRaise\" of w
      get {position, size} of (first UI element of w whose role is \"AXGroup\")
    end tell" 2>/dev/null | tr -d ' ')
    [[ $F == *,*,*,* ]] && break
    sleep 0.5
  done
  [[ $F == *,*,*,* ]] || { echo "no Simulator window for \"$NAME\": nothing sent" >&2; exit 2; }
  IFS=, read FX FY FW FH <<< "$F"
  local tmp=${TMPDIR:-/tmp}/employi-reel-probe.png
  xcrun simctl io $U screenshot "$tmp" >/dev/null 2>&1
  read DW DH <<< $(python3 -c "
from PIL import Image; w, h = Image.open('$tmp').size; s = 3 if w >= 1000 else 2; print(w / s, h / s)")
  FX=$FX FY=$FY FW=$FW FH=$FH DW=$DW DH=$DH "$BIN" "$@"
}

case $1 in
  start)
    SRC=$(source_udid)
    APP=$(source_app $SRC)
    read RT DT <<< $(xcrun simctl list devices -j | python3 -c "
import json, sys
for rt, devs in json.load(sys.stdin)['devices'].items():
    for d in devs:
        if d['udid'] == '$SRC': print(rt, d['deviceTypeIdentifier'])")
    U=$(xcrun simctl create "$NAME" "$DT" "$RT")
    echo $U > $STATE
    xcrun simctl boot $U
    xcrun simctl bootstatus $U -b >/dev/null
    xcrun simctl install $U "$APP"
    xcrun simctl status_bar $U override --time 9:41 --dataNetwork wifi --wifiMode active \
      --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState discharging --batteryLevel 100
    xcrun simctl launch $U $BUNDLE >/dev/null
    echo "temporary simulator $U running the app headless; captures go to $OUT" ;;
  go)
    [[ -n $2 ]] || { echo "usage: sim.sh go '{\"route\": \"/home\", \"role\": \"client\"}'" >&2; exit 64; }
    python3 -c "import json, sys; json.loads(sys.argv[1])" "$2" 2>/dev/null || { echo "not valid JSON: $2" >&2; exit 65; }
    U=$(temp_udid)
    DATA=$(xcrun simctl get_app_container $U $BUNDLE data)
    mkdir -p "$DATA/Documents"
    print -r -- "$2" > "$DATA/Documents/dev_launch.json"
    xcrun simctl terminate $U $BUNDLE 2>/dev/null || true
    xcrun simctl launch $U $BUNDLE >/dev/null
    sleep ${WAIT:-4}
    echo "opened $2 (record or shoot once it has settled)" ;;
  shot)
    mkdir -p "$OUT"
    xcrun simctl io $(temp_udid) screenshot "$OUT/$2.png" >/dev/null 2>&1
    echo "$OUT/$2.png" ;;
  record)
    mkdir -p "$OUT"
    xcrun simctl io $(temp_udid) recordVideo --codec=h264 --force "$OUT/$2.mp4" >/dev/null 2>&1 &
    echo $! > $STATE.rec; sleep 1.5
    echo "recording -> $OUT/$2.mp4 (sim.sh stop to end)" ;;
  stop)
    drive swipe 200 600 200 560 >/dev/null || true
    sleep 1
    PID=$(cat $STATE.rec); kill -INT $PID
    while kill -0 $PID 2>/dev/null; do sleep 0.2; done
    rm -f $STATE.rec; echo "recording stopped" ;;
  tap|swipe|flick) drive "$@" ;;
  finish)
    U=$(temp_udid)
    xcrun simctl shutdown $U 2>/dev/null || true
    xcrun simctl delete $U && rm -f $STATE
    [[ $(xcrun simctl list devices | grep -c Booted) == 0 ]] && osascript -e 'tell application "Simulator" to quit'
    echo "temporary simulator deleted" ;;
  *) sed -n '2,24p' "$0"; exit 64 ;;
esac
