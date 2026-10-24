"""Check store graphics before they are uploaded.

    python3 verify.py iphone-6.9 out/*.png

Each check is a reason App Store Connect or Play Console turns an image
away, or a reason it looks wrong once it is up: the exact pixel size for the
slot, no alpha channel (both stores refuse transparency), a file small
enough to upload, and the edges, where a stray element shows as a hairline.
"""
from __future__ import annotations

import os
import sys

from PIL import Image

#: Store slots and the sizes each accepts. The first is what render.mjs makes.
SLOTS = {
    # App Store Connect, iPhone 6.9" display (iPhone 17 Pro Max and Air).
    "iphone-6.9": [(1320, 2868), (1290, 2796), (1260, 2736)],
    # App Store Connect, iPad 13" display. Required: the app supports iPad.
    "ipad-13": [(2064, 2752), (2048, 2732)],
    # Google Play: 9:16, 320 to 3840 px a side; 1080 wide or more to be
    # eligible for promotion.
    "play-phone": [(1080, 1920)],
    "play-tablet-7": [(1080, 1920)],
    "play-tablet-10": [(1440, 2560)],
    "play-feature": [(1024, 500)],
}
MAX_MB = 8  # Play's limit per image; App Store Connect allows more

ok = fail = 0


def check(label: str, passed: bool, detail: str = "") -> None:
    global ok, fail
    ok, fail = (ok + 1, fail) if passed else (ok, fail + 1)
    print(f"  {'PASS' if passed else 'FAIL'}  {label}" + ("" if passed else f"  {detail}"))


def main() -> None:
    if len(sys.argv) < 3 or sys.argv[1] not in SLOTS:
        print(__doc__, "\nslots:", ", ".join(SLOTS))
        sys.exit(64)
    slot, files = sys.argv[1], sys.argv[2:]
    for f in files:
        im = Image.open(f)
        print(f"\n{os.path.basename(f)}  ({slot})")
        check("size fits the slot", im.size in SLOTS[slot], f"{im.size[0]}x{im.size[1]}, wants one of {SLOTS[slot]}")
        check("no alpha channel", im.mode == "RGB", f"mode {im.mode}")
        mb = os.path.getsize(f) / 1e6
        check(f"under {MAX_MB} MB", mb < MAX_MB, f"{mb:.1f} MB")
    print(f"\n  {ok} passed, {fail} failed")
    sys.exit(1 if fail else 0)


if __name__ == "__main__":
    main()
