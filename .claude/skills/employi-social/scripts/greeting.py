"""Occasion greetings: Independence Day, new month, and whatever comes next.

Eight concepts, each a complete 4:5 post:

    numerals    — the year's number as the hero, set in the national colours
    calendar    — a desk calendar whose page has just turned; one image that
                  says both "new month" and the occasion
    receipt     — the brand's own receipt for the day; the total is NOT FOR SALE
    stamp       — a commemorative stamp, franked on the day
    lockscreen  — a phone at midnight, the greeting arriving as a push
    label       — a woven garment label: made in Nigeria, colourfast since 1960
    board       — a departures board: September departed, October arrived
    triptych    — three brand photographs printed green, white, green

Every concept ends with the same utility: a get-the-app section (the QR
beside both store badges) and where to find us. The receipt carries both in
character: the website in its header, the QR where a barcode would be.

    python3 greeting.py <concept>|all [-o out_dir]

On national colours: this uses green-white-green, never the flag itself.
Section 6 of the Flags and Coats of Arms Act makes using the National Flag or
Coat of Arms "in connection with the carrying on of any business" without a
licence an offence. The colours carry the meaning; the flag stays out.
"""
from __future__ import annotations

import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(os.path.dirname(HERE), "assets")
sys.path.insert(0, HERE)
from build import qr_image  # noqa: E402  (the same QR as every other post)
import brand  # noqa: E402  (the one file that makes this Employi)

W, H = 2160, 2700            # 2x master for a 1080 x 1350 export

NG_GREEN = (0, 135, 81)      # #008751, the flag green
NG_DEEP = (0, 98, 60)
NG_LIGHT = (70, 200, 140)    # the green, lifted for use on dark grounds
INK = brand.INK
NIGHT = (5, 18, 25)
MUTED = brand.MUTED
WHITE = (255, 255, 255)

STORE_ADDRESS = brand.ADDRESS    # None: the footer shows the website alone
APP_URL = brand.APP_URL          # None while brand.py holds it as a TODO
SITE = brand.SITE                # likewise
NAME = brand.NAME


def need_links():
    """Every concept prints the website and a QR to the app link. brand.py
    holds both as TODO until Employi's website is confirmed, and nothing here
    guesses one, so refuse rather than render a greeting without them."""
    missing = [k for k, v in (("SITE", SITE), ("APP_URL", APP_URL)) if not v]
    if missing:
        sys.exit(f"refusing to render: {' and '.join(missing)} still TODO in scripts/brand.py.\n"
                 "  Every greeting prints the website and a QR; set them once the domain is confirmed.")

F_REG, F_SEMI, F_BOLD = brand.F_REG, brand.F_SEMI, brand.F_BOLD
MONO = "/System/Library/Fonts/Menlo.ttc"


def font(path, size):
    return ImageFont.truetype(path, size)


def mono(size, bold=False):
    return ImageFont.truetype(MONO, size, index=1 if bold else 0)


# ── toolkit ──────────────────────────────────────────────────────────────────

def glow(base, cx, cy, rx, ry, colour, peak, power=1.6):
    """Soft radial wash of `colour` over an RGB image."""
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    d = np.sqrt(((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2)
    a = (np.clip(1 - d, 0, 1) ** power * peak)[..., None]
    arr = np.array(base).astype(np.float32)
    arr = arr * (1 - a) + np.array(colour, np.float32) * a
    return Image.fromarray(arr.clip(0, 255).astype(np.uint8))


def grain(im, amount=4.0, seed=7):
    """Monochrome film grain, for dark grounds only: it breaks up the banding
    a smooth gradient shows after JPEG compression. Applied to the ground
    before anything is drawn, so type, badges and the QR stay crisp."""
    rng = np.random.default_rng(seed)
    arr = np.array(im).astype(np.float32)
    n = rng.normal(0, amount, arr.shape[:2])[..., None]
    return Image.fromarray((arr + n).clip(0, 255).astype(np.uint8))


def tracked(d, cx, y, text, f, fill, track):
    """Centred text with letter-spacing, which Pillow doesn't do natively."""
    widths = [f.getlength(ch) for ch in text]
    x = cx - (sum(widths) + track * (len(text) - 1)) / 2
    for ch, w in zip(text, widths):
        d.text((x, y), ch, font=f, fill=fill)
        x += w + track


def logo(width, reversed_=False):
    """The brand's logo, scaled from its own file (brand.lockup). Reversed
    takes the version made for dark grounds."""
    return brand.lockup(round(width * brand.LOGO_SCALE), reversed_)


def tricolour(size, bands=(NG_GREEN, WHITE, NG_GREEN)):
    """Three equal vertical bands — the national colours, not the flag."""
    w, h = size
    im = Image.new("RGBA", size)
    d = ImageDraw.Draw(im)
    edges = [0, round(w / 3), round(2 * w / 3), w]
    for (x0, x1), c in zip(zip(edges, edges[1:]), bands):
        d.rectangle([x0, 0, x1, h], fill=c + (255,))
    return im


def glyph_in_tricolour(ch, f):
    """Render one character filled with the green-white-green bands."""
    bb = f.getbbox(ch)
    w, h = bb[2] - bb[0], bb[3] - bb[1]
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).text((-bb[0], -bb[1]), ch, font=f, fill=255)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.paste(tricolour((w, h)), (0, 0), mask)
    return out


def soft_shadow(size, radius, blur, colour=(0, 30, 20), alpha=70, dy=0):
    w, h = size
    pad = blur * 3
    im = Image.new("RGBA", (w + pad * 2, h + pad * 2), (0, 0, 0, 0))
    ImageDraw.Draw(im).rounded_rectangle([pad, pad + dy, pad + w, pad + h + dy],
                                         radius, fill=colour + (alpha,))
    return im.filter(ImageFilter.GaussianBlur(blur)), pad


def text_h(f, s):
    """Height a line of text occupies when drawn with the default anchor."""
    return f.getbbox(s)[3]


def export(img, name, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    master = img.convert("RGB")
    mp = os.path.join(out_dir, f"{name}-master.png")
    fp = os.path.join(out_dir, f"{name}-1080x1350.jpg")
    master.save(mp)
    master.resize((1080, 1350), Image.LANCZOS).save(fp, quality=95, subsampling=0,
                                                    optimize=True)
    print("wrote", fp)
    return fp


# ── the get-the-app section ──────────────────────────────────────────────────

QR_PX, QR_PAD, CARD_R = 300, 28, 40
BADGE_W, BADGE_GAP, COL_GAP = 520, 22, 72
FOOT_BOTTOM = 110


def store_badge(which, width, dark=False):
    """Official App Store / Google Play artwork.

    Light grounds take the stroke-stripped version. Dark grounds take the
    outlined one: that grey ring is what separates a black badge from a
    near-black background, and it's why Apple and Google ship it.
    """
    name = f"{which}-dark.png" if dark else f"{which}.png"
    im = Image.open(os.path.join(ASSETS, "badges", name)).convert("RGBA")
    return im.resize((width, round(width * im.height / im.width)), Image.LANCZOS)


def pin(width, colour):
    """Map pin: a circle drawn down to a point, with a hole. The flanks are
    true tangents from the tip, so the outline has no kinks."""
    ss = 4
    w = width * ss
    r = w / 2
    h = round(r * 2.7)                          # tip sits 1.7r below centre
    m = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(m)
    d.ellipse([0, 0, w - 1, w - 1], fill=255)
    d.polygon([(r - 0.809 * r, r + 0.588 * r), (r + 0.809 * r, r + 0.588 * r),
               (r, h - 1)], fill=255)
    hr = r * 0.38
    d.ellipse([r - hr, r - hr, r + hr, r + hr], fill=0)
    m = m.resize((width, round(h / ss)), Image.LANCZOS)
    out = Image.new("RGBA", m.size, colour + (255,))
    out.putalpha(m)
    return out


def download_block_size(dark):
    side = QR_PX + QR_PAD * 2
    ab = store_badge("app-store", BADGE_W, dark)
    gb = store_badge("google-play", BADGE_W, dark)
    return side + COL_GAP + BADGE_W, max(side, ab.height + BADGE_GAP + gb.height)


def draw_download_block(img, top, dark):
    """The QR on a white card beside both store badges, centred as one unit."""
    side = QR_PX + QR_PAD * 2
    ab = store_badge("app-store", BADGE_W, dark)
    gb = store_badge("google-play", BADGE_W, dark)
    stack = ab.height + BADGE_GAP + gb.height
    h = max(side, stack)
    x0 = (W - (side + COL_GAP + BADGE_W)) // 2

    card = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    ImageDraw.Draw(card).rounded_rectangle([0, 0, side - 1, side - 1], CARD_R,
                                           fill=WHITE + (255,))
    card.paste(qr_image(APP_URL, QR_PX), (QR_PAD, QR_PAD))
    cy = top + (h - side) // 2
    if not dark:                    # on a dark ground the card needs no lift
        sh, pad = soft_shadow((side, side), CARD_R, 22, alpha=48, dy=10)
        img.alpha_composite(sh, (x0 - pad, cy - pad))
    img.alpha_composite(card, (x0, cy))

    bx, by = x0 + side + COL_GAP, top + (h - stack) // 2
    img.alpha_composite(ab, (bx, by))
    img.alpha_composite(gb, (bx, by + ab.height + BADGE_GAP))
    return top + h


def draw_address(img, y_mid, dark, accent, text_col=None):
    """Pin, the store address, then the website, on one centred line."""
    d = ImageDraw.Draw(img)
    col = text_col or ((170, 188, 183) if dark else MUTED)
    f, fs = font(F_REG, 44), font(F_SEMI, 44)
    sep = "   ·   "
    if not STORE_ADDRESS:                         # no public address: site alone
        d.text((W // 2, y_mid), SITE, font=fs, fill=col, anchor="mm")
        return
    p = pin(30, accent)
    gap = 18
    total = (p.width + gap + f.getlength(STORE_ADDRESS) + f.getlength(sep)
             + fs.getlength(SITE))
    x = (W - total) / 2
    img.alpha_composite(p, (round(x), round(y_mid - p.height * 0.56)))
    x += p.width + gap
    d.text((x, y_mid), STORE_ADDRESS, font=f, fill=col, anchor="lm")
    x += f.getlength(STORE_ADDRESS)
    d.text((x, y_mid), sep, font=f, fill=col, anchor="lm")
    x += f.getlength(sep)
    d.text((x, y_mid), SITE, font=fs, fill=col, anchor="lm")


def footer_parts(dark):
    """The footer's pieces top to bottom, with the height each occupies."""
    _, block_h = download_block_size(dark)
    eye_h = text_h(font(F_SEMI, 40), "GET THE APP")
    return [("rule", 0), ("gap", 58), ("eyebrow", eye_h), ("gap", 46),
            ("block", block_h), ("gap", 74), ("address", 44), ("gap", FOOT_BOTTOM)]


def footer_height(dark):
    return sum(h for _, h in footer_parts(dark))


def draw_footer(img, dark, accent, rule_col=None, text_col=None):
    """Anchored to the floor. Returns where it starts, so the hero above can
    be sized to whatever room is left. Colours default by `dark`; grounds
    that are neither white nor near-black pass their own."""
    need_links()
    y = top = H - footer_height(dark)
    d = ImageDraw.Draw(img)
    for kind, h in footer_parts(dark):
        if kind == "rule":
            d.line([(W / 2 - 380, y), (W / 2 + 380, y)],
                   fill=rule_col or ((38, 70, 60) if dark else (222, 226, 228)), width=3)
        elif kind == "eyebrow":
            tracked(d, W / 2, y, "GET THE APP", font(F_SEMI, 40), accent, 14)
        elif kind == "block":
            draw_download_block(img, y, dark)
        elif kind == "address":
            draw_address(img, y + h / 2, dark, accent, text_col)
        y += h
    return top


# ── concept 1: the numerals ──────────────────────────────────────────────────

def bloom_from(glyph, blur, strength, colour):
    """Glow cast from a glyph's own silhouette.

    Padded before blurring. Blurring inside the glyph's bounding box clips
    the falloff at the box edges and leaves a visible rectangle round each
    character — which is what the first render of this concept did.
    """
    pad = blur * 3
    a = Image.new("L", (glyph.width + pad * 2, glyph.height + pad * 2), 0)
    a.paste(glyph.split()[3], (pad, pad))
    a = a.filter(ImageFilter.GaussianBlur(blur)).point(lambda v: int(v * strength))
    out = Image.new("RGBA", a.size, colour + (0,))
    out.putalpha(a)
    return out, pad


def concept_numerals(out_dir, number="66"):
    """Night-dark ground, the year's number huge in the national colours.
    Dark so the white band has something to stand against."""
    lg = logo(420, reversed_=True)
    header_bottom = 100 + lg.height
    ftop = H - footer_height(dark=True)

    f_eye, f_lab, f_sub = font(F_SEMI, 44), font(F_SEMI, 76), font(F_REG, 58)
    digits = [glyph_in_tricolour(ch, font(F_BOLD, 1180)) for ch in number]
    dh = digits[0].height
    sub = ["And a happy new month from", f"all of us at {NAME}."]
    sub_lh = 82
    eye_h, lab_h = text_h(f_eye, "HAPPY"), text_h(f_lab, "NIGERIA")
    sub_h = sub_lh * (len(sub) - 1) + text_h(f_sub, "Ag")
    block = eye_h + 34 + lab_h + 84 + dh + 96 + sub_h
    lo, hi = header_bottom + 70, ftop - 80
    assert block <= hi - lo, f"numerals: hero needs {block}px, has {hi - lo}"
    y0 = lo + (hi - lo - block) // 2
    num_top = y0 + eye_h + 34 + lab_h + 84

    base = Image.new("RGB", (W, H), NIGHT)
    arr = np.array(base).astype(np.float32)
    lift = np.linspace(1.0, 0.0, H, dtype=np.float32)[:, None, None] ** 2
    arr += lift * np.array([10, 22, 20], np.float32)
    base = Image.fromarray(arr.clip(0, 255).astype(np.uint8))
    base = glow(base, W * 0.5, num_top + dh / 2, W * 0.62, H * 0.30, NG_GREEN, 0.26, 1.8)

    # A brand photograph, if there is one, set behind the digits. Two-tone
    # and faint: atmosphere, not a photograph.
    aisle = store_photo("wide")
    if aisle is not None:
        s = 2.3
        a2 = aisle.resize((round(aisle.width * s), round(aisle.height * s)), Image.LANCZOS)
        a2 = duotone(a2, NIGHT, (62, 158, 116), contrast=1.15)
        tx, ty = W / 2, num_top + dh * 0.5
        layer = Image.new("RGB", (W, H), NIGHT)
        layer.paste(a2, (round(tx - 0.57 * a2.width), round(ty - 0.42 * a2.height)))
        yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
        dd = np.sqrt(((xx - tx) / (W * 0.62)) ** 2 + ((yy - ty) / (H * 0.52)) ** 2)
        m = Image.fromarray((np.clip(1 - dd, 0, 1) ** 1.2 * 0.42 * 255).astype(np.uint8))
        base = Image.composite(layer, base, m)
    img = grain(base).convert("RGBA")

    img.alpha_composite(lg, ((W - lg.width) // 2, 100))
    d = ImageDraw.Draw(img)
    tracked(d, W / 2, y0, "HAPPY INDEPENDENCE DAY", f_eye, NG_LIGHT, 14)
    tracked(d, W / 2, y0 + eye_h + 34, "NIGERIA AT", f_lab, WHITE, 22)

    gap = 64
    total = sum(g.width for g in digits) + gap * (len(digits) - 1)
    x = (W - total) // 2
    for g in digits:
        b, pad = bloom_from(g, 70, 0.55, (30, 170, 105))
        img.alpha_composite(b, (x - pad, num_top - pad + 14))
        x += g.width + gap
    x = (W - total) // 2
    for g in digits:
        img.alpha_composite(g, (x, num_top))
        x += g.width + gap

    d = ImageDraw.Draw(img)
    y = num_top + dh + 96
    for line in sub:
        d.text((W // 2, y), line, font=f_sub, fill=(214, 226, 222), anchor="ma")
        y += sub_lh

    draw_footer(img, dark=True, accent=NG_LIGHT)
    return export(img, "independence-numerals", out_dir)


# ── concept 2: the calendar ──────────────────────────────────────────────────

def calendar_page(size, month, day, weekday, header, day_fill, muted=False):
    """One page of a desk calendar: coloured header, huge date, weekday."""
    w, h = size
    page = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(page)
    r = 64
    d.rounded_rectangle([0, 0, w - 1, h - 1], r, fill=WHITE + (255,))
    hh = round(h * 0.25)
    band = Image.new("L", size, 0)
    ImageDraw.Draw(band).rounded_rectangle([0, 0, w - 1, h - 1], r, fill=255)
    ImageDraw.Draw(band).rectangle([0, hh, w, h], fill=0)
    page.paste(Image.new("RGBA", size, header + (255,)), (0, 0), band)

    for x in range(40, w - 30, 34):            # perforation under the header
        d.ellipse([x, hh - 7, x + 10, hh + 3], fill=(255, 255, 255, 110))

    tracked(d, w / 2, hh * 0.30, month, font(F_SEMI, round(hh * 0.30)), WHITE,
            round(hh * 0.10))

    f_day = font(F_BOLD, round(h * 0.56))
    bb = f_day.getbbox(day)
    gy = hh + round((h - hh - (bb[3] - bb[1])) * 0.36) - bb[1]
    d.text((w / 2, gy), day, font=f_day, fill=day_fill, anchor="ma")
    wy = gy + bb[3] + round(h * 0.05)
    tracked(d, w / 2, wy, weekday, font(F_SEMI, round(h * 0.045)),
            (150, 156, 160) if muted else MUTED, round(h * 0.012))
    return page


def concept_calendar(out_dir, month="OCTOBER", prev="SEPTEMBER", prev_day="30",
                     weekday="THURSDAY", prev_weekday="WEDNESDAY",
                     headline="Here’s to Nigeria",
                     subline=("Happy Independence Day, and a happy",
                              f"new month from all of us at {NAME}.")):
    """The page has just turned. September sits behind, tilted back where it
    was flipped; October stands in front in the flag green. One image
    carries both messages, and changing the months makes it next month's
    post."""
    lg = logo(450)
    header_bottom = 100 + lg.height
    ftop = H - footer_height(dark=False)

    C = 860
    cw = round(C * 0.90)
    hh = round(C * 0.25)
    label_px = round(hh * 0.30)
    label_bottom = round(hh * 0.30) + label_px   # bottom of the month label, in-page
    tilt = 7
    ring_top = 70                                # rings rise this far above October
    # September's label has to clear the rings, with room for the tilt to
    # drop the end of the word nearest them.
    clearance = ring_top + 60
    sep_drop = clearance + label_bottom          # how far September sits above October
    lift = round((cw / 2) * math.sin(math.radians(tilt)))
    peek = sep_drop + lift                       # its highest corner above October's top

    f_head, f_sub = font(F_BOLD, 112), font(F_REG, 54)
    head_h = text_h(f_head, headline)
    sub_lh = 76
    sub_h = sub_lh * (len(subline) - 1) + text_h(f_sub, "Ag")
    block = peek + C + 96 + head_h + 36 + sub_h
    lo, hi = header_bottom + 70, ftop - 70
    assert block <= hi - lo, f"calendar: needs {block}px, has {hi - lo}"
    T = lo + (hi - lo - block) // 2 + peek        # October's top edge
    cx, cy = W // 2, T + C // 2

    base = Image.new("RGB", (W, H), WHITE)
    base = glow(base, W * 0.5, cy - 60, W * 0.70, H * 0.34, (205, 236, 218), 0.85, 1.4)
    base = glow(base, W * 0.5, cy - 60, W * 0.34, H * 0.17, (160, 218, 186), 0.45, 1.5)
    img = base.convert("RGBA")
    img.alpha_composite(lg, ((W - lg.width) // 2, 100))

    # September: behind, raised, tilted back. Offset only slightly left so
    # its "30" stays hidden behind October instead of peeking out as a stray
    # grey curve.
    sep = calendar_page((cw, C), prev, prev_day, prev_weekday,
                        header=(170, 179, 186), day_fill=(200, 206, 211), muted=True)
    sep_rot = sep.rotate(-tilt, resample=Image.BICUBIC, expand=True)
    sh, _ = soft_shadow((cw, C), 64, 50, alpha=40, dy=24)
    sh = sh.rotate(-tilt, resample=Image.BICUBIC, expand=True)
    sx, sy = cx - 70, cy - sep_drop
    for layer in (sh, sep_rot):
        img.alpha_composite(layer, (sx - layer.width // 2, sy - layer.height // 2))

    octo = calendar_page((cw, C), month, "1", weekday, header=NG_GREEN,
                         day_fill=NG_GREEN)
    sh2, pad2 = soft_shadow((cw, C), 64, 60, alpha=72, dy=40)
    img.alpha_composite(sh2, (cx - cw // 2 - pad2, T - pad2))
    img.alpha_composite(octo, (cx - cw // 2, T))

    d = ImageDraw.Draw(img)
    for rx in (cx - round(cw * 0.30), cx, cx + round(cw * 0.30)):
        d.rounded_rectangle([rx - 24, T - ring_top, rx + 24, T + 42], 24, fill=(40, 48, 52))
        d.rounded_rectangle([rx - 11, T - ring_top + 13, rx + 11, T + 29], 11,
                            fill=(92, 102, 108))

    y = T + C + 96
    d.text((W // 2, y), headline, font=f_head, fill=INK, anchor="ma")
    y += head_h + 36
    for line in subline:
        d.text((W // 2, y), line, font=f_sub, fill=MUTED, anchor="ma")
        y += sub_lh

    draw_footer(img, dark=False, accent=NG_GREEN)
    return export(img, "independence-calendar", out_dir)


# ── concept 3: the receipt ───────────────────────────────────────────────────

def zigzag_mask(w, h, tooth=28, depth=18):
    """A torn-off till receipt: serrated top and bottom edges."""
    pts = []
    for x in range(0, w + 1, tooth):
        pts.append((x, depth if (x // tooth) % 2 == 0 else 0))
    pts += [(w, depth), (w, h - depth)]
    for x in range(w, -1, -tooth):
        pts.append((x, h - depth if (x // tooth) % 2 == 0 else h))
    pts.append((0, h - depth))
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).polygon(pts, fill=255)
    return m


def receipt_paper():
    """The receipt itself, before it is torn, tilted and shadowed."""
    need_links()
    rw = 1180
    paper = Image.new("RGBA", (rw, 2600), (253, 253, 251, 255))
    d = ImageDraw.Draw(paper)
    ink, grey = (26, 28, 30), (95, 99, 103)
    pad = 100
    lh = 68
    f, fb = mono(46), mono(46, bold=True)
    y = 100

    lg = logo(580)
    paper.alpha_composite(lg, ((rw - lg.width) // 2, y))
    y += lg.height + 48

    def centre(t, fnt, fill=ink, step=lh):
        nonlocal y
        d.text((rw // 2, y), t, font=fnt, fill=fill, anchor="ma")
        y += step

    def row(left, right, fnt=f, fill=ink):
        nonlocal y
        d.text((pad, y), left, font=fnt, fill=fill)
        d.text((rw - pad, y), right, font=fnt, fill=fill, anchor="ra")
        y += lh

    def rule():
        nonlocal y
        y += 10
        for x in range(pad, rw - pad, 26):
            d.line([(x, y), (x + 13, y)], fill=(150, 154, 158), width=3)
        y += 44

    # a real receipt heads with where you bought it
    if STORE_ADDRESS:
        centre(STORE_ADDRESS.upper(), f, grey)
    else:
        centre(SITE.upper(), f, grey)
    centre("NIGERIA", f, grey)
    rule()
    # One value per line. The receipt is tilted, which drops a right-aligned
    # column by most of a line height and set "066" floating between rows.
    row("RECEIPT NO. 066", "", f, grey)
    row("THU 01 OCT 2026", "", f, grey)
    rule()
    row("QTY  ITEM", "", fb)
    y += 6
    for qty, item in [("1", "Independence Day"), ("1", "New month"),
                      ("66", "Years together")]:
        d.text((pad, y), qty, font=f, fill=ink)
        d.text((pad + 150, y), item, font=f, fill=ink)
        y += lh
    rule()
    d.text((pad, y + 4), "TOTAL", font=mono(56, bold=True), fill=ink)
    d.text((rw - pad, y + 4), "NOT FOR SALE", font=mono(56, bold=True),
           fill=NG_GREEN, anchor="ra")
    y += 96
    rule()
    y += 14
    centre("THANK YOU, NIGERIA", mono(52, bold=True), step=0)
    y += 70

    # the QR sits where a barcode would, with a full quiet zone around it
    qpx, quiet = 380, 56
    y += quiet
    paper.paste(qr_image(APP_URL, qpx), ((rw - qpx) // 2, y))
    y += qpx + quiet
    centre("SCAN TO GET THE APP", mono(40, bold=True), ink, step=0)
    y += 60 + 84

    paper = paper.crop((0, 0, rw, y))
    torn = Image.new("RGBA", paper.size, (0, 0, 0, 0))
    torn.paste(paper, (0, 0), zigzag_mask(rw, y))
    return torn


def concept_receipt(out_dir):
    """The brand's receipt for the day. The line items are the occasion; the
    total reads NOT FOR SALE, because independence is the one thing that
    never goes on the market."""
    rot = receipt_paper().rotate(-2.5, resample=Image.BICUBIC, expand=True)

    f_msg = font(F_REG, 56)
    msg = "Happy Independence Day, and a happy new month."
    msg_h = text_h(f_msg, msg)
    bw, bgap = 500, 40
    ab = store_badge("app-store", bw)
    gb = store_badge("google-play", bw)
    badges_h = max(ab.height, gb.height)
    site_h = text_h(font(F_SEMI, 46), SITE)

    stack = rot.height + 96 + msg_h + 70 + badges_h + 64 + site_h
    lo, hi = 70, H - FOOT_BOTTOM
    assert stack <= hi - lo, f"receipt: needs {stack}px, has {hi - lo}"
    top = lo + (hi - lo - stack) // 2

    base = Image.new("RGB", (W, H), WHITE)
    base = glow(base, W * 0.5, top + rot.height * 0.45, W * 0.72, H * 0.40,
                (205, 236, 218), 0.85, 1.4)
    base = glow(base, W * 0.5, top + rot.height * 0.45, W * 0.34, H * 0.20,
                (165, 220, 190), 0.40, 1.5)
    img = base.convert("RGBA")

    shadow = Image.new("RGBA", (rot.width + 240, rot.height + 240), (0, 0, 0, 0))
    shadow.paste(Image.new("RGBA", rot.size, (0, 40, 25, 70)), (120, 150),
                 rot.split()[3])
    shadow = shadow.filter(ImageFilter.GaussianBlur(40))
    img.alpha_composite(shadow, ((W - shadow.width) // 2, top - 120))
    img.alpha_composite(rot, ((W - rot.width) // 2, top))

    d = ImageDraw.Draw(img)
    y = top + rot.height + 96
    d.text((W // 2, y), msg, font=f_msg, fill=MUTED, anchor="ma")
    y += msg_h + 70
    x0 = (W - (bw * 2 + bgap)) // 2
    img.alpha_composite(ab, (x0, y + (badges_h - ab.height) // 2))
    img.alpha_composite(gb, (x0 + bw + bgap, y + (badges_h - gb.height) // 2))
    y += badges_h + 64
    d.text((W // 2, y), SITE, font=font(F_SEMI, 46), fill=MUTED, anchor="ma")
    return export(img, "independence-receipt", out_dir)


# ── shared: SF Pro, wrapping, text on a circle ───────────────────────────────

SF = "/System/Library/Fonts/SFNS.ttf"


def sf(size, weight=400):
    """SF Pro at a given weight, for anything that imitates iOS itself. The
    variable font's axes run Width, Optical Size, Grade, Weight — in that
    order, so the weight goes last."""
    f = ImageFont.truetype(SF, size)
    f.set_variation_by_axes([100, 96 if size >= 120 else 24, 400, weight])
    return f


def wrap(text, f, width):
    words, lines, cur = text.split(), [], ""
    for w in words:
        t = f"{cur} {w}".strip()
        if f.getlength(t) <= width:
            cur = t
        else:
            lines.append(cur)
            cur = w
    return lines + ([cur] if cur else [])


def text_on_arc(img, cx, cy, radius, text, f, fill, centre_deg=-90, bottom=False,
                track=0):
    """Set text around a circle, centred on `centre_deg` (-90 is the top).
    Top text reads clockwise; bottom text reads left to right, upright."""
    widths = [f.getlength(ch) + track for ch in text]
    span = sum(widths) / radius
    step = -1 if bottom else 1
    a = math.radians(centre_deg) - step * span / 2
    for ch, w in zip(text, widths):
        mid = a + step * (w / 2) / radius
        if ch.strip():
            gw, gh = int(f.getlength(ch)) + 24, int(f.size * 1.8)
            g = Image.new("RGBA", (gw, gh), (0, 0, 0, 0))
            ImageDraw.Draw(g).text((gw / 2, gh / 2), ch, font=f, fill=fill, anchor="mm")
            deg = math.degrees(mid)
            g = g.rotate((-deg + 90) if bottom else (-deg - 90), resample=Image.BICUBIC,
                         expand=True)
            x, y = cx + radius * math.cos(mid), cy + radius * math.sin(mid)
            img.alpha_composite(g, (int(x - g.width / 2), int(y - g.height / 2)))
        a += step * w / radius


def rotated_point(size, angle, pt):
    """Where `pt` lands after Image.rotate(angle, expand=True)."""
    w, h = size
    t = math.radians(angle)
    vx, vy = pt[0] - w / 2, pt[1] - h / 2
    nw = abs(w * math.cos(t)) + abs(h * math.sin(t))
    nh = abs(w * math.sin(t)) + abs(h * math.cos(t))
    return (nw / 2 + vx * math.cos(t) + vy * math.sin(t),
            nh / 2 - vx * math.sin(t) + vy * math.cos(t))


def light_ground(cy, strength=1.0):
    base = Image.new("RGB", (W, H), WHITE)
    base = glow(base, W * 0.5, cy, W * 0.70, H * 0.36, (205, 236, 218), 0.85 * strength, 1.4)
    base = glow(base, W * 0.5, cy, W * 0.34, H * 0.18, (165, 220, 190), 0.42 * strength, 1.5)
    return base


def centred_stack(parts_h, lo, hi, label):
    total = sum(parts_h)
    assert total <= hi - lo, f"{label}: needs {total}px, has {hi - lo}"
    return lo + (hi - lo - total) // 2


# ── brand photography ────────────────────────────────────────────────────────
#
# assets/photos/ takes the brand's own photographs, one file per slot. Every
# slot is optional: the numerals drop their background, the stamp engraves
# the mark, the lock screen falls back to a green gradient, and the triptych
# (which is nothing but photographs) is skipped. Every use grades the photo
# to two tones or keeps it small, so soft sources read as style rather than
# as low resolution.

PHOTO_SLOTS = ("hero", "wide", "detail")


def store_photo(name):
    """A brand photo from assets/photos/, or None if that slot is empty.
    Slots: hero (the stamp picture), wide (backgrounds and the lock-screen
    wallpaper), detail (the triptych's third panel)."""
    path = os.path.join(ASSETS, "photos", f"{name}.jpg")
    return Image.open(path).convert("RGB") if os.path.exists(path) else None


def cover(im, size, focus=(0.5, 0.5)):
    """Scale to fill `size`, cropping around `focus` (fractions of the image)."""
    tw, th = size
    s = max(tw / im.width, th / im.height)
    r = im.resize((max(tw, round(im.width * s)), max(th, round(im.height * s))),
                  Image.LANCZOS)
    x = round((r.width - tw) * focus[0])
    y = round((r.height - th) * focus[1])
    return r.crop((x, y, x + tw, y + th))


def duotone(im, dark, light, contrast=1.0, gamma=1.0):
    """Map luminance onto a two-colour ramp, the way a print in two inks
    would. Also the reason soft source photos look intentional."""
    g = np.array(im.convert("L")).astype(np.float32) / 255.0
    g = np.clip((g - 0.5) * contrast + 0.5, 0, 1) ** gamma
    d, l = np.array(dark, np.float32), np.array(light, np.float32)
    return Image.fromarray((d + (l - d) * g[..., None]).clip(0, 255).astype(np.uint8))


def tracked_left(d, x, y, text, f, fill, track):
    for ch in text:
        d.text((x, y), ch, font=f, fill=fill)
        x += f.getlength(ch) + track
    return x


# ── concept 4: the stamp ─────────────────────────────────────────────────────

def perforation_mask(w, h, r=20, pitch=62):
    """Stamp perforation: semicircles bitten out of every edge."""
    ss = 2
    m = Image.new("L", (w * ss, h * ss), 255)
    d = ImageDraw.Draw(m)
    R = r * ss
    for length, horiz in ((w, True), (h, False)):
        n = max(2, round(length / pitch))
        for i in range(n + 1):
            p = i * length * ss / n
            if horiz:
                for e in (0, h * ss):
                    d.ellipse([p - R, e - R, p + R, e + R], fill=0)
            else:
                for e in (0, w * ss):
                    d.ellipse([e - R, p - R, e + R, p + R], fill=0)
    return m.resize((w, h), Image.LANCZOS)


def stamp_face(w, h):
    """A commemorative stamp.

    Stamps have always shown places, and they have always carried their
    value in a corner. So the picture is printed in green ink the way an
    engraved stamp would be, and the value is 66. With a hero photograph
    that is the photograph; without one it is the brand's mark. Employi's
    is a map pin, which is a place.
    """
    im = Image.new("RGBA", (w, h), (250, 249, 244, 255))
    d = ImageDraw.Draw(im)
    inset = 54
    x0, y0, x1, y1 = inset, inset, w - inset, h - inset
    band_t, band_b, side = 196, 118, 22
    d.rectangle([x0, y0, x1, y1], fill=NG_GREEN + (255,))

    # the picture, in one ink
    px0, py0, px1, py1 = x0 + side, y0 + band_t, x1 - side, y1 - band_b
    photo = store_photo("hero")
    if photo is None:
        # No photograph: engrave the mark itself, in one ink. Employi's is a
        # map pin, a place, which is what a stamp shows.
        pic = Image.new("RGB", (px1 - px0, py1 - py0), (0, 58, 36))
        raw = Image.open(brand.MARK).convert("RGBA")
        raw = raw.crop(raw.getbbox())
        # 70% of the width suits a wide mark; a tall one (Employi's pin is
        # 0.77:1) is held to 78% of the height instead, or it touches the frame.
        mw = round(min(pic.width * 0.70, pic.height * 0.78 * raw.width / raw.height))
        raw = raw.resize((mw, round(raw.height * mw / raw.width)), Image.LANCZOS)
        cream = Image.new("RGBA", raw.size, (244, 242, 226, 255))
        cream.putalpha(raw.split()[3])
        pic.paste(cream, ((pic.width - raw.width) // 2, (pic.height - raw.height) // 2), cream)
        photo_mode = False
    else:
        pic = cover(photo, (px1 - px0, py1 - py0), focus=(0.5, 0.33))
        photo_mode = True
    # Gamma above 1 pulls the mid-tones down, so bright areas of a photo
    # (signage, sky) keep their detail instead of printing as one pale strip.
    if photo_mode:
        pic = duotone(pic, (0, 58, 36), (244, 242, 226), contrast=1.1, gamma=1.45)
    lines = pic.copy()
    ld = ImageDraw.Draw(lines)
    for yy in range(0, lines.height, 7):            # intaglio line screen
        ld.line([(0, yy), (lines.width, yy)], fill=(0, 58, 36), width=1)
    im.paste(Image.blend(pic, lines, 0.45), (px0, py0))
    d.rectangle([px0, py0, px1, py1], outline=(214, 238, 226, 255), width=4)

    # header: country and years on the left, the value on the right
    tracked_left(d, px0 + 6, y0 + 34, "NIGERIA", font(F_SEMI, 68), WHITE, 18)
    tracked_left(d, px0 + 8, y0 + 124, "1960 · 2026", font(F_SEMI, 38),
                 (206, 236, 220), 6)
    d.text((px1 - 4, y0 + band_t / 2 + 4), "66", font=font(F_BOLD, 176), fill=WHITE,
           anchor="rm")

    tracked(d, w / 2, y1 - band_b + 40, "YEARS OF INDEPENDENCE", font(F_SEMI, 38),
            (214, 238, 226), 9)

    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.paste(im, (0, 0), perforation_mask(w, h))
    return out


def postmark(size, ink=(30, 34, 40), wave_len=None):
    """A machine cancellation: the round date stamp on the right, the wavy
    'killer' lines running left from it across the stamp.

    That is how the post office actually strikes them, and it is also what
    keeps the dater legible: its ring text sits on the white envelope, while
    only the lines cross the stamp. The first version put the ring over the
    stamp's dark green frame and the text vanished into it.

    Ink wear is mottled low-frequency noise, so it reads as struck, not drawn.
    """
    s = size
    wl = int(s * 1.25) if wave_len is None else wave_len
    pw = wl + s
    im = Image.new("RGBA", (pw, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    col = ink + (230,)
    cx, cy = pw - s / 2, s / 2
    R = s / 2 - 12
    r2 = R * 0.64
    d.ellipse([cx - R, cy - R, cx + R, cy + R], outline=col, width=10)
    d.ellipse([cx - r2, cy - r2, cx + r2, cy + r2], outline=col, width=6)
    f_ring = font(F_SEMI, int(R * 0.16))
    ring = (R + r2) / 2
    text_on_arc(im, cx, cy, ring, NAME.upper(), f_ring, col, -90, track=9)
    text_on_arc(im, cx, cy, ring, "NIGERIA", f_ring, col, 90, bottom=True, track=10)
    d.text((cx, cy - r2 * 0.22), "01 OCT", font=font(F_BOLD, int(r2 * 0.40)), fill=col,
           anchor="mm")
    d.text((cx, cy + r2 * 0.36), "2026", font=font(F_SEMI, int(r2 * 0.30)), fill=col,
           anchor="mm")
    xe = cx - R - 26
    for i in range(5):
        yy = cy - R * 0.56 + i * R * 0.28
        pts = [(x, yy + math.sin(x / 58) * 16) for x in range(10, int(xe), 3)]
        d.line(pts, fill=col, width=8)

    a = np.array(im.split()[3]).astype(np.float32)
    rng = np.random.default_rng(66)
    n = Image.fromarray((rng.random((s // 6 + 1, pw // 6 + 1)) * 255).astype(np.uint8))
    n = np.array(n.resize((pw, s), Image.BICUBIC).filter(ImageFilter.GaussianBlur(3))) / 255.0
    a *= np.clip(0.35 + n * 1.1, 0.25, 1.0)
    im.putalpha(Image.fromarray(a.clip(0, 255).astype(np.uint8)))
    return im, (cx, cy)


def concept_stamp(out_dir):
    """A commemorative stamp, franked on the day.

    The headline is a letter's sign-off, not a boast. "First class since
    1960" was the obvious pun, and exactly the kind of line that invites
    "what are we celebrating?" in the replies."""
    lg = logo(450)
    header_bottom = 100 + lg.height
    ftop = H - footer_height(dark=False)

    face = stamp_face(860, 1080)
    tilt = 3
    rot = face.rotate(tilt, resample=Image.BICUBIC, expand=True)
    f_head, f_sub = font(F_BOLD, 112), font(F_REG, 54)
    headline = "With love, to Nigeria"
    sub = ["Happy Independence Day, and a happy", f"new month from all of us at {NAME}."]
    head_h = text_h(f_head, headline)
    sub_h = 76 * (len(sub) - 1) + text_h(f_sub, "Ag")
    top = centred_stack([rot.height, 100, head_h, 36, sub_h],
                        header_bottom + 60, ftop - 70, "stamp")

    sx = (W - rot.width) // 2 - 150                 # off-centre, to balance the postmark
    img = light_ground(top + rot.height / 2).convert("RGBA")
    img.alpha_composite(lg, ((W - lg.width) // 2, 100))
    sh = Image.new("RGBA", (rot.width + 200, rot.height + 200), (0, 0, 0, 0))
    sh.paste(Image.new("RGBA", rot.size, (0, 40, 25, 60)), (100, 124), rot.split()[3])
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(30)), (sx - 100, top - 100))
    img.alpha_composite(rot, (sx, top))

    # The cancellation strikes the picture's right edge, where a clerk's
    # stamp would land, and nothing with words in it: the first render put
    # it across "YEARS OF INDEPENDENCE" and the two texts tangled.
    pm, (pcx, pcy) = postmark(440)
    ang = -12
    pmr = pm.rotate(ang, resample=Image.BICUBIC, expand=True)
    ccx, ccy = rotated_point(pm.size, ang, (pcx, pcy))
    target = (sx + rot.width + 190, top + rot.height * 0.55)
    img.alpha_composite(pmr, (int(target[0] - ccx), int(target[1] - ccy)))

    d = ImageDraw.Draw(img)
    y = top + rot.height + 100
    d.text((W // 2, y), headline, font=f_head, fill=INK, anchor="ma")
    y += head_h + 36
    for line in sub:
        d.text((W // 2, y), line, font=f_sub, fill=MUTED, anchor="ma")
        y += 76
    draw_footer(img, dark=False, accent=NG_GREEN)
    return export(img, "independence-stamp", out_dir)


# ── concept 5: the lock screen ───────────────────────────────────────────────

def app_icon(size):
    """The real App Store icon, rounded to iOS's corner radius."""
    im = Image.open(os.path.join(ASSETS, "brand", "app-icon.png")).convert("RGBA")
    im = im.resize((size * 2, size * 2), Image.LANCZOS)
    m = Image.new("L", im.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, im.width - 1, im.height - 1],
                                        round(im.width * 0.2237), fill=255)
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    out.paste(im, (0, 0), m)
    return out.resize((size, size), Image.LANCZOS)


def padlock(width, col):
    """The lock-screen padlock: rounded body, arched shackle."""
    ss = 4
    s = width * ss
    hgt = int(s * 1.3)
    im = Image.new("RGBA", (s, hgt), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    body_top = int(s * 0.58)
    d.rounded_rectangle([0, body_top, s - 1, hgt - 1], int(s * 0.16), fill=col)
    t = int(s * 0.13)
    d.arc([int(s * 0.17), int(s * 0.02), int(s * 0.83), int(s * 0.68)], 180, 360,
          fill=col, width=t)
    d.rectangle([int(s * 0.17), int(s * 0.35), int(s * 0.17) + t, body_top + 4], fill=col)
    d.rectangle([int(s * 0.83) - t, int(s * 0.35), int(s * 0.83), body_top + 4], fill=col)
    return im.resize((width, int(hgt / ss)), Image.LANCZOS)


def frosted(img, box, radius, tint=(250, 252, 250), strength=0.74, blur=42):
    """iOS notification glass: the wallpaper behind the card, blurred and
    washed toward white. Built from what is actually behind it, so the card
    picks up the photo's colour the way the real one does."""
    x0, y0, x1, y1 = box
    pad = blur * 2
    region = img.crop((x0 - pad, y0 - pad, x1 + pad, y1 + pad)).convert("RGB")
    region = region.filter(ImageFilter.GaussianBlur(blur)).crop(
        (pad, pad, pad + x1 - x0, pad + y1 - y0))
    wash = Image.new("RGB", region.size, tint)
    glass = Image.blend(region, wash, strength).convert("RGBA")
    m = Image.new("L", region.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, region.width - 1, region.height - 1],
                                        radius, fill=255)
    glass.putalpha(m)
    return glass


def concept_lockscreen(out_dir):
    """The whole post is a phone at midnight on 1 October. The clock has
    just turned, and a notification from the app carries the greeting: the push
    the app could actually send."""
    ftop = H - footer_height(dark=True)

    # Wallpaper: the wide photograph printed in green, or a green gradient
    # without one. Shaded at the top for the clock and at the bottom for the
    # notification and footer. Avoid a photo with large signage in it: at
    # wallpaper scale a sign becomes the biggest word on the post after the
    # clock.
    photo = store_photo("wide")
    if photo is not None:
        wall = duotone(cover(photo, (W, H), focus=(0.5, 0.46)), (0, 30, 20),
                       (156, 226, 192), contrast=1.2)
    else:
        t = np.linspace(0, 1, H, dtype=np.float32)[:, None, None]
        grad = (np.array([0, 116, 72], np.float32) * (1 - t)
                + np.array([0, 40, 28], np.float32) * t)
        wall = Image.fromarray(np.broadcast_to(grad, (H, W, 3)).clip(0, 255).astype(np.uint8))
        wall = glow(wall, W * 0.16, H * 0.10, W * 0.60, H * 0.32, (70, 196, 136), 0.55, 1.6)
        wall = glow(wall, W * 0.90, H * 0.58, W * 0.55, H * 0.32, (0, 150, 96), 0.45, 1.6)
    arr = np.array(wall).astype(np.float32)
    yy = np.linspace(0, 1, H, dtype=np.float32)[:, None, None]
    top_shade = np.clip(1 - yy / 0.40, 0, 1) ** 1.5 * 0.62
    bot_shade = np.clip((yy - 0.52) / 0.24, 0, 1) ** 1.1 * 0.90
    arr *= 1 - np.maximum(top_shade, bot_shade)
    img = grain(Image.fromarray(arr.clip(0, 255).astype(np.uint8)), 3.0).convert("RGBA")

    lock = padlock(46, (236, 246, 240, 255))
    f_date, f_time = sf(62, 590), sf(500, 680)
    date, clock = "Thursday 1 October", "00:00"
    tb = f_time.getbbox(clock)

    y = 140
    img.alpha_composite(lock, ((W - lock.width) // 2, y))
    y += lock.height + 40
    d = ImageDraw.Draw(img)
    d.text((W // 2, y), date, font=f_date, fill=(236, 246, 240), anchor="ma")
    y += 88
    d.text((W // 2, y - tb[1]), clock, font=f_time, fill=(246, 252, 248), anchor="ma")

    # Notification, bottom-anchored as iOS stacks them now.
    card_w, pad, icon = W - 300, 48, 128
    f_title, f_body, f_now = sf(60, 650), sf(56, 420), sf(48, 420)
    title = "Happy Independence Day, Nigeria"
    body = f"66 years today, and a brand new month to go with it. From all of us at {NAME}."
    text_w = card_w - pad * 2 - icon - 38
    t_lines = wrap(title, f_title, text_w - f_now.getlength("now") - 24)
    b_lines = wrap(body, f_body, text_w)
    lh_t, lh_b = 74, 70
    card_h = max(icon, lh_t * len(t_lines) + 6 + lh_b * len(b_lines)) + pad * 2
    cx0 = (W - card_w) // 2
    cy0 = ftop - 120 - card_h

    # A second notification tucked beneath, so this reads as a stack. It is
    # drawn first and only its lower lip shows: the earlier version let it
    # show through the card and slice across the last line of text.
    gx0, gx1 = cx0 + 52, cx0 + card_w - 52
    img.alpha_composite(frosted(img, (gx0, cy0 + card_h - 40, gx1, cy0 + card_h + 30), 44,
                                strength=0.40), (gx0, cy0 + card_h - 40))
    sh, sp = soft_shadow((card_w, card_h), 58, 40, colour=(0, 20, 12), alpha=60, dy=18)
    img.alpha_composite(sh, (cx0 - sp, cy0 - sp))
    img.alpha_composite(frosted(img, (cx0, cy0, cx0 + card_w, cy0 + card_h), 58),
                        (cx0, cy0))

    d = ImageDraw.Draw(img)
    img.alpha_composite(app_icon(icon), (cx0 + pad, cy0 + pad))
    tx = cx0 + pad + icon + 38
    d.text((cx0 + card_w - pad, cy0 + pad + 4), "now", font=f_now, fill=(96, 104, 108),
           anchor="ra")
    ty = cy0 + pad
    for ln in t_lines:
        d.text((tx, ty), ln, font=f_title, fill=(10, 14, 18))
        ty += lh_t
    ty += 6
    for ln in b_lines:
        d.text((tx, ty), ln, font=f_body, fill=(34, 40, 44))
        ty += lh_b

    draw_footer(img, dark=True, accent=WHITE, rule_col=(60, 110, 88),
                text_col=(214, 236, 224))
    return export(img, "independence-lockscreen", out_dir)


# ── concept 6: the care label ────────────────────────────────────────────────

def linen(w, h):
    """Off-white woven cloth: warp, weft and a little slub. Thread pitch is
    kept to 10px at 2x so it doesn't alias into moire when downsampled."""
    rng = np.random.default_rng(12)
    yy = np.arange(h, dtype=np.float32)[:, None]
    xx = np.arange(w, dtype=np.float32)[None, :]
    base = (243.0 + 2.2 * np.sin(yy * 2 * np.pi / 10) + 2.2 * np.sin(xx * 2 * np.pi / 10))
    slub = rng.normal(0, 1, (h // 10 + 1, w // 10 + 1))
    slub = (slub - slub.min()) / np.ptp(slub) * 255
    slub = np.array(Image.fromarray(slub.astype(np.uint8)).resize((w, h), Image.BICUBIC),
                    np.float32)
    base = base + (slub - 128) * 0.04 + rng.normal(0, 1.4, (h, w))
    rgb = np.stack([base, base - 1.5, base - 5.0], axis=-1)
    return Image.fromarray(rgb.clip(0, 255).astype(np.uint8))


def woven_label(w, h):
    """A green woven garment label, folded and stitched at the top."""
    lab = Image.new("RGBA", (w, h), NG_GREEN + (255,))
    d = ImageDraw.Draw(lab)
    for yy in range(0, h, 6):                       # the weave's fine ribs
        d.line([(0, yy), (w, yy)], fill=(0, 124, 74, 255), width=2)
    fold = 70
    d.rectangle([0, 0, w, fold], fill=(0, 104, 63, 255))
    d.line([(0, fold), (w, fold)], fill=(0, 84, 52, 255), width=5)
    d.line([(0, fold + 5), (w, fold + 5)], fill=(40, 168, 112, 255), width=2)
    for x in range(36, w - 40, 46):                 # the stitching
        d.rounded_rectangle([x, fold // 2 - 6, x + 26, fold // 2 + 6], 6,
                            fill=(236, 242, 236, 255))

    relief = (0, 86, 52)

    def woven(y, text, f, track, fill=WHITE):
        tracked(d, w / 2, y + 3, text, f, relief, track)   # woven relief under the type
        tracked(d, w / 2, y, text, f, fill, track)

    cx = w / 2
    y = fold + 90
    woven(y, "MADE IN", font(F_SEMI, 62), 22)
    y += 96
    woven(y, "NIGERIA", font(F_BOLD, 168), 10)
    y += 214
    d.line([(cx - 250, y), (cx + 250, y)], fill=(170, 218, 196, 255), width=3)
    y += 58
    for line in ("100% NIGERIAN", "COLOURFAST SINCE 1960", "HANDLE WITH LOVE"):
        woven(y, line, font(F_SEMI, 50), 9, (232, 246, 238))
        y += 78
    y += 20
    d.line([(cx - 250, y), (cx + 250, y)], fill=(170, 218, 196, 255), width=3)
    y += 54
    woven(y, "SIZE", font(F_SEMI, 40), 16, (200, 232, 216))
    y += 70
    bw_, bh_ = 250, 150
    d.rounded_rectangle([cx - bw_ / 2, y, cx + bw_ / 2, y + bh_], 18,
                        outline=(236, 246, 240, 255), width=6)
    d.text((cx, y + bh_ / 2 + 3), "66", font=font(F_BOLD, 104), fill=relief, anchor="mm")
    d.text((cx, y + bh_ / 2), "66", font=font(F_BOLD, 104), fill=WHITE, anchor="mm")
    return lab.crop((0, 0, w, min(h, int(y + bh_ + 90))))


def concept_label(out_dir):
    """A garment label: made in Nigeria, colourfast since 1960 — the colours
    haven't run in sixty-six years."""
    lg = logo(450)
    header_bottom = 100 + lg.height
    ftop = H - footer_height(dark=False)

    lab = woven_label(900, 1400)
    rot = lab.rotate(-2, resample=Image.BICUBIC, expand=True)
    f_head, f_sub = font(F_BOLD, 112), font(F_REG, 54)
    headline = "Happy Independence Day"
    sub = ["And a happy new month from", f"all of us at {NAME}."]
    head_h = text_h(f_head, headline)
    sub_h = 76 * (len(sub) - 1) + text_h(f_sub, "Ag")
    top = centred_stack([rot.height, 96, head_h, 34, sub_h],
                        header_bottom + 60, ftop - 70, "label")

    img = linen(W, H)
    img = glow(img, W * 0.5, top + rot.height / 2, W * 0.60, H * 0.32,
               (214, 236, 222), 0.55, 1.5).convert("RGBA")
    img.alpha_composite(lg, ((W - lg.width) // 2, 100))
    lx = (W - rot.width) // 2
    sh = Image.new("RGBA", (rot.width + 160, rot.height + 160), (0, 0, 0, 0))
    sh.paste(Image.new("RGBA", rot.size, (20, 30, 20, 70)), (80, 96), rot.split()[3])
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(18)), (lx - 80, top - 80))
    img.alpha_composite(rot, (lx, top))

    d = ImageDraw.Draw(img)
    y = top + rot.height + 96
    d.text((W // 2, y), headline, font=f_head, fill=INK, anchor="ma")
    y += head_h + 34
    for line in sub:
        d.text((W // 2, y), line, font=f_sub, fill=MUTED, anchor="ma")
        y += 76
    draw_footer(img, dark=False, accent=NG_GREEN)
    return export(img, "independence-label", out_dir)


# ── concept 7: the departures board ──────────────────────────────────────────

def flap(ch, cw, chh, fg, fnt):
    """One split-flap cell: lighter upper flap, darker lower, hinge between."""
    cell = Image.new("RGBA", (cw, chh), (0, 0, 0, 0))
    d = ImageDraw.Draw(cell)
    r = 7
    d.rounded_rectangle([0, 0, cw - 1, chh - 1], r, fill=(40, 42, 45, 255))
    d.rounded_rectangle([0, chh // 2, cw - 1, chh - 1], r, fill=(30, 32, 35, 255))
    d.rectangle([0, chh // 2, cw - 1, chh // 2 + r], fill=(30, 32, 35, 255))
    if ch.strip():
        d.text((cw / 2, chh / 2 + 1), ch, font=fnt, fill=fg, anchor="mm")
    # The hinge. Thin: at 3px on small cells it read as strikethrough.
    d.line([(0, chh // 2), (cw, chh // 2)], fill=(12, 12, 14, 255), width=2)
    for x in (0, cw - 5):
        d.rectangle([x, chh // 2 - 5, x + 4, chh // 2 + 5], fill=(12, 12, 14, 255))
    return cell


def departures_board(width):
    """An airport board where the months come and go.

    Every column is only as wide as its longest word. Thirty-one columns
    across a 1080px post made each letter smaller than body text on a phone;
    twenty-six, with CELEBRATING swapped for SOARING, got them readable.
    The widths come from the rows, so the brand's name sizes its own column.
    """
    DIM, LIT = (146, 152, 158), (238, 238, 230)
    rows = [("23:59", "SEPTEMBER", "DEPARTED", DIM, DIM),
            ("00:00", "OCTOBER", "ARRIVED", LIT, LIT),
            ("00:00", "NIGERIA 66", "SOARING", LIT, NG_LIGHT),
            ("00:01", f"{NAME.upper()} APP", "BOARDING", LIT, NG_LIGHT)]
    cols = [("TIME", 5), ("DESTINATION", max(len(r[1]) for r in rows)),
            ("STATUS", max(len(r[2]) for r in rows))]
    n = sum(c for _, c in cols) + len(cols) - 1
    padx = 54
    pitch = (width - padx * 2) / n
    cw = int(pitch - 6)
    chh = int(cw * 1.58)
    fnt = mono(int(chh * 0.62), bold=True)
    row_gap = 20
    head_y, cols_y, rows_y = 50, 150, 208
    h = rows_y + len(rows) * (chh + row_gap) + 42

    board = Image.new("RGBA", (width, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(board)
    d.rounded_rectangle([0, 0, width - 1, h - 1], 40, fill=(17, 18, 20, 255))
    d.line([(40, 2), (width - 40, 2)], fill=(58, 60, 64, 255), width=3)
    f_title = font(F_SEMI, 42)
    d.text((padx, head_y), "DEPARTURES  ·  ARRIVALS", font=f_title, fill=(224, 228, 232))
    d.text((width - padx, head_y), "01 OCT 2026", font=f_title, fill=(224, 228, 232),
           anchor="ra")
    d.line([(padx, cols_y - 26), (width - padx, cols_y - 26)], fill=(44, 46, 50, 255), width=2)

    col_x, x = [], padx
    for _, span in cols:
        col_x.append(x)
        x += (span + 1) * pitch
    f_col = font(F_SEMI, 30)
    for (name, _), cx_ in zip(cols, col_x):
        d.text((cx_, cols_y), name, font=f_col, fill=(128, 134, 140))

    for r, (t, dest, status, main_col, status_col) in enumerate(rows):
        y = rows_y + r * (chh + row_gap)
        for text, (_, span), cx_, colour in zip((t, dest, status), cols, col_x,
                                               (main_col, main_col, status_col)):
            for i, ch in enumerate(text.ljust(span)[:span]):
                board.alpha_composite(flap(ch, cw, chh, colour, fnt),
                                      (int(cx_ + i * pitch), y))
    return board


def concept_board(out_dir):
    """September departed, October landed, and the brand's app is boarding."""
    lg = logo(450)
    header_bottom = 100 + lg.height
    ftop = H - footer_height(dark=False)

    board = departures_board(W - 140)
    f_head, f_sub = font(F_BOLD, 124), font(F_REG, 54)
    headline = "October has landed"
    sub = ["Happy Independence Day, and a happy", f"new month from all of us at {NAME}."]
    head_h = text_h(f_head, headline)
    sub_h = 76 * (len(sub) - 1) + text_h(f_sub, "Ag")
    top = centred_stack([head_h, 110, board.height, 110, sub_h],
                        header_bottom + 60, ftop - 70, "board")

    img = light_ground(top + head_h + 110 + board.height / 2).convert("RGBA")
    img.alpha_composite(lg, ((W - lg.width) // 2, 100))
    d = ImageDraw.Draw(img)
    d.text((W // 2, top), headline, font=f_head, fill=INK, anchor="ma")
    by = top + head_h + 110
    sh, sp = soft_shadow(board.size, 40, 50, colour=(0, 20, 15), alpha=90, dy=30)
    img.alpha_composite(sh, ((W - board.width) // 2 - sp, by - sp))
    img.alpha_composite(board, ((W - board.width) // 2, by))
    y = by + board.height + 110
    for line in sub:
        d.text((W // 2, y), line, font=f_sub, fill=MUTED, anchor="ma")
        y += 76
    draw_footer(img, dark=False, accent=NG_GREEN)
    return export(img, "independence-board", out_dir)


# ── concept 8: the triptych ──────────────────────────────────────────────────

def concept_triptych(out_dir):
    """Three of the brand's own photographs, printed green, white, green.
    Side by side they are the national colours. The only concept here no
    other brand could post, because it is built from pictures only this
    brand has. Skipped until all three photo slots are filled."""
    lg = logo(450)
    header_bottom = 100 + lg.height
    ftop = H - footer_height(dark=False)

    f_head, f_sub = font(F_BOLD, 118), font(F_REG, 54)
    headline = "Proudly Nigerian"
    sub = ["Happy Independence Day, and a happy", f"new month from all of us at {NAME}."]
    head_h = text_h(f_head, headline)
    sub_h = 76 * (len(sub) - 1) + text_h(f_sub, "Ag")

    gap = 24
    pw = (W - 220 - gap * 2) // 3
    ph = 1100
    top = centred_stack([ph, 100, head_h, 34, sub_h], header_bottom + 64, ftop - 70,
                        "triptych")

    GREEN_INK = ((0, 50, 30), (52, 180, 112))    # mid-tones land near #008751
    WHITE_INK = ((168, 176, 176), (255, 255, 255))
    panels = [
        ("hero", (0.5, 0.36), GREEN_INK),
        ("wide", (0.5, 0.46), WHITE_INK),
        ("detail", (0.5, 0.5), GREEN_INK),
    ]
    missing = [nm for nm, _, _ in panels if store_photo(nm) is None]
    if missing:
        print(f"skipped triptych: add assets/photos/{{{','.join(missing)}}}.jpg")
        return None

    img = light_ground(top + ph / 2, 0.75).convert("RGBA")
    img.alpha_composite(lg, ((W - lg.width) // 2, 100))

    x0 = (W - (pw * 3 + gap * 2)) // 2
    group_w = pw * 3 + gap * 2
    sh, sp = soft_shadow((group_w, ph), 40, 50, colour=(0, 30, 20), alpha=70, dy=30)
    img.alpha_composite(sh, (x0 - sp, top - sp))
    radius = 36
    for i, (name, focus, (dark, light)) in enumerate(panels):
        p = cover(store_photo(name), (pw, ph), focus=focus)
        p = duotone(p, dark, light, contrast=1.2).convert("RGBA")
        m = Image.new("L", (pw, ph), 0)
        ImageDraw.Draw(m).rounded_rectangle([0, 0, pw - 1, ph - 1], radius, fill=255)
        p.putalpha(m)
        img.alpha_composite(p, (x0 + i * (pw + gap), top))

    d = ImageDraw.Draw(img)
    y = top + ph + 100
    d.text((W // 2, y), headline, font=f_head, fill=INK, anchor="ma")
    y += head_h + 34
    for line in sub:
        d.text((W // 2, y), line, font=f_sub, fill=MUTED, anchor="ma")
        y += 76
    draw_footer(img, dark=False, accent=NG_GREEN)
    return export(img, "independence-triptych", out_dir)


CONCEPTS = {
    "numerals": concept_numerals,
    "calendar": concept_calendar,
    "receipt": concept_receipt,
    "stamp": concept_stamp,
    "lockscreen": concept_lockscreen,
    "label": concept_label,
    "board": concept_board,
    "triptych": concept_triptych,
}


if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    out = sys.argv[sys.argv.index("-o") + 1] if "-o" in sys.argv else os.getcwd()
    need_links()
    for k in (CONCEPTS if which == "all" else [which]):
        CONCEPTS[k](out)
