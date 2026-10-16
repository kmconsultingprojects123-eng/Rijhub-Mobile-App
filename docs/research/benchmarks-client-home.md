# Research: client home

Written in October 2026, while rebuilding the homes after the first redesign was rejected. The "current screens" it critiques are that first redesign, since replaced; the benchmarks and sizing rules still apply.

## Recommended layout

Frame: 390x844 (iPhone 14, 15 or 16). The safe area starts at 59pt; RijHub's tab bar is 60pt plus a 34pt home indicator. So the first screen runs from y 59 to 750: 691pt. Side gutter 16pt (the current AppSpace.gutter). Each y range gives the element's top and bottom in points. Icons are written [name].

A) GUEST (after 'Continue as guest', area not set)

y 0–59     status bar
y 59–107   HEADER, 48pt tap height
           [pin] Abuja (chevron), a 36pt pill ............ 'Sign in', text link 15/20 semibold crimson, 48pt hit area
y 115–163  SEARCH, 48pt, radius 12, surfaceMuted
           [search 20] 'What needs fixing?' (16/24) ........ [mic 22] [camera 22], each a 40pt tap
y 171–203  PROBLEM CHIPS, 32pt, scroll sideways, 8pt gaps, the last chip peeks at the edge
           ([snowflake] AC not cooling) ([bulb] No light in one room) ([drop] Leaking pipe) ([gear] Gen won't start) ([plug] Sparking socket) ([fridge] Fridge not cold) …
y 227–253  SECTION, 26pt: 'Top-rated in Abuja' 20/26 bold ........ 'See all' 14/18 crimson
y 261–293  FILTER CHIPS, 32pt: (● Free now) (All, selected) ([icon] AC) ([icon] Electrical) ([icon] Plumbing) ([icon] Generator) ([icon] Cleaning) …
y 301–741  ARTISAN ROWS: 5 rows of 88pt (a Material 3 three-line item), hairline dividers starting at x=84
  +--------------------------------------------------------------+
  | (56 avatar, green dot)  Emeka Nwosu [badge]      from ₦8,000 |  name 16/22 semibold; price 15/20 semibold, right-aligned
  |                         AC technician · ★4.9 (127) · 214 jobs|  13/18, secondary colour
  |                         ● Free now · Wuse 2 · replies ~10 min|  13/18; green dot and 'Free now' in success colour
  +--------------------------------------------------------------+
  A row may swap its last item for one earned tag (12/16 tinted pill), e.g. '● Next free: Tue 9:00 · Garki · [Top rated in Garki]'.
  With no area set, rows show the artisan's area instead of km. Tapping the location pill sets the area.
---- FOLD at 750: 5 artisans fully visible.
     Chrome (header, search, chips) is 144pt, 21% of the first screen.
     The artisan section is 514pt, 74%.
     Today the split is 35% header, 33% categories, 21% crimson card, 0% artisans. ----
y 757–821  POST-A-JOB ROW, 64pt, radius 16, surfaceMuted (not crimson)
           [clipboard on a 40pt crimson-tint tile]  'Not sure who to pick?' 15/20 semibold / 'Describe it once, get quotes in ~15 min' 13/18  (chevron)
y 845–871  SECTION: 'Typical prices in Abuja', with an 'Updated Oct 2026' caption
y 879–1071 4 one-line rows of 48pt:
           AC servicing (1 unit) ₦8k–₦12k
           Gen servicing (up to 10 kVA) ₦10k–₦18k
           Socket or switch replacement ₦3k–₦6k
           Sink or toilet leak ₦5k–₦10k
           Each row opens that problem's results.
y 1095–1151 TRUST STRIP, 56pt: [shield] 'Pay through RijHub. We hold the money until you say the job is done.'  'How it works'
y 1167–1215 ROLE LINK, 48pt: 'Do you fix things? Find work on RijHub'
y 1239     end; total about 1240pt, versus 1248pt today.
No sign-in walls anywhere. Saving, chatting, booking and posting each open the one-sheet phone sign-in, then return the user to the same place with the action done.

B) SIGNED-IN CLIENT WITH AN UPCOMING BOOKING

y 0–59     status bar
y 59–107   HEADER: [pin] Wuse 2 (chevron) ................................ [bell, 40pt, with badge]
y 115–187  ACTIVE BOOKING, 72pt, radius 16, 1pt border (or tinted surface), 12pt padding
           (40 avatar)  AC servicing · Today, 2:30 PM              [chat 36] [phone 36]
                        ● Confirmed · Emeka Nwosu · Start code 4829
           The card changes with the booking's state:
           - Requested: 'Waiting for Emeka · usually accepts in ~10 min'
           - On the way: 84pt, adds a 4pt three-step progress bar and 'Arrives ~2:40'
           - In progress: 'Working since 2:52'
           - Done: 104pt, 'Did Emeka finish?' with two 36pt buttons [Release ₦12,000] and [Report a problem], then 'Rate Emeka'
           Tapping opens THIS booking. With two or more bookings, a '+1 more' link sits on the right.
y 199–247  SEARCH, 48pt
y 255–287  PROBLEM CHIPS, 32pt, ordered by what is trending in Wuse 2 this week
y 311–337  SECTION: 'Top-rated near you' ................................ 'See all'
y 345–377  FILTER CHIPS, 32pt
y 385–737  ARTISAN ROWS, 4 rows of 88pt
           If the client has hired before, row 1 is pinned:
           (avatar) Emeka Nwosu [badge] ........ [Book again] (a text button where the price would be)
           'You hired him · 2 Oct · you rated 5★'
---- FOLD at 750: the booking and 4 artisans are visible. Today: the booking and 0 artisans. ----
y 753–817  POST-A-JOB ROW, 64pt
then the typical prices and the trust strip (no role link for clients).
While a job is live today and the card has scrolled away, it docks as a 56pt mini-bar above the tab bar: '● Emeka arrives ~2:40'. It mirrors the Android 16 Live Update and the iOS Live Activity.

C) THIN SUPPLY (launch reality: fewer than 3 matches)
After the matches, show a 48pt inline note: 'Only 2 AC technicians in Wuse 2 today. Showing 4 more within 5 km.' The extra rows show distance in semibold. The post-a-job row moves directly under the list and reads: 'Post it, and we'll find someone within the hour' (matching assisted by the ops team). Never 'check back later'.

D) PROBLEM CHIP RESULTS (e.g. 'AC not cooling')
y 59–107   [back] 'AC not cooling' 17/22 semibold ........ Wuse 2 (chevron)
y 115–187  HINT CARD, 72pt: 'Usually low gas, a dirty filter or a bad capacitor. Typical ₦8k–₦25k. Inspection ₦3,000, credited if you hire.'
y 195–227  REFINE CHIPS, 32pt: (Split unit) (Window unit) (1 unit) (2+ units) (Today)
y 235–     The same 88pt artisan rows, sorted free now first, then rating, then distance. Each row shows the AC-specific count ('41 AC jobs').
bottom     STICKY CALL TO ACTION, 56pt, above the home indicator: 'Get quotes from these 6, free'.
           It opens a prefilled job sheet: title, category, area and the refine answers, plus an optional photo or voice note and Today / Tomorrow / Pick a time. A guest signs in only at this point.

E) SEARCH FOCUS (tapping the bar)
A full screen with the keyboard up:
- 'Common problems near you': 10 rows of 48pt, each with an icon
- 'Recent': 3 rows
- 'Can't find it? Describe it or show us', using voice or the camera
Results mix problems, categories and artisans, and understand Nigerian synonyms: gen and generator, AC and air conditioner, no light, inverter, borehole, POP, DSTV.

## Critique of the current screens

- **Client home, guest and signed in (390x844)**: The thing the product owner wants first, top-rated artisans near me, starts below the fold. The first screen shows zero artisans. (Measured on the 3x renders (render/client-home-review/final/guest.png and signed_in.png). The visible area ends at about 750pt: 844, minus the 34pt home indicator, minus the 60pt tab bar.
- Guest: the 'Top-rated in Abuja' header is at 835pt and the cards run 880–1110pt. That is about 360pt of scrolling to see one full card.
- Signed in: header at 940pt, cards 984–1214pt, about 464pt of scrolling.
- On a 375x667 phone neither variant reaches the section: guest_375x667.png ends mid 'Post a job' card, and signed_in_375x667.png ends at the category grid.

The benchmarks show content far higher: Airbnb's first listing photo at about 266pt, Bolt Food's 'Order again' at about 235pt, TaskRabbit's and Urban Company's first tiles at about 258pt and 273pt.

NN/g (2018): 57% of viewing time is spent above the fold. Apple's HIG: 'place the most important items near the top'.)
- **Client home: header, greeting and question**: The header block uses about 35% of the first screen and carries no information. (From the top of the safe area (59pt) to the bottom of the search box (300pt) is 241pt. It holds:
- the location pill and Sign in (76–112pt)
- 'Good afternoon' (15pt text)
- 'What do you need help with today?' in AppText.headline 26/32 bold over two lines (about 64pt), the largest text on the screen
- a 52pt search box
- 20–22pt gaps between them

For comparison: Bolt Food fits address and search in about 105pt. Airbnb fits search plus three category tabs in about 138pt. Kuda's whole top row is about 41pt. Airbnb, Bolt Food, Glovo, Chowdeck and Kuda show no greeting at all; TaskRabbit and Handy turn the question into the search placeholder.)
- **Client home: 'Popular services' grid**: A two-row grid of 8 tiles costs about 227pt. Four separate controls lead to the same Explore screen, and the tiles currently lead nowhere. (The section runs from the header at 347pt to the second row of labels at 574pt. Each row is a 60pt icon box, 8pt, and a 16pt label, with a 16pt gap between rows; the section title adds 20pt and a 25pt gap.

One-row benchmarks: Airbnb shows 3 categories in about 75pt, Kuda 4 tiles in about 82pt, Glovo 6 scrolling icons in about 91pt, Bolt 3 tiles in about 95pt.

In client_home_screen.dart the search box, 'See all', the 'All services' tile and the top-rated 'See all' all call _openExplore. Tapping a category only shows a snackbar ('browsing by service is next in the redesign').)
- **Client home: 'Not sure who to hire?' card**: A 180pt crimson block sits exactly where the artisans should start, and it is the loudest element on the screen. (It spans 608–788pt for guests and 712–892pt when signed in, crossing the fold in both. On 375x667 it is cut off mid-card. The code calls it 'The screen's one bold moment'.

It is 2.25 times the booking card (80pt) and about 3 times Bolt's dismissible banner (about 62pt). Angi and Thumbtack put 'Request a quote' on each pro instead of a standalone block. Jumia's stacked promo carousels are the cautionary version of this pattern.)
- **Client home: top-rated artisan strip**: The artisan cards are oversized carousel cards, mostly photo. Only 1.6 artisans are visible, so comparing three needs a sideways swipe. (Each card is 220x230pt and its photo is 140pt (61% of the card). Only 1.6 cards fit across 390pt. Horizontal rows are easy to miss: NN/g's 'Carousels on Mobile Devices' flags weak discoverability, and UX Movement notes that many users never swipe.

Thumbtack, TaskRabbit and Handy list providers vertically. Their tall rows spend the height on trust information:
- Thumbtack: about 224–254pt, with a reason header and a review quote
- TaskRabbit: about 238pt, with the job count for the category and a bio
- Handy: about 173pt

Data cost: a 220x140pt photo is about 660x420px at 3x (about 277k pixels). A 56pt avatar is about 168x168px (about 28k pixels). That is roughly 10 times the pixels per artisan, in a market where 1GB of data doubled in price.)
- **Client home: artisan card content as rendered**: The card is missing trust signals: no review count, jobs done, response time or next free time. (The rendered card shows only '★ 4.9', 'Available today', name and badge, 'AC technician' and 'Wuse 2 · From ₦8,000'. The earlier research said to always show the review count.

client_artisan_card.dart, edited at 15:07, now adds the review count and jobs done, but the renders from 14:24 predate it, so they need re-rendering.

The benchmarks show more:
- Thumbtack: 'Exceptional 5.0 (60) · 350 hires · 51 similar jobs done near you · Responds in about a day'
- TaskRabbit: '★ 5.0 (30 ratings) · 50 TV mounting tasks'
- Handy: '★ 4.8 | 1,323 jobs · Recently Active'
- Airtasker: '98% Completion rate')
- **Client home: 'Available today' chip**: The availability label is vague. It doesn't say how soon someone can come, which is what 'active services' means to a client. (The same 'Available today' chip sits on the photo of both cards. The benchmarks are specific:
- Urban Company InstaHelp: 'In 10 mins / Later / Multi-day'
- Snabbit: 'Arrives in 10 min'
- Thumbtack: 'Online now – responds in about 30 minutes'
- Chowdeck and Glovo: '30–50 min' and '10–20 min' on every card
- Bolt Food: '10:00–10:30')
- **Client home, signed in: upcoming booking card**: The booking card is a label, not a tool. It has no call or chat, no address, no live status and no start code, and tapping it opens the Bookings tab instead of the booking. (It is an 80pt card at 324–404pt: a 44pt avatar, 'AC servicing', 'Confirmed', 'Emeka Nwosu · Today, 2:30 PM'. Its onOpen does context.go(Routes.bookings).

Other apps' trackers carry the live state and the actions:
- Chowdeck: 'arrives in 8 mins', 'Delivery confirmation code 3829', 'Call rider'
- Bolt Food: 'Delivery code 9815'
- Snabbit: 'ARRIVING IN 10 MINS', 'Check-in OTP'
- Thumbtack 'Your team' rows: Book and Message
- Uber: Live Activities on the lock screen since February 2023)
- **Client home, guest: header**: The outlined 'Sign in' button is the most button-like control on the screen. It tells guests they ought to sign in, the opposite of the explore-first brief. (guest.png has a 36pt outlined 'Sign in' button at the top right, opposite the tinted location pill. Contextual sign-in already exists: AuthGate.ensureSignedIn runs on 'Post a job'. So the header needs at most a quiet text link.)
- **Client home: empty state (thin supply at launch)**: The empty state is a dead end. (empty.png says 'No artisans near you yet – Pull down to refresh, or check back later.' It offers nothing else:
- no widening to nearby areas
- no city-wide fallback
- no 'post it and we'll find someone'

This is anti-pattern 12 in docs/research/onboarding-and-home.md, and it will be the most common state in the first weeks in Abuja.)
- **Client home: 'Look for the verified badge' note**: It spends 74pt explaining one icon, while the bigger promise (your money is held until the job is done) is missing from the home. (It sits at 1142–1216pt, at the very bottom. Better models:
- Airtasker: 'PAYMENT SECURED' and an in-chat protection notice
- TaskRabbit: 'you won't be billed until your task is complete'

A tap on any badge can open the badge explanation as a sheet, which frees the space for the payment-protection line.)
- **Client home: type hierarchy and price**: Every title is large and bold, while the price is among the smallest text on the card. (Above the fold sit a 26/32 headline, two 20/26 bold section titles and a 20pt white-on-crimson card title. 'From ₦8,000' is set in AppText.caption 12/16, weight 600. TaskRabbit right-aligns '$65/hr' at name size, and Airbnb puts the total price in the main meta line.)
- **Welcome screen (how guests reach the client home)**: The preview the product owner saw had no visible guest path, which is why onboarding read as forced sign-up. (welcome.png shows two role cards and 'Already have an account? Sign in', with nothing that says 'look around first'. welcome_screen.dart has since gained a 'Continue as guest' main button (changed after that render). Re-render it, and make sure the guest home is complete: no locked or greyed sections, and sign-in only when the user commits.)

## Benchmarks

- **Urban Company (India): the strongest home-services benchmark**: APP (App Store 'Discover' screenshot, older build): membership strip, about 107pt including the status bar → address header 'Home / A-1002, Sector 22 Dwarka…' with a chevron, about 54pt → search 'Search for "AC service"', about 46pt → 3x2 grid of illustrated category tiles (about 109x73pt each, labels of 2 to 3 lines) → 'Home solutions store' banner, about 80pt.

CITY HOME (urbancompany.com/bangalore, which mirrors the app's sections):
- 'Home services at your doorstep'
- 8 categories, with InstaHelp (instant help) FIRST
- Trust stats: 4.8 service rating, 12M+ customers
- 'In the spotlight'
- 'New and noteworthy'
- 'Most booked services': cards show title, rating with review count, and a fixed price, named by the problem. Examples: 'Drain blockage removal 4.77 (96K) ₹199', 'Wash basin leakage repair 4.78 (73K) ₹99', 'Flush tank repair 4.75 (169K) ₹199', 'AC repair 4.73 (876K) ₹299'.
- Category rows: Cleaning essentials, Appliance repair and service, Home repair and installation.

INSTAHELP PAGE (Play screenshot): 'Househelp on leave? We'll arrive in 10 mins' → 'Insta help ★4.8 (2.7 lakhs)' → segmented control 'In 10 mins / Later / Multi-day' → time-package cards (e.g. '1 hr service ₹99', with a Book button).
  - Steal: 1) Services named by the problem, at a fixed price, with rating and review count ('Wash basin leakage repair ₹99'). This is ready-made for RijHub's problem chips and price guide.
2) The instant service as the FIRST category, with a Now / Later / Multi-day control (InstaHelp).
3) Ratings always shown with their counts.

What it leaves out: greetings, headlines, and provider listings on the home.
- **Thumbtack (US)**: From App Store and Play screenshots (2024–2026 builds):
- 'Your team': past pros, each with avatar, name, ★★★★★ (3), 'Hired for lawn care', 'Next booking September 17', and actions Book · Message · More.
- 'Your plan': Booked ('Window cleaning – Booked for April 2'), Planned ('Lawn care – In progress'), and a 'Find a pro' link.
- Seasonal guide cards: 'Boost curb appeal' → 'Tree trimming $400–750 avg. · DIY friendly · Tips and info · Search pros'.
- Pro results ('Top 2 Lawn Mowing Professionals near Chicago') are vertical cards. Each is headed by the reason it appears ('Highly rated', 'Frequently hired', 'Responds quickly') and shows: about 68pt avatar, name + Top Pro badge, 'Exceptional 5.0 ★★★★★ (60)', an 'In high demand' tag, '350 hires on Thumbtack', '51 similar jobs done near you', 'Responds in about a day', and a review quote.
- Pro profile: 'Online now – responds in about 30 minutes', 'Free on-site estimate', 'Check availability'.

April 2026: an AI intake replaces classic search. You describe the problem by text, photo or voice; it diagnoses and scopes the job, asks follow-ups (urgency, location), then shows a shortlist of local pros, each with a reason it fits. I read this through the search index only; the BusinessWire and thumbtack.com pages blocked fetching.
  - Steal: - A reason label on each provider.
- Rating word + score + count ('Exceptional 5.0 (60)').
- 'Similar jobs done near you'.
- Response time and 'Online now'.
- 'Your team' with Book and Message, which works as 'book again'.
- Typical cost ranges ('$400–750 avg.').
- Problem-first intake by photo or voice.
- **TaskRabbit (US)**: HOME (App Store panorama screenshot):
- Location row 'Nearby' with a search icon
- 'I need help with', about 22pt
- Pill search: 'Try "mount TV" or "leaky faucet"'
- 3-column photo tiles with 2-line labels, 9 in total: Help Moving, Furniture Assembly, General Mounting, Cleaning, Minor Home Repairs, Heavy Lifting & Loading, Electrical Help, Indoor Painting, Yard Work.

Taskers appear only after you pick a task, on 'Select a Tasker':
- Filter chips: Within A Week, Flexible, Price
- 'Sorted By: Recommended'
- Each row: about 100pt round avatar; name with '$65/hr' right-aligned at name size; '★ 5.0 (30 ratings)'; '50 TV mounting tasks' (bold green, specific to the category); '80 mounting tasks overall'; ELITE / GREAT VALUE tags; a bio snippet; 'See profile'.

Review and confirm: 'Don't worry, you won't be billed until your task is complete.'
  - Steal: - A problem example in the search placeholder ('leaky faucet').
- Job counts specific to the category.
- Price right-aligned at name size.
- 'Won't be billed until complete' reassurance.
- Reason tags (ELITE, GREAT VALUE).

What it leaves out: promos and providers on the home. Its 9-to-33 tile test raised invitations 3% (earlier research doc).
- **Airtasker (Australia): post a job, get offers**: The store listing shows the posting and offers flow, not the home:
- 'Post task' stepper (Details · Date & time · Budget), starting with 'Task title' and 'Describe your task'.
- Task page with 'Offers 4 / Questions' tabs. Each offer row: avatar, 'Kelly B.' + ID badge, '4.8 ★ (18)', '98% Completion rate', '$160' on the right.
- Private messages with an orange notice: 'For your protection, keep communication and payments within Airtasker'.
- 'Release payment' screen: 'PAYMENT SECURED', 'Are you satisfied that the task is done?', tip chips $5 / $10 / $20 / $30.
  - Steal: - Completion rate next to the rating.
- 'Payment secured' and a one-tap 'Release payment' at the end of the job.
- An off-platform warning inside chat.
- Compact offer rows that still carry the trust stack.
- **Angi (US)**: HOME (tilted marketing frame, older build): hero photo with 'Your home for everything home' and search 'What can we help you with?' → financing strip → 'Browse category' icon row (Roofing & Gutters, Plumbing, Cleaning…) → 'Popular Projects' list.

SERVICE PAGE: 'Repair Faucets, Fixtures and Pipes ★4.4 (25,098)' → 'Book and pay in the app' → 'An experienced, fully-equipped pro will arrive on time' → 'Backed by the Angi Happiness Guarantee' → [See your price].

PRO LIST: name, ★★★★★ 5.0 (102), 'Angi Certified', and a [Request a quote] button on every row.
  - Steal: - Services named by the problem, with an upfront-price call to action ('See your price').
- The guarantee line inside the booking card.
- 'Request a quote' on each provider, which turns browsing into a job without a separate 'Post a job' block.
- **Handy (US)**: HOME (tilted frame): 'How can we help you?' with search 'Search for services or tasks' → one horizontal row of round category icons (Cleaning, Handyman, Home Remodeling, Interior Painting) → 'Popular Services' as list rows (icon, label, chevron).

PRO SEARCH (each row): about 67pt avatar, 'Marietta D.', '★ 4.8 | 1,323 jobs', a green-dot 'Recently Active', 'Works with 12 clients in Long Island City' (another pro: 'Works with 238 repeat clients on Handy'), chevron.

AFTER A JOB: stars, tip chips, then 'Would you work with Marietta again?' with three options: 'Yes, keep as my Favorite Pro' / 'Sure, keep on my Pro Team' / 'No thanks'.
  - Steal: - Local social proof ('Works with 12 clients in Long Island City').
- 'Recently Active'.
- Asking the client to keep the pro right after the rating, which gives 'book again' its data.
- **Fiverr (global)**: The listing shows:
- A categories list: rows with an icon, a title, and a subtitle naming the sub-services ('Graphics & Design – Logo & Brand Identity, Art & Illustration').
- A gig page: 'Top Rated Seller', three price tiers ($210 / $130 / $75).
- A seller dashboard: level, success score, rating and response rate.
The buyer home is not shown.
  - Steal: Subtitles under categories that name the problems they cover, e.g. 'Electrical: sockets, wiring, prepaid meter, inverter'. They bridge the vocabulary gap. Also tiered 'from' prices.
- **Chowdeck (Nigeria)**: HOME:
- 'Select location' with a chevron, and an offers icon (row about 44pt)
- 5 pastel category tiles: Restaurants and Supermarkets large (about 170x84pt); Pharmacies, African and More small (about 108x84pt)
- 8pt grey divider
- 'Explore': a row of circular vendor logos (about 42pt) with names
- 'Featured': horizontal vendor cards (photo about 264x135pt, 'Free delivery by Grey' tag, name, '₦800 · 30–50 min', '★ 4.7', heart)

There is no search bar on the home. Search is a tab (Home · Search · Orders · Support · Profile) with filters, category chips and 'Recent searches'.

TRACKING: 'Hi Tokunbo, Your order arrives in 8 mins', 'Delivery confirmation code 3 8 2 9 – Show this code to your rider', timestamped steps, 'Call rider'.
  - Steal: - A code you show to the courier (a start code for RijHub).
- The meta line format '₦800 · 30–50 min · ★ 4.7'.
- Search as its own surface with recent searches.
- Nigerian tone and ₦ formatting.
- **Glovo (Africa/Europe)**: RESTAURANTS PAGE (App Store screenshot):
- Title
- Search 'Try with pizza'
- Round category icons with labels (Offers, Healthy, Asian, Burger, Pizza, Chicken); the row scrolls
- Filter chips: Offers ×, Cuisines, Sort by, Prime
- 'Best in your city →': horizontal store cards with a '98% (435)' rating chip on the photo, a '-20% in some items' tag, name + cuisine tag, '10–20 min'
- Full-width store cards

STORE PAGE: an 'Order again' block. FEEDBACK: tap chips 'Good quality', 'Delicious', 'Handled with care'.
  - Steal: - A placeholder that gives an example ('Try with pizza' → 'Try "AC not cooling"').
- One icon row plus one filter-chip row above the list.
- An ETA on every card.
- Rating as percent positive with a count.
- Tap-to-rate chips.
- **Bolt (rides; Nigeria)**: HOME (top to bottom):
- Dismissible banner 'Verify your identity – This helps keep rides safe'
- 'Let's go places.' (about 20pt)
- 3 service tiles: Rides 'Let's get moving', eBikes 'Rent and go', Schedule 'Book ahead' (3D icon + 2 lines each)
- 'Where to?' search with a 'Later' pill inside it
- 3 recent places as two-line rows with 43pt icon tiles
  - Steal: - Now/Later inside the search bar.
- Recent destinations right under search, which is 'book again' with no extra section.
- Banners at about 60pt that can be dismissed, never large blocks.
- **Bolt Food (Nigeria)**: HOME:
- Address row
- Search 'Food, restaurants, stores…' with a filter icon (ends about 153pt)
- 'Order again – All' with about 90pt square thumbnails and 2-line names (starts about 235pt)
- One static promo 'Best poke around – Explore now', about 164pt
- 'Restaurants near you – All': cards with a '★ 4.6 (200+)' chip on the photo and an 'Up to −25%' tag
- Tab bar, about 81pt including the home indicator

TRACKING: 'Estimated time of delivery 10:00–10:30', 'Delivery code 9 8 1 5 – For the courier', a list of steps.
  - Steal: - 'Order again' as the first block after search.
- Rating with count shown on the photo.
- Arrival as a time window.
- A delivery code.
- **Jumia (Nigeria): a counter-example**: Search 'Search on Jumia' → hero promo carousel → a second promo carousel with page dots → one row of 4 deal tiles (Flash Sale, Phone & Accessories Deals, Computing Deals, Electronic Deals).
  - Steal: Only the search at the very top. Its stack of brand banners pushing the inventory down is exactly what RijHub's 180pt crimson 'Post a job' block does. NN/g: content that rotates by itself reads as advertising and gets less attention.
- **Kuda (Nigeria): fintech polish**: - One top row: avatar, search field, rewards coins, bell, help
- Account name and number
- Balance '₦1,645,222.00' with 'Last updated 2s ago'
- 'Quick Access – Edit': 4 square tiles in ONE row (Transfer, Airtime, Internet, Betting)
- 'Transactions – View All': two-line rows

SECURITY SCREEN: switches sit inside plain list rows (Face ID, Allow Screenshots, Context Menu).
  - Steal: - One-row shortcuts the user can edit.
- A switch inside a list row, never a card.
- A freshness label ('Last updated 2s ago' becomes 'Availability updated 2 min ago').
- Private mode / hide balance for artisans.
- **Moniepoint Personal Banking (Nigeria)**: The listing shows product screens, not the home:
- Savings products as list rows with rate tags ('10.0% p.a. Up to +₦100.00 per ₦1,000 saved')
- Bill payment rows with chevrons (Cable TV, Electricity, Betting, Others)
- A rewards balance card with 'Cashout'
  - Steal: Restraint. The brand colour goes on the single primary button and on small tags, never on large blocks. Dense, scannable list rows.
- **Airbnb (2025 app, Explore)**: HOME:
- Search pill 'Start your search'
- 3 category tabs, Homes / Experiences / Services, with 3D icons and NEW badges
- 'Recently viewed homes' with square photos and 'Roma Norte · 2 beds · ★4.93'
- 'Stay in Mexico City' with about 2.2 cards in view: 'Guest favorite' pill, heart, 'Apartment in Mexico City', '$844 for 2 nights · ★4.92'

SERVICES:
- 'Services in Los Angeles' photo tiles with counts: 'Chefs · 32 available', 'Photography · 71 available', 'Prepared meals · 12 available'
- Full-width cards: 'California fusion cuisine by Collin – From $50 / guest', with a 'Popular' tag
  - Steal: - Real content within the first 266pt.
- No greeting and no headline.
- 'N available' under each category.
- Badges that are earned ('Guest favorite').
- Total price in the meta line.
- Recently viewed first for returning users.

Guest browsing: from memory, the logged-out app lets you browse and asks you to log in when you save or reserve. I did not verify this in this session.
- **Snabbit (India): 10-minute house help, the 'available now' benchmark**: HOME: address header over a live map with nearby experts as pins → a bottom panel with two tiles: 'Schedule – Pick your time' and 'Instant (10 mins) – Get help now'. A service grid of photo tiles follows.

BOOKING: 'Arrives in 10 min' and time packages (30 min ₹59, 45 min, 60 min…).

LIVE: 'Expert on the way – Lata will arrive on time – ARRIVING IN 10 MINS', 'Check-in OTP 6 7 0 – Share with expert to start service', 'Booked for someone else? Share OTP'.
  - Steal: - Show nearby supply as the reassurance.
- Now vs Schedule as the first decision.
- A check-in code that can be shared with whoever is at home.

## Innovative ideas

- Problem-first entry. The search reads 'What needs fixing?', and one row of problem chips sits under it: 'AC not cooling', 'Leaking pipe', 'Gen won't start', 'Sparking socket', 'Fridge not cold', 'Inverter beeping', 'DSTV no signal'.

Each chip opens matching artisans, a typical price and a prefilled job ('Get quotes from these 6'). The backend maps each problem to a category, quick questions and a price range, and orders the chips by live demand in the user's area and season (AC chips first in the February–April heat).

Copy needs testing: in Nigeria 'No light' usually means a grid outage, which an artisan can't fix. 'No light in one room' or 'Breaker keeps tripping' describe fixable faults. (value: People know the symptom, not the trade name. From the home it is two taps to a matched list or a posted job, and lower-literacy users don't have to type.)
- Show it instead of typing it. Put a mic and a camera inside the search bar. The user records a 15-second voice note (English, Pidgin, Hausa, Yoruba or Igbo) or takes a photo or short video. The backend transcribes it, classifies the category, likely fault and urgency, and drafts the job. Artisans quote from the media. (value: No trade vocabulary needed, fewer 'what exactly is wrong?' calls, and more accurate first quotes.)
- 'Free now' as a live state, not a label. Each artisan row gets a green presence dot and either 'Free now · about 35 min away' or 'Next free: Tue 9:00'. A 'Free now' filter chip and a live count ('6 electricians free now in Wuse 2') complete it. Artisans set it with the availability switch and their calendar; the backend expires it after inactivity. (value: It answers the real question, 'can someone come today?', before any tap. It also makes the product owner's 'active services' concrete.)
- A reason tag on every artisan: one short label, earned from data, that explains the ranking. Examples: 'Top rated in Wuse 2', 'Replies in ~10 min', '41 AC jobs', 'You hired before'. (value: Ranking becomes legible and believable, and the tag helps the user choose between artisans with similar stars.)
- Book again, built into the list. Past artisans are pinned at the top ('You hired Emeka · 2 Oct · you rated 5★') with a one-tap 'Book again' that reuses the address, notes and preferred time. After each rating, ask 'Keep Emeka as your AC person?'. (value: Returning clients skip search entirely, and the platform keeps the repeat relationship instead of losing it to WhatsApp.)
- A live job card with a start code. It moves through: requested → confirmed (code 4829) → on the way (ETA and progress) → working → 'Did Emeka finish? Release ₦12,000 / Report a problem' → rate. It is mirrored to the lock screen as an Android 16 Live Update (ProgressStyle) and an iOS Live Activity. 'Share with someone at home' sends the status and code over WhatsApp. (value: The right person gets through the gate, the client worries less, and the payment is released in one tap. A gateman or house help can receive the artisan.)
- An estate gate pass. When a booking is confirmed, RijHub generates a visitor pass: the artisan's photo and name, a masked phone number, the code and the time window, ready to forward to estate security. (value: Many Abuja estates control visitors at the gate. The pass removes the 'he is stuck at the gate' phone call and adds a safety check.)
- Prices before the call:
- a 'Typical prices in Abuja' block on the home
- a range on every problem page, e.g. 'AC not cooling: ₦8k–₦25k; inspection ₦3,000, credited if you hire', with an 'updated' date
The backend computes the ranges from completed RijHub jobs. (value: It removes the fear of being overcharged, gives the client a fair anchor, and shows up unrealistic quotes.)
- A quote-speed promise on posting. Show the live median time to the first quote ('Usually 3 quotes within 15 min in Wuse 2') on the post-a-job row and on the sticky button in results. (value: It sets expectations and makes posting a job feel as fast as booking one.)
- Neighbourhood proof: 'Hired 12 times in Wuse 2', 'Works with 9 households near you'. Use counts across many clients, never individual names. (value: Proof from nearby clients carries more weight than a citywide star average.)
- Experience in the category being searched: show '41 AC jobs' rather than total jobs, plus the completion rate. (value: Relevance. A great plumber with three AC jobs is not an AC specialist.)
- A 'My home' profile with maintenance nudges:
- Store the AC units (brand, HP), the generator's kVA and the inverter size.
- One static seasonal card: 'Harmattan dust: service your AC before the March heat'.
- Service reminders: 'Gen service due: about 250 hours'. (value: Exact prices (generator servicing priced by kVA), proactive care, and fewer emergencies.)
- Safety first for dangerous problems. Chips flagged as dangerous ('Sparking socket', 'Gas smell') show one instant safety step ('Switch off the main breaker') before the artisan list, and default the list to artisans who are free now. (value: Real help in the moment, which earns trust on day one.)
- A guest home that is complete. Everything can be browsed without an account. Saving, chatting, booking and posting each open a one-sheet phone sign-in and then complete the action the guest started. (value: Explore first, as the product owner asked. Sign-up comes only at the moment of commitment.)

## Sizing rules

- Budget for the first screen. On a 390x844 phone, the 59pt top inset plus RijHub's 60pt tab bar and 34pt home indicator leave y 59–750, which is 691pt. Give chrome (header, search, chips) at most about 25% and the primary content at least 60%. Today the split is 35% header and question, 33% categories, 21% crimson card and 0% artisans; the proposal is 21% chrome and 74% artisan section. Source: RijHub renders measured at 3x; NN/g 'Scrolling and Attention' (2018): 57% of viewing time above the fold, 74% within the first two screenfuls.
- Real content should start by about y 260–300pt. Measured from App Store screenshots scaled to a 390pt screen: Airbnb's first listing at about 266pt, Bolt Food's 'Order again' at about 235pt, the first tiles of TaskRabbit and Urban Company at about 258pt and 273pt. RijHub's first artisan is at 880pt for guests and 984pt when signed in.
- Header row: 48pt tap height with a 36pt visual pill. Header plus search together: about 104–110pt (Bolt Food measures about 105pt). A search-first home has no greeting and no headline; none of Airbnb, Bolt Food, Glovo, Chowdeck or Kuda shows one.
- Search field: 48pt. The benchmarks range from 45 to 57pt: TaskRabbit about 45, Urban Company about 46, Glovo about 48, Bolt and Bolt Food about 49, Airbnb about 57 (all measured). The Material 3 SearchBar container height is 56dp (androidx SearchBarTokens.kt). RijHub is 52pt today.
- Chips: 32pt tall with an 18pt icon, 8pt gaps and 12–16pt side padding. Material 3 AssistChip and FilterChip tokens give a container height of 32dp and an icon size of 18dp; Glovo measures about 33pt and TaskRabbit about 35pt. Pad the hit area to 48pt (AppSize.minTapTarget = 48).
- List rows: 56, 72 and 88pt for one-, two- and three-line items, with a 56pt leading image or a 40pt avatar, 16pt side insets and 12pt between image and text. Source: Material 3 ListTokens.kt (ItemOneLineContainerHeight 56dp, ItemTwoLineContainerHeight 72dp, ItemThreeLineContainerHeight 88dp, ItemLeadingImage 56dp, ItemLeadingAvatarSize 40dp, ItemLeadingSpace 16dp, ItemBetweenSpace 12dp). Use 88pt for artisan rows on the home, 72pt for the booking card and 56pt for settings-style rows.
- Provider rows: a home preview uses compact rows of about 76–88pt (Airtasker's offer rows are about 76pt with a 50pt avatar). A dedicated 'choose an artisan' screen can be taller when the height carries trust information: Handy about 173pt, Thumbtack about 224–254pt, TaskRabbit about 238pt (all measured). Spend height on information, never on a decorative photo; RijHub's card is 230pt, 61% of it photo.
- Categories: one row of 72–96pt, not a two-row grid. Measured: Airbnb about 75pt for 3, Kuda about 82pt for 4, Glovo about 91pt for 6 (scrolling), Bolt about 95pt for 3. RijHub's grid of 8 tiles takes about 182pt plus a 45pt header.
- A switch belongs in a list row, never in a card. Apple's HIG on toggles: 'Use the switch toggle style only in a list row.' The Material 3 switch track is 52x32dp (SwitchTokens.kt), and a row containing a switch is 56pt (one line) or 72pt (two lines); Kuda's security switches sit in rows of about 48pt. RijHub's artisan 'You're available' card measures 94pt and should become a 56–64pt row.
- Touch targets: at least 44x44pt. Apple's HIG on buttons: 'a button needs a hit region of at least 44x44 pt'. On Android and Material it is 48dp (RijHub's AppSize.minTapTarget = 48). The visual size can be smaller (a 36pt pill, a 32pt chip) as long as the hit area is padded.
- Banners and promos: at most 64pt, static and dismissible. Bolt's 'Verify your identity' banner measures about 62pt. Never rotate them automatically (NN/g on auto-forwarding; Baymard's mobile carousel guideline 957). RijHub's post-a-job block is 180pt.
- Section rhythm: 24pt between sections, 8pt from a section title to its chips, 8pt from the chips to the list, 16pt before a call-to-action row. Measured: Airbnb about 31pt between sections, Bolt Food 26–40pt. RijHub uses 32pt plus line-box padding, about 47pt from glyph to glyph.
- Type: one 20/26 section title per section, names at 16/22 semibold, metadata at 13/18, captions at least 12pt (Apple's HIG gives an iOS default of 17pt and a minimum of 11pt). Set the price at 15pt semibold or larger, right-aligned on the name line, as TaskRabbit shows '$65/hr' at name size. Remove the two-line 26/32 headline from the home.
- Bottom navigation of 60–80pt is normal. Material 3 NavigationBar: 64dp container (flexible) or 80dp (tall), from NavigationBarTokens.kt. iOS tab bar: 49pt plus the 34pt home indicator (a UIKit value from memory, not fetched). RijHub's 60pt bar is fine.
- Images: use 56pt avatars (about 168x168px at 3x, about 28k pixels) on the home, not 220x140pt card photos (about 660x420px, about 277k pixels). That is roughly 10 times fewer pixels per artisan in a market where 1GB of data doubled in price (earlier research, section 4.2). Work photos belong on the profile.
- The status or booking card is 72pt with two 36pt icon actions (44pt hit areas). It grows to about 84pt with a 4pt progress bar while the job is live, and to about 104pt in the confirm-and-release state. RijHub's 80pt card has no actions.
- Gutter: 16pt, now the AppSpace.gutter token and the Material compact margin. Keep the current radii: cards 16, inputs 12, chips fully rounded. Use the brand crimson for one primary action and small accents only, never for large blocks (Moniepoint, Kuda and Airbnb all show this restraint).