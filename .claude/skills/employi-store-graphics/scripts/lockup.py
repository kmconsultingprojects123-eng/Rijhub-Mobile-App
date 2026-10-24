"""The store graphics' Employi lockup: the logo with the pin brought down.

In the logo file the pin is 1.7 times the height of "employi" (389 px
against 228), which at header sizes makes the name look small beside it.
The owner asked for the balance to change, so this cuts the file into its
pin, its wordmark and its "powered by RijHub" line, scales the pin alone
(the art is never redrawn) and sets it centred on the word.

    python3 lockup.py      # writes assets/brand/lockup{,-on-dark,-white}.png
"""
from pathlib import Path

from PIL import Image

BRAND = Path(__file__).resolve().parent.parent / "assets" / "brand"
PIN = (3, 3, 303, 392)          # x0, y0, x1, y1 in the 1261x400 logo files
WORD = (367, 78, 1258, 307)     # "employi", ascender to descender
LINE = (765, 335, 1258, 395)    # "powered by RijHub"
PIN_SCALE = 0.78                # pin = 1.33x the word's height
GAP = 0.19                      # pin-to-word gap, in pin heights (as the file)

for src, out in (("logo.png", "lockup.png"), ("logo-on-dark.png", "lockup-on-dark.png"),
                 ("logo-white.png", "lockup-white.png")):
    logo = Image.open(BRAND / src).convert("RGBA")
    pin = logo.crop(PIN)
    pin = pin.resize((round(pin.width * PIN_SCALE), round(pin.height * PIN_SCALE)), Image.LANCZOS)
    word, line = logo.crop(WORD), logo.crop(LINE)
    gap = round(pin.height * GAP)
    top = min(0, (word.height - pin.height) // 2)            # pin centred on the word
    w = pin.width + gap + word.width
    h = max(pin.height, word.height) + (LINE[1] - WORD[1]) - word.height + line.height + word.height - max(pin.height, word.height)
    canvas = Image.new("RGBA", (w, (LINE[3] - WORD[1]) - top), (0, 0, 0, 0))
    canvas.alpha_composite(pin, (0, 0))
    wx, wy = pin.width + gap, -top
    canvas.alpha_composite(word, (wx, wy))
    canvas.alpha_composite(line, (wx + (LINE[0] - WORD[0]), wy + (LINE[1] - WORD[1])))
    canvas = canvas.crop(canvas.getbbox())
    canvas.save(BRAND / out)
    print(out, canvas.size)
