"""Check a rendered graphic before it goes out.

Every check here exists because the corresponding mistake actually shipped
at some point: a QR that scanned to the wrong domain, an aspect ratio that
was nearly-but-not-4:5, a badge carrying its dark-background stroke.

    python3 verify.py post.jpg --format feed [--qr URL_THE_QR_MUST_DECODE_TO]
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
FORMATS = {"feed": (1080, 1350), "square": (1080, 1080), "story": (1080, 1920)}

ok = fail = warn = 0


def check(label, passed, detail=""):
    global ok, fail
    if passed:
        ok += 1
        print(f"  PASS  {label}")
    else:
        fail += 1
        print(f"  FAIL  {label}  {detail}")


def note(label, detail=""):
    global warn
    warn += 1
    print(f"  WARN  {label}  {detail}")


def decode_qr(path):
    """macOS Vision, via the bundled Swift helper. Returns payloads found."""
    swift = os.path.join(HERE, "qr_decode.swift")
    try:
        out = subprocess.run(["swift", swift, path], capture_output=True,
                             text=True, timeout=180).stdout
    except Exception as exc:                       # pragma: no cover
        return None, str(exc)
    return [l.split("payload:", 1)[1].strip()
            for l in out.splitlines() if "payload:" in l], None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("--format", default="feed", choices=sorted(FORMATS))
    ap.add_argument("--qr", help="URL the QR must decode to")
    ap.add_argument("--max-kb", type=int, default=8000)
    ap.add_argument("--ground", default="white", choices=["white", "any"],
                    help="'any' for deliberately non-white grounds (dark, textured)")
    ap.add_argument("--full-bleed", action="store_true",
                    help="the design runs a photo to the edges on purpose")
    a = ap.parse_args()

    im = Image.open(a.image)
    W, H = im.size
    want = FORMATS[a.format]

    print(f"\n{os.path.basename(a.image)}  ({a.format})")
    check("exact export size", (W, H) == want, f"got {W}x{H}, want {want[0]}x{want[1]}")
    check("aspect ratio exact", abs(W / H - want[0] / want[1]) < 1e-6,
          f"{W/H:.4f} vs {want[0]/want[1]:.4f}")
    check("no alpha channel", im.mode == "RGB", f"mode={im.mode}")

    kb = os.path.getsize(a.image) / 1024
    check("file size sane", kb <= a.max_kb, f"{kb:.0f} KB")

    px = im.convert("RGB")
    corners = [px.getpixel(p) for p in
               [(2, 2), (W - 3, 2), (2, H - 3), (W - 3, H - 3)]]
    if a.ground == "white":
        check("corners are clean white", all(min(c) > 248 for c in corners), str(corners))

    # Nothing important should touch the edge: a 12px frame of near-uniform
    # background means the layout has real margins.
    arr = np.array(px).astype(int)
    frame = np.concatenate([arr[:12].reshape(-1, 3), arr[-12:].reshape(-1, 3),
                            arr[:, :12].reshape(-1, 3), arr[:, -12:].reshape(-1, 3)])
    if not a.full_bleed:
        check("nothing bleeds off the edge", frame.std(axis=0).max() < 12,
              f"edge variance {frame.std(axis=0).max():.1f}")

    if a.qr:
        payloads, err = decode_qr(a.image)
        if err:
            note("QR could not be decoded (tooling)", err)
        elif not payloads:
            check("QR scans at export size", False,
                  "no code detected — usually too small; enlarge it")
        else:
            check("QR scans at export size", True)
            check("QR points at the intended URL", payloads[0] == a.qr,
                  f"decoded {payloads[0]!r}, expected {a.qr!r}")

    print(f"\n  {ok} passed, {fail} failed" + (f", {warn} warnings" if warn else ""))
    sys.exit(1 if fail else 0)


if __name__ == "__main__":
    main()
