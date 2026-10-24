---
name: employi-social
description: Produce Employi social graphics for Instagram (app posts, feature slides, carousels, story cards and occasion greetings). Employi, powered by RijHub, is the RijHub app renamed; clients in Abuja book ID-checked artisans through it. Screens are captured from the running Employi app on the project's own iOS Simulator (DevLaunch opens any screen without taps), framed in iPhone mockups with the app's own logo file, Inter and official store badges, then the export is verified. Use whenever asked for an Employi post, graphic, announcement image, carousel, story card or greeting, or a RijHub one now that the app is Employi.
---

# Employi social graphics

Renders finished, post-ready graphics from a JSON config. Nothing in the
output is image-generated: the app screens, the logo, the store badges and
the QR are real files placed at computed coordinates, and the type is set
in Inter, the app's only typeface. Same config in, same pixels out.

Employi is the RijHub app, renamed in October 2026: same app, same store
listings, same bundle id (`com.rijhub.app`), live since February 2026.
Clients in Abuja say what needs fixing (typed, a photo or a voice note),
see ID-checked artisans near them with prices up front, book and pay in
the app, chat with the artisan, and give a start code when the artisan
arrives. The money is held until the client confirms the job is done.
Artisans join with just a phone number, add their services and prices,
check their ID, get booked, and get paid into an in-app wallet they
withdraw to their bank.

## Where the pieces come from

**1. Screens: from the running app. Always.** Run Employi on the project's
simulator and capture the real screens (`scripts/capture/sim.sh`, below).
That is the best source there is: the current UI, full resolution. Never
an image model, which invents UI text and prices because it regenerates
fine type instead of placing it.

**2. Look: from the app itself.** The house style is the app's design
system: `lib/core/theme/palette.dart` (the crimson scale), `lib/core/theme/app_typography.dart`
(Inter, display 30/36 at w700 with -0.8 tracking) and `docs/design-system.md`
("Trust is the product. Verification, ratings, prices and distance are
shown the same way everywhere, calmly and without hype."). The store listing is still RijHub's until the
1.2.0 update ships, so don't take the look from it. `build.py` does the
two-tone headline (`*accent*` sets that part in crimson) on a white ground
with a faint crimson blush.

An image model is fine for exploring a composition, the way the Jummall
layout was found. It never supplies the pixels that get posted.

**3. Fuller screens: sample data or seeded demo data, never real people.**
A debug build without `--dart-define=API_BASE_URL` runs on the app's
sample data, so nothing touches production; but its artisans (Emeka
Nwosu, Yusuf Abdullahi and the rest), prices and addresses are made up.
Show that UI small, and never present a sample artisan as someone you can
book. Against the live API every booking, quote, message and sign-in is
real, so:

- ask the user before seeding demo artisans or bookings, and keep the
  window between insert and delete short;
- first check what each write triggers (push, SMS, WhatsApp, email, a
  Paystack checkout) and don't set any of it off;
- use demo accounts and photos you have the right to use, never a real
  artisan's or client's;
- delete by the ids you inserted, then re-run the counts below to confirm
  the database is back where it was.

Tool permissions may refuse a production write. If they do, stop and ask
the user.

## Capture screens

**Ask the user before booting any simulator.** They sometimes need every
simulator for other work. Captures run on a dedicated one, never the one
the user works on: `sim.sh` finds it by name (`SIM`, default "RijHub
Redesign", an iPhone 17 Pro with a debug build installed) and boots it
headless.

**Navigate with DevLaunch, not taps.** The app's debug builds read
`Documents/dev_launch.json` from their data container at launch
(`lib/app/dev_launch.dart`) and open straight on the screen it names.
`sim.sh go` writes it (into `xcrun simctl get_app_container <udid>
com.rijhub.app data`) and relaunches the app, so no cursor moves and no
window comes forward:

```bash
S=~/Desktop/projects/flutter/Rijhub-Mobile-App/.claude/skills/employi-social/scripts/capture/sim.sh
$S start                                                     # boot headless, 9:41 status bar, launch
$S go '{"route": "/home", "role": "client"}'; $S shot home   # the guest client home
$S go '{"route": "/home", "role": "client", "ask": "AC not cooling"}'; $S shot ask
$S go '{"route": "/home", "role": "artisan", "signedIn": true}'; $S shot artisan-home
$S finish                    # deletes dev_launch.json, clears the status bar, shuts the simulator down
```

Shots land in `~/Downloads/employi-screens/` (`OUT=...` to change). Other
launches, from the comment at the top of `dev_launch.dart`:

| JSON | Opens |
|---|---|
| `{"route": "/welcome"}` | the first-launch welcome conversation |
| `{"route": "/home", "role": "client", "area": "Gwarinpa", "sheet": "area"}` | the area picker |
| `{"route": "/home", "role": "client", "signIn": "postJob", "phone": "8031234567", "code": "4829"}` | the sign-in sheet at the code step |
| `{"route": "/account/wallet", "role": "artisan", "signedIn": true}` | the wallet, as the sample artisan |

`route` takes any path in `lib/app/routes.dart` (`/bookings`, `/messages`,
`/booking/<id>`, `/chat/<id>`, ...); the sample ids are in
`lib/data/mock/`. `"signedIn": true` signs in the app's sample user, so it
shows no personal data.
`"verify": true` signs in for real through the API: live data, so demo
accounts only.

**Taps are the fallback,** for what DevLaunch can't reach (a scrolled
list, a half-open sheet). They are real input: the Simulator window opens
and comes forward, and the cursor moves for a moment and is put back.
Don't type while one runs. (It has to be real input; the Simulator
ignores events posted straight to its process.) `sim.sh` raises this
simulator's own window by name before measuring it, because "window 1"
can be the user's simulator.

```bash
$S shot list; $S tap 200 480       # device points: a capture's pixels divided by 3
$S swipe 200 600 200 300           # slow and held before release; a quick drag is a fling and overshoots
```

- Take a shot before every tap and read the coordinates off it.
- Simulator captures include the Dynamic Island; device screenshots don't.
  `build.py` draws one at the iPhone 17's real size, so both work.
- `start` sets the status bar to 9:41. Captures taken without it (the two
  screens the examples use show 7:47 and 7:48) should be retaken before a
  post goes out.
- Android works the way the Jummall captures did: `adb exec-out screencap
  -p > shot.png`, `adb shell input tap X Y`, and SystemUI demo mode for a
  clean status bar, on an emulator the user isn't using. iOS captures suit
  the iPhone mockups better.

## Render a post

```bash
cd ~/Desktop/projects/flutter/Rijhub-Mobile-App/.claude/skills/employi-social
python3 scripts/build.py examples/app-announcement.json -o ~/Downloads
python3 scripts/verify.py ~/Downloads/app-announcement-1080x1350.jpg --format feed
```

The examples read their screens from `~/Downloads/employi-screens/`:
`app-announcement.json` uses `i2_booking.png` and `i3_chat.png` (a finished
booking and its chat, on sample data); the carousel's first slide also
needs `ask.png` (the Ask conversation, captured as above). `build.py`
accepts a single config object or an array of them; an array is a
carousel, one slide per entry, each with its own `name`.

No QR and no website yet: `SITE` and `APP_URL` in `scripts/brand.py` are
TODO, and `build.py` refuses a config with `qr` or `site` until they are
set. Once the user confirms the domain, set both, add `"qr": {"url":
"<APP_URL>?src=instagram", "caption": "Scan to download"}` and `"site":
"<SITE>"` to the configs, and pass `--qr` to `verify.py`.

## Config

| Key | Meaning |
|---|---|
| `name` | Output filename stem |
| `format` | `feed` (1080×1350), `square` (1080×1080), `story` (1080×1920) |
| `logo` | Show the Employi logo at the top. Default true |
| `eyebrow` | Small crimson kicker; letter-spacing is applied automatically |
| `headline` | String or array of lines. `*fixing?*` sets that part in crimson |
| `headline_size` | Default 122, in 4:5 master units |
| `subline` | Array of lines, one per rendered line |
| `screenshots` | Paths (`~` is expanded), or `{"path": ..., "erase": [[y0, y1]]}` to remove a band, in the capture's pixels |
| `tilt` | Degrees; devices alternate direction. Default 6.0 |
| `overlap` | How far devices tuck behind each other; negative leaves a gap. Default 26 |
| `qr` | `{"url": ..., "caption": ...}`, or omit for no QR. Refused while `APP_URL` is a TODO |
| `badges` | Show the store badges. Default true |
| `site` | Footer URL. Refused while `SITE` is a TODO |
| `glow` | Splash strength, 0 to 1.5. Default 1.0 |
| `linework` | HomeLands' architectural drawings. Never drawn here: `brand.LINEWORK` is None |

Formats other than `feed` reuse the same rhythm scaled to the canvas, so a
config renders in all three without edits.

## Which format

**`feed` (4:5) is the default and usually right.** It is the tallest the
feed allows and matches the profile grid, so nothing is cropped. `square`
is safe everywhere but loses its left and right edges in the 4:5 grid, and
on a layout with a QR on one side and badges on the other, that matters.
`story` is 9:16 full screen.

Export at exactly 1080 wide. Instagram recompresses anything larger, which
softens small type like badge wording and QR modules.

## Always verify before handing the file over

Run `verify.py`, and look at the export yourself. Every check in it exists
because that exact mistake shipped at some point:

- **Exact export size.** A graphic at 3712×4608 is 0.8056, not 0.8000.
  Nearly-4:5 gets letterboxed or cropped.
- **QR decodes, and to the right URL** (once there is a QR). A QR can
  survive resizing, still scan, and point somewhere the footer
  contradicts. The check decodes the final export, not the master,
  because a QR that reads at 2160px can fail at 1080.
- **Corners clean, nothing bleeding off the edge.**

Then read the screens in the export: prices whole, nobody's personal data,
nothing cut by the other phone.

## Traps this skill already handles

**Store badges ship with a stroke.** Apple's and Google's official badges
come in a bordered variant with a ~2.3%-of-height grey outline, meant to
separate them from a dark background. On white it reads as a sticker edge.
The plain files in `assets/badges/` have it stripped and the corners
re-rounded. Do not re-download them into the layout without stripping it.

**Device frames must be dark.** A light titanium rail has almost no
contrast against a white ground and reads as a border round the phone, not
as hardware. The body is dark with a hairline lit edge.

**Rotate at 2× then downsample.** Rotating a hard-edged RGBA at final size
leaves a pale fringe along the silhouette. `build.py` supersamples for this
reason.

**The Dynamic Island is drawn at its real size.** Measured off a simulator
capture (0.312 × 0.091 of the screen width, 0.035 down) and drawn a hair
larger, it exactly covers the island a simulator capture bakes in. Drawn
smaller, the baked one showed round its edge.

**Headlines are kerned.** This machine's Pillow can't kern (it has no
libraqm), which sets pairs like "To" loose. Headlines are laid out with
HarfBuzz's `hb-shape` (Homebrew's `harfbuzz`) at the app's display
tracking, -0.027em. Without `hb-shape` they fall back to unkerned; install
harfbuzz rather than accept that.

**The logo is the app's own file.** `brand.lockup()` scales
`assets/brand/logo.png` (the app's `rijhub_logo.png`: the crimson and
black pin with the handshake, the "employi" wordmark, "powered by RijHub"
under it). Never redraw it, recolour it, drop the "powered by" line, or
set the name in type beside the mark. Light grounds take `logo.png`, dark
grounds and photos `logo-on-dark.png`, crimson grounds `logo-white.png`,
the same rule as the app's `RijHubLogo` widget.

**A second phone can hide the first one's prices.** With the default
overlap, the chat phone covered the booking screen's price column and the
export showed "₦10,00", which reads as a broken price. The example uses
`"overlap": -24`. Check every pair: whatever sits at the inner edges is
what gets covered.

**Inter has ₦.** The app's Inter (3.019) carries U+20A6 in all five
weights, so prices are typed with the real sign, here and in the reel.

## Check claims against the database before writing copy

The most expensive mistakes are true-sounding lines that the data
contradicts. Before writing a headline or subline, check it:

```bash
cd ~/Desktop/projects/python/rijhub_backend
.venv/bin/python - <<'PY'
import os
from dotenv import load_dotenv
from pymongo import MongoClient
load_dotenv('.env')
db = MongoClient(os.environ['MONGODB_URI'])[os.environ.get('MONGODB_DB', 'rijhub')]
agg = lambda c, g, m={}: {r['_id']: r['n'] for r in db[c].aggregate([{'$match': m}, {'$group': {'_id': g, 'n': {'$sum': 1}}}])}
live = {'listed': True, 'deleted': {'$ne': True}}          # bookable: ID-checked, with prices
print('users by role        :', agg('users', '$role'))
print('artisans by ID check :', agg('artisans', '$verification.status', {'deleted': {'$ne': True}}))
print('bookable artisans    :', db.artisans.count_documents(live))
print('bookable by trade    :', agg('artisans', '$category_id', live))
print('bookable by area     :', agg('artisans', '$service_area.area', live))
print('rated, and average   :', list(db.artisans.aggregate([{'$match': {**live, 'rating.count': {'$gt': 0}}},
                                 {'$group': {'_id': None, 'n': {'$sum': 1}, 'avg': {'$avg': '$rating.average'}}}])))
print('bookings by status   :', agg('bookings', '$status'))
print('payments by state    :', agg('bookings', '$payment.state'))
PY
```

It loads `.env` itself and never prints it. `MONGODB_URI` and `MONGODB_DB`
in that file decide which database answers; make sure it's the one the
live app uses before you trust a count. "Bookable" is the same number the
app's welcome card calls ID-checked artisans (`/v1/catalog/stats`). No
counts are recorded here yet: run it before the first post that leans on
one.

Known landmines:

- **Few verified artisans so far.** Any "hundreds of artisans" (or
  thousands, or "every trade") claim is false until the counts back it.
  The welcome screen's stats card shows the live count and average rating;
  on the empty live database in October 2026 it read "0 ID-checked
  artisans · 0.0 average rating". Keep it out of captures, or erase it,
  until the numbers are worth showing.
- **Abuja only.** No "Nigeria-wide", no other cities, no "every area of
  Abuja" unless the by-area counts say so.
- **The payment hold.** Say "held safely until you confirm the job is
  done". Never "escrow", even though the backend's own code calls it that.
  And don't promise more than the rule: the hold also ends on its own 48
  hours after the artisan marks the job done (`auto_release_hours`)
  unless the client confirms or reports a problem first, so nothing like
  "nothing moves until you say so".
- **The SMS sender ID still says RijHub** (Termii), and WhatsApp codes
  arrive from Flutterwave's verified account without Employi's name. Don't
  show or describe a sign-in code as coming from Employi.
- **The store listings.** The App Store page still says RijHub until the
  1.2.0 update ships; check that the Google Play listing has been renamed
  too. Don't tell people to search for "Employi" until both listings show
  the new name. The badges alone are fine.
- **Sample data is made up.** Captures on sample data show invented
  artisans, prices, addresses and photos. The photos in the app's
  `assets/images/onboarding/` and `assets/mock/avatars/` carry no recorded
  licence: never use them as post imagery.

## House copy rules

- **No em dashes** in the graphic's own copy. Screenshots may contain them.
- **No launch language.** The app has been live since February 2026: no
  "now live", "launching", "out now", "coming soon", "new app".
- **The rename only in posts about the rename.** "RijHub is now Employi"
  belongs in a rename post and nowhere else; the logo's "powered by
  RijHub" is part of the art.
- **Employi**, capital E, in running copy. Lower case only in the logo.
  Capitals only in tracked eyebrows.
- **Don't over-claim.** No counts the database doesn't back, no "best",
  "trusted by", "guaranteed". "ID-checked" means the artisan matched their
  NIN to a live selfie (the app's own words); not "vetted", "certified" or
  "background-checked". "Prices up front" is the artisan's own price;
  Employi adds a small service fee on top for the client, so never "no
  fees".
- **No personal data.** Capture from demo accounts or sample data only:
  no real names, phone numbers, addresses or faces.
- **The app's own voice:** short, plain, calm. Lines the app already uses:
  "What needs fixing?", "Type, snap or say it", "ID-checked near you",
  "Top-rated in Abuja", "Free. Just your phone number." (for artisans),
  "Find jobs near you and get paid safely". Two-tone headlines with the
  second half in crimson ("What needs *fixing?*").
- **Links:** none until `SITE` and `APP_URL` are confirmed. The team's
  email is on rijhub.com and the app's share links say rijhub.com, but
  nobody has confirmed it as Employi's site: ask, never guess. When there
  is a link, give each campaign its own `?src=` tag (`instagram`,
  `billboard`, ...) so Play Console's acquisition report can tell them
  apart.
- For anything formal: "Employi, powered by RijHub", as the Terms put it.

## Campaign posts and billboards

`scripts/campaign.py` is homelands-social's `launch.py`, ported and
renamed because Employi isn't launching. Two feed posts beyond
`build.py`'s layout, and two billboards:

```bash
python3 scripts/campaign.py all -o ~/Downloads/employi-campaign   # or one:
# photo, proof, billboard-landscape, billboard-portrait
```

- **photo**: a brand photograph full bleed, "What needs *fixing?*" on its
  top, the QR and dark badges on a fade at the bottom.
- **proof**: "ID-checked. *Prices up front.*", three true proof points
  (NIN matched to a live selfie; chat and a start code; the money held
  safely until you confirm the job is done) and one phone on
  `artisan.png`, an artisan's profile with the ID-checked badge.
- **billboard-landscape**: 2:1, 48-sheet (6096 x 3048 mm). A few words,
  the logo, badges, a QR for passengers in traffic and the typed link set
  large, because most roadside readers can't scan.
- **billboard-portrait**: 2:3, 6-sheet (1200 x 1800 mm) for shelters and
  malls, where people stand close enough for a big QR.

**None of it renders yet, by design.** Every concept prints the website
and a QR, so it refuses while `SITE` and `APP_URL` are TODO. The photo
post and both billboards also need Employi content: `assets/photos/wide.jpg`,
a photograph Employi owns (HomeLands used its app's welcome artwork;
Employi's app has none). Re-check the fades against that photograph. Feed
QRs carry `?src=instagram`, billboards `?src=billboard`. Billboard exports
are concept size; for print, re-render at the vendor's spec.

## HTML posts

`examples/follow-us/` is the HTML kit for posts `build.py` can't lay out:
`common.js` (layout helpers, the logo, phones, badges, QR, and the overlap
bookkeeping), `common.css` (Inter, the palette, the phone) and `shoot.mjs`
(renders pages with headless Chrome and fails on any overlap, margin
breach, missing file or refusal). `starter.html` is the smallest page that
uses all of it.

```bash
cd ~/Desktop/projects/flutter/Rijhub-Mobile-App/.claude/skills/employi-social/examples/follow-us
node shoot.mjs OUT 1 starter       # 1080x1350; OUT 3 for the 3240x4050 HD master
```

- `shoot.mjs` loads playwright-core from employi-reel's
  `engine/node_modules`; run `npm install` there once.
- Fonts, logo and badges come from the skill's `assets/` by relative path,
  so a copy of this folder beside it keeps working. Captures come from
  `~/Downloads/employi-screens` (`SCREENS=...` to change), through
  `screen('name.png')`.
- `SITE`, `APP_URL` and `HANDLES` in `common.js` are TODO: `site()`,
  `qr()` and `need(HANDLES, ...)` throw until they are set, and a page that
  throws is never captured. A QR also needs `assets/qrS.svg`, made from
  the confirmed link (from the skill folder), then `node shoot.mjs OUT 1 page:S`:

  ```bash
  python3 -c "import sys; sys.path.insert(0, 'scripts'); import brand, segno; segno.make(brand.require('APP_URL') + '?src=socials', error='h').save('examples/follow-us/assets/qrS.svg', border=0, dark='#171717')"
  ```
- The "follow us on all our socials" post needs Employi's handles, which
  aren't on record. HomeLands' approved one (a floor plan where each
  platform's card is a room) is at
  `~/Desktop/projects/flutter/homelands_app/.claude/skills/homelands-social/examples/follow-us/follow.html`:
  read it for structure; its floor plan is HomeLands' own art.
- Keep regular posts in the house style. On HomeLands, off-theme concepts
  (an invitation flat-lay, a wall with metal letters) were rejected as
  making the account look unserious, and a concept the viewer could take
  literally, such as an event invitation, is misleading.

## Occasion greetings

`scripts/greeting.py` renders occasion posts (Independence Day, new month,
and whatever is next) as eight concepts sharing one footer: the QR beside
both store badges, then the website. **It refuses to render until `SITE`
and `APP_URL` are set**, because that footer is on every concept.

```bash
python3 scripts/greeting.py all -o ~/Downloads/out      # or one: numerals, calendar,
                                                        # receipt, stamp, lockscreen,
                                                        # label, board, triptych
python3 scripts/verify.py <file> --format feed --qr "<APP_URL>"
```

Deliberately non-white designs need the matching flags, or the white-corner
check fails by design and teaches people to ignore it: `--ground any` for
dark or textured grounds (numerals, label, lockscreen), plus `--full-bleed`
where the wallpaper runs to the edges (lockscreen).

`calendar` is the monthly template: change the month names and weekday and
it is next month's post. The dates and "66" in the other concepts are
Independence Day 2026's; change them for the next occasion.

**Photo slots are optional.** `assets/photos/{hero,wide,detail}.jpg` are
empty. Without them the numerals drop their background, the stamp
engraves the Employi pin (a map pin is a place, which is what stamps
show), the lock screen uses a green gradient, and the triptych, which is
nothing but photographs, is skipped. Fill them with photographs Employi
owns: not an artisan's photos without their consent, and not the app's
sample-data photos.

**National colours, never the flag.** Section 6 of the Flags and Coats of
Arms Act makes using the National Flag or Coat of Arms in connection with a
business, without a licence, an offence. Green-white-green carries the
meaning; the flag itself stays out.

**Dark grounds take outlined badges.** `assets/badges/*-dark.png` keep the
grey ring Apple and Google ship for dark backgrounds; the plain versions
have it stripped for white. Use the wrong one and a black badge either
vanishes into the ground or wears a sticker border.

**Tone for national days is hopeful, not triumphant.** Big Nigerian brands
lead with unity and heritage. "First class since 1960" was cut from the
HomeLands stamp for that reason: it invites "what are we celebrating?"

## One brand file, one shared engine

`scripts/brand.py` is everything that makes this Employi: the name, the
links (TODO), colours, type, the logo files. The layout engine, the
capture tooling and the verification are shared with the homelands-social
and jummall-social skills, so a fix in one belongs in all of them: copy
the changed file across and check that the other brands' renders don't
move. Where Employi's copies differ, and why:

- `build.py`: refuses `qr` and `site` while `brand.APP_URL` / `brand.SITE`
  are unset; skips the line-work when `brand.LINEWORK` is None; an unused
  alias that named a HomeLands colour is gone.
- `greeting.py`: refuses while the links are unset; the stamp fits a tall
  mark by height (the pin is 0.77:1); docstrings name no brand.
- `campaign.py`: Employi's port of `launch.py`.
- `capture/sim.sh`: finds the dedicated simulator by name, boots it
  headless, adds `go` (DevLaunch) and raises its own window before a tap.
- `examples/follow-us/`: the kit made brand-neutral (relative assets,
  `screen()`, refusals, playwright-core from employi-reel).
- `verify.py` and `qr_decode.swift` are unchanged but for one docstring
  example.

## Where this lives

The canonical copy is
`~/Desktop/projects/flutter/Rijhub-Mobile-App/.claude/skills/employi-social/`.
Once reviewed, `~/.claude/skills/employi-social` is meant to be a symlink
to it, so it loads as a personal skill in every session whichever project
is open:

```bash
ln -s "$(pwd)/.claude/skills/employi-social" ~/.claude/skills/employi-social
```

## Assets

- `assets/fonts/`: Inter Regular, Medium, SemiBold, Bold and ExtraBold
  (3.019), the app's own `assets/fonts/inter`
- `assets/brand/`: the app's own files, byte for byte, renamed:
  `logo.png` (`rijhub_logo.png`, 1261x400), `logo-on-dark.png`,
  `logo-white.png`, `mark.png` and `mark-white.png` (the pin alone,
  464x600), `app-icon.png` (`assets/icon/app_icon.png`, 1024px). The file
  names in the app still say rijhub; the art is Employi's. Scale only,
  never redraw
- `assets/badges/`: official App Store and Google Play artwork; plain
  versions stroke-stripped for light grounds, `-dark` versions outlined
- `assets/photos/`: optional brand photographs for the greetings and
  campaign concepts (empty)
- `scripts/capture/`: `sim.sh` and `simtap.swift`, the simulator capture
- `scripts/qr_decode.swift`: QR reader via macOS Vision, used by `verify.py`

Brand colours (`lib/core/theme/palette.dart`): crimson `#A20025` (crimson600,
from the logo; 8.2:1 on white, so it carries small text too), with the
scale 50 `#FCF2F4`, 100 `#F9E3E8`, 200 `#F2C4CE`, 300 `#E595A6` (crimson
text on dark grounds), 400 `#D25A75`, 500 `#BB1C43`, 700 `#87001F`, 800
`#6C0019`, 900 `#520013`. Ink `#171717` (the logo's black), muted text
`#6B6B6B`, light ground `#F7F7F7`, success `#16A34A`.
