#!/bin/zsh
# The whole reel in one go: sub-frames, motion blur, sound, covers.
#
#   scripts/make.sh [OUT_DIR]          default ~/Downloads/<reel name>
#
# REEL=, BRAND=, CUES= (paths) render a variant without touching the
# originals. Sub-frames (about 2 GB) go to a scratch folder and are deleted
# when it finishes. Missing media stops the render (it would ship as a
# placeholder); ALLOW_PLACEHOLDERS=1 renders anyway, for storyboard previews.
set -e
SKILL=${0:A:h:h}
E=$SKILL/engine
export REEL=${REEL:-$SKILL/reel.json} BRAND=${BRAND:-$SKILL/brand.json} CUES=${CUES:-$SKILL/cues.json}
NAME=$(python3 -c "import json, os; print(json.load(open(os.environ['REEL']))['name'])")
TOTAL=$(python3 -c "import json, os; print(json.load(open(os.environ['CUES']))['total'])")
OUT=${1:-$HOME/Downloads/$NAME}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/reel-XXXXXX")
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"

[[ -d $E/node_modules/playwright-core ]] || (cd "$E" && npm install --silent)

# each recording -> 30 fps frames, once (delete its folder to re-extract)
SKILL=$SKILL E=$E python3 - <<'PY'
import json, os, subprocess
skill, e = os.environ["SKILL"], os.environ["E"]
for key, rec in json.load(open(os.environ["REEL"]))["recordings"].items():
    d = os.path.join(e, rec["dir"])
    if os.path.isdir(d) and os.listdir(d):
        continue
    src = os.path.join(skill, rec["source"])
    if not os.path.exists(src):
        print(f"  recording '{key}' not captured yet: {rec['source']}"); continue
    os.makedirs(d, exist_ok=True)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", src, "-vf", "fps=30", "-q:v", "2", os.path.join(d, "%04d.jpg")], check=True)
    print(f"  {key}: {len(os.listdir(d))} frames from {rec['source']}")
# patched frames (scripts/settle_region.py) go over the extracted ones, every run
for key, rec in json.load(open(os.environ["REEL"]))["recordings"].items():
    pd = rec.get("patches")
    if pd and os.path.isdir(os.path.join(skill, pd)):
        import shutil
        for f in sorted(os.listdir(os.path.join(skill, pd))):
            shutil.copy(os.path.join(skill, pd, f), os.path.join(e, rec["dir"], f))
        print(f"  {key}: patched frames applied from {pd}")
PY

echo "1/5 sub-frames ($TOTAL frames)"
(cd "$E" && node render.mjs frames "$WORK" 0 $TOTAL) || [[ -n $ALLOW_PLACEHOLDERS ]] || { echo "stopped: media missing (see above)"; exit 1; }
echo "2/5 motion blur and encode"
python3 "$E/blur.py" "$WORK" $TOTAL "$WORK/video.mp4"
echo "3/5 sound"
python3 "$E/audio.py" "$WORK/audio"
echo "4/5 mux at Instagram loudness"
python3 "$E/mux.py" "$WORK/video.mp4" "$WORK/audio/mix.wav" "$OUT/$NAME.mp4"
python3 "$E/mux.py" "$WORK/video.mp4" "$WORK/audio/sfx.wav" "$OUT/$NAME-sfx-only.mp4"
echo "5/5 covers"
(cd "$E" && node covers.mjs "$OUT")
echo "done: $OUT"
