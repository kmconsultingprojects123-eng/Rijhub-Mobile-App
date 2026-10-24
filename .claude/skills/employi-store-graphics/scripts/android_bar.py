"""iPad captures, made fit for Google Play's tablet slots.

Play's 7- and 10-inch tablet graphics reuse the iPad frame and captures
(the app is the same on both: Flutter draws it), with one change: the iPad's
status bar ("9:41 AM Fri Oct 23", iOS's icons) is replaced by an Android
one, the time on the left and Wi-Fi, signal and battery on the right.

    python3 android_bar.py      # assets/screens/ipad-*.png -> tablet-*.png
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

SCREENS = Path(__file__).resolve().parent.parent / "assets" / "screens"
FONT = Path.home() / "Desktop/projects/flutter/Rijhub-Mobile-App/assets/fonts/inter/Inter-SemiBold.ttf"
BAR = 48            # the iPad status bar at 2x: 24 points


def bar(src: Path, dst: Path) -> None:
    im = Image.open(src).convert("RGB")
    w, _ = im.size
    # Clear the iOS bar: each column takes the colour just below the bar,
    # so a white header stays white and a photo carries on up.
    below = im.crop((0, BAR + 2, w, BAR + 3)).resize((w, BAR))
    im.paste(below, (0, 0))
    band = im.crop((0, 0, w, BAR)).convert("L")
    lum = sum(band.getdata()) / (w * BAR)
    busy = max(band.getdata()) - min(band.getdata()) > 60
    if busy:
        # Over a photo: the scrim Android draws under a status bar, which
        # also hides the streaks left by clearing the bar.
        shade = Image.new("L", (1, BAR * 3))
        shade.putdata([round(150 * (1 - y / (BAR * 3)) ** 1.6) for y in range(BAR * 3)])
        im.paste(Image.new("RGB", (w, BAR * 3), (0, 0, 0)), (0, 0), shade.resize((w, BAR * 3)))
    ink = (255, 255, 255) if busy or lum < 140 else (28, 28, 30)
    d = ImageDraw.Draw(im)
    f = ImageFont.truetype(str(FONT), 26)
    d.text((40, BAR / 2), "9:41", font=f, fill=ink, anchor="lm")
    # Right side, from the edge in: battery, signal, Wi-Fi.
    x, cy = w - 40, BAR // 2
    d.rounded_rectangle((x - 40, cy - 11, x, cy + 11), radius=6, outline=ink, width=3)
    d.rounded_rectangle((x - 36, cy - 7, x - 4, cy + 7), radius=3, fill=ink)
    d.rectangle((x + 1, cy - 4, x + 4, cy + 4), fill=ink)
    x -= 62
    d.polygon([(x, cy + 12), (x + 26, cy + 12), (x + 26, cy - 14)], fill=ink)
    x -= 46
    for r, t in ((24, 4), (16, 4), (8, 4)):
        d.arc((x - r, cy + 12 - r, x + r, cy + 12 + r), start=225, end=315, fill=ink, width=t)
    d.ellipse((x - 3, cy + 7, x + 3, cy + 13), fill=ink)
    im.save(dst)


if __name__ == "__main__":
    for src in sorted(SCREENS.glob("ipad-*.png")):
        dst = SCREENS / src.name.replace("ipad-", "tablet-")
        bar(src, dst)
        print(dst.name)
