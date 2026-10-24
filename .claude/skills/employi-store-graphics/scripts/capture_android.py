"""Real Employi screens from the project's own Android emulators.

The same debug launch file as on iOS (lib/app/dev_launch.dart), copied into
the app's files with run-as (debug builds allow it), so nothing is tapped.
SystemUI demo mode gives the clean status bar the stores expect: 9:41, full
signal and battery, no notification icons.

    python3 capture_android.py install [phone|tablet]
    python3 capture_android.py plan ../shots.json [phone|tablet] [name ...]
    python3 capture_android.py finish [phone|tablet]

`tablet` is the same emulator at a tablet's size and density (wm size
1600x2560, density 320), so the app lays out as it does on a 10-inch
tablet; `finish` puts the emulator back. Shots land in
~/Downloads/employi-store-screens/<phone|tablet>/.

Only ever drives emulator-5580 ("RijHub_Client"), the AVD made for this.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

SERIAL = "emulator-5580"
PKG = "com.rijhub.app"
APK = Path.home() / "Desktop/projects/flutter/Rijhub-Mobile-App/build/app/outputs/flutter-apk/app-debug.apk"
OUT = Path(os.environ.get("OUT", Path.home() / "Downloads/employi-store-screens"))
DEMO = Path(__file__).resolve().parent.parent / "demo.local.json"
SIZES = {"phone": None, "tablet": ("1600x2560", "320")}


def adb(*args: str, check: bool = True, binary: bool = False):
    r = subprocess.run(["adb", "-s", SERIAL, *args], capture_output=True, text=not binary)
    if check and r.returncode != 0:
        raise RuntimeError(f"adb {' '.join(args)}: {r.stderr}")
    return r.stdout


def demo_mode() -> None:
    adb("shell", "settings", "put", "global", "sysui_demo_allowed", "1")
    for extras in (["-e", "command", "enter"],
                   ["-e", "command", "clock", "-e", "hhmm", "0941"],
                   ["-e", "command", "battery", "-e", "level", "100", "-e", "plugged", "false"],
                   ["-e", "command", "network", "-e", "wifi", "show", "-e", "level", "4", "-e", "fully", "true"],
                   ["-e", "command", "network", "-e", "mobile", "hide"],
                   ["-e", "command", "notifications", "-e", "visible", "false"]):
        adb("shell", "am", "broadcast", "-a", "com.android.systemui.demo", *extras)


def size(kind: str) -> None:
    if SIZES[kind]:
        w, d = SIZES[kind]
        adb("shell", "wm", "size", w)
        adb("shell", "wm", "density", d)
    else:
        adb("shell", "wm", "size", "reset")
        adb("shell", "wm", "density", "reset")


def install(kind: str) -> None:
    adb("install", "-r", str(APK))
    size(kind)
    demo_mode()


def signed_in(options: dict) -> dict:
    who = options.pop("as", None)
    return {**json.loads(DEMO.read_text())[who], **options} if who else options


def shot(kind: str, name: str, options: dict, wait: float) -> Path:
    options = signed_in(dict(options))
    adb("shell", "am", "force-stop", PKG)
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        json.dump(options, f)
    adb("push", f.name, "/data/local/tmp/dev_launch.json")
    os.unlink(f.name)
    # One string: adb joins its arguments for the device's shell, which would
    # otherwise split the compound command.
    adb("shell", f"run-as {PKG} sh -c 'mkdir -p app_flutter && cp /data/local/tmp/dev_launch.json app_flutter/dev_launch.json'")
    adb("shell", "am", "start", "-W", "-n", f"{PKG}/.MainActivity")
    time.sleep(wait)
    demo_mode()  # the clock again, in case the app's launch redrew the bar
    time.sleep(1)
    out = OUT / kind
    out.mkdir(parents=True, exist_ok=True)
    path = out / f"{name}.png"
    path.write_bytes(adb("exec-out", "screencap", "-p", binary=True))
    return path


def finish(kind: str) -> None:
    adb("shell", "am", "broadcast", "-a", "com.android.systemui.demo", "-e", "command", "exit", check=False)
    adb("shell", "wm", "size", "reset", check=False)
    adb("shell", "wm", "density", "reset", check=False)
    adb("shell", "run-as", PKG, "rm", "-f", "app_flutter/dev_launch.json", check=False)


if __name__ == "__main__":
    a = sys.argv[1:]
    cmd = a[0] if a else ""
    if cmd == "install":
        install(a[1] if len(a) > 1 else "phone")
        print("installed")
    elif cmd == "plan":
        kind = a[2] if len(a) > 2 else "phone"
        size(kind)
        only = set(a[3:])
        for row in json.loads(Path(a[1]).read_text()):
            if not only or row["name"] in only:
                print(shot(kind, row["name"], row["launch"], row.get("wait", 18) + 4), flush=True)
    elif cmd == "finish":
        finish(a[1] if len(a) > 1 else "phone")
        print("emulator restored")
    else:
        print(__doc__)
        sys.exit(64)
