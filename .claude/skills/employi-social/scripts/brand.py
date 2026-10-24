"""Employi, in one place.

Every renderer takes its name, links, colours, type and logo from here.
This file is the difference between this skill and its siblings,
homelands-social and jummall-social: the layout engine, the verification
and the traps they guard against are shared; the brand is not.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys

from PIL import Image, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(os.path.dirname(HERE), "assets")

# ── identity ─────────────────────────────────────────────────────────────────

#: The app's name since the October 2026 rebrand. Capital E in running copy;
#: the logo sets it lower case, with "powered by RijHub" under it. Same app,
#: same store listings and the same bundle id (com.rijhub.app) as RijHub.
NAME = "Employi"

#: TODO: Employi has no confirmed website. The team's email is on
#: rijhub.com, and the app's share links still say rijhub.com, but nobody
#: has confirmed either as Employi's public site. Leave both None until the
#: user names the domain: build.py, greeting.py and campaign.py refuse to
#: print a URL or draw a QR while they are unset. Never guess a domain.
SITE = None       # the footer domain, e.g. "<domain>"
#: Where the QR sends people: a link that sends iPhones to the App Store and
#: Android to Google Play (HomeLands' is homelandsng.com/app). Add
#: ?src=<campaign> per campaign so Play Console reports the install source.
APP_URL = None    # e.g. "https://<domain>/app"

#: The store listings: the RijHub listings, renamed in place. The App Store
#: page still says RijHub until the 1.2.0 update ships.
APP_STORE_URL = "https://apps.apple.com/ng/app/rijhub/id6758886544"
PLAY_STORE_URL = "https://play.google.com/store/apps/details?id=com.rijhub.app"
STORES_LIVE = True

#: A public address line for the footer, or None to leave it out. Employi
#: has no public office address on record.
ADDRESS = None


def require(name):
    """SITE or APP_URL, or stop. Both are TODO until the website is confirmed,
    and nothing prints a URL or a QR on a guess."""
    value = {"SITE": SITE, "APP_URL": APP_URL}[name]
    if not value:
        sys.exit(f"refusing to print {name}: it is a TODO in {os.path.abspath(__file__)}.\n"
                 "  Employi has no confirmed website yet. Ask the user for it; never guess\n"
                 "  a domain. Until then, posts carry the store badges and no QR or URL.")
    return value


# ── colour (lib/core/theme/palette.dart) ─────────────────────────────────────

#: The brand colour, taken from the logo: crimson600.
CRIMSON = (162, 0, 37)           # #A20025
CRIMSON_50 = (252, 242, 244)     # #FCF2F4
CRIMSON_100 = (249, 227, 232)    # #F9E3E8
CRIMSON_200 = (242, 196, 206)    # #F2C4CE
CRIMSON_300 = (229, 149, 166)    # #E595A6
CRIMSON_400 = (210, 90, 117)     # #D25A75
CRIMSON_500 = (187, 28, 67)      # #BB1C43
CRIMSON_700 = (135, 0, 31)       # #87001F
CRIMSON_800 = (108, 0, 25)       # #6C0019
CRIMSON_900 = (82, 0, 19)        # #520013

INK = (23, 23, 23)               # #171717 neutral900, the logo's black
MUTED = (107, 107, 107)          # #6B6B6B neutral500, secondary text
GROUND = (247, 247, 247)         # #F7F7F7 neutral50, the app's light ground
SUCCESS = (22, 163, 74)          # #16A34A green500
WHITE = (255, 255, 255)

#: Crimson is 8.2:1 on white, so unlike HomeLands' terracotta it carries
#: small text as well as large shapes: one colour for both slots.
ACCENT = CRIMSON                 # eyebrows and small accent type
ACCENT_FILL = CRIMSON            # the *starred* half of a headline, shapes
ACCENT_ON_DARK = CRIMSON_300     # accent type on near-black grounds (7:1)

#: Shadows under devices and cards: the logo's black with a trace of
#: crimson, so they sit on the blush splash instead of reading as cold grey.
SHADOW = (40, 14, 20)

#: HomeLands draws architectural line drawings behind its headlines, from
#: its App Store graphics. That art is HomeLands' own and Employi has no
#: equivalent yet, so the line-work is off: build.py skips it while this is
#: None, whatever a config says.
LINEWORK = None

#: The soft field behind the hero, in place of HomeLands' warm splash and
#: Jummall's teal: (cx, cy, rx, ry as fractions of the canvas, colour,
#: peak, falloff). The crimson scale's lightest steps, kept faint so the
#: ground still reads white.
SPLASH = [
    (0.50, 0.505, 0.78, 0.44, (250, 236, 239), 0.80, 1.35),
    (0.50, 0.480, 0.46, 0.27, (244, 214, 221), 0.50, 1.30),
    (0.29, 0.575, 0.26, 0.18, (248, 226, 231), 0.42, 1.40),
]

# ── type ─────────────────────────────────────────────────────────────────────

#: Inter, the app's only typeface (lib/core/theme/app_typography.dart),
#: copied from the app's assets/fonts/inter. Version 3.019, which has ₦
#: (U+20A6) in every weight, so prices are set with the real sign.
_F = os.path.join(ASSETS, "fonts")
F_REG = os.path.join(_F, "Inter-Regular.ttf")
F_MED = os.path.join(_F, "Inter-Medium.ttf")
F_SEMI = os.path.join(_F, "Inter-SemiBold.ttf")
F_BOLD = os.path.join(_F, "Inter-Bold.ttf")
F_XBOLD = os.path.join(_F, "Inter-ExtraBold.ttf")


def font(path, size):
    return ImageFont.truetype(path, size)


#: Headline tracking, from the app's display style: 30/36 at w700 with
#: -0.8 letter-spacing, which is -0.027em.
DISPLAY_TRACK = -0.8 / 30


def advances(path, size, text):
    """The pen advance after each character, with the font's kerning.

    Pillow only kerns through libraqm, which this machine's Pillow can't
    load, so it sets pairs like "To" too loose. HarfBuzz's hb-shape
    (Homebrew's harfbuzz ships it) returns kerned advances. Ligatures are
    switched off so each character keeps its own glyph. Without hb-shape
    this falls back to Pillow's unkerned advances.
    """
    f = ImageFont.truetype(path, size)
    hb = shutil.which("hb-shape")
    if hb and text:
        try:
            out = subprocess.run(
                [hb, "--output-format=json", "--font-size=10000",
                 "--features=-liga,-clig,-dlig", path, text],
                capture_output=True, text=True, timeout=20, check=True).stdout
            glyphs = json.loads(out)
            index = {}                       # UTF-8 byte offset -> character
            b = 0
            for i, ch in enumerate(text):
                index[b] = i
                b += len(ch.encode("utf-8"))
            adv = [0.0] * len(text)
            for g in glyphs:
                adv[index[g["cl"]]] += g["ax"] * size / 10000
            return adv
        except (subprocess.SubprocessError, ValueError, KeyError):
            pass
    return [f.getlength(ch) for ch in text]


# ── the logo ─────────────────────────────────────────────────────────────────
#
# The app's own files, byte for byte (its assets/brand/rijhub_logo*.png and
# rijhub_mark*.png, and assets/icon/app_icon.png). The file names there
# still say rijhub; the art is Employi's.

LOGO = os.path.join(ASSETS, "brand", "logo.png")                  # light grounds
LOGO_ON_DARK = os.path.join(ASSETS, "brand", "logo-on-dark.png")  # dark grounds
LOGO_WHITE = os.path.join(ASSETS, "brand", "logo-white.png")      # crimson grounds
MARK = os.path.join(ASSETS, "brand", "mark.png")                  # the pin alone
MARK_WHITE = os.path.join(ASSETS, "brand", "mark-white.png")
APP_ICON = os.path.join(ASSETS, "brand", "app-icon.png")

#: The layouts were drawn around Jummall's 4.1:1 wordmark. Employi's lockup
#: is 3.2:1 once its transparent margin is cropped, so at the same width it
#: would sit taller and heavier; scaling the width by the square root of
#: the ratio of ratios gives it the same area on the page.
LOGO_SCALE = 0.88


def lockup(width, reversed_=False, white=False):
    """The Employi logo, `width` pixels wide.

    The whole lockup is one piece of art: the crimson and black pin with
    the handshake, the "employi" wordmark, and "powered by RijHub" under
    it. Scale it, never redraw or recolour it, and never set the name in
    type beside the mark instead. Reversed takes the file the app uses on
    dark grounds (white wordmark, white half pin); white takes the
    all-white one, for crimson grounds.
    """
    path = LOGO_WHITE if white else LOGO_ON_DARK if reversed_ else LOGO
    raw = Image.open(path).convert("RGBA")
    raw = raw.crop(raw.getbbox())                # the files carry a 3 px margin
    return raw.resize((width, round(raw.height * width / raw.width)), Image.LANCZOS)


def sign_off():
    """The line every greeting ends on."""
    return f"from all of us at {NAME}."
