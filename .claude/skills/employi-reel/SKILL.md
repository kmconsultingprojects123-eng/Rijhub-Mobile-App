---
name: employi-reel
description: Make Employi Instagram Reels and other 9:16 video ads. Motion-graphic videos built from photographs Employi owns and real screen recordings of the Employi app (powered by RijHub, the RijHub app renamed) on the project's own iOS Simulator, with an iPhone mockup, true motion blur, synthesised music and sound effects at Instagram loudness, optional Gemini TTS narration once a voice is chosen, and a designed cover. Use whenever asked for an Employi reel, video ad, motion graphic, voiceover, story or TikTok video, or a RijHub one now that the app is Employi.
---

# Employi reels

Renders finished vertical video (1080×1920, 30 fps, H.264, AAC) from three
data files. The engine is the one behind Jummall's approved launch reel;
everything that looks like Employi lives in
`brand.json`: the crimson scale, Inter, the app's own logo file, and a
pegboard as the wall the app scenes play on, because a pegboard is where an
artisan's tools hang.

How it works: an HTML stage is drawn by headless Chrome, and `scene.js`
is a pure function of time, so any instant renders identically in any
order. Each output frame averages 3 to 20 sub-frames in linear light, which
is real motion blur, not a filter. The soundtrack is synthesised from the
same cue sheet, so every cut lands on the 120 BPM grid.

Employi is the RijHub app, renamed in October 2026 and live since February
2026: clients in Abuja say what needs fixing, see ID-checked artisans near
them with prices up front, book and pay in the app, chat, and give a start
code when the artisan arrives; the money is held until they confirm the
job is done. Artisans join with a phone number, list their prices, get
booked and are paid into an in-app wallet.

## Start here: what the user approved

Nothing Employi-specific has been approved yet. These came from the user's
feedback on the sibling reels, and they hold here:

- **Each reel is its own idea.** The user called the template below what
  "thousands of other people" would make. Build a new concept with its own
  sound, flow and design. The approved reference build ("its perfect") is
  HomeLands' film at
  `~/Desktop/projects/flutter/homelands_app/.claude/skills/homelands-reel/films/a-film-by-you/`:
  copy its structure (scene.js as a pure function of time, a cue sheet, a
  synthesised score, two-worker render, motion blur, covers), not its look.
- **Every reel with sound is narrated,** and the user loved the natural
  Nigerian voice on HomeLands. Which voice and which key Employi uses is
  the user's decision, still open: see **Voice**. Until it's made, ship
  without narration or ask; don't record a placeholder or swap in a
  library voice.
- **Pace it to the voice.** At 30 s with eight scenes the user "cant even
  focus on anything", "this dosent mean you make it too slow too". Write the
  narration first, then time every scene from the line lengths: about 1.6
  to 2.4 s per idea, text changes cut on whole frames, pauses inside lines
  tightened.
- **Deliver HD and check the video itself**: frames pulled from the encoded
  mp4, a listening review of the mix, and covers inside the 3:4 grid crop.
  Copy rules and data landmines live in employi-social's SKILL.md.

## Voice

`voice/voice.py` and `voice/voicemix.py` are homelands-reel's, unchanged.
As they stand they narrate in HomeLands' stored voice, with HomeLands' key:

- `voice.py` reads its key itself from one fixed file, the `ENV` constant
  at its top: `~/Desktop/projects/python/homelands_server/.env`, the line
  named by `--key` (default `DISPOSIBLE_GEMINI_API_KEY`;
  `DISPOSIBLE_GEMINI_API_KEY_2` is a spare on another project, where the
  voice doesn't exist). Never open, print or copy that file, or any other
  `.env`.
- `VOICE` (`voice_jqwxy5vx454b`) is a designed Lagos narrator stored in that
  key's Gemini project. Stored voices belong to one project, and expire
  after a year unused.
- Model `gemini-3.8-flash-tts`. Gemini's library has no Nigerian voices, so
  the accent comes from voice design (`region_code: NG`), never from a
  style prompt. Free tier: 10 TTS requests a day per key (3 a minute, 10K
  tokens a minute); one request voices a whole script.
- No Gemini key is on record for Employi: `rijhub_backend` has no Gemini
  setting, and the Ask's speech provider isn't chosen yet.

**Decision for the user, before any narration:**

1. **Reuse HomeLands' key and narrator.** No change to `voice.py`. Employi
   would sound like HomeLands, and both brands would share one key's daily
   quota.
2. **Give Employi its own.** A Gemini API key in a Google Cloud project
   Employi controls, kept in an env file the user picks (never inside the
   skill). Then point `ENV` and the `--key` default at it, make Employi's
   narrator with `voice.py design`, judge it with `check`, and set `VOICE`
   to the new id. The character is the user's call too: the HomeLands
   description below is a Lagos man, and Employi is Abuja-only.

Small things to change either way: `syllables()` knows "homelands" but not
"employi" (it counts two vowel groups in a three-syllable word; fine unless
`align` misplaces a cut), and `review`'s default `--what` describes
HomeLands, so pass `--what` every time.

The workflow, once the voice is settled:

```bash
V=~/Desktop/projects/flutter/Rijhub-Mobile-App/.claude/skills/employi-reel/voice/voice.py
python3 $V speak lines.json take.wav          # ONE request: every line, joined by <long pause>
python3 $V align take.wav lines.json segs.json # find each line in the take
python3 $V check take.wav segs.json           # transcribe every clip + rate the accent
python3 $V cut take.wav segs.json vo/          # vo/line_NN.wav + vo/cut.json (durations)
# ... build the cue sheet from the durations, write vo/place.json, mix ...
python3 $V review audio/mix.wav --what "a 30-second reel for Employi, an Abuja app for booking ID-checked artisans"
```

- **lines.json**: one entry per line, short and spoken the way a Nigerian
  VO artist would say it. Write numbers as words ("ten thousand naira").
  A little Naija is welcome where it fits; keep the brand voice polished.
- **check is not optional.** `align` matches line lengths to syllable
  counts and once put a cut a phrase early on the first try. Any `??`
  clip: move its cut to the real silence (`segs.json`), then `cut`.
- **cut** shortens pauses inside a line to 170 ms and lifts the tempo
  1.07x; the trailer read is slow, and this keeps it natural.
- **Place the lines, then build the cues from them.** The scenes follow the
  voice, not the other way round. The reference film's `vo/fit.py` is the
  worked example.
- **Mix with `voice/voicemix.py`**: the voice levelled and EQ'd for phone
  speakers, the music ducked 9 dB and the effects 4 dB under it, the voice
  7 dB over the ducked bed. Ride scene loudness before ducking. Ship two
  cuts: the full mix, and voice plus effects with no music (for posting
  with a trending sound).
- The description behind HomeLands' narrator, for reference: "A Lagos-born
  Nigerian man in his early thirties, a top Nigerian voice-over artist
  narrating a premium TV commercial. Natural, native Nigerian English as
  educated Lagosians speak it: syllable-timed rhythm, Yoruba-influenced
  intonation and vowels, crisp consonants, never American or British.
  Warm, rich mid-low voice with relaxed confidence and a smile in it;
  measured and grounded, not a hyped radio host." A hyped "radio host"
  description scored 5/10 and was deleted.

## The reference build

`homelands-reel/films/a-film-by-you/` (path above) is the #HomeLands500K
challenge reel, 49.6 s: a film countdown, a studio ident, an empty cinema,
five clapper-slated takes, the entry steps on a film strip, festival
laurels, and a film-poster end card that runs back into the countdown so it
loops. Read it there; nothing of it is copied here.

- `scene.js` + `index.html`: the stage; `cues.json`: every timing, written
  by `vo/fit.py` from the narration; `audio.py`: the score, the narration
  and the mix; `render.mjs` (two workers), `covers.mjs`, `deliver.py`;
  `sheet.py`, `vcheck.py` and `tiles.py` for review sheets, video frame
  checks and grid tiles. `vo/` keeps the take and its cuts, so it
  re-renders without spending a TTS request.
- To start an Employi film, make `films/<name>/` here and bring over its
  code, not its assets, `vo/` or renders. Its relative paths
  (`../../engine`) then resolve to this skill's engine and node_modules.
  Its look, copy and delivery folder are HomeLands'; replace them all.
- Needs about 4 GB free while the sub-frames exist (the disk filled once
  mid-render; its `make.sh` deletes them at the end).

## The template engine (a storyboard, not a reel)

`reel.json` is a draft. Its structure is the approved template's; its copy
comes from the app's own lines and its Abuja price guide; every photo and
recording is an empty slot. Missing media render as labelled placeholders,
so the storyboard can be previewed now. `scripts/make.sh` stops before it
encodes a final video while any slot is empty (`ALLOW_PLACEHOLDERS=1`
previews anyway).

The story, 22 seconds (`cues.json`):

1. **Hook, 0 to 4 s.** Twelve photos swiped like Reels, each tagged with a
   job and its usual Abuja price ("AC servicing, 1 unit", ₦8,000 to
   ₦12,000), under "What needs *fixing?*" and "Type it, *snap it* or say
   it." It lands on the twelfth.
2. **Reveal, 4 to 7 s.** The twelfth photo pulls back into its own card
   inside the app recording; "Artisans near you. *All ID-checked.*"; four
   trade cards fly out (AC repair, Plumbing, Electrical, Generator).
3. **Shop, 7 to 11 s.** The wall's lights come on, the card is tapped,
   three tags hang from pins (the area, the price, "Booking requested"),
   the booking flies into the chat bubble. "Prices up front." then "Book
   in the app."
4. **Value, 11 to 14 s.** "Held safely." on the crimson flood, with the
   chip "Until you confirm the job is done".
5. **Place, 14 to 16 s.** The artisan side: a photo card, "An artisan?
   *Get booked.*", and a pill: "Free to join", "Just your phone number."
   Optional: delete `"place"` and the value scene holds instead.
6. **End, 16 to 22 s.** The logo, "Download *Employi*", three chips
   (ID-checked, Prices up front, Chat in the app), the store badges, and
   the phone playing the second recording.

## Fill the slots

- **`engine/media/hook-01.jpg` to `hook-12.jpg`:** 1080×1920 frames.
  `scripts/photo916.py IN OUT` fits any photo (portrait is cropped to 9:16;
  landscape is set sharp over a blurred fill of itself).
  `hook-12-full.jpg` is the twelfth photo uncropped, for the pull-back and
  the flying booking.
- **Whose photos:** photographs Employi owns or has written permission to
  use: a job in progress, an AC unit, a leaking sink. Never an artisan's
  or a client's photo without their consent, never a watermarked stock
  image, and never the app's sample-data photos (`assets/images/onboarding/`,
  `assets/mock/avatars/`), which carry no recorded licence.
- **Tags:** each `hook.photos` entry takes a `label`, a `price` and a
  `unit`. The draft's come from the app's price guide (`app/catalog.py` in
  `rijhub_backend`: `PRICE_GUIDE` and `TRIAGE_RULES`, what jobs usually cost
  in Abuja), with the range's top in `unit` ("to ₦12,000"). They are
  ranges, not quotes: check them against the guide and the listed
  artisans' real prices before rendering. `"price": null` shows the label
  alone.
- **`engine/media/cat-*.jpg`** (the four trade cards, roughly square) and
  **`engine/media/place.jpg`** (an artisan at work, with consent).
- **`recordings/shop.mp4` and `recordings/end.mp4`:** real screen
  recordings of the app (below). `shop`: the client home with the twelfth
  job's artisan card on screen, the tap, then the booking the shop tags
  describe. `end`: the client home scrolling.
- **Then measure** `reveal.card`, the artisan's card in the first frame of
  `shop.mp4` as fractions of the frame (the hook lands on it exactly; the
  draft's numbers are a placeholder), and set `recordings.*.segments`, the
  map from reel frames to recording frames: `[from, firstFrame, rate,
  maxFrame]`, `from` being a frame or a cue such as `"rec.grid"`. Taps 2
  and 3 sit at the bottom centre as placeholders; measure them too. Skip
  loading states: find the frame where a region settles by diffing it
  against a later frame. A loading state inside a transition can only be
  covered: `scripts/settle_region.py` pastes the loaded region from a later
  frame over the page as it slides in; point the recording's `patches` at
  its output and `make.sh` applies it.
- **The shop chips** (₦10,000, "AC service and gas top-up") are the sample
  booking's: make them match whatever the recording shows.
- **Copy:** every line is a draft. Check each claim against the database
  and employi-social's copy rules before rendering: that the trades on the
  cards have bookable artisans, that the area is served, that prices are
  current.

## Capture

**Screens come from the running app, always.** Never mockups, store
graphics or image-model screens. **Ask the user before booting any
simulator.** `capture/sim.sh start` clones the dedicated simulator ("RijHub
Redesign", or `SIM=`) and its debug build into a temporary one and boots it
headless, so no simulator anyone works on is touched; `finish` deletes it.
**Navigate with DevLaunch** (`go`, see employi-social's SKILL.md and
`lib/app/dev_launch.dart`); taps are for the motion a recording needs.

```bash
S=~/Desktop/projects/flutter/Rijhub-Mobile-App/.claude/skills/employi-reel/capture/sim.sh
$S start
$S go '{"route": "/home", "role": "client"}'      # straight to the client home, no taps
$S shot home                    # read coordinates off a shot: pixels / 3 on a 3x iPhone
$S record shop; $S tap X Y; sleep 2; $S tap X Y; sleep 4; $S stop
$S finish
```

`swipe` drags slowly and holds, scrolling exactly that far; `flick`
releases while moving, for natural momentum. Taps bring the Simulator
window forward and borrow the cursor; `sim.sh` raises the temporary
device's own window by name first. The recorder only writes a frame when
the screen changes, so `stop` nudges the screen first: don't use the
frames after the nudge. Recordings land in `~/Downloads/employi-reel-captures/`;
move them into `recordings/`.

**Sample data or live data.** A debug build without
`--dart-define=API_BASE_URL` runs on sample data: nothing touches
production, but the artisans (Emeka Nwosu and the rest), their prices and
addresses are made up, so the reel can show the UI but not present them as
real people. Against the live API a booking request is a real booking that
notifies a real artisan and opens a Paystack checkout: ask the user first,
use demo accounts, and follow employi-social's seeding rules (check what a
write triggers, delete by id, confirm the counts).

## Make it

```bash
cd ~/Desktop/projects/flutter/Rijhub-Mobile-App/.claude/skills/employi-reel
(cd engine && npm install)                          # once: playwright-core
cd engine && node render.mjs stills ~/Downloads/employi-review 1.2 2.6 5.9 8.6 9.9 13.4 14.8 19.5 && cd ..
scripts/make.sh                                     # -> ~/Downloads/employi-reel/
REEL=~/x/reel.json scripts/make.sh ~/Downloads/x     # a variant
```

About 12 minutes. Out come `<name>.mp4`, `<name>-sfx-only.mp4` (for posting
with a trending sound instead), `cover.jpg` (the value scene, recommended)
and `cover-alt.jpg` (the reveal). `render.mjs` exits 3 and lists the
missing media while any slot is empty. Stills sit on whole frames and some
bugs only exist between them, so after the full render, look at the moving
parts in the video itself (`ffmpeg -i x.mp4 -vf "select=eq(n\,225)" -frames:v 1 f.png`).

**Covers:** never post a frame grab. Keep everything inside the profile
grid's centred 3:4 crop (y 240 to 1680) and check at tile size, about
389 px wide. Both covers carry the logo on a white plate. To post: Edit
cover, then Add from camera roll.

## The house look

- **Employi's colours and nothing else:** crimson `#A20025` and its scale
  (50 `#FCF2F4` to 900 `#520013`, from the app's `palette.dart`), ink
  `#171717`, white. Photos are the only other colour. On Jummall, one
  off-palette field was called a regression; hold this palette the same
  way.
- **The logo is the app's own file** (`engine/assets/brand/logo.png`, the
  app's `rijhub_logo.png`: pin, handshake, "employi", "powered by RijHub").
  `brand.json` places it as an image, 640 wide on the end card, the same
  height as Jummall's approved end card. Scale it, never redraw it or drop
  the "powered by" line.
- **Creative means things from Employi's own world.** The wall is a
  pegboard because that's where an artisan's tools hang (HomeLands' is a
  draughtsman's grid, Jummall's its store's pegboard); the pin that drops
  in the place scene is the shape of Employi's own mark.
- **Copy rules and data landmines:** employi-social's SKILL.md is the
  source of truth. Read it first. In short: Abuja only; few verified
  artisans so far; "held safely until you confirm the job is done", never
  escrow; no launch language; the App Store listing still says RijHub until
  the 1.2.0 update ships.

## Traps (each one shipped once, on Jummall, HomeLands or here)

1. **Missing media rendered blank.** A sub-frame asked for recording frame
   `43.25.jpg` and the phone washed out for 0.4 s. Frame maps are floored,
   and missing files draw placeholders and fail the render.
2. **Chrome won't load CSS mask images from file://.** Use `border-radius`.
3. **`will-change` and `preserve-3d`** produce black boxes in headless
   screenshots.
4. **Blur in linear light, with enough samples:** 20 on fast moves.
5. **The Simulator ignores events posted to its process.** `simtap` sends
   real input and puts the cursor back.
6. **A quick drag is a fling.** `swipe` drags slowly and holds; `flick`
   releases while moving.
7. **The recorder drops the tail of a still screen.** `stop` nudges first.
8. **Overshoot on the last hook photo** shows black below it; it lands
   with a scale punch and a shake instead.
9. **Spring overshoot made words collide** ("itarrives"). Damping 9 and
   word margins.
10. **Captions overlapped at the handover.** The first exits fast, before
    the second arrives.
11. **Elements placed only inside their scene** stack at the corner when a
    cover is composed from another moment; `covers.mjs` hides them.
12. **A pale highlight vanishes on the lit wall.** On covers it goes on a
    white plate.
13. **Long tags left the frame.** A hanging tag now moves its pin inward.
14. **The engine's type sizes are fixed, and Inter is wide.** The value
    line is set at 178 px, the shop lines at 100, the end headline at 134.
    "Your money," ran edge to edge in the value scene, so it became "Held
    / safely." Keep big lines short and check every still for overflow.
15. **Inter has ₦** (`currency.draw` is false). Poppins doesn't, which is
    why Jummall draws N with two bars. And Inter at 800 doesn't set a loose
    full stop the way Plus Jakarta Sans does, so `tightPunct` is left out.
16. **A fix can uncover the next bug.** On Jummall, once the push stopped
    washing out, the seller card under it was visibly "Loading…". After
    any fix, look at the frames around it again.
17. **Phone speakers can't play sub-bass.** Check the octave balance
    against pink noise and master at −14 LUFS. Nobody here can listen, so
    have the mix reviewed (`voice.py review`, once a key is settled), and
    the cut without music always ships too.
18. **Scene loudness swings when booms and pads dominate.** Measure each
    scene above 150 Hz (what a phone plays) and ride it to a target
    relative to the median, then brighten the master (presence +7 dB above
    2.6 kHz, air +5 dB above 7 kHz).
19. **Text that changes mid-frame ghosts.** Motion blur averages
    sub-frames; switch text on whole frames (`Math.round(f)`).
20. **Recording touches production** when the build talks to the live API.
    Keep takes few, and see Capture.

## The engine is shared

`engine/` is the same as homelands-reel's and jummall-reel's (except
`assets/` and `media/`), so a fix in one belongs in all of them: copy the
changed file across and check that the other brands' stills don't move.
Employi's one addition: `scene.js` has three more line icons (`snow`,
`drop`, `wrench`) for the trade cards; copying it to the siblings changes
none of their stills. `scripts/` and `capture/simtap.swift` are unchanged;
`capture/sim.sh` differs (the dedicated simulator by name, a headless
start, `go`, and raising its own window before a tap). `voice/` is
unchanged on purpose until the voice decision.

Brand options in `brand.json`: `"wall"` (`pegboard` or `drafting`),
`tightPunct` (optical full stops for typefaces that set them loose), the
logo as an `image` or a `lockup` built from a mark and a name,
`currency.draw`, and `unit` on prices.

## Where this lives

The canonical copy is
`~/Desktop/projects/flutter/Rijhub-Mobile-App/.claude/skills/employi-reel/`.
Once reviewed, `~/.claude/skills/employi-reel` is meant to be a symlink to
it. Node dependencies install into `engine/node_modules` (employi-social's
HTML kit borrows its playwright-core too); they, the extracted recording
frames and any film's renders (`work/`, `audio/`, mp4s, covers) are
gitignored. `voice/` is the narration toolkit; `films/` will hold finished
reels as reference builds.
