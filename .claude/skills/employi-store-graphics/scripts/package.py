"""Lays the rendered graphics, icons, text and builds out for upload.

    python3 package.py RENDERED_DIR DEST_DIR

RENDERED_DIR holds render.mjs's output (iphone-01.png ... feature-graphic.png);
DEST_DIR becomes one folder per store, each slot in its own folder with the
files named in upload order, every image checked by verify.py's rules.
"""
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
SKILL = HERE.parent
APP = Path.home() / "Desktop/projects/flutter/Rijhub-Mobile-App"

NAMES = ["01-say-whats-wrong", "02-id-checked-prices-up-front", "03-book-and-pay-safely",
         "04-follow-every-step", "05-chat-in-the-app", "06-for-artisans"]
SLOTS = [  # (render prefix, store folder, slot folder, verify slot)
    ("iphone", "App Store", "Screenshots - iPhone 6.9 inch", "iphone-6.9"),
    ("ipad", "App Store", "Screenshots - iPad 13 inch", "ipad-13"),
    ("android", "Google Play", "Phone screenshots", "play-phone"),
    ("tablet", "Google Play", "7-inch tablet screenshots", "play-tablet-10"),
    ("tablet", "Google Play", "10-inch tablet screenshots", "play-tablet-10"),
]


def main(src: Path, dest: Path) -> None:
    if dest.exists():
        shutil.rmtree(dest)
    checks = []
    for prefix, store, slot, kind in SLOTS:
        d = dest / store / slot
        d.mkdir(parents=True)
        for i, name in enumerate(NAMES, 1):
            shutil.copy(src / f"{prefix}-0{i}.png", d / f"{name}.png")
        checks.append((kind, sorted(d.glob("*.png"))))
    gp = dest / "Google Play"
    shutil.copy(src / "feature-graphic.png", gp / "Feature graphic 1024x500.png")
    checks.append(("play-feature", [gp / "Feature graphic 1024x500.png"]))
    # Icons: Play wants a 512px 32-bit PNG; the App Store takes the 1024px icon
    # from the build itself, so it's here only to compare against.
    icon = Image.open(APP / "assets/icon/app_icon.png").convert("RGB")
    icon.resize((512, 512), Image.LANCZOS).convert("RGBA").save(gp / "App icon 512x512.png")
    icon.save(dest / "App Store" / "App icon 1024x1024 (already in the build).png")
    subprocess.run([sys.executable, str(SKILL / "listing.py"), str(dest / "App Store")], check=True,
                   stdout=subprocess.DEVNULL)
    (dest / "App Store" / "Google Play text.txt").replace(gp / "Google Play text.txt")
    for kind, files in checks:
        subprocess.run([sys.executable, str(HERE / "verify.py"), kind, *map(str, files)], check=True,
                       stdout=subprocess.DEVNULL)
    print(f"packaged and verified: {dest}")


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
