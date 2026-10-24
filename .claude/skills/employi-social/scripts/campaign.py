"""Campaign concepts: two feed posts and two billboards.

Ported from homelands-social's launch.py. There they were HomeLands' launch
set; Employi has been live since February 2026, so nothing here says it is
new ("available now", "launching", "out now" are all out).

    photo               4:5 post. A brand photograph full bleed, the headline
                        on its top, the get-the-app block on a dark fade.
    proof               4:5 post. How it works, said plainly: ID-checked
                        artisans, chat and a start code, the money held
                        safely until the job is done. One phone, one capture.
    billboard-landscape 2:1 (48-sheet, 6 x 3 m). Photo left, message right.
    billboard-portrait  2:3 (6-sheet, 1.2 x 1.8 m). Photo above, message and
                        a large QR below, for people on foot.

    python3 campaign.py <concept>|all [-o out_dir] [--src instagram]

Every piece is placed, not generated: the photograph is the brand's own,
the phones hold simulator captures from ~/Downloads/employi-screens (see
SKILL.md), and badges, logo, QR and type come from the helpers build.py and
greeting.py use.

Needs Employi content before anything renders:
  - SITE and APP_URL in brand.py (TODO): every concept prints both.
  - assets/photos/wide.jpg for photo and both billboards: a photograph
    Employi owns. HomeLands' version used its app's welcome artwork;
    Employi's app has none, and the app's sample-data photos carry no
    recorded licence.
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import brand  # noqa: E402
from build import background, drop_shadow, phone, qr_image  # noqa: E402
from greeting import cover, store_badge, store_photo  # noqa: E402

SCREENS = os.path.expanduser("~/Downloads/employi-screens")

INK, WHITE = brand.INK, brand.WHITE
NIGHT = (16, 12, 13)                  # the fade under the download block
ACCENT_ON_DARK = brand.ACCENT_ON_DARK


def f(path, size):
    return brand.font(path, size)


def headline_width(line, size, path=brand.F_BOLD):
    text = line.replace("*", "")
    adv = brand.advances(path, size, text)
    return sum(adv) + size * brand.DISPLAY_TRACK * (len(text) - 1)


def draw_headline(d, x, y, line, size, ink=INK, accent=brand.ACCENT_FILL,
                  align="left", path=brand.F_BOLD):
    """One kerned line; *starred* parts in the accent, like build.py."""
    chars = []
    for k, part in enumerate(line.split("*")):
        chars += [(ch, accent if k % 2 else ink) for ch in part]
    text = "".join(ch for ch, _ in chars)
    adv = brand.advances(path, size, text)
    track = size * brand.DISPLAY_TRACK
    width = sum(adv) + track * (len(text) - 1)
    if align == "center":
        x = x - width / 2
    fnt = f(path, size)
    for (ch, col), a in zip(chars, adv):
        d.text((x, y), ch, font=fnt, anchor="la", fill=col)
        x += a + track
    return width


def tracked(d, x, y, text, fnt, fill, track, align="left"):
    widths = [fnt.getlength(ch) for ch in text]
    total = sum(widths) + track * (len(text) - 1)
    if align == "center":
        x -= total / 2
    for ch, w in zip(text, widths):
        d.text((x, y), ch, font=fnt, fill=fill)
        x += w + track
    return total


def qr_card(url, qr_px, pad, radius, shadow=True):
    side = qr_px + pad * 2
    card = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    ImageDraw.Draw(card).rounded_rectangle([0, 0, side - 1, side - 1], radius,
                                           fill=WHITE + (255,))
    card.paste(qr_image(url, qr_px), (pad, pad))
    if not shadow:
        return card, 0
    sp = radius
    out = Image.new("RGBA", (side + sp * 2, side + sp * 2), (0, 0, 0, 0))
    ImageDraw.Draw(out).rounded_rectangle(
        [sp, sp + radius // 4, sp + side, sp + side + radius // 4], radius,
        fill=brand.SHADOW + (60,))
    out = out.filter(ImageFilter.GaussianBlur(radius // 2))
    out.alpha_composite(card, (sp, sp))
    return out, sp


def vfade(size, y0, y1, colour, a0, a1):
    """Vertical fade of `colour` from alpha a0 at y0 to a1 at y1."""
    w, h = size
    yy = np.arange(h, dtype=np.float32)[:, None]
    t = np.clip((yy - y0) / max(1, y1 - y0), 0, 1)
    t = t * t * (3 - 2 * t)                       # smoothstep: no hard seam
    a = (a0 + (a1 - a0) * t) * 255
    layer = Image.new("RGBA", size, colour + (0,))
    layer.putalpha(Image.fromarray(np.repeat(a, w, axis=1).astype(np.uint8)))
    return layer


def art(size, focus_y):
    """The brand photograph, or stop: this concept needs Employi content."""
    photo = store_photo("wide")
    if photo is None:
        sys.exit("needs Employi content: add assets/photos/wide.jpg, a photograph Employi "
                 "owns (see SKILL.md). Then check the fades against it.")
    return cover(photo, size, (0.5, focus_y))


def typed_link():
    """The app link as people type it: no scheme."""
    return brand.require("APP_URL").split("://", 1)[-1]


def export(img, name, out_dir, size):
    os.makedirs(out_dir, exist_ok=True)
    master = img.convert("RGB")
    mp = os.path.join(out_dir, f"{name}-master.png")
    fp = os.path.join(out_dir, f"{name}-{size[0]}x{size[1]}.jpg")
    master.save(mp)
    master.resize(size, Image.LANCZOS).save(fp, quality=95, subsampling=0,
                                            optimize=True)
    print("wrote", fp)
    return fp


def shot(name):
    p = os.path.join(SCREENS, name)
    if not os.path.exists(p):
        sys.exit(f"missing capture {p}: take it first (SKILL.md, Capture screens)")
    return Image.open(p).convert("RGB")


# ── feed: photo ──────────────────────────────────────────────────────────────

def concept_photo(out_dir, url):
    W, H = 2160, 2700
    img = art((W, H), 0.30).convert("RGBA")
    # Lift the top a touch so ink type holds; the photo decides how much.
    img.alpha_composite(vfade((W, H), 0, 900, (255, 255, 255), 0.42, 0.0))
    img.alpha_composite(vfade((W, H), 1640, 2160, NIGHT, 0.0, 0.93))
    d = ImageDraw.Draw(img)

    logo = brand.lockup(round(640 * brand.LOGO_SCALE))
    img.alpha_composite(logo, ((W - logo.width) // 2, 118))

    tracked(d, W / 2, 330 + logo.height - 105, "ID-CHECKED ARTISANS IN ABUJA",
            f(brand.F_SEMI, 40), brand.ACCENT, 15, align="center")
    draw_headline(d, W / 2, 408 + logo.height - 105, "What needs", 158, align="center")
    draw_headline(d, W / 2, 600 + logo.height - 105, "*fixing?*", 158, align="center")

    # The get-the-app block: QR card beside both badges, centred as one unit.
    card, sp = qr_card(url, 300, 28, 40, shadow=False)
    side = card.width
    bw = 540
    ab = store_badge("app-store", bw, dark=True)
    gb = store_badge("google-play", bw, dark=True)
    gap_col, gap_b = 72, 24
    stack = ab.height + gap_b + gb.height
    block_h = max(side, stack)
    site_y = H - 170                              # site line, clear of the floor
    top = site_y - 64 - block_h
    tracked(d, W / 2, top - 92, "GET THE APP", f(brand.F_SEMI, 40),
            ACCENT_ON_DARK, 15, align="center")
    x0 = (W - (side + gap_col + bw)) // 2
    img.alpha_composite(card, (x0, top + (block_h - side) // 2))
    bx, by = x0 + side + gap_col, top + (block_h - stack) // 2
    img.alpha_composite(ab, (bx, by))
    img.alpha_composite(gb, (bx, by + ab.height + gap_b))
    d.text((W / 2, site_y), brand.require("SITE"), font=f(brand.F_SEMI, 46),
           fill=(214, 206, 208), anchor="ma")
    return export(img, "campaign-photo", out_dir, (1080, 1350))


# ── feed: proof ──────────────────────────────────────────────────────────────

def concept_proof(out_dir, url):
    W, H = 2160, 2700
    img = background(W, H, 0.9).convert("RGBA")
    d = ImageDraw.Draw(img)
    M = 160                                       # left margin

    logo = brand.lockup(round(560 * brand.LOGO_SCALE))
    img.alpha_composite(logo, (M, 128))
    tracked(d, M, 400, "HOW IT WORKS", f(brand.F_SEMI, 40), brand.ACCENT, 15)
    draw_headline(d, M, 470, "ID-checked.", 164)
    draw_headline(d, M, 684, "*Prices up front.*", 164)

    # Three proof points, left; the phone on an artisan's profile, right.
    # Each is true of the app today; check them again before posting.
    points = [
        ("NIN matched to a live selfie", "before an artisan can be booked"),
        ("Chat in the app", "and a start code when they arrive"),
        ("Your money, held safely", "until you confirm the job is done"),
    ]
    y = 1060
    f1, f2 = f(brand.F_BOLD, 58), f(brand.F_REG, 52)
    for i, (a, b) in enumerate(points):
        r = 30
        d.ellipse([M, y + 8, M + r * 2, y + 8 + r * 2], fill=brand.ACCENT_FILL)
        d.text((M + r, y + 8 + r), str(i + 1), font=f(brand.F_BOLD, 34),
               fill=WHITE, anchor="mm")
        d.text((M + 100, y), a, font=f1, fill=INK)
        d.text((M + 100, y + 76), b, font=f2, fill=brand.MUTED)
        y += 240

    # Below the headline, never over it: the phone starts under line two.
    # artisan.png: an artisan's profile with the ID-checked badge showing.
    dev = phone(shot("artisan.png"), 520)
    rot = dev.rotate(-5, resample=Image.BICUBIC, expand=True)
    rot = rot.resize((rot.width // 2, rot.height // 2), Image.LANCZOS)
    sh, pad = drop_shadow(rot, 50, 34)
    cx, cy = 1650, 1585
    img.alpha_composite(sh, (int(cx - sh.width / 2), int(cy - sh.height / 2 + 20)))
    img.alpha_composite(rot, (int(cx - rot.width / 2), int(cy - rot.height / 2)))

    # Footer: QR left with its caption, badges beside it, site below.
    fy = 2280
    card, sp = qr_card(url, 236, 22, 34)
    img.alpha_composite(card, (M - sp, fy - sp))
    d.text((M + (card.width - 2 * sp) / 2, fy + (card.width - 2 * sp) + 18),
           "Scan to download", font=f(brand.F_REG, 36), fill=brand.MUTED, anchor="ma")
    bw = 430
    ab = store_badge("app-store", bw)
    gb = store_badge("google-play", bw)
    bx = M + (card.width - 2 * sp) + 64
    img.alpha_composite(ab, (bx, fy + 4))
    img.alpha_composite(gb, (bx, fy + 4 + ab.height + 20))
    d.text((W - M, fy + 140), brand.require("SITE"), font=f(brand.F_SEMI, 46),
           fill=brand.MUTED, anchor="rm")
    return export(img, "campaign-proof", out_dir, (1080, 1350))


# ── billboards ───────────────────────────────────────────────────────────────

def concept_billboard_landscape(out_dir, url):
    """48-sheet proportions (6096 x 3048 mm). Read at speed: a few words, the
    name, where to get it. The QR is for passengers in traffic, so the typed
    address is set large too."""
    W, H = 6000, 3000
    img = Image.new("RGBA", (W, H), brand.GROUND + (255,))
    pw = 3300                                     # the picture's share
    pic = art((pw, H), 0.40).convert("RGBA")
    img.alpha_composite(pic, (0, 0))
    # Blend the picture into the panel instead of cutting it off.
    blend = Image.new("RGBA", (700, H), brand.GROUND + (0,))
    a = np.tile(np.linspace(0, 1, 700, dtype=np.float32) ** 1.6 * 255, (H, 1))
    blend.putalpha(Image.fromarray(a.astype(np.uint8)))
    img.alpha_composite(blend, (pw - 700, 0))
    d = ImageDraw.Draw(img)

    X = 3380
    logo = brand.lockup(round(1180 * brand.LOGO_SCALE))
    img.alpha_composite(logo, (X, 280))
    size = 300
    y = 680 + logo.height - 190
    for line in ("What needs", "*fixing?*"):
        draw_headline(d, X, y, line, size)
        y += round(size * 1.18)
    d.text((X, y + 40), "ID-checked artisans in Abuja.", font=f(brand.F_REG, 120),
           fill=brand.MUTED, anchor="la")
    # Download row: QR, then badges with the address people can type under
    # them, all inside a bottom margin the frame of a real board won't eat.
    fy = 1960
    card, sp = qr_card(url, 430, 36, 56)
    img.alpha_composite(card, (X - sp, fy - sp))
    bw = 900
    ab = store_badge("app-store", bw)
    gb = store_badge("google-play", bw)
    bx = X + (card.width - 2 * sp) + 100
    img.alpha_composite(ab, (bx, fy))
    img.alpha_composite(gb, (bx, fy + ab.height + 36))
    d.text((X, fy + ab.height + 36 + gb.height + 90), typed_link(),
           font=f(brand.F_BOLD, 120), fill=INK, anchor="la")
    return export(img, "billboard-landscape-48sheet", out_dir, (3000, 1500))


def concept_billboard_portrait(out_dir, url):
    """6-sheet proportions (1200 x 1800 mm): bus shelters, malls, walkways.
    People stand close, so the QR can be large and the copy can run longer."""
    W, H = 2400, 3600
    img = art((W, H), 0.18).convert("RGBA")
    img.alpha_composite(vfade((W, H), 0, 1100, (255, 255, 255), 0.46, 0.0))
    img.alpha_composite(vfade((W, H), 2050, 2600, NIGHT, 0.0, 0.94))
    d = ImageDraw.Draw(img)

    logo = brand.lockup(round(820 * brand.LOGO_SCALE))
    img.alpha_composite(logo, ((W - logo.width) // 2, 150))
    y = 470 + logo.height - 130
    for line, size in (("What needs", 214), ("*fixing?*", 214),
                       ("Book an ID-checked artisan.", 104)):
        draw_headline(d, W / 2, y, line, size, accent=brand.ACCENT_FILL, align="center")
        y += round(size * 1.2)

    top = 2650
    card, sp = qr_card(url, 520, 44, 60, shadow=False)
    side = card.width
    bw = 760
    ab = store_badge("app-store", bw, dark=True)
    gb = store_badge("google-play", bw, dark=True)
    stack = ab.height + 36 + gb.height
    gap = 110
    x0 = (W - (side + gap + bw)) // 2
    img.alpha_composite(card, (x0, top))
    tracked(d, x0 + side + gap, top + 6, "SCAN TO GET THE APP",
            f(brand.F_SEMI, 52), ACCENT_ON_DARK, 16)
    by = top + 110
    img.alpha_composite(ab, (x0 + side + gap, by))
    img.alpha_composite(gb, (x0 + side + gap, by + ab.height + 36))
    d.text((x0 + side + gap, by + stack + 60), typed_link(),
           font=f(brand.F_BOLD, 86), fill=WHITE, anchor="la")
    return export(img, "billboard-portrait-6sheet", out_dir, (2000, 3000))


CONCEPTS = {
    "photo": concept_photo,
    "proof": concept_proof,
    "billboard-landscape": concept_billboard_landscape,
    "billboard-portrait": concept_billboard_portrait,
}

if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    out = sys.argv[sys.argv.index("-o") + 1] if "-o" in sys.argv else os.getcwd()
    src_feed = sys.argv[sys.argv.index("--src") + 1] if "--src" in sys.argv else "instagram"
    brand.require("SITE")
    app_url = brand.require("APP_URL")
    for name, fn in CONCEPTS.items():
        if which in ("all", name):
            src = "billboard" if name.startswith("billboard") else src_feed
            fn(out, f"{app_url}?src={src}")
