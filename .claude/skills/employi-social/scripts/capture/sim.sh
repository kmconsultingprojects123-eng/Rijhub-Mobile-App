#!/bin/zsh
# Capture real screens from the Employi app on the iOS Simulator.
#
#   sim.sh start               boot the dedicated simulator headless, 9:41 status bar, launch the app
#   sim.sh go 'JSON'           open a screen with no taps: writes Documents/dev_launch.json, relaunches
#   sim.sh shot NAME           save NAME.png (full resolution) into $OUT
#   sim.sh tap X Y             tap at device points (open a shot to read coordinates:
#   sim.sh swipe X1 Y1 X2 Y2     pixels / 3 on a 3x iPhone). Shows the Simulator window, moves your cursor
#   sim.sh finish              delete dev_launch.json, clear the status bar, shut the simulator down
#
# SIM names the simulator: default "RijHub Redesign", the project's own
# iPhone 17 Pro with a debug build installed. Never the one you work on.
# OUT defaults to ~/Downloads/employi-screens. `go` needs a debug build: the
# app reads dev_launch.json (lib/app/dev_launch.dart) in debug builds only.
# Taps take the cursor for a moment and put it back; don't type while one runs.
set -e
BUNDLE=com.rijhub.app
SIM=${SIM:-RijHub Redesign}
OUT=${OUT:-$HOME/Downloads/employi-screens}
HERE=${0:A:h}
BIN=${TMPDIR:-/tmp}/employi-social-simtap

udid() {
  # The dedicated simulator, found by name, never "whichever has the app":
  # that could be the simulator you are working on.
  local u
  u=$(xcrun simctl list devices -j | python3 -c "
import json, sys
for devs in json.load(sys.stdin)['devices'].values():
    for d in devs:
        if d['name'] == sys.argv[1] and d.get('isAvailable', True):
            print(d['udid']); sys.exit()" "$SIM")
  [[ -n $u ]] || { echo "no simulator named \"$SIM\": create it (xcrun simctl create \"$SIM\" \"iPhone 17 Pro\") and install a debug build on it" >&2; exit 1; }
  echo $u
}
U=$(udid)

drive() {
  [[ -x $BIN && $BIN -nt $HERE/simtap.swift ]] || swiftc -O "$HERE/simtap.swift" -o "$BIN"
  # Taps land wherever the screen point is, so show this device's window and
  # raise it by name. "window 1" can be another simulator's.
  open -a Simulator --args -CurrentDeviceUDID $U
  osascript -e 'tell application "Simulator" to activate'
  local F="" i
  for i in {1..20}; do                 # the window can take a moment to appear
    F=$(osascript -e "tell application \"System Events\" to tell process \"Simulator\"
      set w to first window whose name contains \"$SIM\"
      perform action \"AXRaise\" of w
      get {position, size} of (first UI element of w whose role is \"AXGroup\")
    end tell" 2>/dev/null | tr -d ' ')
    [[ $F == *,*,*,* ]] && break
    sleep 0.5
  done
  [[ $F == *,*,*,* ]] || { echo "no Simulator window for \"$SIM\": nothing sent" >&2; exit 2; }
  IFS=, read FX FY FW FH <<< "$F"
  # device size in points, from a capture's pixel size (3x iPhones, 2x otherwise)
  local tmp=${TMPDIR:-/tmp}/employi-social-probe.png
  xcrun simctl io $U screenshot "$tmp" >/dev/null 2>&1
  read DW DH <<< $(python3 -c "
from PIL import Image; w, h = Image.open('$tmp').size; s = 3 if w >= 1000 else 2; print(w / s, h / s)")
  FX=$FX FY=$FY FW=$FW FH=$FH DW=$DW DH=$DH "$BIN" "$@"
}

case $1 in
  start)
    xcrun simctl boot $U 2>/dev/null || true
    xcrun simctl bootstatus $U -b >/dev/null
    xcrun simctl status_bar $U override --time 9:41 --dataNetwork wifi --wifiMode active \
      --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState discharging --batteryLevel 100
    xcrun simctl launch $U $BUNDLE >/dev/null
    echo "started $SIM ($U), headless; shots go to $OUT" ;;
  go)
    [[ -n $2 ]] || { echo "usage: sim.sh go '{\"route\": \"/home\", \"role\": \"client\"}'" >&2; exit 64; }
    python3 -c "import json, sys; json.loads(sys.argv[1])" "$2" 2>/dev/null || { echo "not valid JSON: $2" >&2; exit 65; }
    DATA=$(xcrun simctl get_app_container $U $BUNDLE data)
    mkdir -p "$DATA/Documents"
    print -r -- "$2" > "$DATA/Documents/dev_launch.json"
    xcrun simctl terminate $U $BUNDLE 2>/dev/null || true
    xcrun simctl launch $U $BUNDLE >/dev/null
    sleep ${WAIT:-4}
    echo "opened $2 (take the shot once it has settled)" ;;
  shot)
    mkdir -p "$OUT"
    xcrun simctl io $U screenshot "$OUT/$2.png" >/dev/null 2>&1
    echo "$OUT/$2.png" ;;
  tap|swipe) drive "$@" ;;
  finish)
    DATA=$(xcrun simctl get_app_container $U $BUNDLE data 2>/dev/null) && rm -f "$DATA/Documents/dev_launch.json"
    xcrun simctl status_bar $U clear
    xcrun simctl shutdown $U 2>/dev/null || true
    echo "dev_launch.json removed, status bar restored, $SIM shut down" ;;
  *) sed -n '2,15p' "$0"; exit 64 ;;
esac
