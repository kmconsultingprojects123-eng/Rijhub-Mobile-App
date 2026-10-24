"""Bring a supersampled capture down to the store's exact size.

    python3 finish.py big.png out.png W H

Lanczos from 2x is what keeps rotated phone edges and small UI type clean;
Chrome's own downscale of a 1320px capture inside a scaled phone is softer.
The result is flattened to RGB, because both stores reject alpha.
"""
import sys

from PIL import Image

src, dst, w, h = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
im = Image.open(src).convert("RGBA")
flat = Image.new("RGB", im.size, (255, 255, 255))
flat.paste(im, mask=im.split()[3])
if flat.size != (w, h):
    flat = flat.resize((w, h), Image.LANCZOS)
flat.save(dst, optimize=True)
print(f"{dst}  {w}x{h}")
