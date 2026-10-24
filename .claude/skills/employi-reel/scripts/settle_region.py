"""Hide a loading state inside a page that is still sliding in.

    python3 settle_region.py FRAMES_DIR --source 85 --frames 43-56 \
        --rows 1900-2270 --band 1311-1835 --out recordings/patches/add-to-cart

For each frame in --frames, finds how far the incoming page still is from
its resting place (by sliding --band, a strip of the page's own content,
against the same strip in --source), then pastes --rows from --source,
shifted by that offset, over the incoming page. The page arrives with its
content already loaded. Patched frames are written to --out; make.sh
copies them over the extracted frames on every run.

Made for the add-to-cart take, whose seller card reads "Loading… New
seller" (and the label under it "Quantity", not "Delivery") all through
the push transition.
"""
import argparse, os
import numpy as np
from PIL import Image

ap = argparse.ArgumentParser()
ap.add_argument("frames"); ap.add_argument("--source", type=int, required=True)
ap.add_argument("--frames", dest="span", required=True); ap.add_argument("--rows", required=True)
ap.add_argument("--band", required=True); ap.add_argument("--out", required=True)
a = ap.parse_args()
rng = lambda s: tuple(int(v) for v in s.split("-"))
f0, f1 = rng(a.span); r0, r1 = rng(a.rows); b0, b1 = rng(a.band)
load = lambda i: np.asarray(Image.open(os.path.join(a.frames, f"{i:04d}.jpg")).convert("RGB"))
src = load(a.source); H, W, _ = src.shape
gsrc = src.mean(axis=2)
os.makedirs(a.out, exist_ok=True)
for i in range(f0, f1 + 1):
    fr = load(i); g = fr.mean(axis=2)
    def err(dx):
        x = g[b0:b1, dx:]; y = gsrc[b0:b1, :W - dx]
        return np.abs(x - y).mean() if x.shape[1] >= 120 else 1e9
    coarse = min(range(0, W - 120, 4), key=err)
    dx = min(range(max(0, coarse - 4), min(W - 120, coarse + 5)), key=err)
    out = fr.copy()
    out[r0:r1, dx:] = src[r0:r1, :W - dx]
    Image.fromarray(out).save(os.path.join(a.out, f"{i:04d}.jpg"), quality=95, subsampling=0)
    print(f"frame {i}: page {dx}px from rest, rows {r0}-{r1} settled from frame {a.source}")
