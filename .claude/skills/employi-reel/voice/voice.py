#!/usr/bin/env python3
"""Nigerian narration for HomeLands reels, made with Gemini.

    voice.py speak  LINES.json TAKE.wav [--style S] [--voice ID] [--key ENVNAME]
    voice.py align  TAKE.wav LINES.json SEGS.json
    voice.py check  TAKE.wav SEGS.json [--key ENVNAME]
    voice.py cut    TAKE.wav SEGS.json OUTDIR [--tempo 1.07]
    voice.py review MIX.wav [--what "a 50-second reel announcing ..."] [--key ENVNAME]
    voice.py design NAME "DESCRIPTION" [--key ENVNAME]

LINES.json is a list of lines: ["text", ...] or [["text", cue_frame], ...].

speak   ONE text-to-speech request for the whole script (lines joined by
        <long pause>), in the designed Lagos voice. The free tier allows 10
        TTS requests a day per key, so never call it once per line.
align   Splits the take into its lines. The longest silences are not reliable
        line breaks (a pause inside a line can be as long as one between
        lines), so this picks the breaks that make every line's length match
        its syllable count, preferring long silences.
check   One request to a general Gemini model: transcribes every cut clip and
        rates the accent. Fix any clip whose transcript starts or ends with a
        neighbour's words (move that cut to the silence before it), then run
        cut. Costs nothing from the TTS quota.
cut     Writes OUTDIR/line_NN.wav and OUTDIR/cut.json: each line with pauses
        inside it shortened to 170 ms and the tempo lifted (default 1.07, the
        trailer read is slow), and its new duration. Build the reel's cues
        from these durations.
review  A blunt listening review of a finished soundtrack: intelligibility,
        accent, glitches, phone-speaker balance and pacing, as JSON.
design  Creates a stored voice from a description (region NG). Only needed
        for a new character; the narrator below already exists.

Keys come from homelands_server/.env: DISPOSIBLE_GEMINI_API_KEY, with
DISPOSIBLE_GEMINI_API_KEY_2 as a spare (free tier: 3 requests/min, 10K
tokens/min, 10 requests/day each).
"""
import argparse, base64, io, json, os, re, subprocess, sys, time, wave
import urllib.request, urllib.error
import numpy as np

ENV = os.path.expanduser("~/Desktop/projects/python/homelands_server/.env")
API = "https://generativelanguage.googleapis.com/v1beta"
TTS_MODEL = "gemini-3.8-flash-tts"
VOICE = "voice_jqwxy5vx454b"  # designed Lagos narrator; Gemini judged it 9 to 10/10 Nigerian
LISTEN = ["gemini-flash-latest", "gemini-3.7-flash", "gemini-3.5-flash", "gemini-3.8-flash"]


def key(name):
    for line in open(ENV):
        if line.startswith(name + "="):
            return line.split("=", 1)[1].strip().strip('"').strip("'")
    sys.exit(f"{name} is not in {ENV}")


def call(path, body, keyname, method="POST", timeout=300):
    req = urllib.request.Request(f"{API}/{path}", data=None if body is None else json.dumps(body).encode(),
                                 headers={"x-goog-api-key": key(keyname), "Content-Type": "application/json"}, method=method)
    return json.loads(urllib.request.urlopen(req, timeout=timeout).read().decode() or "{}")


def listen(parts, keyname, json_out=True):
    """generateContent on the first general model that isn't overloaded."""
    body = {"contents": [{"role": "user", "parts": parts}]}
    if json_out: body["generationConfig"] = {"responseMimeType": "application/json"}
    for model in LISTEN:
        try:
            d = call(f"models/{model}:generateContent", body, keyname)
            text = "".join(p.get("text", "") for p in d["candidates"][0]["content"]["parts"])
            return model, (json.loads(text) if json_out else text)
        except urllib.error.HTTPError as e:
            print(f"  {model}: HTTP {e.code}, trying the next model", file=sys.stderr)
            if e.code not in (429, 500, 503): raise
            time.sleep(2)
    sys.exit("every listening model is busy; try again in a minute")


def lines_of(p):
    return [(l if isinstance(l, str) else l[0]) for l in json.load(open(p))]


def read_wav(p):
    w = wave.open(p)
    return w.getframerate(), np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float64)


def write_wav(p, sr, x):
    w = wave.open(p, "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
    w.writeframes(np.clip(x, -32768, 32767).astype("<i2").tobytes()); w.close()


def wav_b64(sr, x):
    buf = io.BytesIO(); w = wave.open(buf, "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
    w.writeframes(np.clip(x, -32768, 32767).astype("<i2").tobytes()); w.close()
    return base64.b64encode(buf.getvalue()).decode()


def quiet_runs(x, sr, rel_db=38.0, thr=None):
    """10 ms frames; returns (quiet mask, threshold). The threshold sits rel_db
    below the take's loud frames; pass the take's own thr when testing a clip."""
    hop = sr // 100
    env = np.array([np.sqrt(np.mean(x[i:i + hop] ** 2)) for i in range(0, len(x) - hop, hop)])
    db = 20 * np.log10(env / 32768 + 1e-9)
    if thr is None: thr = np.percentile(db, 95) - rel_db
    return db < thr, thr


def speak(a):
    lines = lines_of(a.lines)
    text = " <long pause> ".join(lines)
    content = {"type": "text", "text": text}
    if a.style: content["annotations"] = [{"type": "speech_metadata", "style": a.style}]
    body = {"model": TTS_MODEL, "input": [{"type": "user_input", "content": [content]}],
            "response_format": {"type": "audio"}, "generation_config": {"speech_config": [{"voice": a.voice}]}}
    try:
        d = call("interactions", body, a.key)
    except urllib.error.HTTPError as e:
        sys.exit(f"HTTP {e.code}: {e.read().decode()[:600]}")
    best = ""
    def walk(o):
        nonlocal best
        if isinstance(o, dict): [walk(v) for v in o.values()]
        elif isinstance(o, list): [walk(v) for v in o]
        elif isinstance(o, str) and len(o) > len(best): best = o
    walk(d)
    raw = base64.b64decode(best)
    if raw[:4] == b"RIFF": open(a.out, "wb").write(raw)
    else: write_wav(a.out, 24000, np.frombuffer(raw, dtype="<i2").astype(np.float64))
    sr, x = read_wav(a.out)
    print(f"{a.out}: {len(x) / sr:.1f} s for {len(lines)} lines | usage {d.get('usage', {}).get('total_tokens')} tokens")


def syllables(t):
    t = t.lower().replace("homelands", "home lands").replace("naira", "nai ra").replace("oya", "o ya")
    n = 0
    for wd in re.findall(r"[a-z']+", t):
        v = re.findall(r"[aeiouy]+", wd)
        n += max(1, len(v) - (1 if wd.endswith("e") and len(v) > 1 and not wd.endswith("le") else 0))
    return n


def align(a):
    sr, x = read_wav(a.take)
    lines = lines_of(a.lines); n = len(lines)
    S = np.array([syllables(t) for t in lines], float)
    q, thr = quiet_runs(x, sr)
    gaps = []; i = 0
    while i < len(q):
        if q[i]:
            j = i
            while j < len(q) and q[j]: j += 1
            if i > 0 and j < len(q) and j - i >= 12: gaps.append((i, j))
            i = j
        else: i += 1
    s0 = int(np.argmax(~q)); e0 = len(q) - int(np.argmax(~q[::-1]))
    G = np.array(gaps, float); m = len(G)
    if m < n - 1: sys.exit(f"only {m} silences for {n} lines: re-speak with <long pause> between lines")
    def solve(rate):
        INF = 1e18
        cost = np.full((n, m), INF); back = np.zeros((n, m), int)
        lc = lambda k, s, e: ((((e - s) / 100) - (rate * S[k] + 0.15)) / (rate * S[k] + 0.15)) ** 2 * 6
        gb = lambda j: -0.9 * np.log((G[j, 1] - G[j, 0]) / 10)
        for j in range(m): cost[0, j] = lc(0, s0, G[j, 0]) + gb(j)
        for k in range(1, n - 1):
            for j in range(k, m):
                c = [cost[k - 1, p] + lc(k, G[p, 1], G[j, 0]) for p in range(k - 1, j)]
                p = int(np.argmin(c)); cost[k, j] = c[p] + gb(j); back[k, j] = p + k - 1
        c = [cost[n - 2, p] + lc(n - 1, G[p, 1], e0) for p in range(n - 2, m)]
        p = int(np.argmin(c)) + n - 2; idx = [p]
        for k in range(n - 2, 0, -1): idx.append(back[k, idx[-1]])
        return idx[::-1]
    rate = 0.22
    for _ in range(4):
        idx = solve(rate)
        st = [s0] + [G[j, 1] for j in idx]; en = [G[j, 0] for j in idx] + [e0]
        rate = float(np.sum(np.array([(e - s) / 100 for s, e in zip(st, en)]) - 0.15) / np.sum(S))
    raw = json.load(open(a.lines)); segs = []
    for k, (s, e) in enumerate(zip(st, en)):
        seg = {"text": lines[k], "a": round(max(0, s / 100 - 0.03), 3), "b": round(min(len(x) / sr, e / 100 + 0.06), 3)}
        if not isinstance(raw[k], str): seg["cue"] = raw[k][1]
        seg["dur"] = round(seg["b"] - seg["a"], 3); segs.append(seg)
        print(f"{k + 1:2d} {seg['a']:6.2f}-{seg['b']:6.2f}  {seg['dur']:4.2f}s  {lines[k]}")
    json.dump(segs, open(a.segs, "w"), indent=1)
    print(f"{rate * 1000:.0f} ms/syllable; now run: voice.py check {a.take} {a.segs}")


def check(a):
    sr, x = read_wav(a.take); segs = json.load(open(a.segs))
    parts = [{"text": f"Here are {len(segs)} short voice clips from one narrator, in order. For EACH clip, transcribe exactly what is said. "
              "Then rate from 1 to 10 how natural and convincingly Nigerian (Lagos) the accent sounds to a Nigerian listener, and name any clip "
              "that sounds clearly non-Nigerian or mispronounced. Reply as JSON: {\"clips\": [\"...\"], \"accent_score\": n, \"notes\": \"...\"}"}]
    for k, s in enumerate(segs):
        parts += [{"text": f"Clip {k + 1}:"}, {"inline_data": {"mime_type": "audio/wav", "data": wav_b64(sr, x[int(s["a"] * sr): int(s["b"] * sr)])}}]
    model, out = listen(parts, a.key)
    norm = lambda t: re.sub(r"[^a-z0-9 ]", "", t.lower().replace("500,000", "five hundred thousand").replace("500k", "five hundred k"))
    for k, (s, heard) in enumerate(zip(segs, out.get("clips", []))):
        want, got = norm(s["text"]).split(), norm(heard).split()
        flag = "ok " if want[:1] == got[:1] and want[-1:] == got[-1:] else "?? "
        print(f"{flag}{k + 1:2d} heard {heard!r:58} | line {s['text']}")
    print(f"[{model}] accent {out.get('accent_score')}/10: {out.get('notes')}")
    print("?? = check that cut: move it to the silence where the line really starts or ends (edit SEGS.json), then cut.")


def cut(a):
    sr, x = read_wav(a.take); segs = json.load(open(a.segs)); os.makedirs(a.outdir, exist_ok=True)
    _, thr = quiet_runs(x, sr)
    out = []
    for k, s in enumerate(segs):
        y = x[int(s["a"] * sr): int(s["b"] * sr)]
        q, _ = quiet_runs(y, sr, thr=thr)
        hop = sr // 100; keep = np.ones(len(y), bool); i = 0
        while i < len(q):
            if q[i]:
                j = i
                while j < len(q) and q[j]: j += 1
                if i > 3 and j < len(q) - 3 and j - i > 22: keep[(i + 8) * hop:(j - 9) * hop] = False
                i = j
            else: i += 1
        raw = os.path.join(a.outdir, f"_raw_{k:02d}.wav"); dst = os.path.join(a.outdir, f"line_{k:02d}.wav")
        write_wav(raw, sr, y[keep])
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", raw, "-filter:a", f"atempo={a.tempo}", dst], check=True)
        os.remove(raw)
        r = wave.open(dst); dur = r.getnframes() / r.getframerate()
        out.append({"file": f"line_{k:02d}.wav", "text": s["text"], "dur": round(dur, 3), **({"cue": s["cue"]} if "cue" in s else {})})
        print(f"{k + 1:2d} {dur:4.2f}s  {s['text']}")
    json.dump(out, open(os.path.join(a.outdir, "cut.json"), "w"), indent=1)
    print(f"total speech {sum(o['dur'] for o in out):.1f} s -> {a.outdir}/cut.json; place each line on its cue and write place.json")


def review(a):
    mp3 = a.mix + ".check.mp3"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", a.mix, "-ac", "1", "-ar", "16000", "-b:a", "64k", mp3], check=True)
    data = base64.b64encode(open(mp3, "rb").read()).decode(); os.remove(mp3)
    prompt = (f"This is the soundtrack of {a.what}. Listen like a picky Nigerian audio engineer and creative director. Be blunt and specific with timestamps:\n"
              "1) Is every narration line clearly intelligible over the music and sound effects? List any line that is masked, too quiet or too loud.\n"
              "2) Does the narrator sound naturally Nigerian? (1-10)\n3) Any clicks, cut-off words, distortion, awkward gaps or overlaps between lines?\n"
              "4) Is the music/sound design balance good for phone speakers? Anything harsh, boomy or distracting?\n5) Overall pacing: too fast, too slow, or right?\n"
              "Reply as JSON: {\"intelligibility\": [..], \"accent_score\": n, \"glitches\": [..], \"balance\": \"..\", \"pacing\": \"..\", \"top_fixes\": [..]}")
    model, out = listen([{"inline_data": {"mime_type": "audio/mp3", "data": data}}, {"text": prompt}], a.key)
    print(f"[{model}]"); print(json.dumps(out, indent=1))


def design(a):
    body = {"store": True, "voice": {"type": "prompted", "display_name": a.name, "accent": "Nigerian (Lagos)", "region_code": "NG",
                                      "prompted": {"input": a.description}}}
    try:
        d = call("voices", body, a.key)
    except urllib.error.HTTPError as e:
        sys.exit(f"HTTP {e.code}: {e.read().decode()[:600]}")
    sample = re.sub(r"[^a-z0-9]+", "-", a.name.lower()) + "-sample.wav"
    open(sample, "wb").write(base64.b64decode((d.get("sample_audio") or {}).get("data", "")))
    print(f"voice id {d.get('id')} | sample {sample} | judge it with: voice.py check (or review) before using it")


p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
sp = p.add_subparsers(dest="cmd", required=True)
k = dict(default="DISPOSIBLE_GEMINI_API_KEY", help="env var holding the API key (or DISPOSIBLE_GEMINI_API_KEY_2)")
s = sp.add_parser("speak"); s.add_argument("lines"); s.add_argument("out"); s.add_argument("--voice", default=VOICE)
s.add_argument("--style", default="warm, confident movie-trailer narration with playful energy and a smile"); s.add_argument("--key", **k); s.set_defaults(fn=speak)
s = sp.add_parser("align"); s.add_argument("take"); s.add_argument("lines"); s.add_argument("segs"); s.set_defaults(fn=align)
s = sp.add_parser("check"); s.add_argument("take"); s.add_argument("segs"); s.add_argument("--key", **k); s.set_defaults(fn=check)
s = sp.add_parser("cut"); s.add_argument("take"); s.add_argument("segs"); s.add_argument("outdir"); s.add_argument("--tempo", type=float, default=1.07); s.set_defaults(fn=cut)
s = sp.add_parser("review"); s.add_argument("mix"); s.add_argument("--what", default="an Instagram reel for HomeLands, a Nigerian property app"); s.add_argument("--key", **k); s.set_defaults(fn=review)
s = sp.add_parser("design"); s.add_argument("name"); s.add_argument("description"); s.add_argument("--key", **k); s.set_defaults(fn=design)
a = p.parse_args(); a.fn(a)
