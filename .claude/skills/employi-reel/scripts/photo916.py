"""Fit a photo to a 1080 x 1920 reel frame.

    python3 photo916.py IN.jpg OUT.jpg [--focus 0.5]

Portrait photos are cropped to 9:16 around --focus (0 = left edge, 1 =
right). Landscape ones would lose most of the subject to a crop, so they
are set sharp across the frame over a blurred fill of themselves, edges
feathered (the Kenwood iron in the approved reel).
"""
import sys
import numpy as np
from PIL import Image, ImageEnhance, ImageFilter, ImageOps


def fit916(src, focus=0.5):
    im = ImageOps.exif_transpose(Image.open(src)).convert("RGB")
    w, h = im.size
    if h >= w:
        cw = round(h * 9 / 16)
        x0 = round((w - cw) * focus) if cw <= w else 0
        if cw > w:                                   # narrower than 9:16: crop height instead
            ch = round(w * 16 / 9); y0 = (h - ch) // 2
            return im.crop((0, y0, w, y0 + ch)).resize((1080, 1920), Image.LANCZOS)
        return im.crop((x0, 0, x0 + cw, h)).resize((1080, 1920), Image.LANCZOS)
    bg = im.resize((round(w * 1920 / h), 1920), Image.LANCZOS)
    x0 = (bg.width - 1080) // 2
    bg = ImageEnhance.Brightness(bg.crop((x0, 0, x0 + 1080, 1920)).filter(ImageFilter.GaussianBlur(40))).enhance(0.95)
    fw = 1300
    fg = im.resize((fw, round(h * fw / w)), Image.LANCZOS)
    a = np.full((fg.height, fg.width), 255, np.float32)
    feather = 90
    r = np.arange(fg.height)
    a *= (np.clip(r / feather, 0, 1) * np.clip((fg.height - 1 - r) / feather, 0, 1))[:, None]
    bg.paste(fg, ((1080 - fw) // 2, (1920 - fg.height) // 2 + 60), Image.fromarray(a.astype(np.uint8)))
    return bg


if __name__ == "__main__":
    focus = float(sys.argv[sys.argv.index("--focus") + 1]) if "--focus" in sys.argv else 0.5
    fit916(sys.argv[1], focus).save(sys.argv[2], quality=93, subsampling=0)
    print("wrote", sys.argv[2])
