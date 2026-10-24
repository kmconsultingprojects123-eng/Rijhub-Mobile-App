"""Average each frame's sub-frames in linear light and stream to ffmpeg.

    python3 blur.py SUBFRAME_DIR FRAMES OUT.mp4 [--keep PNG_DIR]

A shutter integrates light, so sub-frames are averaged after undoing the
sRGB curve and re-encoded after: averaging sRGB values directly darkens
every edge that moves.
"""
import os, subprocess, sys
import numpy as np
from PIL import Image

import json
src, frames, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
subs = {int(k): v for k, v in json.load(open(os.path.join(src, "subs.json"))).items()}
keep = sys.argv[sys.argv.index("--keep") + 1] if "--keep" in sys.argv else None
if keep: os.makedirs(keep, exist_ok=True)

lut = np.arange(256, dtype=np.float64) / 255.0
to_lin = np.where(lut <= 0.04045, lut / 12.92, ((lut + 0.055) / 1.055) ** 2.4).astype(np.float32)
_grid = np.linspace(0, 1, 4096)
_enc = (np.where(_grid <= 0.0031308, _grid * 12.92, 1.055 * np.power(_grid, 1 / 2.4) - 0.055) * 255 + 0.5).astype(np.uint8)
def to_srgb8(x):
    return _enc[np.clip((x * 4095 + 0.5).astype(np.int32), 0, 4095)]

ff = subprocess.Popen([
    "ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "1080x1920", "-r", "30", "-i", "-",
    "-vf", "scale=out_color_matrix=bt709:out_range=tv,format=yuv420p",
    "-c:v", "libx264", "-preset", "slow", "-crf", "15", "-profile:v", "high", "-level", "4.2",
    "-x264-params", "keyint=60:min-keyint=30:aq-mode=3",
    "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709",
    "-movflags", "+faststart", out], stdin=subprocess.PIPE)
for f in range(frames):
    sub = subs[f]
    acc = None
    for s in range(sub):
        a = to_lin[np.asarray(Image.open(os.path.join(src, f"f{f:04d}_{s}.jpg")).convert("RGB"))]
        acc = a if acc is None else acc + a
    rgb = to_srgb8(acc / sub)
    ff.stdin.write(rgb.tobytes())
    if keep and (f % 15 == 0): Image.fromarray(rgb).save(os.path.join(keep, f"f{f:04d}.png"))
ff.stdin.close(); ff.wait()
print("wrote", out, "rc", ff.returncode)
