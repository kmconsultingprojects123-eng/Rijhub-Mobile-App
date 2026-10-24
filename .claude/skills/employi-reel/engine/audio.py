"""Sound for the reel, synthesised: an amapiano-flavoured groove at 120 BPM
plus sound effects locked to the picture's frames.

    python3 audio.py OUT_DIR

Writes music.wav, sfx.wav and mix.wav (48 kHz stereo). Every cue below is
a frame number from scene.js; at 30 fps and 120 BPM a beat is 15 frames,
so the edit and the groove share one grid.
"""
import json, os, sys, wave
import numpy as np

SKILL = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CUE = json.load(open(os.environ.get("CUES") or os.path.join(SKILL, "cues.json")))
REEL = json.load(open(os.environ.get("REEL") or os.path.join(SKILL, "reel.json")))
SR = 48000
DUR = CUE["total"] / CUE["fps"]
N = int(SR * DUR)
BEAT = 0.5
rng = np.random.default_rng(7)
fr = lambda f: f / 30.0                       # frame -> seconds

out = sys.argv[1] if len(sys.argv) > 1 else "."
os.makedirs(out, exist_ok=True)

# ── building blocks ─────────────────────────────────────────────────────────
def t_(d): return np.arange(int(SR * d)) / SR

def fft_filter(x, lo=None, hi=None, slope=4.0):
    """Static band filter in the frequency domain, smooth (no ringing)."""
    n = len(x)
    X = np.fft.rfft(x, n=2 * n)
    f = np.fft.rfftfreq(2 * n, 1 / SR)
    g = np.ones_like(f)
    if lo: g *= 1 / (1 + (lo / np.maximum(f, 1)) ** slope)
    if hi: g *= 1 / (1 + (f / hi) ** slope)
    return np.fft.irfft(X * g)[:n]

def sweep_noise(d, f0, f1, q=1.2, frame=1024, hop=256):
    """Noise through a band-pass whose centre glides f0 -> f1 (log)."""
    n = int(SR * d) + frame
    x = rng.standard_normal(n)
    win = np.hanning(frame)
    y = np.zeros(n)
    freqs = np.fft.rfftfreq(frame, 1 / SR)
    steps = max(1, (n - frame) // hop)
    for i in range(steps):
        p = i / steps
        c = f0 * (f1 / f0) ** p
        bw = c / q
        g = np.exp(-0.5 * ((freqs - c) / (bw * 0.6)) ** 2)
        seg = x[i * hop:i * hop + frame] * win
        y[i * hop:i * hop + frame] += np.fft.irfft(np.fft.rfft(seg) * g) * win
    return y[:int(SR * d)] / 1.5

def env(n, a=0.002, d=0.3, curve=1.0):
    t = np.arange(n) / SR
    att = np.clip(t / max(a, 1e-4), 0, 1)
    return att * np.exp(-np.maximum(t - a, 0) / max(d, 1e-4)) ** curve

def norm(x, peak=1.0):
    m = np.max(np.abs(x)) or 1
    return x / m * peak

def place(buf, x, t, gain=1.0, pan=0.0):
    i = int(t * SR)
    if i >= len(buf): return
    x = x[: len(buf) - i]
    l, r = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
    buf[i:i + len(x), 0] += x * gain * l * 1.4142
    buf[i:i + len(x), 1] += x * gain * r * 1.4142

# ── drums ───────────────────────────────────────────────────────────────────
def kick():
    t = t_(0.45)
    f = 52 + 96 * np.exp(-t / 0.035)
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) * env(len(t), 0.001, 0.22)
    click = fft_filter(rng.standard_normal(len(t)), lo=1500, hi=6000) * env(len(t), 0.0005, 0.006)
    return np.tanh(1.6 * (body + 0.35 * click)) * 0.9

def clap():
    n = int(SR * 0.4)
    x = np.zeros(n)
    nz = fft_filter(rng.standard_normal(n), lo=900, hi=5200)
    for k, off in enumerate([0.0, 0.011, 0.022]):
        i = int(off * SR)
        x[i:] += nz[: n - i] * env(n - i, 0.0005, 0.010) * (0.8 if k < 2 else 1.0)
    x += nz * env(n, 0.024, 0.12) * 0.55
    return norm(x, 0.8)

def hat(open_=False):
    n = int(SR * (0.32 if open_ else 0.07))
    x = fft_filter(rng.standard_normal(n), lo=7200, hi=16000)
    return norm(x * env(n, 0.0007, 0.11 if open_ else 0.018), 0.5)

def shaker():
    n = int(SR * 0.11)
    x = fft_filter(rng.standard_normal(n), lo=4200, hi=11000)
    t = np.arange(n) / SR
    e = np.clip(t / 0.012, 0, 1) * np.exp(-np.maximum(t - 0.012, 0) / 0.035)
    return norm(x * e, 0.35)

def log_drum(freq, d=0.42):
    """The amapiano log drum: a pitched thud that drops onto its note."""
    t = t_(d)
    f = freq * (1 + 1.1 * np.exp(-t / 0.012))
    ph = 2 * np.pi * np.cumsum(f) / SR
    tone = 0.8 * np.sin(ph) + 0.5 * np.sin(2 * ph) + 0.26 * np.sin(3 * ph + 0.4) + 0.1 * np.sin(4 * ph)
    e = env(len(t), 0.002, d * 0.42)
    knock = fft_filter(rng.standard_normal(len(t)), lo=300, hi=1800) * env(len(t), 0.0005, 0.008)
    return np.tanh(2.2 * (tone * e + 0.25 * knock)) * 0.75

def keys(notes, d):
    """Soft electric-piano chord: sine partials, gentle attack, tremolo."""
    t = t_(d)
    x = np.zeros(len(t))
    for i, n in enumerate(notes):
        f = 440 * 2 ** ((n - 69) / 12)
        det = 1 + (i % 2 - 0.5) * 0.0016
        x += (np.sin(2 * np.pi * f * det * t) + 0.32 * np.sin(4 * np.pi * f * t) * np.exp(-t / 0.35)
              + 0.12 * np.sin(6 * np.pi * f * t) * np.exp(-t / 0.18))
    trem = 1 + 0.12 * np.sin(2 * np.pi * 4.6 * t)
    e = np.clip(t / 0.012, 0, 1) * np.exp(-t / (d * 0.55))
    return x * e * trem / len(notes)

# ── music ───────────────────────────────────────────────────────────────────
music = np.zeros((N, 2))
K, C, HC, HO, SH = kick(), clap(), hat(), hat(True), shaker()
# A minor: Am9 | Fmaj9 | Dm9 | Em7  (one chord per bar of 2 s)
CHORDS = [[57, 60, 64, 67, 71], [53, 57, 60, 64, 67], [50, 53, 57, 60, 64], [52, 55, 59, 62, 66]]
BASS = [45, 41, 38, 40]                      # A2 F2 D2 E2: an octave up, so phone speakers carry it
# log-drum rhythm inside a bar (in 16ths) and the note offsets for each hit
LOG = [(0, 0), (3, 0), (6, 7), (10, 0), (12, 12), (14, 10)]

def silent(t):
    """The groove holds its breath for the Buldak landing and the white wipe."""
    return CUE["land"] / 30 <= t < CUE["pull"][0] / 30 + 0.03 or CUE["wipe"][0] / 30 - 0.05 <= t < CUE["logo"] / 30

for b in range(int(DUR / (4 * BEAT))):
    bar0 = b * 4 * BEAT
    for s16 in range(16):
        t = bar0 + s16 * BEAT / 4 + (0.018 if s16 % 2 else 0)       # light swing
        if t >= DUR - 0.6 or silent(t): continue
        if s16 % 4 == 0: place(music, K, t, 0.78)
        if s16 in (4, 12): place(music, C, t, 0.42, pan=0.08)
        if s16 % 4 == 2: place(music, HO, t, 0.20, pan=0.25)
        place(music, SH, t, 0.16 if s16 % 2 else 0.11, pan=-0.3)
    root = BASS[b % 4]
    for s16, off in LOG:
        t = bar0 + s16 * BEAT / 4
        if t >= DUR - 0.6 or silent(t): continue
        place(music, log_drum(110 * 2 ** ((root + off - 45) / 12)), t, 0.46)
    if not silent(bar0 + 0.25) and bar0 < DUR - 1:
        for s16 in (2, 6, 10):                                       # off-beat stabs
            t = bar0 + s16 * BEAT / 4
            place(music, keys(CHORDS[b % 4], 0.6), t, 0.30, pan=0.15 if s16 == 6 else -0.15)

# ── sound effects, on the picture's frames ──────────────────────────────────
sfx = np.zeros((N, 2))

def whoosh(d=0.32, up=True, gain=0.5, pan_from=-0.6, pan_to=0.6, t0=0.0):
    x = sweep_noise(d, 500 if up else 6000, 6000 if up else 500, q=1.0)
    n = len(x); tt = np.arange(n) / n
    x *= np.sin(np.pi * tt) ** 1.4
    for k in range(0, n, 2048):                                       # pan as it passes
        p = pan_from + (pan_to - pan_from) * k / n
        place(sfx, x[k:k + 2048], t0 + k / SR, gain, pan=p)

def impact(t0, gain=1.0):
    t = t_(1.4)
    sub = np.sin(2 * np.pi * (55 + 45 * np.exp(-t / 0.08)) * t) * env(len(t), 0.002, 0.28)
    crash = fft_filter(rng.standard_normal(len(t)), lo=2500, hi=12000) * env(len(t), 0.001, 0.35)
    place(sfx, np.tanh(1.8 * sub) * 0.9 + crash * 0.22, t0, gain)

def riser(t0, d, gain=0.5):
    x = sweep_noise(d, 300, 9000, q=0.8)
    tt = np.arange(len(x)) / len(x)
    tone = np.sin(2 * np.pi * np.cumsum(220 * 4 ** tt) / SR) * 0.25
    place(sfx, (x + tone) * tt ** 2.2, t0, gain)

def tick(t0, gain=0.5, f=2600):
    t = t_(0.06)
    x = np.sin(2 * np.pi * f * t) * env(len(t), 0.0003, 0.012) + fft_filter(rng.standard_normal(len(t)), lo=3000) * env(len(t), 0.0002, 0.003)
    place(sfx, x, t0, gain)

def tap(t0, gain=0.55):
    t = t_(0.09)
    x = np.sin(2 * np.pi * 1450 * t) * env(len(t), 0.0004, 0.018) * 0.8
    x += fft_filter(rng.standard_normal(len(t)), lo=1800, hi=7000) * env(len(t), 0.0002, 0.004) * 0.6
    place(sfx, x, t0, gain)

def chime(t0, notes=(88, 95), gain=0.42, step=0.085):
    for i, n in enumerate(notes):
        t = t_(1.2)
        f = 440 * 2 ** ((n - 69) / 12)
        x = (np.sin(2 * np.pi * f * t) + 0.35 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t / 0.12)
             + 0.18 * np.sin(2 * np.pi * f * 5.4 * t) * np.exp(-t / 0.05)) * env(len(t), 0.002, 0.42)
        place(sfx, x, t0 + i * step, gain, pan=0.15 * (1 if i else -1))

def thump(t0, gain=0.7, f=95):
    t = t_(0.35)
    x = np.sin(2 * np.pi * (f + 60 * np.exp(-t / 0.03)) * t) * env(len(t), 0.001, 0.09)
    place(sfx, np.tanh(2 * x) * 0.9, t0, gain)

def pop(t0, gain=0.4, f0=380, f1=760):
    t = t_(0.09)
    f = f0 + (f1 - f0) * np.clip(t / 0.05, 0, 1)
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(len(t), 0.001, 0.03)
    place(sfx, x, t0, gain)

# hook: a whoosh per swipe, tighter as the scroll speeds up
A, D = CUE["arrive"], CUE["dur"]
for k in range(1, len(A)):
    d = max(0.12, D[k] / 30 + 0.12)
    whoosh(d, up=True, gain=0.38 if k < 4 else 0.3, pan_from=0.3, pan_to=-0.3, t0=fr(A[k] - D[k]) - 0.04)
for k in range(1, 4):
    tick(fr(A[k] + 1), 0.28, 3100)                     # price tags landing
riser(fr(A[4]), fr(CUE["land"]) - fr(A[4]), 0.42)      # the scroll speeds up
impact(fr(CUE["land"]), 1.0)                           # lands on Buldak
whoosh(0.9, up=False, gain=0.5, pan_from=-0.2, pan_to=0.2, t0=fr(CUE["pull"][0] - 1))   # into the phone
pop(fr(CUE["head2"][0] + 1), 0.25); pop(fr(CUE["head2"][0] + 4), 0.2, 500, 900)
for i_ in range(len(REEL["reveal"].get("categories") or [])):   # category cards, rising
    pop(fr(CUE["cats"][0] + i_ * 5 + 2), 0.24, 420 + i_ * 90, 840 + i_ * 180)
whoosh(0.45, up=True, gain=0.3, pan_from=-0.5, pan_to=0.5, t0=fr(CUE["cats"][1]))
whoosh(0.5, up=False, gain=0.3, t0=fr(CUE["s3bg"][0]))
tap(fr(CUE["tap1"]))
pop(fr(CUE["stock"] + 2), 0.26, 520, 1040); pop(fr(CUE["price"] + 2), 0.26, 600, 1200)
pop(fr(CUE["cart"] + 2), 0.3, 360, 720)
tap(fr(CUE["tap2"]))
whoosh(0.55, up=True, gain=0.32, pan_from=-0.2, pan_to=0.7, t0=fr(CUE["fly"][0]))  # into the cart
chime(fr(CUE["badge"]), (88, 95), 0.44)                # the badge
for k in range(5): tick(fr(CUE["badge"]) + 0.03 * k, 0.12, 4200 + 300 * k)       # sparkle
pop(fr(CUE["added"] + 2), 0.28, 640, 1280)
whoosh(0.4, up=False, gain=0.25, t0=fr(CUE["chipsOut"]))
riser(fr(CUE["flood"][0] - 4), fr(CUE["pay"][0]) - fr(CUE["flood"][0] - 4), 0.42)  # teal floods in
whoosh(0.7, up=True, gain=0.35, pan_from=0.0, pan_to=0.0, t0=fr(CUE["flood"][0]))
impact(fr(CUE["pay"][0]), 0.75)                        # "Pay"
for f_ in CUE["pay"][1:]: thump(fr(f_), 0.55)          # "when" "it" "arrives."
pop(fr(CUE["payChip"]), 0.35, 520, 1040)               # cash on delivery chip
if REEL.get("place"):                                  # the place scene is optional
    whoosh(0.55, up=True, gain=0.42, pan_from=0.0, pan_to=0.0, t0=fr(CUE["card"][0] - 2))   # the card rises
    thump(fr(CUE["pin"] + 7), 0.45, 95); tick(fr(CUE["pin"] + 11), 0.25, 1800)              # the pin lands
whoosh(0.6, up=False, gain=0.4, t0=fr(CUE["wipe"][0]))                                  # white wipe
impact(fr(CUE["logo"]), 0.55); chime(fr(CUE["logo"] + 1), (81, 88, 93), 0.38, 0.07)     # logo
for i_ in range(3): pop(fr(CUE["endChips"] + i_ * 4 + 1), 0.22, 600 + i_ * 120, 1200 + i_ * 240)
pop(fr(CUE["badges"][0]), 0.3, 600, 1200); pop(fr(CUE["badges"][1]), 0.3, 700, 1400)  # store badges

# ── reverb, mix, master ─────────────────────────────────────────────────────
def reverb(x, secs=1.3, mix=0.16):
    n = int(SR * secs)
    t = np.arange(n) / SR
    ir = rng.standard_normal((n, 2)) * np.exp(-t / (secs / 5))[:, None]
    ir[:, 0] = fft_filter(ir[:, 0], hi=6500); ir[:, 1] = fft_filter(ir[:, 1], hi=6500)
    ir /= np.sqrt((ir ** 2).sum(axis=0))
    m = len(x) + n
    L = 1 << int(np.ceil(np.log2(m)))
    y = np.stack([np.fft.irfft(np.fft.rfft(x[:, c], L) * np.fft.rfft(ir[:, c], L), L)[: len(x)] for c in range(2)], axis=1)
    return x + y * mix

def low_shelf(x, f0, gain_db):
    """Smooth shelf: full cut well below f0, none well above."""
    n = len(x)
    X = np.fft.rfft(x, n=2 * n)
    f = np.fft.rfftfreq(2 * n, 1 / SR)
    g = 10 ** (gain_db / 20)
    w = 1 / (1 + (f / f0) ** 4)                         # 1 below f0 -> 0 above
    return np.fft.irfft(X * (1 + (g - 1) * w))[:n]

def master(x, peak_db=-1.0):
    x = x - x.mean(axis=0)
    # phones can't reproduce below ~40 Hz; there it only costs headroom
    x = np.stack([low_shelf(fft_filter(x[:, c], lo=34, slope=8), 90, -6.0) for c in range(2)], axis=1)
    x = np.tanh(x * 1.05) / 1.05                       # gentle glue
    fade = np.ones(len(x)); k = int(SR * 0.5)
    fade[-k:] = np.linspace(1, 0, k) ** 2
    x *= fade[:, None]
    return x / (np.max(np.abs(x)) or 1) * 10 ** (peak_db / 20)

music = reverb(music, 1.1, 0.12)
sfx = reverb(sfx, 1.4, 0.18)

def write(path, x):
    y = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(y.tobytes())
    print("wrote", path)

write(os.path.join(out, "music.wav"), master(music))
write(os.path.join(out, "sfx.wav"), master(sfx))
write(os.path.join(out, "mix.wav"), master(music * 0.78 + sfx * 0.9))
