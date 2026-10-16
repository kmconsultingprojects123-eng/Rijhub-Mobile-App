# Research: artisan home

Written in October 2026, while rebuilding the homes after the first redesign was rejected. The "current screens" it critiques are that first redesign, since replaced; the benchmarks and sizing rules still apply.

## Recommended layout

FRAME AND METHOD
- Phone: 390×844.
- Status bar: 62pt. This matches the render harness; most iPhones use 47–59pt.
- Bottom bar: 94pt (60pt bar plus 34pt home indicator). The visible content band is therefore y=62–750, 688pt.
- Side gutter: 16pt.
- Type uses RijHub's own tokens: headline 26/32, titleSmall 16/22 (weight 600), label 16/20 (weight 600), bodySmall 13/18, caption 12/16.
- Ordering principle: the home answers four questions in order.
  1. Can clients book me now? One pill.
  2. What must I do today?
  3. Who picked me and is waiting?
  4. What new work fits my trades?
- Money is one pill. Stats and setup are one row each, below the work. Everything else moves to an Earnings tab.
- Sizing rule: size follows consequence. A binary state gets a 40pt pill. A decision with money and a deadline gets a card of up to 116pt. A passive number gets a pill.

A) SIGNED-IN ARTISAN, TYPICAL DAY (available, 2 bookings today, 1 direct request)
- y 0–62: status bar.
- y 62–118, top bar (56pt):
  - Left: [● Available ▾], a 40pt pill with a green 12% tint.
  - Right: [₦86,500 ›], a 40pt wallet pill, then [🔔] at 40×40.
  - No avatar or greeting; the Profile tab already holds identity.
- y 126–150, section label (24pt): "TODAY · THU 16 OCT" on the left (caption caps, weight 600, tertiary); "Schedule ›" on the right.
- y 154–230, Today card (76pt):
  - Line 1: "2:30 PM" | "AC servicing · Chidinma O." | (💬)(📞) as two 36pt icon buttons.
  - Line 2: "in 1 h 10" | "Wuse 2 · near Banex Plaza · 3.1 km".
  - From 60 minutes before start, the card grows to about 120pt. Line 2 becomes "Leave by 2:05 · about 25 min drive", and a full-width 40pt [I'm on my way] button appears that notifies the client.
- y 230–266, timeline line (36pt): "5:00 PM · Generator service · Jabi ›". At most 2 such lines, then "+N more".
- y 286–310, section label (24pt): "REQUESTS FOR YOU · 1".
- y 314–430, request card (116pt), crimson 6% tint, radius 16:
  - Line 1: "Ngozi A. wants to book you", with a "⏱ 14 min" timer chip on the right.
  - Line 2: "Socket repair · Today 4–6 PM · Wuse 2 · ₦6,000".
  - Actions: "Not now" text button on the left; [Accept] on the right, 36pt tall, 120pt wide, filled crimson.
- y 450–474, section label (24pt): "NEW JOBS FOR YOU" on the left; "AC repair · Electrical ▾" on the right.
- y 478–566, job row (88pt):
  - [❄] icon tile, 36pt.
  - Title: "AC not cooling and leaking water".
  - Line 2: "₦8,000–12,000 · Garki Area 11 · 3.1 km".
  - Line 3: "⚡ Urgent · 12 min ago · Be the first to quote".
- y 567–655: job row (88pt). Rows are separated by a hairline inset 64pt.
- y 656–744: job row (88pt).
- y 750: the fold.
  - Above the fold: 6 work items (today's job, a second job today, 1 request, 3 new jobs). Status chrome is 128pt, 19% of the band.
  - Today's build shows 0 work items, with 567pt (82%) of chrome.
- Below the fold:
  - Job rows 4–6.
  - "See all 42 jobs ›" (48pt).
  - Performance row (56pt): "This week · 6 jobs · ★4.9 (31 reviews) · replies 96% ›", linking to the Earnings tab.
  - Setup row (64pt), shown only while setup is unfinished: a progress ring reading "3/4", "Add photos of your work", "Profiles with photos get more bookings ›".
- States:
  - No requests: that block disappears. Jobs start at y=314: 4 full rows plus 92% of a fifth above the fold.
  - Nothing booked today: Today collapses to one 44pt line, "Nothing booked today · available until 7 PM".
  - A metric below target (for example replies under 80%): one amber 56pt row appears under the top bar until it recovers.
  - At 130% text: the wallet pill shows the amount only, and titles may wrap (rows grow to 108pt). Prices and times never truncate.

B) SIGNED-IN, NEW ARTISAN (ID check not done, so bookings are blocked; currently off)
- y 62–118, top bar: [○ Off ▾] as a grey outlined pill on the left; [🔔] on the right. The wallet pill is hidden until the first earning.
- y 126–206, setup banner (80pt), amber 8% tint:
  - "Verify your ID to start getting booked".
  - "2 minutes · NIN + selfie".
  - Four progress dots: ● ● ○ ○. Phone and trade are already done, so the artisan starts with a head start.
  - [Start] button on the right, 36pt.
- y 226–250, section label: "NEW JOBS FOR AC REPAIR" on the left; "Change ▾" on the right.
- y 254–698: 5 job rows (88pt each).
  - Quoting stays open while the ID check is pending (backend rule: bookings and payouts need ID; quotes don't).
- Non-blocking steps (photos, prices, bio) never get a banner. They get one 64pt row below the jobs and a dot on the Profile tab.

C) GUEST ARTISAN, EXPLORING BEFORE SIGN-UP
- y 62–118, top bar (56pt): [📍 Abuja ▾] as a 40pt area pill on the left; "Sign in" as a 40pt text button on the right.
- y 126–158, title (32pt): "Jobs near you" (headline 26/32).
- y 160–178, subtitle (18pt), live demand: "126 open jobs in Abuja this week". With a trade chosen it becomes "46 AC repair jobs this week · most budgets ₦8,000–15,000".
- y 190–222, trade chips: 32pt visible, 48pt touch area, scrolling edge to edge. All · AC repair · Electrical · Plumbing · Generator · Solar · Cleaning · Auto.
- y 234–322: job row (88pt).
- y 323–411: job row (88pt).
- y 412–500: job row (88pt).
- y 512–576, join row (64pt), crimson 6% tint, radius 16:
  - [💼] icon, 36pt.
  - "Quote on jobs like these".
  - "Free · 1 minute · just your phone number".
  - [Join free] button on the right, 36pt.
- y 588–676: job row (88pt).
- y 677–765: job row (88pt). It crosses the fold, with 83% visible.
- y 750: the fold.
  - Above the fold: 4 full jobs, most of a fifth, and a 64pt invitation (9% of the band).
  - Today's build: 1 job and a 274pt pitch (40%).
- Below the fold:
  - Rows 6–10.
  - "See all 126 jobs ›".
  - One trust line: "Clients pay into RijHub. You're paid when the job is done."
- Guest flow:
  1. Tap a job to open the job sheet: photos (loaded on tap), a voice note, area-level location, budget, client signals and the typical price.
  2. "Send quote" opens the quote composer.
  3. Only on Send: "Add your phone number to send this quote. Your quote is saved."
  4. OTP, then the quote is sent, and the artisan lands on view B.

COMPONENT SPECS
- Availability pill:
  - Size: 40pt tall (48pt touch), fully rounded, 12/14pt padding, 8pt dot, label 16/20 (weight 600), 16pt chevron.
  - Available: green 12% tint, label "Available".
  - Busy: amber dot, "Busy till 3 PM".
  - Off: surface fill, 1pt border, hollow dot, "Off".
  - Tapping opens a sheet of about 320pt:
    - A demand line: "Busy now in Wuse 2 · 12 AC jobs today".
    - Three 56pt radio rows: "Available now, until 7:00 PM ▾" / "Busy until 3:00 PM ▾" / "Off today, back tomorrow 8:00 AM".
    - "Repeat off-times" (for example Friday 1–2:30 PM, Sunday morning).
    - [Save], 56pt.
  - The first switch to Available asks for notification permission in context.
- Wallet pill:
  - 40pt tall: a 16pt wallet icon, "₦86,500" in label 16/20 (weight 600), and a "this week" caption when there is room.
  - Tapping opens the Earnings tab.
  - "Hide amounts" shows ₦ ••••• instead. The setting lives on the Earnings tab, and amounts hide automatically while a job is in progress.
- Today card:
  - 76pt, 1pt border, radius 16, 14/16pt padding.
  - A 56pt time column: label 16/20 over caption 12/16 in brand colour.
  - Title in titleSmall 16/22; line 2 in bodySmall 13/18; two 36pt icon buttons.
  - Tapping opens the booking: map, landmark and gate notes, start code.
- Request card:
  - Up to 116pt, crimson 6% tint, radius 16.
  - Title 16/22 (weight 600); meta 13/18.
  - Timer chip: 24pt, caption weight 600. Amber under 10 minutes, red under 3.
  - Actions: 36pt tall.
- Job row:
  - 88pt; 108pt when the title wraps.
  - Flat white row, no border, hairlines inset 64pt.
  - Icon tile: 36pt, radius 10, muted fill, 18pt glyph.
  - Title: 16/22 (weight 600), at most 2 lines, about 290pt wide.
  - Line 2: 13/18, with the budget in weight 600 and primary colour, then area · km in secondary.
  - Line 3: 12/16. "Urgent" in amber, then age, then "Be the first to quote" in green or "N quotes".
  - Tapping the row opens the job sheet. Swiping left marks it "Not for me". No button inside the row.
- Section label:
  - 24pt row. Caption 12/16 in caps, weight 600, +0.4 tracking, tertiary colour.
  - A right-hand link at 13/18 in brand colour.
  - 8pt from label to content; 20pt between sections.

WHAT LEAVES THE HOME
- Earnings tab (new):
  - Week total with daily bars and the comparison with last week.
  - Held for jobs in progress / Ready to withdraw / Next payout date.
  - [Withdraw], 56pt.
  - Transactions.
  - Performance: jobs, rating with review count, response rate with its definition and target ("reply within 30 min"), completion rate.
- Profile: the full setup checklist with a reason for each step, plus tips.
- Jobs tab: the full feed with trade chips, distance, sort, saved jobs and My quotes.

NAVIGATION
- Recommended tabs: Home · Jobs · Earnings · Messages · Profile. This follows Uber (Home, Earnings, Inbox, Menu), Chowdeck (Home, Deliveries, Wallet, Support, Profile) and Bolt.
- Schedule moves into Home (TODAY with a "Schedule ›" link to the full calendar) and into a "Booked" segment of Jobs.
- Alternative: keep Schedule as a tab and move Messages into a header icon, as Tasker by Taskrabbit does.
- Keep text labels on all tabs.

## Critique of the current screens

- **Artisan home, signed in (whole first screen)**: There is no work above the fold. The first screen is entirely about the artisan's status: no next job and no new jobs are visible without scrolling. (Measured from the render signed_in_light.png (390×1470pt at 3x; the harness uses a 62pt top inset and the bottom bar is 60 + 34 = 94pt, so the visible band on a 390×844 phone runs y=62–750, 688pt). Before any work appear: availability 94pt (y138–232), earnings 215pt (y244–459), stats about 68pt (about y471–539) and setup 150pt (y555–705), plus gaps: 567pt, or 82% of the band. The "Next job" card is at y775–853, below the fold. The first job card starts at y945, 195pt below the fold. At 375×667 (signed_in_first_view_375.png) the first screen ends inside the stats and setup cards: zero work. For comparison, Tasker by Taskrabbit shows availability, 4 tasks and an earnings line on one screen; Uber and Bolt show one status control on a map.)
- **Artisan home, signed in: "You're available" card**: A binary state takes a 94pt bordered card with a two-line explanation and a switch. It is oversized and uses the wrong component. (94pt card plus 12pt gap = 106pt, 15% of the first screen. Contents: an 18pt status dot, a 16/22 title, a 13/18 sentence that wraps to two lines ("Clients near Wuse 2 can book you now.") and a 51×31 switch. Apple HIG (Toggles): "Use the switch toggle style only in a list row… Outside of a list, use a button that behaves like a toggle, not a switch." Measured equivalents: Bolt's "Go offline" pill is about 182×49pt inside the top bar, so it costs no extra row; Glovo's "Status · Online" pill is about 100×47pt; Lyft's status is one sentence ("You're online / We're looking for rides"). There is also no end time, so availability goes stale. TaskRabbit switches same-day availability off automatically at midnight.)
- **Artisan home, signed in: earnings card**: The heaviest block on the page is a passive number. It makes money, not work, the focal point, and it shows the balance in large type while the artisan may be standing in a client's home. (215pt, 31% of the first screen, a black slab. ₦86,500 is set in AppText.display (32/38), the token RijHub's own type scale reserves for "Hero headlines on onboarding screens". The card holds 6 items: label, "↑ 20%" pill, amount, last week, divider, and the withdraw block with a 36pt button. There is no way to hide it. Benchmarks: Uber shows earnings as a small top tracker drivers can hide (Privacy Mode; 86% of drivers use the tracker on driving days); Tasker shows one 2-line row ("You've earned $849.50 this month"); Bolt shows one tile of about 79pt. UC Partner, Chowdeck and Uber keep the breakdown and withdrawal on a separate Money, Wallet or Earnings screen.)
- **Artisan home, signed in: stats row (6 jobs / 4.9★ / 96%)**: These numbers change slowly and come with no definitions or targets, but they take prime space on a daily screen. (About 68pt plus a 16pt gap. The rating is shown without its review count, which the research brief warns against. Uber puts rating, acceptance and cancellation on the profile card in its Menu tab; Tasker puts reviews and Elite progress on a Performance tab; Chowdeck puts orders, km and minutes on its Deliveries tab. Only Fiverr's seller home leads with stats, and Fiverr is an async digital marketplace, not local, time-critical work.)
- **Artisan home, signed in: "Finish your profile" card**: An optional nudge outranks a confirmed paid job, at 150pt. (The card is 150pt (y555–705) with a 36pt gap after it, and it sits above "Next job". It holds a 4-segment progress bar, a two-line "Next:" sentence and a link, all for 1 remaining optional step (work photos). Uber handles setup on a separate checklist screen ("Complete 7 more steps to start earning", rows with a "Recommended next step"). A non-blocking step fits a 64pt row placed below the work.)
- **Artisan home, signed in: "Next job"**: The most time-critical item is buried and can't be acted on. (The 78pt card sits at y775, below 4 status blocks and the fold. It shows only service, client, area and time. It has no time-to-leave, landmark, call, chat, directions or "I'm on my way", and tapping it just opens the Bookings tab. Tasker puts TODAY'S SCHEDULE at the top of home. Housecall Pro's "On my way" button texts the customer in one tap.)
- **Both artisan homes: job cards**: Each job is 2 to 2.4 times taller than benchmark rows, about 60pt of each card is chrome, and the same bordered "Send quote" button repeats on every card. (Cards are 149pt with a one-line title or 171pt with a two-line title, plus 12pt gaps, so 161–183pt per job. The chrome: a 40pt icon-tile column (52pt of width including its gap), a 12 + 1 + 12pt divider band, 16pt padding top and bottom, and a border. Tasker's rows sit at a 75pt pitch; a Material 3 three-line list item is 88dp. The title column is 266pt wide, but only about 188pt next to the "Urgent" tag, which shares the title row and forces a wrap: the two 171pt cards are exactly the urgent ones ("AC not cooling and leaking water", "Socket sparking in the kitchen"). The guest screen shows 6 identical "Send quote" buttons. Upwork, Airtasker and Thumbtack list rows are tappable, with the action in the detail screen.)
- **Artisan home, signed in: section rhythm**: Headers and gaps eat a third of a screen. (Each section starts with about 64–70pt of chrome: a 32pt top gap, a 20/26 bold title and a 12pt gap. Measured gaps: setup to "Next job" 36pt, next-job card to "New jobs near you" 47pt, title to first card 25pt. In total, about 224pt of whitespace and titles sits between the header and the first job. Tasker uses section labels of about 11pt caps that take about 28pt each.)
- **Artisan home, signed in: what is (not) shown**: The home lacks the two lanes that matter most: direct requests, and jobs that match the artisan's trades. (The home calls openJobsNearby(area, limit: 3). There is no trade filter, only 3 jobs, and the heading is "New jobs near you", not "for you". BookingStatus.requested exists in the model, but the home has no "Requests for you" lane and no reply-by timer. Thumbtack leads with "Brian C. wants to book you" and an "Only picked you" chip. Tasker's first group is PENDING with "Chat today by 9:00pm". Glovo shows "16 seconds to auto-decline". Upwork ranks "Best Matches".)
- **Artisan home, signed in: visual noise**: Too many competing styles leave the eye with no single focal point. This is the "so much is happening" the product owner felt. (The first screen has 27 separately styled elements (avatar, greeting, name, bell, dot, title, subtitle, switch, 8 earnings items, 6 stat parts, 5 setup parts) and three container styles (outlined, black-filled, grey-filled). Numbers appear at five sizes (32, 20, 16, 13 and 12pt). Accents include green (dot, switch, +20%), amber (star), crimson (button text, progress, link) and a black slab. Benchmarks use one or two accents (Uber black and blue; Tasker green) and one container style for list content.)
- **Artisan home, guest**: It leads with a sign-up pitch, which contradicts the "explore first" brief, and shows almost no jobs above the fold. (The dark join card is 274pt (y140–414), 40% of the first screen, and it comes before any job. Two auth buttons ("Sign in" and a 56pt "Create your free profile") appear before the first job. Only one job is visible: card 1 at y558–729, while card 2 starts at y741, so only 9pt of it shows. At 375×667 (guest_first_view_375.png) the join card is 264pt and the first job starts at y542: no complete job is visible. NN/g found content just above the fold is viewed far more than content below it (84% average difference, holding "on any size screen"), and that 57% of viewing time is spent above the fold. The most valuable pixels go to a pitch instead of proof of demand.)
- **Artisan home, guest: header**: The greeting and the title add nothing for an anonymous guest, and the title duplicates the section heading below it. ("Good afternoon" plus a 26pt "Find work near you" takes 45pt, and "Jobs near you" repeats 340pt lower. That space could show live demand ("126 open jobs in Abuja this week") and an area picker. Thumbtack sells demand in exactly this way: "There were 65 local jobs in this service last month".)
- **Artisan home, guest: trade chips**: The chips are oversized, the last one is cut off mid-word, and the filter exists only for guests. (The chips are 40pt tall with icons (y506–546), and the 4th reads "Pl…" at the screen edge. Material 3 filter and assist chips are 32dp tall. The signed-in home has no trade filter, even though signed-in artisans are the ones who need their trades matched.)

## Benchmarks

- **Uber Driver**: OFFLINE HOME: the map fills the screen. Floating round buttons sit at the lower corners (safety shield on the left, map report on the right). A round blue GO button is centred just above the bottom sheet. Under it is the bottom status strip: "You're offline", with a driving-preferences icon on the left and a list icon on the right. Swiping up opens a sheet of cards, such as Inbox: "Complete personal safety education" and a "Surging now" demand map. The tab bar has 4 sections: Home, Earnings, Inbox, Menu. ONLINE: a real-time earnings tracker sits at the top of the screen (2018 relaunch). Uber's 2019 engineering post shows earnings and incentives in the upper right. Trip offers arrive as a modal card, top to bottom: tags (Delivery, Exclusive), the fare in large bold type ($12.34), "Expected tip included", "4 min (2.2 mi) total", pickup and drop-off, then a full-width Accept button. NOT ON HOME: the weekly breakdown (week total, daily bars, online time, trips, points, balance with next payment date, Cash out) is on the Earnings tab. Rating 4.95, acceptance 90% and cancellation 2% are on a profile card in the Menu tab. Sign-up steps are a separate checklist screen ("Welcome, Paula. Complete 7 more steps to start earning", with a segmented progress bar and rows, one tagged "Recommended next step").
  - Steal: (1) Show status as one line of text plus one control, never a card with an explanation. (2) Make earnings a tiny tracker the driver can hide (Privacy Mode); 86% of drivers use it on driving days. (3) Put rating, acceptance and cancellation on the profile and the breakdown on the Earnings tab. (4) Make setup its own checklist screen with a "Recommended next step", not a home card. (5) Make the offer card the one place where size goes big: price first, then time and distance, then one full-width Accept.
- **Bolt Driver**: ONLINE HOME: a top bar floats over the map with a round menu button on the left, an orange "» Go offline" pill in the centre and a safety shield on the right. The map follows, with floating map and filter buttons on the right. At the bottom is a sheet with a grab handle and three tiles: Today's earnings 25.50€ (tall, left), then Driver Score 94% and Acceptance rate 94% stacked on the right. The tab bar has 4 tabs: Home, Earn More, Rides, Help. NOT ON HOME: payment history (Daily/Weekly, with a Bolt commission line per day), the weekly payout and "Early cashout" are on Earnings. The profile/menu has Driver Score 98% and Acceptance rate 98% tiles, then rows for Earnings, Trip history, Campaigns, Scheduled rides and Support. Rewards tiers (Silver, Unlock Gold) are on their own screen.
  - Steal: (1) Put availability in the top bar as a pill that shows the state and is the control, at about 44–49pt instead of a 94pt card. (2) The » chevrons signal a deliberate swipe, which guards against accidental toggles. (3) Show today's earnings as one small tile, not a hero card. (4) Bolt keeps two metrics on home only because acceptance rate directly gates rewards. RijHub should surface a metric on home only while it is below target.
- **Lyft Driver**: ONLINE: the map shows bonus zones (30%, 40%). The bottom sheet reads "You're online" with one line under it, "We're looking for rides", followed by an active bonus row ("10% Turbo · Active"). GOING ONLINE (2018 help): "Just tap the wheel to receive ride requests", using the steering-wheel icon. There are three states: offline, online and last ride ("you won't receive any new requests until you go back online"). The current Go control's position isn't shown in the store shots (unknown). OFFER CARD: "$20.85 incl. $2.50 bonus", "$41.56/hr est. rate for this ride", 6 min · 2.1 mi and 23 min · 13 mi, the rider ("Alexandra, Verified ★4.9"), an "Assisted" tag, then a full-width Accept. NOT ON HOME: Earnings is a full screen with Week/Month/Year tabs, $248.17, daily bars and "View weekly breakdown".
  - Steal: (1) Write status as a sentence ("You're online, we're looking for rides") instead of a card. (2) A third "last ride" state means finish this job and take no new requests; RijHub's version is "Busy until 3 PM". (3) Show the estimated hourly rate on an offer. For RijHub: "₦12,000 · about 2 h work · 3.1 km" helps an artisan judge whether a job is worth it. (4) Show trust signals about the customer (Verified, ★4.9) on the offer.
- **TaskRabbit (Tasker by Taskrabbit)**: HOME, top to bottom: a dark green header with avatar, "Hello, Benjamin", and announcements and inbox icons with badges (1, 10). Next is the availability status row "Same day tasks [RECEIVING]" with one line, "Get tasks that need to be done today". An 8pt grey band follows. Then: PENDING, a row with an initials avatar (JM): "Furniture Assembly: Justin M" / "Chat today by 9:00pm". TODAY'S SCHEDULE: "Furniture Assembly: Hayley G" / "Today at 10:30am". THIS WEEK: "Home Repairs: Parker H" / "Tue, Jun 10 at 10:00am" and "Mounting: Alyssa M" / "Wed, Jun 11 at 12:30pm". Another grey band, then one summary row: "5 completed tasks this June / You've earned $849.50 this month ›". The tabs are icon-only: Home, Map, Calendar, Performance, Profile. NOT ON HOME: the Performance tab holds Earnings (June total, task count), Reviews (4.5/5, 142 reviews), Skills & Rates ("1 of your rates can be optimized") and Elite progress (3 of 4 milestones, 75%). Rules: the Same Day toggle "is automatically turned off at midnight every night". Calendar availability runs up to 17 days ahead, in blocks of 2.5h or more. TaskRabbit also tested moving the Tasks screen into Home and dropping the Tasks tab (UK blog roundup, via search summary).
  - Steal: This is the closest model for RijHub. (1) Make home an agenda grouped by urgency: Pending (with a reply-by deadline), then Today, then This week. (2) Use flat rows at a 75pt pitch, not bordered cards. (3) Make earnings one sentence on home, with stats on a separate Performance tab. (4) Show availability as a status tag (RECEIVING) that switches itself off at midnight. (5) Use small caps section labels instead of 20pt titles. (6) Put Messages in the header with a badge rather than a tab. Don't copy the icon-only tabs: RijHub's users need text labels.
- **Thumbtack for Professionals**: Pieced together from store screenshots and docs; the full home isn't shown. DIRECT LEAD HERO: "Brian C. wants to book you.", the location, chips "Exact match" and "Only picked you", job details as a checklist (Property type: Apartment, Flooring: Carpets, Pets in home: Yes, Job size: 3 rooms) and a full-width Reply button. LEAD LIST CARDS: customer name, service ("Appliance installation"), date and time, address, phone. INSIGHT CARDS: "Add low-competition jobs: Adjust your preferences"; response time compared as bars ("You 1h 20m · Avg. pro 5h 21m · Top pro 50m"); "Get new types of jobs: There were 65 local jobs in this service last month. Add this service"; a weekly budget ring ("48%, $60 of $125 spent this week"). Leads are split into Direct leads (matching the pro's preferences) and Opportunities (outside preferences; the customer has already contacted another pro). Quick Replies stores saved messages.
  - Steal: (1) Put a "Requests for you" lane above open jobs, with "Only picked you" and "Exact match" chips. (2) Make nudges about demand ("65 local jobs in this service last month") instead of a generic "finish your profile". (3) Compare response time ("you vs top pros") on the Earnings/Performance tab. (4) Quick Replies become RijHub's one-tap quote templates.
- **Urban Company Partner (UC Partner)**: The store screenshots show onboarding (documents, selfie, Aadhaar) and the MONEY screen, not the home. MONEY SCREEN, top to bottom: a top bar with menu, a credits pill ("287 ◎") and a bell; a "Money" title; a card with "₹48,911 Earned this month" and monthly bars; "Bank transfers" as horizontal cards (₹2,861 · 22–24 Feb · Upcoming; ₹3,187 · 18–21 Feb · In processing); a rewards row ("Win upto ₹2 lakh in shares"). Earnings detail has Monthly, Weekly and Subscription tabs with Total earnings, Deductions and Net earnings, plus a payslip download. The listing describes the partner workflow as "managing your calendar, taking advanced trainings, getting alerted with the latest opportunities". Jobs are likely assigned into calendar slots rather than a live online/offline toggle (inferred, not documented).
  - Steal: (1) Give money its own screen, with payouts broken into stages (Upcoming, In processing, Paid). That is where RijHub's 215pt earnings card belongs. (2) Use a compact balance pill in the header instead of a hero card. (3) Trainings and opportunity alerts sit behind menus, not on home.
- **Airtasker (as a Tasker)**: BROWSE TASKS (web, fetched): a filter bar first: distance (e.g. "50 km" around a location, plus remote), price ("Any price"), other filters and sort. Without signing in, the page showed "0 new tasks" around Lagos and a prompt to join or log in. TASK CARD anatomy (inferred from product knowledge; the public page returned no cards): title; location or "Remote"; date or "Flexible"; status "Open · N offers"; price on the right; poster avatar. TASK DETAIL (store screenshots): title, location, date, "150 AUD Budget", description, then Offers (4) / Questions tabs. Offer rows show avatar, ★4.8 (18), "98% Completion rate", price and Accept. On payment release: "Payment secured", task price, optional tip.
  - Steal: (1) Show the price as a scannable column. (2) Show date flexibility ("Flexible" / "Today") on every task. (3) Filter by distance radius. (4) Show completion rate as a trust signal. (5) Let guests browse real tasks, with joining asked only to go further.
- **Upwork (freelancer side)**: FIND WORK feed with tabs Best Matches and Most Recent; My Feed comes from saved searches, and a thumbs-down refines recommendations (community). Job tiles (inferred; the store shots don't show the feed): posted time, title, budget or hourly rate and level, 2–3 lines of description, skill chips, client signals (payment verified, rating, amount spent, country) and proposal count. Not on home: Reports Overview rows (Work in progress $789.43 · In review $485.98 · Pending $874.21 · Available $7,543.47, each a label and amount row with a chevron); the contract room ("In escrow $4,497.40"); an AI assistant that drafts proposals ("Insert cover letter").
  - Steal: (1) Rank jobs as "Best matches" for the artisan's trades, with a way to say "not for me". (2) Break money down by stage: in progress, in review, pending, available. (3) AI help to write a quote.
- **Fiverr (seller side): counter-example**: SELLER HOME (dark), top to bottom: "Hi Moon, Welcome back" with an avatar carrying an online dot. A 2×2 grid follows: My level (Top Rated badge), Success score 9, Rating 5.0, Response rate 98%, each with a progress bar against its requirement. Then rows Orders 50/50, Unique clients 20/20, Earnings $10,000/$10,000. Then an Earnings section (Personal balance $12,562, Earnings in May $2,864, Avg. selling price, Active orders, View details). The buyer/seller switch and the availability and earnings controls are in the account menu (Fiverr help, via search summary; the page returned 403).
  - Steal: Nothing for RijHub's home: this is the pattern RijHub's current dashboard resembles, and it suits async digital orders where sellers chase level requirements. Keep only (1) progress bars that show a metric against its target, for the Performance tab, and (2) an online dot on the avatar.
- **Glovo Rider (with Wolt Courier Partner as a second courier reference)**: GLOVO ONLINE: a top bar over the map with a round menu button (left), a "Status · Online" pill with a green dot (centre) and a refresh button. Below is a demand heatmap, then a bottom card: "Searching for orders… Red areas can have more opportunities for orders". GOING ONLINE opens a "Start working" sheet: vehicle type, bag type, an Auto-Accept Orders switch, agreements, and Start. OFFER: "€4.70" large, "Includes €3,70 extra", pickup and drop-off with km and minutes, a "16 seconds to auto-decline" progress line, a full-width "Accept order" button, a "Decline" pill and an "Acceptance 89%" pill at the top. In some markets couriers book hourly slots ahead (Technext, 2022). WOLT OFFLINE: a top bar reading "You are offline", the map, then a sheet: "Delivery area · Berlin Central · Area demand: Busy", a "Slide to go online" slider, and rows for Previous task, Scheduled offline and Support. WOLT EARNINGS SHEET: "Your earnings this week €490,65 ›"; earnings per hour over the last 24h (€13.4) with Total offered and Declined; "Expected demand today" as hourly bars with a NOW marker.
  - Steal: (1) Show status in a pill that names the state. (2) Put an auto-decline countdown on offers. (3) Put "Area demand: Busy" next to the availability control so the worker knows whether going online pays. (4) Put session choices in a short sheet rather than on home. (5) "Scheduled offline" lets workers set off-blocks in advance.
- **Chowdeck Rider (Nigeria)**: Tabs: Home, Deliveries, Wallet, Support, Profile. The home isn't in the store screenshots. The listing says to "simply go online when you're ready to ride", with a "Live earnings tracker" and "Instant wallet access, withdraw your earnings at any time". The DELIVERIES tab holds the metrics, with a "Today ▾" filter: 42 Orders (progress toward targets 40/60/80), 400 km, 256 mins, a bonus collected today of ₦2,500. WALLET: "Available balance ₦250,500,000" with a "Withdraw Money" button, "Request for Loan" and the last 10 transactions (Fuel, Weekly Bonus, April Salary, You withdrew). A riding-hours plan is chosen at sign-up (Full time 9h × 6 days, Part time, Weekend). NIN is verified at sign-up, and riders can always see whether it is Verified, Pending or Failed.
  - Steal: (1) Local conventions: full ₦ amounts, "Withdraw Money" as the wallet's main action, and an expectation of instant withdrawal. (2) Metrics on their own tab with a time filter. (3) The availability plan set once at sign-up, so day-to-day toggling is light.

## Innovative ideas

- Availability that runs itself. One pill with three states (Available until 7 PM / Busy until 3 PM / Off today), plus:
- it switches off automatically at the chosen time;
- tapping "I've started" on a job sets Busy, and "Job done" sets Available again;
- recurring off-times can be set (for example Friday prayers, Sunday service, market day). (value: Clients can't book the artisan while they are asleep or on another job. Response rate isn't hurt by ghost availability. The artisan almost never touches the control.)
- A "Requests for you" lane on home, above open jobs. Each request shows:
- a reply-by countdown;
- one-tap Accept or Not now;
- an "Only picked you" chip.
If push isn't delivered, the request falls back to SMS or WhatsApp. (value: The artisan wins the jobs where a client has already chosen them, which convert best, and replies are fast enough to count.)
- A trade-matched feed. "New jobs for you" ranks the artisan's trades and nearby areas first. Swiping left on a job marks it "Not for me" (with an optional reason: too far, not my trade, budget too low), and the ranking learns from it. (value: An AC technician never scrolls past plumbing jobs. The feed gets better each day without any setup.)
- "Jobs on your way." Inside the Today card, show open jobs within about 2 km of the next booking: "2 more AC jobs near your 2:30 PM in Wuse 2, quote now". (value: Less travel across Abuja's spread-out districts, and more jobs per trip and per litre of fuel.)
- One-tap quote templates with an Abuja price guide. Each trade has saved lines, for example "Service 1 split unit ₦10,000", "Gas top-up 1.5HP ₦18,000", "Inspection visit ₦3,000, credited if hired". The job sheet shows "Most AC artisans quoted ₦10,000–14,000 for jobs like this" and splits workmanship from materials. (value: A quote can be sent in about 5 seconds from a job site. Artisans underprice less, quotes look professional, and clients see prices they can compare.)
- Voice-first quoting and job briefs. Clients can attach a voice note to a job, and artisans can reply with a voice quote. Both are transcribed automatically (English and Pidgin) and shown as text with the price pulled out for confirmation. (value: Artisans can quote hands-free from a ladder or under a generator. It suits lower-literacy users, and clients hear a confident professional.)
- A Today timeline built for Abuja. It shows a leave-by time based on live traffic, the client's landmark and gate notes ("blue gate opposite Banex Plaza"), a start code, and one tap on "I'm on my way" that sends the client an ETA by push or SMS. (value: Better punctuality, the right house found first time, fewer "where are you?" calls, and a clear record that the job started.)
- A private wallet pill. Earnings show as one pill in the top bar, with "Hide amounts" that masks them (₦ •••••). Amounts hide automatically while a job is in progress at a client's home. The full breakdown lives on the Earnings tab. (value: Safety and discretion in strangers' homes, without losing the motivating glance.)
- A demand hint where the availability decision is made. The availability sheet says "Busy now in Wuse 2 · 12 AC jobs today · busiest 4–7 PM". A small hourly demand chart sits on the Earnings tab. (value: Artisans know when going available is worth it and can plan their week around real demand.)
- A demand preview for guests. Before sign-up, an artisan picks a trade and area and sees live proof: "46 AC repair jobs this week · most budgets ₦8,000–15,000 · 3 posted in the last hour". (value: The guest sees there is real money for their trade before giving a phone number. This is the honest version of "explore first".)
- Quote-first sign-up. A guest can open any job and write a full quote. The phone number is asked only at Send ("Your quote is saved"), and the draft survives OTP and onboarding. (value: Sign-up has an obvious reason and no work is lost. The first session ends with a real quote sent, not an empty profile.)
- "Visit first" quotes. When a job can't be priced from photos, the artisan offers a paid inspection visit (for example ₦3,000), credited to the job if they are hired. (value: Fair quotes for complex jobs (generators, wiring), fewer disputes, and the artisan is paid for diagnosis time.)
- Client signals on every job sheet: "Phone verified · Payment ready · Client ★4.8 (6 jobs) · Usually confirms within 1 h". (value: Artisans skip time-wasters and spend fuel on clients who pay.)
- Setup prominence that matches the consequence. A step that blocks bookings (ID check) gets one banner and turns the pill to "Off · ID needed". Optional steps (photos, prices) get one row below the work and a dot on the Profile tab. The checklist starts with steps already done (phone ✓, trade ✓). (value: No nagging, and the artisan knows exactly when something actually stops them earning.)
- A low-data, offline-tolerant home. Job rows are text only, with photos loaded on tap. The last feed is cached and labelled "Updated 2 min ago". When data is off, direct requests also go out by SMS or WhatsApp with a reply code. (value: The app works on ₦575/GB data and patchy networks, and a paying request is never missed because data ran out.)
- A weekly goal on the wallet pill, for example "₦86,500 of ₦100,000" shown as a thin progress ring. The artisan sets the target on the Earnings tab, and the ring is hidden when amounts are hidden. (value: Motivation without a dashboard: one glance shows how much more work this week needs.)

## Sizing rules

- Touch targets: 44×44pt default on iOS (minimum 28×28) and 48dp on Android. Visible pills can be 32–40pt as long as the hit area is 48. Sources: Apple HIG Accessibility, 'Default control size 44x44 pt, Minimum 28x28 pt' (developer.apple.com/design/human-interface-guidelines/accessibility); RijHub AppSize.minTapTarget = 48.
- Never put a switch in a standalone card. Apple HIG Toggles: 'Use the switch toggle style only in a list row… Outside of a list, use a button that behaves like a toggle, not a switch.' Availability should be a 40pt toggle pill in the top bar. Measured precedents, scaled to 390pt: Bolt's 'Go offline' pill is about 182×49pt and Glovo's 'Status · Online' pill about 100×47pt (Play screenshots). RijHub's card is 94pt.
- List item heights are 56 / 72 / 88 for one, two and three lines, with a 40 leading avatar, 24 leading icon and 16 side padding. Sources: Material 3 tokens in material-web v0_192 _md-comp-list.scss; Flutter ListTile defaults 56/72/88 (dense 48/64/76) in packages/flutter/lib/src/material/list_tile.dart. RijHub: job row 88 (108 when the title wraps), Today card about 76, request card up to 116.
- Feed density benchmark: Tasker by Taskrabbit's home rows sit at a 75pt pitch with 48pt avatars, and 4 tasks plus status plus earnings fit one screen (App Store screenshot; 436px screen = 390pt). Target at least 4 job rows per 390×844 screen. Today RijHub fits 1 (guest) and 0 (signed in), because its cards are 149–171pt plus 12pt gaps.
- Chips are 32dp tall: the M3 assist and filter chip container height is 32px (material-web tokens). RijHub's trade chips are 40pt. Use 32–36pt visible with 48pt touch, and let the row scroll edge to edge with a fade, not a cut-off word.
- Buttons: the M3 filled button is 40dp. Inside rows or cards, use 32–36pt pills (RijHub AppSize.buttonSmall is 36). Use a 56pt large button once per screen or sheet, for the main commit (Send quote, Save, Withdraw), never repeated on every list item. RijHub's guest home repeats 'Send quote' 6 times.
- Bars: the M3 small top app bar is 64dp and the navigation bar 80dp (material-web tokens); Flutter's kToolbarHeight is 56. The RijHub home top bar should be 56pt with 40pt pills inside, so the status and money pills cost no extra rows. The bottom bar stays at 60pt plus the safe area.
- When a switch is the right control, in a settings list: the M3 track is 52×32 (handle 16/24/28) and iOS 51×31 (Flutter switch.dart, Material and Cupertino configs). Neither needs a 94pt card around it.
- Section labels: 12–13pt caps at weight 600 in a 24pt row, 8pt to content and 20pt between sections. Tasker uses labels of about 11pt caps taking about 28pt each. RijHub today spends about 64–70pt per section (32pt gap, a 20/26 bold title, 12pt gap), about 224pt before the first job.
- Type in proportion: keep the 32/38 display size for onboarding and empty states. RijHub's own AppText.display doc says 'Hero headlines on onboarding screens', yet the earnings card uses it. On home, money in pills and rows is 16/20 at weight 600, row titles 16/22, metadata 12–13. Benchmarks keep home numbers small (Uber's tracker, Tasker's one-line '$849.50 this month'). iOS default body text is 17pt and the minimum 11pt (Apple HIG Accessibility).
- Above-the-fold budget on 390×844, a 688pt band after a 62pt status bar and 94pt bottom bar: at least 3 actionable work items, status chrome of about 130pt or less (about 20%), and no passive block taller than about 100pt (15%). NN/g found 57% of viewing time above the fold and 74% in the first two screenfuls (nngroup.com/articles/scrolling-and-attention, 2018), and an 84% average attention difference across the fold 'on any size screen, be it mobile, tablet, or desktop' (nngroup.com/articles/page-fold-manifesto, 2015).
- Size by consequence and urgency, not by how much data a block holds. A binary state gets a 40pt pill. A passive number gets a pill or a 56pt row. An optional nudge gets a row of 64pt or less. A time-limited decision with money attached (a direct request) gets up to about 116pt. Only a screen's single job gets a hero control: Uber's GO button is about 78pt (20% of the width) and Wolt's 'Slide to go online' about 83pt tall, both on offline screens with nothing else to do (measured from Play screenshots).
- Gutters and padding: use 16pt side padding (M3 list leading and trailing space 16). Today's 20pt gutters, 16pt card padding and 40pt icon column leave 266pt for job titles (about 188pt beside an 'Urgent' tag). Flat 88pt rows with a 36pt tile and the tag moved to line 3 leave about 290pt.
- Separators over containers: feed rows are flat with 1pt hairlines inset to the text column. Tasker uses flat rows with 8pt grey bands between groups. Keep bordered or tinted cards for the one or two items that need a decision (today's job, a direct request), so colour and borders signal 'act on this'.
- Text-size resilience: at 130% text, pills drop secondary words (the wallet pill shows the amount only), rows grow to two-line titles (108pt), and prices and times are never truncated. Test at 375×667 as well: today both artisan homes show zero complete jobs there (guest_first_view_375.png, signed_in_first_view_375.png).