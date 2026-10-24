"""Put the sound on the picture, at Instagram's loudness.

    python3 mux.py VIDEO.mp4 AUDIO.wav OUT.mp4

Two-pass loudnorm to -14 LUFS integrated, -1.5 dBTP: Instagram turns
louder uploads down anyway, and a master pushed past that just arrives
squashed. The video stream is copied, never re-encoded.
"""
import json, re, subprocess, sys

video, audio, out = sys.argv[1:4]
target = "I=-14:TP=-1.5:LRA=11"
p1 = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", audio, "-af", f"loudnorm={target}:print_format=json", "-f", "null", "-"],
                    capture_output=True, text=True).stderr
m = json.loads(re.search(r"\{[^{}]*\"input_i\"[^{}]*\}", p1, re.S).group(0))
af = (f"loudnorm={target}:measured_I={m['input_i']}:measured_TP={m['input_tp']}:measured_LRA={m['input_lra']}"
      f":measured_thresh={m['input_thresh']}:offset={m['target_offset']}:linear=true,aresample=48000")
subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", video, "-i", audio, "-map", "0:v:0", "-map", "1:a:0",
                "-c:v", "copy", "-af", af, "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-ac", "2",
                "-shortest", "-movflags", "+faststart", out], check=True)
r = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", out, "-map", "0:a", "-af", "ebur128=peak=true", "-f", "null", "-"],
                   capture_output=True, text=True).stderr
i = re.findall(r"I:\s+(-?[\d.]+) LUFS", r)[-1]
pk = re.findall(r"Peak:\s+(-?[\d.]+) dBFS", r)[-1]
print(f"wrote {out}: {i} LUFS integrated, true peak {pk} dBFS (input was {m['input_i']} LUFS)")
