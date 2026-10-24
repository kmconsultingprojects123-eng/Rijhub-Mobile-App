"""Put the narration into a reel's synthesised soundtrack.

    import sys; sys.path.insert(0, "<skill>/voice")
    from voicemix import load_voice, duck_curve, voice_gain
    vo = load_voice(place, vo_dir, SR, n)     # mono at SR: lines resampled, levelled, EQ'd, placed
    dk = duck_curve(vo, SR)                   # 0..1, how much the voice is speaking
    music *= 1 - dk * (1 - 10 ** (-9 / 20))   # music ducks 9 dB under the voice
    sfx *= 1 - dk * (1 - 10 ** (-4 / 20))     # effects duck 4 dB
    k = voice_gain(bed, vo, dk, SR)           # the voice sits 7 dB over the ducked bed (above 150 Hz)
    mix = bed + np.stack([vo, vo]) * k

place is a list of {"file": "line_00.wav", "start": seconds}. Ride and EQ the
bed BEFORE ducking (a section-loudness ride measured after ducking would undo
it), and add the voice after the bed's master EQ so the presence boost meant
for the music doesn't make the voice sibilant. The "A film by you" audio.py
does exactly this inline.
"""
import json, os, wave
import numpy as np


def _filt(x, lo=None, hi=None, slope=4.0, sr=48000):
    n = len(x); X = np.fft.rfft(x); f = np.fft.rfftfreq(n, 1 / sr); g = np.ones_like(f)
    if lo: g = g / (1 + (lo / np.maximum(f, 1e-3)) ** slope)
    if hi: g = g / (1 + (f / hi) ** slope)
    return np.fft.irfft(X * g, n)


def _resample(y, sr_in, sr_out):
    n_out = int(round(len(y) * sr_out / sr_in))
    Y = np.fft.rfft(y); Y2 = np.zeros(n_out // 2 + 1, complex); m = min(len(Y), len(Y2)); Y2[:m] = Y[:m]
    return np.fft.irfft(Y2, n_out) * (n_out / len(y))


def load_voice(place, vo_dir, sr, n):
    vo = np.zeros(n)
    for pl in place:
        w = wave.open(os.path.join(vo_dir, pl["file"]))
        y = _resample(np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float64) / 32768, w.getframerate(), sr)
        fd = int(0.006 * sr); y[:fd] *= np.linspace(0, 1, fd); y[-fd:] *= np.linspace(1, 0, fd)
        act = y[np.abs(y) > 0.015]
        r = np.sqrt(np.mean(act ** 2)) if len(act) else 0.1
        y = y * 10 ** (np.clip(20 * np.log10(0.1 / r), -4, 4) / 20)          # every line at the same level, within 4 dB
        i0 = int(pl["start"] * sr); vo[i0:i0 + len(y)] += y[: n - i0]
    vo = _filt(vo, 85, None, 3, sr)
    vo = vo - _filt(vo, 220, 480, 2, sr) * (1 - 10 ** (-2.5 / 20))            # less mud
    vo = vo + _filt(vo, 2500, 6500, 2, sr) * (10 ** (3 / 20) - 1)            # presence for phone speakers
    vo = vo + _filt(vo, 9000, None, 2, sr) * (10 ** (2 / 20) - 1)            # air
    return np.tanh(vo * 2.2) / 2.2                                            # gentle peak control


def duck_curve(vo, sr, attack_ms=15, release_ms=260):
    blk = sr // 1000; nb = len(vo) // blk
    peak = np.abs(vo[: nb * blk]).reshape(nb, blk).max(axis=1)
    env = np.zeros(nb); e = 0.0; at, rl = np.exp(-1 / attack_ms), np.exp(-1 / release_ms)
    for i in range(nb):
        e = at * e + (1 - at) * peak[i] if peak[i] > e else rl * e + (1 - rl) * peak[i]
        env[i] = e
    dk = np.clip((20 * np.log10(env + 1e-9) + 50) / 15, 0, 1)
    dk = np.convolve(dk, np.ones(25) / 25, mode="same")
    dk = np.repeat(dk, blk)
    return np.concatenate([dk, np.zeros(len(vo) - len(dk))])


def voice_gain(bed, vo, dk, sr, over_db=7.0):
    on = dk > 0.6
    hb = _filt((bed[0] + bed[1]) / 2, 150, None, 4, sr)
    rb = np.sqrt(np.mean(hb[on] ** 2)); rv = np.sqrt(np.mean(vo[on] ** 2))
    return 10 ** ((20 * np.log10(rb / rv) + over_db) / 20)
