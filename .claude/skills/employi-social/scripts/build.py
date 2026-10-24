"""Render an Employi social graphic from a JSON config.

Deterministic by design. Nothing here is generated: the screenshots, logo,
store badges and QR are real files placed at computed coordinates, and the
type is set in the app's own Inter. Same config in, same pixels out.

    python3 build.py post.json [-o out_dir]

Config keys are documented in SKILL.md; examples/ has working ones.
"""
from __future__ import annotations

import io
import json
import math
import os
import sys

import numpy as np
import segno
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
SKILL = os.path.dirname(HERE)
ASSETS = os.path.join(SKILL, "assets")

# ── brand ────────────────────────────────────────────────────────────────────
sys.path.insert(0, HERE)
import brand  # noqa: E402  (the one file that makes this Employi)

INK = brand.INK
TEAL = brand.ACCENT          # the accent slot; name kept from the shared engine
MUTED = brand.MUTED
WHITE = brand.WHITE

F_REG, F_SEMI, F_BOLD = brand.F_REG, brand.F_SEMI, brand.F_BOLD

#: Masters render at 2x the export size, then downsample. Rotating a
#: hard-edged device at final size leaves a pale fringe that reads as a
#: grey outline against white.
FORMATS = {
    "feed":   (1080, 1350),   # 4:5, tallest allowed in feed, matches the grid
    "square": (1080, 1080),   # 1:1, sides get cropped in the 4:5 profile grid
    "story":  (1080, 1920),   # 9:16 full screen
}
SS = 2


def font(path, size):
    return ImageFont.truetype(path, size)


# ── background ───────────────────────────────────────────────────────────────

def background(W, H, strength=1.0):
    """White ground with the brand's soft splash (brand.SPLASH) behind the subject."""
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    out = np.full((H, W, 3), 255.0, dtype=np.float32)
    for cx, cy, rx, ry, col, pk, pw in brand.SPLASH:
        d = np.sqrt(((xx - W * cx) / (W * rx)) ** 2 + ((yy - H * cy) / (H * ry)) ** 2)
        a = (np.clip(1.0 - d, 0, 1) ** pw * pk * strength)[..., None]
        out = out * (1 - a) + np.array(col, np.float32) * a
    return Image.fromarray(out.clip(0, 255).astype(np.uint8))


def linework(W, H):
    """Faint architectural drawings in the top corners, after the App Store
    graphics: a gabled elevation on the left, a floor plan on the right.

    Drawn from scratch rather than lifted from those images. Fades out
    before the devices and toward the centre so the headline stays clean,
    and dissolves near the canvas edge instead of stopping at it.
    """
    S = W / 2160.0

    def P(*pts):
        return [(round(x * S), round(y * S)) for x, y in pts]

    m = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(m)
    lw = max(2, round(3 * S))
    ln = lambda *pts: d.line(P(*pts), fill=255, width=lw, joint="curve")
    rect = lambda x0, y0, x1, y1: d.rectangle(P((x0, y0), (x1, y1)), outline=255, width=lw)

    # left: a gabled house front
    ln((-60, 520), (330, 175), (720, 520))              # roof, with overhang
    ln((-30, 545), (330, 226), (690, 545))              # roof thickness
    ln((505, 330), (505, 205), (575, 205), (575, 392))  # chimney
    for x in (30, 630):                                 # walls
        ln((x, 545), (x, 1300))
    ln((30, 1210), (630, 1210))                         # ground line
    for x0 in (95, 385):                                # two windows with mullions
        rect(x0, 650, x0 + 180, 850)
        ln((x0 + 90, 650), (x0 + 90, 850))
        ln((x0, 750), (x0 + 180, 750))
        ln((x0 - 14, 866), (x0 + 194, 866))             # sill
    rect(262, 960, 398, 1210)                           # door
    ln((372, 1080), (380, 1080))                        # handle

    # right: a floor plan, walls drawn double
    def wall(x0, y0, x1, y1, t=18):
        ln((x0, y0), (x1, y1))
        if x0 == x1:
            ln((x0 + t, y0), (x1 + t, y1))
        else:
            ln((x0, y0 + t), (x1, y1 + t))
    wall(1560, 130, 2260, 130)                          # top
    wall(1560, 130, 1560, 250)                          # left, broken by a window
    wall(1560, 430, 1560, 1060)
    for dx in (0, 9, 18):                               # window symbol
        ln((1560 + dx, 250), (1560 + dx, 430))
    wall(1880, 148, 1880, 560)                          # interior wall
    wall(1578, 560, 1650, 560)                          # interior wall, door gap
    wall(1780, 560, 2260, 560)
    d.arc([round(1650 * S - 130 * S), round(560 * S - 130 * S),
           round(1650 * S + 130 * S), round(560 * S + 130 * S)],
          270, 360, fill=255, width=lw)                 # door swing
    ln((1650, 560), (1650, 430))                        # the door leaf
    rect(1960, 640, 2080, 730)                          # basin
    d.ellipse(P((1990, 660), (2050, 710)), outline=255, width=lw)
    for i in range(9):                                  # stair treads
        y = 700 + i * 36
        ln((1610, y), (1820, y))
    ln((1610, 700), (1610, 1024)); ln((1820, 700), (1820, 1024))
    ln((1715, 1010), (1715, 740)); ln((1695, 765), (1715, 740), (1735, 765))  # up arrow

    # fade: full at the top, gone by ~half height; clear down the centre;
    # dissolving over the last 70px at the canvas edge
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    fy = np.clip((0.50 * H - yy) / (0.30 * H), 0, 1)
    dc = np.abs(xx - W / 2) / W
    fx = np.clip((dc - 0.20) / 0.14, 0, 1)
    edge = np.minimum.reduce([xx, W - 1 - xx, yy, H - 1 - yy])
    fe = np.clip((edge - 12 * S) / (70 * S), 0, 1)
    a = np.array(m).astype(np.float32) / 255 * fy * fx * fe
    out = Image.new("RGBA", (W, H), brand.LINEWORK + (0,))
    out.putalpha(Image.fromarray((a * 255).astype(np.uint8)))
    return out


# ── device ───────────────────────────────────────────────────────────────────

def phone(shot, screen_w, ss=SS):
    """iPhone-style device with the screenshot placed exactly.

    The body is dark with a hairline lit edge. An earlier version used a
    light titanium band for the rail; against white that has almost no
    contrast and reads as a sticker border rather than a phone.
    """
    sw = screen_w * ss
    sh = round(sw * shot.height / shot.width)
    rail = max(2, round(sw * 0.015))
    bez = max(2, round(sw * 0.026))
    pad = rail + bez
    ow, oh = sw + pad * 2, sh + pad * 2
    r_out = round(ow * 0.152)

    card = Image.new("RGBA", (ow, oh), (0, 0, 0, 0))
    d = ImageDraw.Draw(card)
    hair = max(2, round(sw * 0.004))
    d.rounded_rectangle([0, 0, ow - 1, oh - 1], r_out, fill=(126, 124, 121, 255))
    d.rounded_rectangle([hair, hair, ow - hair - 1, oh - hair - 1],
                        r_out - hair, fill=(30, 30, 33, 255))
    d.rounded_rectangle([rail, rail, ow - rail - 1, oh - rail - 1],
                        round(r_out * 0.90), fill=(9, 9, 11, 255))

    shot_r = shot.resize((sw, sh), Image.LANCZOS).convert("RGBA")
    sm = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(sm).rounded_rectangle([0, 0, sw - 1, sh - 1],
                                         round(sw * 0.118), fill=255)
    card.paste(shot_r, (pad, pad), sm)

    # Device screenshots have no Dynamic Island; simulator captures have one
    # baked in. Drawn at the iPhone 17's real size (measured off a simulator
    # capture: 0.312 x 0.091 of the screen width, 0.035 down), a hair larger,
    # it stands in for the first and exactly covers the second.
    iw, ih, it = round(sw * 0.315), round(sw * 0.094), round(sw * 0.0335)
    d.rounded_rectangle([pad + (sw - iw) // 2, pad + it,
                         pad + (sw - iw) // 2 + iw, pad + it + ih],
                        ih // 2, fill=(0, 0, 0, 255))

    btn = (96, 95, 92, 255)
    for y0, y1 in [(0.205, 0.240), (0.285, 0.352), (0.370, 0.437)]:
        d.rounded_rectangle([0, round(oh * y0), rail, round(oh * y1)], rail, fill=btn)
    d.rounded_rectangle([ow - rail - 1, round(oh * 0.262), ow - 1, round(oh * 0.360)],
                        rail, fill=btn)
    return card


def drop_shadow(dev, blur, dy, alpha=92):
    pad = blur * 3
    sh = Image.new("RGBA", (dev.width + pad * 2, dev.height + pad * 2), (0, 0, 0, 0))
    sh.paste(Image.new("RGBA", dev.size, brand.SHADOW + (alpha,)), (pad, pad + dy),
             dev.split()[3])
    return sh.filter(ImageFilter.GaussianBlur(blur)), pad


# ── badges + QR ──────────────────────────────────────────────────────────────

def badge(name, width):
    """Official store artwork, already stripped of its dark-background stroke."""
    im = Image.open(os.path.join(ASSETS, "badges", name)).convert("RGBA")
    return im.resize((width, round(width * im.height / im.width)), Image.LANCZOS)


def qr_image(url, px):
    buf = io.BytesIO()
    segno.make(url, error="h").save(buf, kind="png", scale=20, border=0,
                                    dark="#000000", light="#FFFFFF")
    buf.seek(0)
    return Image.open(buf).convert("RGB").resize((px, px), Image.NEAREST)


# ── screenshot preparation ───────────────────────────────────────────────────

def erase_band(im, y0, y1, blur=45):
    """Remove a band of UI (a false claim, a stale badge) from a screenshot.

    Rebuilds the ground by interpolating the rows above and below, then
    blurs the patch through a feathered mask so no rectangular ghost of the
    removed element's shadow survives.
    """
    a = np.array(im.convert("RGB")).astype(float)
    top = a[max(0, y0 - 10):y0 - 2, :].mean(axis=0)
    bot = a[y1 + 2:y1 + 10, :].mean(axis=0)
    t = (np.arange(y1 - y0) / max(1, y1 - y0 - 1))[:, None, None]
    a[y0:y1, :] = top[None] * (1 - t) + bot[None] * t
    filled = Image.fromarray(a.clip(0, 255).astype(np.uint8))
    b = filled.filter(ImageFilter.GaussianBlur(blur))
    m = Image.new("L", filled.size, 0)
    ImageDraw.Draw(m).rectangle([0, y0 - 30, filled.width, y1 + 30], fill=255)
    return Image.composite(b, filled, m.filter(ImageFilter.GaussianBlur(30)))


def load_shot(spec):
    path = os.path.expanduser(spec["path"] if isinstance(spec, dict) else spec)
    if not os.path.exists(path):
        sys.exit(f"screenshot not found: {path}\n"
                 "  take it on a device or the simulator, or change the path in the config")
    im = Image.open(path).convert("RGB")
    if isinstance(spec, dict):
        for band in spec.get("erase", []):
            im = erase_band(im, band[0], band[1])
    return im


# ── layout ───────────────────────────────────────────────────────────────────

def build(cfg, out_dir):
    fmt = cfg.get("format", "feed")
    ew, eh = FORMATS[fmt]
    W, H = ew * SS, eh * SS
    S = W / 2160.0                      # scale everything off the 4:5 master

    # Employi hook: the URL and the QR come from links brand.py holds as TODO
    # until the website is confirmed. Refuse rather than print a guess.
    if cfg.get("qr") and not brand.APP_URL:
        sys.exit(f"{cfg.get('name', 'post')}: refusing to draw a QR: brand.APP_URL is a TODO "
                 "(scripts/brand.py).\n  Drop \"qr\" from the config until the link is confirmed.")
    if cfg.get("site") and not brand.SITE:
        sys.exit(f"{cfg.get('name', 'post')}: refusing to print a URL: brand.SITE is a TODO "
                 "(scripts/brand.py).\n  Drop \"site\" from the config until the domain is confirmed.")

    img = background(W, H, cfg.get("glow", 1.0)).convert("RGBA")
    # The line-work is HomeLands' own art; a brand without any (brand.LINEWORK
    # is None) never draws it.
    if brand.LINEWORK and cfg.get("linework", True):
        img.alpha_composite(linework(W, H))
    d = ImageDraw.Draw(img)

    def px(v):
        return round(v * S)

    # header ------------------------------------------------------------------
    y = px(92)
    if cfg.get("logo", True):
        logo = brand.lockup(round(px(530) * brand.LOGO_SCALE))
        img.alpha_composite(logo, ((W - logo.width) // 2, y))
        y += logo.height + px(68)

    if cfg.get("eyebrow"):
        spaced = " ".join(cfg["eyebrow"].upper())
        d.text((W // 2, y), spaced, font=font(F_SEMI, px(39)), fill=TEAL, anchor="ma")
        y += px(86)

    if cfg.get("headline"):
        hs = px(cfg.get("headline_size", 122))
        f_h = font(F_BOLD, hs)
        track = hs * brand.DISPLAY_TRACK
        for line in cfg["headline"] if isinstance(cfg["headline"], list) else [cfg["headline"]]:
            # "Find it. *Tour it.* Live it." sets the starred part in the
            # accent, the two-tone headline of the App Store graphics.
            chars = []
            for k, part in enumerate(line.split("*")):
                chars += [(ch, brand.ACCENT_FILL if k % 2 else INK) for ch in part]
            text = "".join(ch for ch, _ in chars)
            adv = brand.advances(F_BOLD, hs, text)
            x = (W - (sum(adv) + track * (len(text) - 1))) / 2
            for (ch, col), a in zip(chars, adv):
                d.text((x, y), ch, font=f_h, anchor="la", fill=col)
                x += a + track
            y += px(cfg.get("headline_size", 122) * 1.42)

    if cfg.get("subline"):
        f_s = font(F_REG, px(53))
        for line in cfg["subline"]:
            d.text((W // 2, y), line, font=f_s, fill=MUTED, anchor="ma")
            y += px(72)

    # footer + download row, anchored from the floor --------------------------
    site_top = H - px(140)
    if cfg.get("site"):
        d.text((W // 2, site_top), cfg["site"], font=font(F_SEMI, px(47)),
               fill=MUTED, anchor="ma")

    qr_cfg = cfg.get("qr")
    want_badges = cfg.get("badges", True)
    row_h = 0
    if qr_cfg or want_badges:
        qpx, qpad, cap_gap = px(320), px(30), px(16)
        card_side = qpx + qpad * 2
        f_cap = font(F_REG, px(38))
        cap_h = f_cap.getbbox("Ag")[3]
        qr_block = card_side + cap_gap + cap_h if qr_cfg else 0
        bw = px(640)
        badge_gap = px(26)
        ab = badge("app-store.png", bw) if want_badges else None
        gb = badge("google-play.png", bw) if want_badges else None
        badges_h = (ab.height + badge_gap + gb.height) if want_badges else 0
        row_h = max(qr_block, badges_h)
        # With devices present the row sits just above the footer. With none,
        # anchoring to the floor leaves a dead field in the middle, so the row
        # floats into the space the devices would have occupied.
        if cfg.get("screenshots"):
            row_top = site_top - px(66) - row_h
        else:
            row_top = y + px(60) + ((site_top - px(66)) - (y + px(60)) - row_h) // 2
        margin = px(232)

        if qr_cfg:
            card = Image.new("RGBA", (card_side, card_side), (0, 0, 0, 0))
            ImageDraw.Draw(card).rounded_rectangle(
                [0, 0, card_side - 1, card_side - 1], px(44), fill=WHITE + (255,))
            card.paste(qr_image(qr_cfg["url"], qpx), (qpad, qpad))
            shp = px(56)
            sh = Image.new("RGBA", (card_side + shp * 2,) * 2, (0, 0, 0, 0))
            ImageDraw.Draw(sh).rounded_rectangle(
                [shp, shp + px(12), shp + card_side, shp + card_side + px(12)],
                px(44), fill=brand.SHADOW + (58,))
            sh = sh.filter(ImageFilter.GaussianBlur(px(22)))
            sh.alpha_composite(card, (shp, shp))
            qy = row_top + (row_h - qr_block) // 2
            img.alpha_composite(sh, (margin - shp, qy - shp))
            d.text((margin + card_side // 2, qy + card_side + cap_gap),
                   qr_cfg.get("caption", "Scan to download"),
                   font=f_cap, fill=MUTED, anchor="ma")

        if want_badges:
            bx = W - margin - bw if qr_cfg else (W - bw) // 2
            by = row_top + (row_h - badges_h) // 2
            img.alpha_composite(ab, (bx, by))
            img.alpha_composite(gb, (bx, by + ab.height + badge_gap))
    else:
        row_top = site_top - px(66)

    # devices ------------------------------------------------------------------
    shots = [load_shot(s) for s in cfg.get("screenshots", [])]
    if shots:
        tilt_deg = cfg.get("tilt", 6.0)
        overlap = px(cfg.get("overlap", 26))
        top = y + px(44)
        avail = (row_top - px(54)) - top
        rad = math.radians(tilt_deg)
        n = len(shots)
        denom = 2.262 * math.cos(rad) + 1.088 * math.sin(rad)
        screen_w = int(avail / denom)
        if n > 1:                       # keep the pair inside the canvas
            max_w = (W - px(240) + overlap * (n - 1)) / n / 1.088
            screen_w = int(min(screen_w, max_w))

        devs = [phone(s, screen_w) for s in shots]
        body_w = devs[0].width // SS

        def tilt(dev, ang):
            r = dev.rotate(ang, resample=Image.BICUBIC, expand=True)
            return r.resize((r.width // SS, r.height // SS), Image.LANCZOS)

        angles = [tilt_deg * (1 if i % 2 == 0 else -1) for i in range(n)]
        rots = [tilt(dv, a) for dv, a in zip(devs, angles)]
        cy = top + avail / 2
        span = body_w * n - overlap * (n - 1)
        for i, r in enumerate(rots):
            cx = (W - span) / 2 + body_w * i - overlap * i + body_w / 2
            dy = screen_w * 0.045 * (1 if i % 2 == 0 else -1)
            sh, _ = drop_shadow(r, round(screen_w * 0.075), round(screen_w * 0.05))
            for layer in (sh, r):
                img.alpha_composite(layer, (int(cx - layer.width / 2),
                                            int(cy + dy - layer.height / 2)))

    master = img.convert("RGB")
    os.makedirs(out_dir, exist_ok=True)
    name = cfg.get("name", "post")
    mp = os.path.join(out_dir, f"{name}-master.png")
    fp = os.path.join(out_dir, f"{name}-{ew}x{eh}.jpg")
    master.save(mp)
    master.resize((ew, eh), Image.LANCZOS).save(fp, quality=95, subsampling=0,
                                                optimize=True)
    print(f"master {master.size} -> {fp}")
    return fp


if __name__ == "__main__":
    cfg_path = sys.argv[1]
    out = sys.argv[sys.argv.index("-o") + 1] if "-o" in sys.argv else os.getcwd()
    with open(cfg_path) as fh:
        conf = json.load(fh)
    for one in (conf if isinstance(conf, list) else [conf]):
        build(one, out)
