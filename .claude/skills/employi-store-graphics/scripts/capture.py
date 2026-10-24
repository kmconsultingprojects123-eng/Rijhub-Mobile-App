"""Real Employi screens from the dedicated store simulators, without a tap.

The app's debug launch file (lib/app/dev_launch.dart) opens any screen in
any state: the route, the role, a signed-in demo account, an area, even an
Ask conversation already under way. So a capture is: write the file, launch,
wait, screenshot. Nothing moves the cursor or brings the Simulator forward,
and the user's own simulators are never touched.

    python3 capture.py install [iphone|ipad]     boot, 9:41 status bar, install the build
    python3 capture.py shot NAME '{"route": "/home", ...}' [wait] [iphone|ipad]
    python3 capture.py plan shots.json [iphone|ipad] [name ...]   every shot in the list
    python3 capture.py finish [iphone|ipad]      clear the status bar, uninstall, shut down

`"as": "client"` (or `"artisan"`) in a launch signs in as that demo account,
from demo.local.json (kept out of git).

The build is a debug simulator build against the demo server (its own
database and Paystack test keys), so demo accounts and bookings show and no
real person's data can:

    flutter build ios --simulator --debug \
        --dart-define=API_BASE_URL=https://demo---rijhub-api-u64o6bn7gq-nw.a.run.app

Shots land in ~/Downloads/employi-store-screens/<device>/ (OUT= to change).
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

#: One simulator per store size, made for this and nothing else.
DEVICES = {
    "iphone": ("Employi Store iPhone 6.9", "iPhone-17-Pro-Max"),  # 1320x2868
    "ipad": ("Employi Store iPad 13", "iPad-Pro-13-inch-M5-12GB"),  # 2064x2752
}
BUNDLE = "com.rijhub.app"
APP = Path.home() / "Desktop/projects/flutter/Rijhub-Mobile-App/build/ios/iphonesimulator/Runner.app"
OUT = Path(os.environ.get("OUT", Path.home() / "Downloads/employi-store-screens"))


def simctl(*args: str, check: bool = True) -> str:
    r = subprocess.run(["xcrun", "simctl", *args], capture_output=True, text=True)
    if check and r.returncode != 0:
        raise RuntimeError(f"simctl {' '.join(args)}: {r.stderr.strip()}")
    return r.stdout.strip()


def udid(device: str) -> str:
    """The store simulator's id, made on first use."""
    name, kind = DEVICES[device]
    found = json.loads(simctl("list", "devices", "-j"))["devices"]
    for runtime in found.values():
        for d in runtime:
            if d["name"] == name and d.get("isAvailable", True):
                return d["udid"]
    return simctl("create", name, f"com.apple.CoreSimulator.SimDeviceType.{kind}")


def boot(u: str) -> None:
    if f"{u}) (Booted)" not in simctl("list", "devices"):
        simctl("boot", u)
        simctl("bootstatus", u, "-b")
    # The status bar Apple's own screenshots show: 9:41, full signal and
    # battery. Without it every capture shows the time it was taken.
    simctl("status_bar", u, "override", "--time", "9:41", "--dataNetwork", "wifi",
           "--wifiMode", "active", "--wifiBars", "3", "--cellularMode", "active",
           "--cellularBars", "4", "--batteryState", "discharging", "--batteryLevel", "100")


def install(device: str) -> None:
    u = udid(device)
    boot(u)
    simctl("install", u, str(APP))


#: The demo accounts' sign-in (Firebase test numbers): kept out of git,
#: because a test number signs in anywhere the app runs.
DEMO = Path(__file__).resolve().parent.parent / "demo.local.json"


def signed_in(options: dict) -> dict:
    """`"as": "client"` or `"artisan"` signs in as that demo account."""
    who = options.pop("as", None)
    return {**json.loads(DEMO.read_text())[who], **options} if who else options


def shot(device: str, name: str, options: dict, wait: float) -> Path:
    options = signed_in(dict(options))
    u = udid(device)
    boot(u)
    simctl("terminate", u, BUNDLE, check=False)
    docs = Path(simctl("get_app_container", u, BUNDLE, "data")) / "Documents"
    docs.mkdir(parents=True, exist_ok=True)
    (docs / "dev_launch.json").write_text(json.dumps(options))
    simctl("launch", u, BUNDLE)
    time.sleep(wait)
    out = OUT / device
    out.mkdir(parents=True, exist_ok=True)
    path = out / f"{name}.png"
    simctl("io", u, "screenshot", "--type=png", str(path))
    return path


def finish(device: str) -> None:
    u = udid(device)
    simctl("status_bar", u, "clear", check=False)
    simctl("terminate", u, BUNDLE, check=False)
    simctl("uninstall", u, BUNDLE, check=False)
    simctl("shutdown", u, check=False)


if __name__ == "__main__":
    a = sys.argv[1:]
    cmd = a[0] if a else ""
    if cmd == "install":
        install(a[1] if len(a) > 1 else "iphone")
        print("installed")
    elif cmd == "shot":
        wait = float(a[3]) if len(a) > 3 else 12
        print(shot(a[4] if len(a) > 4 else "iphone", a[1], json.loads(a[2]), wait))
    elif cmd == "plan":
        # python3 capture.py plan shots.json [iphone|ipad] [name ...]
        device = a[2] if len(a) > 2 else "iphone"
        only = set(a[3:])
        for row in json.loads(Path(a[1]).read_text()):
            if not only or row["name"] in only:
                print(shot(device, row["name"], row["launch"], row.get("wait", 18)))
    elif cmd == "finish":
        finish(a[1] if len(a) > 1 else "iphone")
        print("status bar cleared, app removed, simulator shut down")
    else:
        print(__doc__)
        sys.exit(64)
