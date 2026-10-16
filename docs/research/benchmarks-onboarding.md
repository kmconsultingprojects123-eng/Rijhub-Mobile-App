# Research: onboarding

Written in October 2026, while rebuilding the homes after the first redesign was rejected. The "current screens" it critiques are that first redesign, since replaced; the benchmarks and sizing rules still apply.

## Recommended layout

IN ONE LINE: make 'look around' the default and obvious path, put the artisan door one line below it, keep 'Sign in' small in the top right, and only ask for a phone number at the last step of a real action.

A. WELCOME, VARIANT 1 (RECOMMENDED): 'live welcome' sheet over the real home
Shown on first launch only. The system splash (app icon on crimson) goes straight here; the extra Flutter splash and its 1.1s wait are removed.
Behind the sheet (y 0–844): the real guest client home, already rendered with live data (area chip, 'Sign in', search, categories, top-rated artisans) under a 40% black scrim (60% in dark mode). It is visible but clearly not the thing to tap.
Sheet: modal bottom sheet, white (neutral-900 in dark mode), top radius 28, sized to its content, about 408pt tall (y 436–844).
  y 444–448   drag handle, 32x4, centred
  y 464–496   header row: RijHub logo (24pt tall) on the left; 'Sign in' text button on the right (15/20 semibold, crimson, 48x48 tap target)
  y 512–580   headline 28/34 bold, 2 lines: "Abuja's verified artisans, / one tap away" (checked with the bundled Inter-Bold: line 1 is 319pt of the 350pt available)
  y 588–632   body 15/22, secondary colour, 2 lines: "Look around first. You'll only need your phone number when you book."
  y 644–662   trust line 13/18 medium, 1 line, 16pt icons: "✓ ID-checked artisans · 🔒 Payment held until the job is done" (each part opens a one-screen explainer)
  y 682–738   PRIMARY button, 56pt, full width (350pt), crimson: "Explore as a guest →"
  y 750–802   SECONDARY button, 52pt, full width, 1pt neutral outline, radius 12: [briefcase 20pt] "I'm an artisan — find work"
  y 810–844   home indicator / safe area
How it behaves:
  - 'Explore as a guest', swiping the sheet down, or tapping the scrim all make the person a guest client. The sheet slides away (240ms) and the home is already there.
  - 'I'm an artisan' cross-fades the background to the artisan guest home (real 'Jobs near you' with budgets, areas and post times), then the sheet slides away.
  - 'Sign in' swaps the same sheet to the phone step, with no new screen.
  - Returning people go straight to Home.
  - Offline: the background shows cached categories and skeleton cards, and both buttons still work.
  - TalkBack order: headline, body, trust line, primary, secondary, Sign in. The scrim is not a separate focus stop.
  - Data: no hero photo. The background reuses the home's own 160px WebP thumbnails (about 60–80KB in total; estimate).

B. WELCOME, VARIANT 2 ('STOREFRONT'): fallback, or the B arm of an A/B test
Use this if the home can't be meaningful on the very first, offline launch.
  y 0–452     ONE static photo of a real RijHub artisan in Abuja (with consent), full bleed under the status bar, with a gradient to 60% black over the bottom 140pt. No carousel, no chip. WebP of 100KB or less at 1080px wide.
  y 47–95     top bar, 48pt: logo (white, 28pt tall) on the left; 'Sign in' white text button on the right (48x48 target)
  y 440–844   white panel, top radius 28, overlapping the photo by 12pt:
    y 464–532 headline 28/34 bold, 2 lines (same copy as Variant 1)
    y 540–584 body 15/22, 2 lines (same copy)
    y 604–660 PRIMARY, 56pt, crimson: "Explore as a guest →"
    y 672–724 SECONDARY, 52pt, outlined: "I'm an artisan — find work"
    y 744–760 trust line 12/16, tertiary colour, centred: "ID-checked artisans · Payment held until the job is done"
    y 776–792 optional footnote 12/16: "You can switch any time in Profile"
    y 810–844 home indicator
Removed compared with today: the two 169x148pt tiles, the 'Already have an account?' footer, 4 of the 5 photos, the auto-rotation and the trade chip.

C. REJECTED: a segmented control ("I need an artisan | I'm an artisan", 40pt) above one CTA
It adds a decision to the majority path and still reads as choosing an account type. Upwork asks the role at sign-up only because it sets the account type; RijHub can learn the role from which door is used.

D. 360x800dp ANDROID CHECK (24dp status bar, 48dp 3-button nav, screenutil scale 0.923)
  - Headline renders at 25.8/31 and stays 2 lines; measured line 1 is 292 of the 323pt available.
  - Body stays 2 lines.
  - Buttons stay 52dp and 48dp (the AppSize floors).
  - The Variant 1 sheet is about 392dp, leaving about 408dp of live home visible.
  - At 1.3x font scale the headline may wrap to 3 lines: let the sheet grow and keep the buttons pinned. Never shrink buttons below 48dp.

E. FIRST SCREEN AFTER THE WELCOME (guest)
  - At least one artisan card must be above the fold on 390x844 (today the first is at y=836, under the tab bar at 750); the home track owns this layout.
  - Keep 'Sign in' as the small header button (Jiji's pattern).
  - Add a 13/18 link at the end of the client home: "Are you an artisan? Find work on RijHub →" (Lyft-style door) for people who dismissed the welcome fast.
  - Deep links from WhatsApp (rijhub.com/a/<artisan>, /j/<job>) skip the welcome and open that page directly as a guest.

F. SIGN-IN SHEET WHEN A GUEST COMMITS (example: 'Book Emeka')
Trigger: only the LAST step of an action (Confirm booking, after describing a job, Send quote, Message). Never on app open, never from a tab.
Sheet: radius 28, sized to its content (about 480pt), rises above the keyboard so the CTA is always visible.
  - drag handle 32x4; close X (24pt icon, 48pt target) top right
  - context card, 64pt: 40pt avatar, "Emeka Nwosu ✓" (15/20 semibold), "AC servicing · Sat 18 Oct, 10:00 · ₦8,000" (13/18)
  - title 22/28 bold: "Confirm with your phone number"
  - body 15/22: "We'll text you a 6-digit code. No password. Emeka won't see your number — you'll chat in RijHub."
  - phone field, 56pt: [🇳🇬 +234 | 803 123 4567]
  - PRIMARY, 56pt: "Text me the code"
  - text button, 44pt: "Send it on WhatsApp instead" (only once that route is live)
  - legal 12/16: "By continuing you agree to RijHub's Terms and Privacy Policy."
  - Hide Google and Apple until they work.
Code step: same sheet; 6 boxes of 48x56; SMS auto-read; resend timer.
New number: one more field, "Your first name". Artisans give a name and up to 3 trades, pre-filled from the job's trade.
On success: the original action completes by itself and the sheet closes onto the result ("Request sent to Emeka · usually replies in ~10 min"). Any success beat stays at 900ms or less.
On close: nothing typed or chosen is lost, and there is no new prompt until the next commitment.
Titles per trigger:
  - Book: "Book Emeka"
  - Post a job (shown after the description): "Where should quotes go?"
  - Message: "Message Emeka"
  - Send quote: "Send your ₦12,000 quote"
  - Save (♥): no prompt; it saves to the guest session. After 2 or more saves, one inline card offers "Keep your saved artisans on any phone."

G. GUEST TABS (390x844; content runs y 62–750; empty states start just under the title rather than centred)
BOOKINGS (client guest):
  y 86–118    title 'Bookings', 26/32
  y 134–206   only if a draft or recent artisan exists, a 72pt card: "Pick up where you left off · AC not cooling (draft)" [Continue]
  y 222–278   56pt icon
  y 290–316   "No bookings yet", 20/26 bold
  y 322–366   "Book an artisan and you'll follow the job here, from 'on the way' to 'paid'.", 15/22
  y 382–430   PRIMARY, 48pt: "Find an artisan" (goes to Home)
  y 438–482   text button, 44pt: "Booked before? Sign in"
  y 506–674   'How booking works' in 3 rows of 56pt (32pt numbered circle + 15/22 text):
              1. Pick a verified artisan and see the price first
              2. Pay into RijHub — we hold it
              3. Release it when the job is done
  Artisan 'Schedule' version: "No jobs yet" + "See jobs near you" + "Sign in" + 'How you get paid' in 3 rows.
MESSAGES (guest):
  y 86–118    title 'Messages'
  y 134–206   pinned 72pt row: 44pt RijHub avatar, "RijHub Help" (15/20 semibold), "Ask us anything — we reply in about 10 min" (13/18), chevron. Opens a support chat that works without an account (guest session).
  y 238–286   48pt icon
  y 298–322   "Chats with artisans show up here", 17/22
  y 328–372   "Message an artisan from their profile. You'll add your number then.", 15/22
  y 388–436   SECONDARY, 48pt: "Find an artisan"
  y 444–488   text button: "Sign in to see your chats"
PROFILE (guest):
  y 86–118    title 'Profile'
  y 134–206   72pt identity row: 48pt grey avatar, "You're browsing as a guest" (15/20 semibold), "Sign in or create an account" (13/18, crimson), chevron. The whole row opens the sheet.
  y 230 on    56pt rows (Material 3 one-line list height), 13/18 section labels, 24pt between sections:
              YOU: Area · Wuse 2 › | Saved artisans · 3 › | Switch to artisan mode ›
              SETTINGS: Language · English › | Appearance · System ›
              HELP: Chat with RijHub Help › | How RijHub keeps you safe › | Help centre ›
              ABOUT: Terms › | Privacy › | Version
EXPLORE: until the real screen ships, send it to search plus all categories rather than a 'Coming in the redesign' placeholder.

H. CHANGING ROLE LATER
  - A Profile row: "Switch to artisan mode" or "Switch to hiring" (Airbnb, Fiverr).
  - Long-pressing the Profile tab as a shortcut (Airbnb: 'Hold Profile and then tap Hosting').
  - The client-home footer link from E.
  - One account can hold both modes on the same phone number; switching never signs the person out.

I. COPY DECK
Welcome:
  - Headline: "Abuja's verified artisans, one tap away" (alternative: "Verified artisans, ready when you are")
  - Body: "Look around first. You'll only need your phone number when you book."
  - Trust line: "ID-checked artisans · Payment held until the job is done"
  - Primary: "Explore as a guest" (A/B alternative: "Find an artisan", with the body line kept)
  - Secondary: "I'm an artisan — find work"
  - Top right: "Sign in"
Never use on the welcome: "Already have an account?", "Sign up", "Register" or "Create account".

## Critique

- **Welcome**: The guest option is invisible. The two role tiles are the guest entry, but nothing on the screen says guest, explore, browse or 'no account needed'. (Code: both tiles call SessionController.continueAsGuest(role) (welcome_screen.dart, _enter). The only text near them is 'Already have an account? Sign in'. Baymard (Jan 2023): a guest option people don't notice is 'as bad as if it wasn't offered at all'; it should be a button, placed at the top, using the word 'Guest'. The product owner's reading ('forcing users to sign up') is exactly what that research predicts.)
- **Welcome**: The footer 'Already have an account? Sign in' makes the whole screen read as a sign-up form. (That sentence is the standard footer of registration forms. TaskRabbit's Sign Up form (Jan 2026) ends with 'Already have an account? Log in', and eBay's sign-in screen uses the mirror line 'Haven't signed up yet? Create an account'. Placed under two 'pick your type' tiles, it reads as 'create an account as a client or an artisan', which is Upwork's sign-up role step. Semantics dump: the sign-in row is 234x48pt at y=762.)
- **Welcome**: The role tiles are oversized and equally weighted, so the screen has no primary action. (Each tile is 169x148pt (semantics dump, y=606–754), 2.6 times RijHub's own large button (AppSize.buttonLarge, 56pt). The two saturated tiles cover about 50,000pt², roughly 15% of the 390x844 screen, for a two-way choice. Benchmarks solve the same problem with one 48pt primary and a one-line provider door (Lyft: 'Get started' plus 'Ready to earn? Open the driver app →'), or with a mode switch later (Airbnb: 'Hold Profile and then tap Hosting').)
- **Welcome**: An auto-rotating five-photo hero uses half the screen, and a lot of memory, to say one word. (The photo area runs from 0 to 447pt (53% of 844pt), and its only content is a 32pt chip reading 'AC technicians'. Five photos cross-fade every 3.8s (Timer.periodic 3800ms with a 900ms fade); NN/g's auto-forwarding research in the earlier brief found moving panels read as ads and hurt lower-literacy readers. The five WebPs are 992x1488 and add 724KB to the app. precacheImage decodes all five at full size (~5.9MB each, ~30MB in total) under AssetImage keys, but the screen draws ResizeImage keys, so each photo shown is decoded twice. Target phones such as the Tecno Spark 40 have a 6.67in 720x1600 screen and 4–8GB RAM (GSMArena).)
- **Welcome**: The message is generic and hides RijHub's two real advantages. (The copy is 'Find trusted artisans near you / Verified pros for every job in Abuja.' (32/38 display). It never says you can look around without signing up, or that payment is held until the job is done. The closest local rival makes users sign up first ('Sign up as a user' comes before 'Select a service' in wrkman's App Store listing, Oct 2026) and leads with 'escrow protection', so RijHub's welcome undersells its edge. The home headline 'What do you need help with today?' is almost identical to wrkman's 'What help do you need today?'.)
- **Splash to welcome**: Two brand screens and an artificial 1.1s wait before the first decision. (SplashScreen fades the logo in over 600ms and then waits Future.delayed(1100ms), even though the session is already restored; the router then cross-fades for 350ms. Android's guidance says the system splash 'is dismissed as soon as your app draws its first frame', and its design guidelines 'recommend against using a branding image'. Apple's HIG says 'The launch screen isn't a branding opportunity' and that people 'sometimes … don't want to wait more than a couple of seconds.')
- **First screen after the welcome (client guest home)**: The welcome's promise isn't kept: a guest who taps 'Hire an artisan' sees no artisans. (Client guest home semantics: the 'Top-rated in Abuja' header is at y=798 and the first artisan cards at y=836, below the tab bar at y=750, so there are no artisans above the fold. Above them sit a greeting, a 64pt two-line headline, a 52pt search field, 8 category tiles (y=370–554) and a 176pt crimson 'Post a job' card. The layout fix belongs to the home track, but for onboarding it means guest exploring starts with nothing to explore.)
- **Sign-in sheet (Post a job, Send quote)**: The account is requested before the person has put anything in. (_postJob() in client_home_screen.dart calls ensureSignedIn(AuthPrompt.postJob) before any job form appears. _sendQuote() in artisan_home_screen.dart asks the artisan to 'Create your free profile' before a quote is written. Baymard recommends moving account creation to the confirmation step. Luke Wroblewski's 'gradual engagement' (Sign Up Forms Must Die, A List Apart) lets people do the task first, and Duolingo's later sign-up (earlier brief) points the same way.)
- **Sign-in sheet (all prompts)**: A dead full-width 'Continue with Google' button, and no context or reassurance. (In phone_step.dart, tapping Continue with Google only shows 'Google sign-in is coming soon. Use your phone number for now.', so a full-width outlined button competes with 'Send code' and does nothing. The sheet has a title ('Post your job', 'See your bookings') but never shows what is being confirmed (artisan, time, price), and never says artisans won't get the client's number. Apple's HIG on managing accounts: 'write a brief, friendly description of the reasons for the requirement and its benefits. Display this message in your sign-in view.')
- **Bookings and Messages tabs (guest)**: Both tabs are dead ends whose only action is 'Sign in or sign up'. (Semantics: the heading is at y=391 and a 286x48pt 'Sign in or sign up' button at y=493, in a body running from y=62 to 750, with about 180pt of empty space above the icon and below the caption. There is no way back to exploring and no explanation of how booking or payment protection works. Booking.com's empty Trips tab explains what will appear there, and Airbnb's Messages includes a 'Support' thread type. Two of RijHub's five tabs give a guest nothing.)
- **Profile tab (guest)**: A 216pt join card and nothing else, so guests can't reach help, safety information, terms, their area or appearance settings. (Semantics: the 'Join RijHub' card is 350x216pt (y=142–358), followed by a 350x74pt 'Are you an artisan? Find work on RijHub' card, then about 300pt of blank screen down to the tab bar. Craigslist's logged-out account tab (May 2026) still lists settings, feedback, privacy and about.)
- **Explore tab**: For guests, the tab actually named Explore is a placeholder. (ExploreTab returns _ComingSoon('Coming in the redesign') for both clients and artisans (tab_screens.dart). Exploring is the whole point of guest mode, yet the second tab is a dead end.)
- **Artisan guest home**: A 274pt sales card sits above every job, so a guest artisan sees only one job before scrolling. (Semantics: the join card is 350x274pt (y=140–414) with three bullet lines, a 56pt 'Create your free profile' button and a caption. 'Jobs near you' starts at y=446, the first job card runs y=536–707, and the second is cut off by the tab bar at 750. Everand's single promo card is about 150pt and sits beside content, not in place of it.)
- **Onboarding preview board shown to the product owner**: The preview presented onboarding as sign-up: four of six panels are account screens, and none shows what a guest can do. (rijhub-onboarding-preview.jpg panels: Welcome, 'Sign-in sheet, only when needed', '6-digit code', 'New artisan: name and trades', 'Done', and 'Area picker'. Nothing shows the guest path after the welcome (home, then an artisan profile, then booking, with the sheet at the end). Future previews should lead with that journey.)

## Benchmarks

- **Duolingo: welcome screen (iOS capture, 2 Aug 2026). Guest-first done right.**: Make the primary verb about starting to use the product, never 'Sign up'. Give returning users a full-width but quieter outlined button, and don't add a third option. Create the account after the person has had some value; the earlier brief's First Round source reports about 20% more daily active users from moving sign-up later.
- **Lyft: rider welcome (iOS capture, 29 Jan 2026). A two-sided marketplace handled with one line.**: Treat the provider side as a clearly labelled secondary door under the consumer button ('Ready to earn?') instead of two equal tiles. Offer language at the door.
- **Depop: welcome for a buy-and-sell marketplace (iOS capture, 23 Nov 2025)**: Copy the one headline that speaks to both sides, so no role question is needed to understand the app. Don't copy the guest path hidden as a corner 'Skip'; it fails the same way the product owner says RijHub's welcome fails.
- **Etsy: sign-in screen at launch (iOS capture, 28 Jan 2026). A counter-example for the guest option.**: Copy the single combined action 'Sign in or create account' (one flow for new and returning people). Don't copy the guest link. Baymard (Jan 2023) found 47% of sites fail to make guest the most prominent option, and text links get missed. It recommends a button, placed at the top, that uses the word 'Guest'.
- **Airbnb: combined 'Log in or sign up' sheet (iOS capture, 26 Jan 2026) and host/guest mode switch**: There is no separate sign-in vs sign-up decision: one phone-first flow works it out from the number. The provider side is a mode, not a launch question; the help article says 'Hold Profile and then tap Hosting.' The notification pre-prompt comes in context, after sign-up. A 2021 Pratt critique notes the sheet 'pops up automatically when entering the app', so Airbnb's launch ask was a sheet over the app, not a separate gate (not re-verified for 2026).
- **eBay: home and sign-in modal (iOS capture, 27 May 2026). Buying and selling in one app.**: The selling side is a tab in the same app, not a first-launch fork. The sign-in screen leads with a benefit and can be closed so browsing continues.
- **Everand: flow titled 'Explore without signing up' (iOS capture, 23 Nov 2025)**: Guests land on real content. The account ask is a single card in the feed, not a gate, and the Saved and Account tabs exist for guests.
- **Uber Eats, Pinterest and Nextdoor: sign-in walls at launch (iOS captures, 2025–26). Contrast set.**: Copy the tight, consistent 48pt button rhythm, not the wall. NN/g (Budiu, 2014): 'Users are utterly vexed to have to enter information before they get a taste of what is in store for them.'
- **Jiji Nigeria: classifieds (help centre text; no screenshot verified)**: Nigerian users already know the pattern: browse freely, a small 'Login' top right, and phone plus SMS to join. Put RijHub's 'Sign in' in the same place, and use phone plus code as the only required path.
- **wrkman: Nigerian artisan app in Lagos and Abuja (NG App Store listing v37.10.1, 6 Oct 2026). Direct competitor with a sign-up wall.**: Nothing to copy; use it as the contrast. RijHub's no-sign-up browsing is a real advantage over its closest local rival, so the welcome must say so plainly. Note too that wrkman's home headline ('What help do you need today?') is almost the same as RijHub's ('What do you need help with today?').
- **TaskRabbit: sign-up modal and home (iOS capture, 29 Jan 2026)**: Use a search placeholder with real examples (for RijHub: 'Try "AC not cooling" or "gen won't start"'). The lesson for RijHub: 'Already have an account? Log in' is the footer of a sign-up form, so the same sentence under RijHub's tiles makes the welcome read as sign-up. Whether TaskRabbit itself allows guest browsing is not verified; the X suggests the modal can be closed.
- **Craigslist logged-out Account tab and Booking.com empty Trips tab (iOS captures, 27 May 2026)**: A guest's Profile tab should still be a working settings and help page. Empty states should name what will appear and point to the next useful action.
- **Upwork (formerly oDesk) and Fiverr: when two-sided freelance marketplaces ask for the role**: Don't make the role a gate. Learn it from which door the person uses, and keep a mode switch in Profile.
- **Jumia Nigeria, Chowdeck and Glovo: Nigerian commerce and delivery (store screenshots and third-party text only)**: Treat 'account at checkout, not at the door' as the local commerce norm (weak evidence). Before final sign-off, check Chowdeck, Glovo and Bolt on a test phone.

## Ideas

- A 'live welcome': the welcome is a bottom sheet over the real, already-loaded home (Variant 1), and 'Explore as a guest' simply lowers the sheet. (value: People see real artisans, prices and ratings before deciding anything, so 'you can look around' is shown rather than claimed. There is no navigation step and no hero photo to download or decode.)
- Account-last flows: finish the action first (describe the job, pick the time and price, type the quote), then confirm with a phone number as the final step. The action completes automatically once the code is entered. (value: Giving a phone number feels like 'send', not 'register'. The person has already put in effort and sees exactly what they are confirming.)
- A guest session from first launch, holding no personal data, that is upgraded in place when the person verifies a phone number. Since RijHub controls the backend, this can be a guest token plus a merge endpoint. (value: Saved artisans, recent searches, drafts, the chosen area and the support chat all survive sign-up, so the sheet can honestly say 'your 3 saved artisans come with you'.)
- Let artisans try their side before choosing: 'I'm an artisan' swaps the live background to real 'Jobs near you' (budgets, areas, minutes since posting) before any sign-up. (value: Artisans see real demand and earning potential first, which is the strongest reason to register.)
- One door for clients and one for artisans on the welcome, with a reversible mode switch later (a Profile row plus a long-press on the Profile tab). (value: Either audience gets in with one tap, clients never see artisan tools, and nobody is locked into their first choice.)
- Links shared on WhatsApp skip the welcome: rijhub.com/a/<artisan> and /j/<job> open that page directly as a guest, including straight after install. (value: Referrals, which is how Nigerians actually find artisans, land on the exact artisan with reviews and a Book button, with no detour.)
- A sign-in sheet that shows what is being confirmed and makes a privacy promise ('Emeka won't see your number — you'll chat in RijHub'). (value: It feels like the next step of booking rather than a login wall, and it answers the scam and harassment worry at the moment of commitment.)
- A support chat that works for guests: 'RijHub Help' pinned at the top of Messages. (value: A guest can ask 'Is this safe? How does payment work?' before giving a number, which builds trust before commitment and stops Messages being a dead end.)
- Soft prompts that are earned, never shown on open: after 2 or more saved artisans or 5 profile views, one inline card that can be dismissed ('Keep your saved artisans on any phone — add your number'). (value: The ask appears when there is a reason for it, and dismissing it costs nothing.)
- Say the advantages at the door: 'No sign-up to look around' and 'Payment held until the job is done', each tappable for a one-screen explainer. (value: It addresses the two biggest Nigerian hesitations, forced registration and being cheated, in the first few seconds, and sets RijHub apart from the walled local rival.)
- No double splash: go from the system splash (icon) to the welcome or home on the first frame, and let the welcome carry the brand moment. (value: Every cold start reaches the first decision about 1.1–1.5s sooner on Tecno, Infinix and itel phones.)
- An optional language choice at the door (English or Pidgin), added only once a full Pidgin copy set exists. (value: Lower-literacy and Pidgin-first users feel addressed from the first screen.)

## Sizing

- Touch targets: at least 48x48dp on Android ('at least 48dp x 48dp', Android accessibility docs) and 44x44pt on iOS (Apple HIG default; 28x28 is the absolute minimum). RijHub's AppSize.minTapTarget is already 48. Keep text buttons such as 'Sign in' padded to 48 even when the visible text is 15pt.
- Button heights: primary 56pt, secondary 48–52pt, text buttons 44–48pt of tap height. Measured from 3x captures: Airbnb's sheet uses a 56pt primary with 47pt secondaries; Duolingo, Uber Eats, Lyft and Nextdoor use 48pt; eBay 40pt; Pinterest about 36pt. Flutter's Material 3 FilledButton minimum is 64x40 (Flutter SDK, filled_button.dart).
- A two-way choice is never bigger than the primary button. Express the role as one 56pt primary plus one 52pt secondary, or as a 40pt segmented control (Flutter's M3 SegmentedButton is 40 tall, for 2–5 options). Today's role tiles are 169x148pt, 2.6 times the 56pt button, and cover 15% of the screen.
- Leave 12pt between stacked buttons. Apple HIG: 'about 12 points of padding around elements that include a bezel', and about 24pt around elements without one. Measured gaps: Uber Eats and Nextdoor 8pt, Duolingo 15pt, Airbnb 16pt.
- Put the welcome's decision block in the bottom 45–50% of the screen, the thumb zone. Hoober (UXmatters, 2013, 1,333 observations): 49% of people use the phone one-handed, 36% cradled, 15% two-handed. Lyft, Duolingo and Nextdoor all put their buttons in the bottom third.
- Keep hero media to about half of a 390x844 screen (420pt or less) and static, with at most one image on the welcome: a WebP of 100KB or less at 1080px wide. That budget is inferred from today's 126–178KB files; the current hero is 447pt (53%) and rotates through five photos.
- Entry-screen type: headline 28/34 bold, at most 2 lines at 360dp (Material 3 headlineMedium is 28/36 in Flutter's typography.dart; measured with the bundled Inter-Bold, "Abuja's verified artisans," is 292pt of the 323pt available). Body 15–16 on 22–24. Button labels 16/20 semibold. Footnotes 12–13 on 16–18. No more than 5 text sizes per screen; today's welcome headline is 32/38.
- Bottom sheets: 32x4 drag handle (Flutter's M3 default in bottom_sheet.dart), top radius 28 (RijHub's AppRadius.xl and the M3 sheet shape), 20pt side padding. Height follows content: the welcome sheet is about 408pt (48%) and the sign-in sheet about 480pt without the keyboard. The sheet must rise with the keyboard so the main button is never covered (Baymard: Walgreens' keyboard hid its guest option).
- The context card inside a sign-in sheet is 64pt tall: a 40pt avatar plus two lines at 15/20 and 13/18.
- Guest prompts inside content are 88pt tall or less (one line plus one 36pt small button) and never sit above the first content item. Today's artisan join card is 274pt and pushes the first job down to y=536.
- Empty states in tabs start just under the title, no more than 120pt below it. Use a 48–56pt icon, a 20/26 title, at most 2 body lines at 15/22, a 48pt primary button for the next useful action, and sign-in as a 44pt text button. Never centre them vertically in the 688pt body; today they leave about 180pt blank above and below.
- List rows are 56pt for one line and 72pt for two lines (Flutter SDK list_tile.dart defaults: 56/72/88 for one, two and three lines), with 16–20pt icons and 24pt between sections.
- Chips are 32dp tall visually with a 48dp touch area (Flutter M3 _kChipHeight = 32).
- Design and test at 360x800dp with font scale 1.3. The Tecno Spark 40 has a 6.67in 720x1600 screen and 4–8GB RAM (GSMArena); 720px at xhdpi is about 360dp wide (inferred). Headlines may wrap to 3 lines, but buttons stay pinned and never drop below 48dp.
- Bottom navigation: RijHub's 60pt bar is fine and more compact than Flutter's M3 NavigationBar default of 80dp. Keep labels at 11pt or larger, and keep the same five tabs for guests and signed-in users so the layout doesn't shift after sign-in; make the guest tabs useful instead of hiding them.