"""Draw the phone frame: assets/brand/phone_frame.png.

    python3 phone.py

An iPhone 17 Pro-style body, drawn at 2x and downsampled, with a
transparent screen hole of 1200 x 2609 (the recordings' 1206 x 2622
aspect, so app frames sit in it nearly 1:1) and the Dynamic Island at its
real size (0.312 x 0.091 of the screen width, 0.035 down, measured off a
simulator capture), drawn a hair larger so it covers the island a
simulator capture bakes in.
"""
import os
import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
SS = 2
SW, SH = 1200, 2609
BEZ, RAIL = 30, 16
PAD = BEZ + RAIL
OW, OH = SW + 2 * PAD, SH + 2 * PAD
R_OUT, R_IN, R_SCR = 196, 180, 156
BTN = 9
W, H = (OW + 2 * BTN) * SS, OH * SS


def rr(d, box, r, fill):
    d.rounded_rectangle([v * SS for v in box], r * SS, fill=fill)


frame = Image.new("RGBA", (W, H), (0, 0, 0, 0))
d = ImageDraw.Draw(frame)
ox = BTN
btn = (58, 59, 63, 255)
for y0, y1 in [(0.205, 0.236), (0.292, 0.352), (0.368, 0.428)]:      # action, volume up, volume down
    rr(d, (0, OH * y0, ox + 14, OH * y1), 6, btn)
for y0, y1 in [(0.268, 0.352), (0.560, 0.612)]:                       # side button, camera control
    rr(d, (ox + OW - 14, OH * y0, ox + OW + BTN, OH * y1), 6, btn)
rr(d, (ox, 0, ox + OW, OH), R_OUT, (150, 150, 154, 255))             # titanium rail: lit edge,
rr(d, (ox + 3, 3, ox + OW - 3, OH - 3), R_OUT - 3, (64, 65, 69, 255))      # darker body,
rr(d, (ox + 7, 7, ox + OW - 7, OH - 7), R_OUT - 7, (44, 45, 49, 255))
rr(d, (ox + RAIL - 2, RAIL - 2, ox + OW - RAIL + 2, OH - RAIL + 2), R_IN + 2, (92, 93, 98, 255))  # inner highlight
rr(d, (ox + RAIL, RAIL, ox + OW - RAIL, OH - RAIL), R_IN, (6, 6, 8, 255))  # black glass bezel

hole = Image.new("L", (W, H), 0)
ImageDraw.Draw(hole).rounded_rectangle(
    [(ox + PAD) * SS, PAD * SS, (ox + PAD + SW) * SS, (PAD + SH) * SS], R_SCR * SS, fill=255)
a = np.array(frame.split()[3]).astype(np.int16) - np.array(hole).astype(np.int16)
frame.putalpha(Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)))

iw, ih, it = round(SW * 0.315), round(SW * 0.094), round(SW * 0.0335)
d = ImageDraw.Draw(frame)
rr(d, (ox + PAD + (SW - iw) / 2, PAD + it, ox + PAD + (SW + iw) / 2, PAD + it + ih), ih / 2, (0, 0, 0, 255))

out = os.path.join(HERE, "assets", "brand", "phone_frame.png")
frame.resize((W // SS, H // SS), Image.LANCZOS).save(out)
print("wrote", out, frame.size[0] // SS, "x", frame.size[1] // SS)
