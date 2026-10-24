---
name: employi-store-graphics
description: Make Employi's App Store and Google Play graphics in the approved Knolling style (a tradesman's kit laid out flat round the device, a different kit per graphic), from real screens captured on dedicated simulators and an emulator, rendered by headless Chrome at each store's exact size, checked, and packaged with the listing text into one upload folder. Use whenever asked for Employi (or RijHub) store screenshots, store graphics, App Store or Play Store images, the feature graphic, the store icon or the listing text.
---

# Employi store graphics

Renders every store image from HTML: real app screens inside drawn device
frames, a two-line headline in Inter, and a knolled kit of vector tools on a
workshop bench. Nothing is image-generated, and the same inputs give the
same pixels. One template (`concepts/knolling.html`) draws all six graphics
in all four formats.

## The approved style: Knolling (chosen 23 October 2026)

Five concepts were made for the first graphic (`concepts/v1` to `v5`:
Conversation, Split, Schematic, Knolling, Map). The owner chose **Knolling**:
"It's the most creative thing I've ever seen... replicate that creativeness
across all the store graphics". It works like this:

- **A bench, shot from above:** warm concrete (#F2EEE9 to #DED8D0) with grain.
- **The kit:** tools in brand colours only (crimson grips, black rubber,
  brushed steel), laid square to the canvas and spaced evenly.
- **A kit per graphic, and each kit means something:**

| | Headline | Screen | Kit |
|---|---|---|---|
| 1 | Say what's wrong. Get a trusted artisan. | Ask conversation | screwdriver, AC remote (24°), nuts, spanner, level, hammer, bulb, brush; tape beside "artisan." |
| 2 | ID-checked artisans. Prices up front. | artisan profile | ID card, magnifier, rubber stamp and its CHECKED mark, pencil, clips; a ₦10,000 price tag |
| 3 | Book in minutes. Pay safely. | booking summary | stopwatch, key, receipt ("Held safely"), coins, OCT 24 calendar, pen, card; padlock beside "Pay safely." |
| 4 | Follow every step. Right to the end. | on the way, start code 4829 | clipboard with the job's steps ticked, torch, hard hat with the pin, gloves, tape roll, zip ties |
| 5 | Chat with your artisan. Right in the app. | chat | walkie-talkies, crimson and black like the logo's halves, flanking the phone; notepad, pencil, sticky notes |
| 6 | Artisan? Get booked. Get paid. | artisan wallet ("Sent to your bank") | toolbox, multimeter, pliers, coins; wallet beside "Get paid." |

- **Rhythm:** devices are centred (1, 3, 5), left (2, 6) and right (4).
- **Creative wit:** items placed beside the words they echo (the padlock by
  "Pay safely.", the price tag by "Prices up front."), and the screens'
  details repeated in the kit (the clipboard's steps, the calendar's date,
  the receipt's total).
- **The lockup:** `assets/brand/lockup.png`, made by `scripts/lockup.py`. The
  owner found the logo file's pin too big beside "employi", so the pin is
  scaled to 78% and centred on the word. It's the same art, never redrawn.

## Store slots

| Format | Size | Device | Screens from |
|---|---|---|---|
| `iphone` | 1320 x 2868 (App Store 6.9") | iPhone 17 Pro Max | "Employi Store iPhone 6.9" simulator |
| `ipad` | 2064 x 2752 (App Store 13"; required, the app runs on iPad) | iPad Pro 13" | "Employi Store iPad 13" simulator |
| `android` | 1080 x 1920 (Play phone) | Android phone, punch-hole camera | emulator-5580 (RijHub_Client) |
| `tablet` | 1440 x 2560 (Play 7" and 10", one set fits both) | the iPad frame | the iPad captures with an Android status bar (`scripts/android_bar.py`) |
| feature | 1024 x 500 (Play feature graphic) | none | `concepts/feature.html` |

The owner's tip: Play's tablets reuse the iPad frame and captures, because
an iPad has no Dynamic Island. Never put an iPhone frame or an iOS status
bar in a Play image.

## Capture

**One device at a time:** boot it, capture, shut it down, then start the
next. The owner is memory-conscious.

```bash
cd ~/.claude/skills/employi-store-graphics/scripts
# the build: a debug build against the demo server (its own database, Paystack test keys)
flutter build ios --simulator --debug --dart-define=API_BASE_URL=https://demo---rijhub-api-u64o6bn7gq-nw.a.run.app
python3 capture.py install iphone && python3 capture.py plan ../shots.json iphone && python3 capture.py finish iphone
python3 capture.py install ipad   && python3 capture.py plan ../shots.json ipad   && python3 capture.py finish ipad
# Android: build the debug APK the same way, boot only emulator-5580, then
python3 capture_android.py install phone && python3 capture_android.py plan ../shots.json phone
python3 capture_android.py finish phone && adb -s emulator-5580 emu kill
python3 android_bar.py                    # ipad-*.png -> tablet-*.png
```

- **No taps.** The app's debug launch file (`lib/app/dev_launch.dart`) opens
  any screen. `shots.json` lists each shot's launch.
  - `"as": "client"` or `"artisan"` signs in as a demo account, with the
    credentials in `demo.local.json`, which git ignores because a Firebase
    test number signs in anywhere.
  - `"ask"` and `"askScript"` play the Ask conversation as far as the booking
    summary.
- **Demo data lives in `rijhub_demo` only.** The stagers are in the session
  scratchpad, so redo them if they're lost:
  - Amaka and Emeka, from the walkthrough.
  - An on-the-way booking (ref RJH-60412, start code 4829, today 10:00 Lagos).
    Re-run its stager on another day so it still reads "Today".
  - Emeka's GTBank •••• 6789 and his payout.
- Copy the shots into `assets/screens/<format>-<name>.png` before rendering.

## Render, check, package

```bash
cd ~/.claude/skills/employi-store-graphics
npm install                                      # once: playwright-core
node render.mjs out/final $(for f in iphone ipad android tablet; do for i in 1 2 3 4 5 6; do
  echo "concepts/knolling.html?slide=$i&format=$f"; done; done) concepts/feature.html
python3 scripts/package.py out/final "$HOME/Downloads/Employi Store Listing"
```

- `render.mjs` draws at 2x and downsamples with Lanczos to the exact size, as
  RGB (both stores reject alpha).
- It fails on overlapping information or on text outside the margins. Every
  tool, line, pin and device registers its box. The first map pin collided
  with the headline because it hadn't.
- `package.py` names files in upload order, adds the icons and the listing
  text (`listing.py`, every field checked against its limit), and runs
  `scripts/verify.py` on each slot.

## Claims (checked 23 October 2026; check again before changing copy)

- **ID-checked:** artisans are listed only once verified.
- **Prices up front:** every service shows its price before booking.
- **Money held until the job is done:** it's released when the client
  confirms, or 48 hours after the job is marked done. A problem raised
  pauses the release until support decides. So never "only when you say".
- **Paid straight to their bank:** automatic payouts are live on the demo
  server. They're live in production once the payout revision takes traffic.
  Without a bank account the money waits in the wallet.
- **Leave out:**
  - voice notes, which the app can't understand yet (the server answers 503);
  - any artisan count, since there are few artisans so far;
  - "escrow";
  - anywhere outside Abuja.
- **No personal data:** demo accounts only, with no em dashes in our copy.

## Traps (each happened once)

1. **Captures signed in as the wrong person.**
   - Reset kept the last account's server session, so the profile showed
     "0.0 km" (seen as the artisan himself) and the chat came out from the
     artisan's side. The launch file now signs out first.
   - Repeated sign-ins tripped the server's limit on code requests ("That's
     a lot of codes"). Now a run signs in once and later shots keep the
     session. To clear the demo counters, delete `otp-*` from
     `rijhub_demo.limits`.
2. **A deploy in the middle of a capture run** broke its sign-ins. Don't
   redeploy the demo server while capturing.
3. **A pop-out that half-covers its original** shows the text twice. Centre it
   over the source.
4. **Tracking:** -0.04em is too tight at Inter Display sizes; use -0.026 to
   -0.035em. `.hl span` needs `width: max-content` to be measured.
5. **₦ is in Inter's latin-ext subset.** Load both woff2 subsets.
6. **Beside items squeezed into a sliver came out tiny.** One sits beside the
   words only at near its own size; otherwise it joins the wider column.
7. **The app's own bugs show in screenshots.** Fix them in the app rather
   than hiding them: "1 reviews", an unknown reply rate shown as "0%", and
   the area repeated in the summary.

## Moving it to Jummall and HomeLands

The engine (`kit/`, `render.mjs`, `scripts/verify.py`, `scripts/finish.py`)
is brand-neutral. A sibling skill copies it and swaps:

- the brand tokens and fonts in `kit/base.css`;
- the lockup;
- the kits (Jummall: aisles and baskets; HomeLands: a draughtsman's tools);
- `SLIDES` in `knolling.html`;
- the capture plans.

## Where this lives

The canonical copy is `Rijhub-Mobile-App/.claude/skills/employi-store-graphics/`,
and `~/.claude/skills/employi-store-graphics` is a symlink to it.
`node_modules/`, `out/` and `demo.local.json` are gitignored.
