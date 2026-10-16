# RijHub onboarding and home screens: UX research brief (Abuja launch)

Written in October 2026 to inform the redesign. Sources are linked inline.

**How this was researched and how far to trust it**
- **Source types.** Primary or expert sources were used wherever possible: platform guidelines from Apple, Google and Android; Nielsen Norman Group (NN/g) and Baymard research; official help centres, app store listings and company blogs; and Nigerian market data and press.
- **Screen libraries.** Mobbin, Page Flows and Lazyweb all require a login, so their teardowns were not used. Some official pages (Thumbtack's guide pages, Axios, BusinessWire, the Google Play blog on Medium) blocked fetching. Where a figure came through a search index or a secondary write-up, it is marked **(secondary)**. Vendor marketing claims are marked **(vendor claim)**.

---

## TL;DR

1. **Don't use an intro carousel.** In NN/g's controlled test, a swipe-through tutorial gave no task benefit and made tasks feel harder. Use one static value screen that doubles as the client/artisan fork.
2. **Let clients browse as guests.** Ask for sign-in only at the first commitment (book, post a job, message), and explain why at that moment. Apple guideline 5.1.1(v), Baymard's checkout research and Duolingo's sign-up test all point the same way.
3. **Sign-up should be phone-first and passwordless.** Send the code by SMS on a properly registered transactional route, offer WhatsApp as a second channel, and read the code automatically. Google and Apple sign-in are secondary and still need phone verification.
4. **The client home should be built around search and categories,** with a full trust stack on every artisan card: what was verified, rating with review count, jobs done, response time, "from ₦" price and area. It should also have a "Post a job, get quotes" entry and, for returning users, "Book again".
5. **The artisan home should be built around availability:** an online/offline toggle, direct requests, next job, nearby jobs (showing signals about the client), earnings (pending, held, available, with a hide toggle), a setup checklist and clearly defined performance metrics.
6. **The Nigeria-specific fundamentals are:**
   - Payment protection: money is held by RijHub and released when the client confirms.
   - Bank transfer as the first-class way to pay.
   - Area-plus-landmark addresses.
   - Data-light screens for sub-$200 Android phones.
   - Plain Nigerian English with local trade words.
   - Verified ID with a liveness selfie for artisans, under NDPA consent rules.

---

## 1. Onboarding

### 1.1 Intro carousel vs none: the evidence

- **NN/g controlled study** ([Kendrick, Mar 2020](https://www.nngroup.com/articles/mobile-tutorials/)): 70 participants, 4 iOS apps.
  - Task success was 91% with a deck-of-cards tutorial and 94% without (not significant).
  - People who saw the tutorial rated tasks as *harder* (single-ease rating 4.92 vs 5.49 on a 1–7 scale, p=0.047).
  - Time on task showed no significant difference, and that excludes the time spent reading the tutorial.
- **NN/g guidance** ([Jun 2020](https://www.nngroup.com/articles/mobile-app-onboarding/)):
  - "we don't recommend deck-of-cards onboarding."
  - "Avoid feature-promotion onboarding at first launch."
  - Content customization is the legitimate use. If cards are used anyway: a visible Skip, very few cards, one concept each.
- **Vevo A/B test** (160k users over 4 weeks; vendor-reported via Apptimize, about 10 years old) **(secondary)**: the group with no tutorial logged in about 10% more and signed up about 6% more ([Mobile World Live](https://www.mobileworldlive.com/apps/focus-apps/apptimize-onboarding-tutorials-value-ab-testing/)).
- **Google Material (M1) onboarding models** ([source](https://m1.material.io/growth-communications/onboarding.html)): Self-select, Quickstart, and Top user benefits (a short carousel with at most 3 benefits). Returning users never see onboarding.
- **Duolingo** ([First Round](https://review.firstround.com/the-tenets-of-a-b-testing-from-duolingos-master-growth-hacker)):
  - "Simply moving the sign-up screen back a few steps led to about a 20% increase in DAUs."
  - Soft (skippable) sign-up prompts placed before a hard wall matter: "without those soft walls … hard walls perform significantly worse."
  - Later tuning of the prompts added another 8.2% DAU.
- **Thumbtack's 2024 relaunch** onboards homeowners with "personalized, bite-sized educational content". That is customization, not a feature tour ([Airship recap](https://www.airship.com/podcast/secrets-to-a-successful-app-redesign/)).

**Verdict for RijHub:** one static screen with the value proposition, the client/artisan fork and a "Sign in" link. Teach in context instead: empty states, the first job flow, tooltips on badges. Background imagery is acceptable only if the message and calls to action stay still (see the auto-forwarding finding in 2.2).

### 1.2 When to ask client vs artisan

| Pattern | Examples |
|---|---|
| Separate app per side | TaskRabbit and Tasker; Thumbtack and [Thumbtack for Professionals](https://apps.apple.com/us/app/thumbtack-for-professionals/id908795016); Urban Company and [UC Partner](https://apps.apple.com/in/app/id1483049403); Bark and [Bark for Professionals](https://apps.apple.com/us/app/-/id1206370169); Angi and Angi for Pros ([Angi](https://www.angi.com/how-it-works)) |
| One app, role asked at the very first sign-up step | Upwork: "I'm a client, hiring for a project" ([Upwork](https://www.upwork.com/resources/upwork-client-profiles-what-you-need-to-know)) |
| One app, both roles on one account | [Airtasker](https://apps.apple.com/us/app/airtasker/id512137061): "post a task" and "browse thousands of new tasks" in the same app |

- **Fred Wilson's view** ([AVC](https://avc.com/2015/11/mobile-apps-for-both-sides-of-the-market/)): on mobile "it seems that it is better to have different native mobile apps for both sides", and "I've seen folks try to put both sides … in a single mobile app and it doesn't work that well". The cost is "more development and marketing resources".

**Verdict:**
- Keep one Flutter app with two distinct experiences (navigation, home, copy). Ask the role once, as a one-tap fork on the first screen.
- Clients go straight into guest browsing. Artisans go into a short sign-up.
- Let one account hold both roles later.
- Revisit a separate "RijHub for Artisans" listing only once the artisan side has dedicated staffing. Wilson's warning is that the provider app tends to get neglected.

### 1.3 Phone-first sign-up and what works in Nigeria

**Precedent.** Nigerian consumer apps verify by phone. Chowdeck asks for name, phone and email, then sends the code by SMS and email ([Chowdeck help](https://help.chowdeck.com/en/articles/16876603-what-is-chowdeck)). The phone number is also how artisans and clients actually reach each other.

**How SMS codes behave in Nigeria** ([Telerivet, Apr 2026](https://www.telerivet.com/blog/nigeria-sms-sender-id-dnd-compliance)):
- Transactional messages such as login codes *can* reach numbers on the Do Not Disturb registry (users join it by texting STOP to 2442), as long as they travel on a transactional route.
- "An OTP message that appends a promo line stops being authentication traffic in the operator's eyes." Never add marketing text to a code message.
- The sender name must be registered separately with MTN, Airtel, Glo and 9mobile, typically 3–5 business days once paperwork is complete.
- Networks filter messages silently, so monitor *delivery* status, not "sent" status.
- The NCC began licensing international bulk-SMS (A2P) aggregators in July 2025 ([NCC](https://ncc.gov.ng/media-center/public-notices/commencement-licensing-provision-international-a2p-messaging-aggregator)). Use a compliant local route.

**WhatsApp as the second channel:**
- WhatsApp is installed on 95% of surveyed smartphones: 13,251 respondents in 12 cities including Abuja. Installed does not mean active ([KPMG/Orange via Innovation Village](https://innovation-village.com/kpmg-study-opay-whatsapp-lead-nigeria-smartphone-apps/)).
- Meta's authentication message templates support copy-code, one-tap and zero-tap autofill ([Meta](https://developers.facebook.com/documentation/business-messaging/whatsapp/templates/authentication-templates/copy-code-button-authentication-templates)).
- Pricing has been per message since 1 Jul 2025. Nigeria is priced as its own market, and authentication rates were cut on 1 Feb 2025 ([Meta pricing](https://developers.facebook.com/docs/whatsapp/pricing/)).
- It only reaches numbers that are on WhatsApp, so keep SMS as the primary channel.

**Reading the code automatically.** Android's SMS Retriever API reads the code with no SMS permission; the message must include the app's hash ([Google](https://developers.google.com/identity/sms-retriever/overview)).

**Number entry** **(vendor reference)** ([sent.dm](https://sent.dm/resources/NG)):
- Accept `0803…`, `803…` and `+234 803…`, and store everything in international format.
- After dropping the leading 0, valid mobile numbers start with 70, 80, 81, 90 or 91.
- Numbers have been portable between networks since 2013, so never guess the network from the prefix.

**Apple requirement.** If the app supports account creation, it must also offer account deletion inside the app (guideline 5.1.1(v), [Apple](https://developer.apple.com/app-store/review/guidelines/)).

### 1.4 Social sign-in

- **Apple guideline 4.8:** if Google sign-in creates the main account on iOS, the app must also offer an equivalent privacy-preserving option. Sign in with Apple qualifies. The rule does not apply when the app only uses its own account system ([Apple](https://developer.apple.com/app-store/review/guidelines/)).
- Upwork offers Google and Apple; Airtasker offers Facebook, Google and Apple ([Airtasker help](https://support.airtasker.com/hc/en-us/articles/21358983849625-How-do-I-sign-up)).
- **For RijHub:** this is optional and low priority. If offered, follow it with phone verification, because the phone is the operational identity and a fraud control.

### 1.5 Minimum sign-up fields

- Apple 5.1.1(v): "Apps may not require users to enter personal information to function, except when directly relevant to the core functionality of the app or required by law."
- Nigeria's data protection rules (NDPA 2023, with the GAID 2025 directive in force since 19 Sep 2025) require data minimisation ("minimum necessary") and recorded consent ([Mondaq](https://www.mondaq.com/nigeria/privacy-protection/1606106/the-nigeria-data-protection-commission-issues-the-general-application-and-implementation-directive-2025-gaid)).
- **Client:** phone and first name at the first commitment. Last name and email optional. Address is captured at booking. Never ask clients for NIN or BVN.
- **Artisan:** phone, name, up to 3 trades, work area. Everything else (ID, services and prices, work photos, payout account) goes into a checklist after sign-up (see 3.3).

### 1.6 Asking for permissions

**Apple Human Interface Guidelines** ([source](https://developer.apple.com/design/human-interface-guidelines/privacy)):
- "Avoid requesting permission at launch unless the data or resource is required for your app to function."
- "Ideally, wait to request permission until people actually use an app feature that requires access."
- A custom screen before the system prompt is allowed, but:
  - it gets one button titled "Continue" or "Next";
  - no "Allow" wording;
  - no way to close or cancel;
  - no incentives.

**App Store rules** ([Apple](https://developer.apple.com/app-store/review/guidelines/)):
- 5.1.1(iv): "if a user declines to share Location, offer the ability to manually enter an address."
- 5.1.2(i): apps may not *require* notifications or location in order to be used.

**Android notifications (Android 13+)** ([Android](https://developer.android.com/develop/ui/views/notifications/notification-permission)):
- "let them familiarize themselves with your app."
- Trigger the prompt from a user action, for example "The user submits an order."
- Show a rationale screen only when `shouldShowRequestPermissionRationale()` returns true.

**Android location** ([Android](https://developer.android.com/training/location/permissions)): "Your app should still work when the user grants only approximate location access."

**Context:** since Android 13 made notifications opt-in, Airship reports Android and iOS opt-in rates at "near parity" ([Airship 2026](https://www.airship.com/mobile-app-push-notification-benchmarks-for-2026/)). Asking at the right moment matters on both platforms.

**When RijHub should ask:**
- Client notifications: after posting a job ("get notified when quotes arrive") or after booking.
- Artisan notifications: when they first switch to Available.
- Location: never at launch. Use an Abuja area picker, with "Use my location" (approximate) as an optional button.

### 1.7 Guest browsing

- **Apple 5.1.1(v):** "If your app doesn't include significant account-based features, let people use it without a login." Browsing artisans, prices and reviews is not account-based.
- **Baymard:** 19% of US shoppers who abandoned a checkout did so because the site wanted them to create an account ([Baymard](https://baymard.com/blog/current-state-of-checkout-ux)). Statista's 2024 chart of the same survey shows 26% ([Statista](https://www.statista.com/statistics/1228452/reasons-for-abandonments-during-checkout-united-states)).
- **Angi** lets homeowners use the site and app at no cost for hiring, estimates and pricing lookups ([Angi](https://www.angi.com/how-it-works)).
- **For RijHub:** browse as a guest, then show a soft prompt with context at book, post, message or save ("Book Musa: add your phone number and we'll confirm"). The branch's `AuthPrompt` approach already does this (section 7).

### 1.8 Trust messaging

- **Reviews are the strongest trust lever.** Airbnb and Stanford (PNAS 2017, 8,906 users): a high reputation offset people's bias toward hosts similar to themselves ([PNAS](https://pmc.ncbi.nlm.nih.gov/articles/PMC5603987); [Stanford](https://news.stanford.edu/stories/2017/09/reputation-can-offset-social-bias)).
- **Guarantees are tied to paying on-platform:**
  - TaskRabbit Happiness Pledge: up to $10,000, only for tasks booked and paid through the platform ([TaskRabbit](https://support.taskrabbit.com/hc/en-us/articles/360035570011)).
  - Angi Happiness Guarantee covers jobs booked and paid through Angi ([Angi](https://www.angi.com/how-it-works)).
  - Urban Company listings advertise a 30-day service guarantee and ₹10,000 damage protection ([UC listing](https://www.urbancompany.com/delhi-ncr-microwave-repair-sector-43-noida)).
  - Airtasker holds payment "until the task is done" ([App Store](https://apps.apple.com/us/app/airtasker/id512137061)).
- **Nigerian norms:**
  - Jiji tells buyers: "Do not send an advance payment directly to the seller or use a payment link sent in chat." Its Safe Deal holds payment with a 24-hour inspection window after delivery ([Jiji](https://jiji.ng/faq/safe-deal-for-buyers); [tips](https://jiji.ng/faq/57)).
  - Wrkman (an artisan app in Lagos and Abuja) leads with "30-day job guarantee" and "Secure funds" ([Wrkman](https://wrkmanapp.com/)).
- **Principle:** make claims specific and checkable ("ID checked with NIN and selfie"), let every badge open a short explanation, and tie the guarantee to paying in-app.

---

## 2. Client home

### 2.1 What leading apps put first

| App | What they prioritise | Source |
|---|---|---|
| Urban Company | Fixed-price service catalogue; instant services "in under 30 minutes"; "trained, 4.8+ rated professionals". Checkout combines picking the provider and time slot, and preselects the address | [App Store](https://apps.apple.com/us/app/urban-company-prev-urbanclap/id1032480595); [3 Sided Coin case study](https://thehardcopy.co/?p=6215) |
| TaskRabbit | Task tiles: growing them from 9 to 33 produced "3% more task invitations". Tasker list shows Elite badge, rating, tasks done in that category, photos, tools and vehicles. "Save favorites", "Rebook" | [Blog, Jun 2024](https://taskrabbit.com/blog/?p=24445); [Help](https://support.taskrabbit.com/hc/articles/360050012971); [App Store](https://apps.apple.com/us/app/taskrabbit-handyman-errands/id374165361) |
| Thumbtack | Started as "a search box" (CEO, as reported by [Fast Company](https://www.fastcompany.com/91072715/thumbtack-wants-to-become-the-go-to-app-for-your-home-improvement)) **(secondary)**. The 2024 relaunch added a Home Profile, project plans and personalized suggestions. The app highlights cost estimates and in-app chat | [BusinessWire](https://www.businesswire.com/news/home/20240402253139/en/One-App-for-Your-Home-Introducing-a-New-Thumbtack-for-a-New-Generation-of-Homeowners); [App Store](https://apps.apple.com/us/app/thumbtack-home-service-pros/id852703300) |
| Angi | Instant booking with upfront pricing based on cost data from past projects; Angi Certified pros; Happiness Guarantee | [Angi](https://www.angi.com/how-it-works) |
| Airtasker | Post a task and receive offers; payment held; verified badges | [App Store](https://apps.apple.com/us/app/airtasker/id512137061) |
| Urban Company (model) | Separate paths: book directly for standard services, "connect" with a pro for custom work | [YourStory](https://yourstory.com/2021/03/product-roadmap-urban-company-home-services-startup-survived-test-time/amp) |

### 2.2 Patterns and evidence

**Search and categories**
- On mobile, homepage category links get outsized attention, and about two-thirds of mobile sites score mediocre or poor on homepage and category navigation ([Baymard](https://baymard.com/research-articles/mobile-homepage-usability)).
- 70% of sites failed searches using a synonym for the product type (2014 study) ([Baymard](https://baymard.com/blog/ecommerce-search-report-and-benchmark)). 69% lack autocomplete that tolerates misspellings ([Baymard](https://baymard.com/research-articles/offer-autocomplete-suggestions-for-misspellings)).
- RijHub's search needs local synonyms: gen/generator, AC/air conditioner, fridge, inverter/solar, POP/ceiling, tiler, vulcanizer, DSTV, borehole.
- A local category set to model on (Wrkman): electrician, plumbing, AC and cooling, carpentry, moving; generator and transfer switch, solar/inverter, CCTV, Starlink installs ([Wrkman](https://wrkmanapp.com/)).

**Trust signals on artisan cards**
- Showing 5 reviews raised purchase likelihood by 270% compared with none ([Spiegel](https://spiegel.medill.northwestern.edu/How-Online-Reviews-Influence-Sales)). Purchases peaked at average ratings of 4.2–4.5; a perfect 5.0 looks less believable ([Spiegel PDF](https://spiegel.medill.northwestern.edu/wp-content/uploads/sites/2/2021/04/Spiegel-research-reveals-4.5-stars-are-better-than-5-The-Medill-IMC-Spiegel-Research-Center.pdf)). Always show the review count next to the rating.
- Thumbtack: pros who reply within 30 minutes are about 25% more likely to be hired than those who take up to 3 hours ([2025 Pro Summit recap](https://www.thumbtack.com/guide/content/3-takeaways-from-the-2025-pro-summit)) **(secondary)**. Show "Usually replies in ~X min".
- Airtasker shows each Tasker's completion rate on profiles and offers ([help](https://support.airtasker.com/hc/en-au/articles/225875007)).

**Price transparency**
- Urban Company publishes rate cards and lets customers dispute anything above them. The visit fee is credited to the final bill, and parts carry a 180-day warranty ([UC listing](https://www.urbancompany.com/mumbai-washing-machine-repair-union-park-chembur-east)).
- Airbnb has shown the total price by default worldwide since April 2025, ahead of the US FTC's rule against hidden fees ([Local10](https://www.local10.com/news/national/2025/04/21/airbnb-to-display-total-prices-by-default)).

**Rebooking.** TaskRabbit's favorites and "Rebook". For mature users, Thumbtack-style seasonal maintenance plans ([Thumbtack press](https://press.thumbtack.com/announcements/thumbtack-debuts-first-ever-home-care-experience-to-partner-with-homeowners-in-the-continuous-care-of-their-largest-asset)). That suits later, not launch.

**Promotions.** Auto-rotating panels cut visibility, and "because it moves, users automatically assume that it might be an advertisement". They are also worse for lower-literacy and second-language readers ([NN/g](https://www.nngroup.com/articles/auto-forwarding/)). Use one static promo slot.

### 2.3 Proposed client home, top to bottom

1. **Header:** area chip ("Gwarinpa, Abuja"), notifications. Greeting optional.
2. **Search:** "What do you need fixed?" with synonyms, recent searches and suggestion chips.
3. **Active booking or job card** (when there is one): status, artisan, call or chat. This outranks everything below it.
4. **Category grid:** 8 tiles (2×4), ordered by Abuja demand, plus "All services".
5. **"Post a job, get quotes" card** for custom work; fixed-price packages are for standard jobs.
6. **Returning users: "Book again"** (past and favourite artisans). First-time users: "Top-rated near you" with the full trust stack.
7. **One static promo or education slot,** plus a one-line safety reminder ("Pay through RijHub. We hold it until you confirm").

---

## 3. Artisan home

### 3.1 Job feed

- **TaskRabbit** sends clients' picks to Taskers as invitations. Its "Performance Score" is invoiced tasks divided by invitations, and Elite status requires being in the top 35% plus a task-volume minimum ([TaskRabbit](https://support.taskrabbit.com/hc/en-gb/articles/46260521586715-What-s-Required-to-Become-an-Elite-Tasker)).
- **Upwork** splits the feed into "Best Matches" and "Most Recent" ([community](https://community.upwork.com/t5/Freelancers/Best-Matches-Job-Feed/m-p/1211125)). Freelancers judge jobs by client signals such as payment verified, money spent and hires made **(third-party)** ([GigUp](https://giguphq.com/blog/upwork-client-history-metrics)).
- **Thumbtack and Bark** charge pros per lead. Reviews complain about paying for leads that never convert ([Thumbtack Pro app](https://apps.apple.com/us/app/thumbtack-for-professionals/id908795016); [Bark analysis](https://sidehusl.com/bark/) **(third-party)**).

**For RijHub,** use two lanes:
- **"Requests for you"**: direct bookings with an accept-by timer.
- **"Open jobs near you"**: jobs to quote on.

Each job card shows: trade, area and distance, budget or "Open to quotes", how long ago it was posted, number of quotes so far, an urgent tag, and client signals (phone verified, payment ready or held, client rating).

### 3.2 Earnings summary

- Uber's 2018 driver app: "Track your earnings at a glance", per trip plus daily and weekly summaries ([Uber](https://www.uber.com/en-ZA/blog/introducing-the-new-driver-app-za)). The earnings badge on the home screen could be customized or hidden **(secondary)** ([Axios](https://www.axios.com/2018/04/10/uber-overhauls-its-1523354239); [TPG](https://thepointsguy.com/news/ubers-redesigned-app-shows-drivers-where-they-can-get-peak-fares)).
- Kuda's Private Mode includes "Hide Balance" ([Kuda](https://help.kuda.com/en/articles/8943120-use-private-mode)).
- Artisans work inside clients' homes, so a hide toggle matters.
- **Show:** this week's earnings, money held for jobs in progress, available to withdraw, and next payout.

### 3.3 Profile completeness and ID-check prompts

- **TaskRabbit** tested a new-Tasker checklist showing "the steps needed to appear in client searches". It showed "earning potential and skill demand during registration", and prompted for tools, vehicles and photos when a skill is activated ([TaskRabbit, May 2023](https://www.taskrabbit.com/blog/?p=17173)).
- **Thumbtack Pro Rewards** tiers require a complete profile and a background check ([community](https://community.thumbtack.com/discussion/comment/711)) **(community post, may be dated)**.
- **Airtasker's ID Verified badge** runs through an outside provider and has included a live face scan since October 2024 ([Airtasker](https://support.airtasker.com/hc/en-au/articles/360001621807)).
- **Head-start effect:** in a car-wash loyalty-card study, completion was 34% when the card started with 2 of 10 stamps already filled, versus 19% for a blank 8-stamp card ([Nunes and Drèze 2006](https://ideas.repec.org/a/oup/jconrs/v32y2006i4p504-512.html)) **(figures secondary)**. Start the checklist with steps already done (phone verified, trade chosen).

### 3.4 Availability toggle

- Uber's model: a single Go control on the home screen ([Uber](https://www.uber.com/at/en/drive/driver-app)) **(secondary)**.
- Thumbtack lets pros set their own working hours and budget ([App Store](https://apps.apple.com/us/app/thumbtack-for-professionals/id908795016)).
- A Thumbtack moderator says pausing does not hurt ranking but slow replies do **(community)**.

### 3.5 Performance metrics

| Platform | Metric and rule |
|---|---|
| Fiverr | Response rate = first messages answered within 24h over the last 90 days. Level 1 needs 80%; Level 2 and Top Rated need 90% ([Fiverr](https://help.fiverr.com/hc/en-us/articles/360011451678); [levels](https://help.fiverr.com/hc/en-us/articles/360010560118-Achieving-levels)) |
| Thumbtack | Replies within 1 hour, counted 8am–8pm. Gold needs 65%, Platinum 75% **(community)** |
| Airtasker | Completion rate, hidden until 5 tasks. 90% or more = "highly reliable"; under 50% = "extremely unreliable" ([Airtasker](https://support.airtasker.com/hc/en-au/articles/225875007)) |

**For RijHub:** show 3 numbers (response rate, rating, completion rate), each with a one-line definition, the target, and what to do to improve it.

### 3.6 Proposed artisan home, top to bottom

1. Availability toggle with area, plus a prompt to turn on job alerts.
2. Direct requests with accept-by timers.
3. Next job card: time, area and landmark, client, chat or masked call, "I've arrived", start code.
4. Open jobs near you.
5. Earnings card with hide toggle.
6. Setup checklist, each step with its "why".
7. Metrics row, plus a single link to tips and training.

---

## 4. Market specifics (Nigeria, Abuja)

### 4.1 Devices and performance

**The phones people have**
- 88% Android; Tecno on 30% of surveyed phones ([KPMG/Orange 2025 study](https://innovation-village.com/kpmg-study-opay-whatsapp-lead-nigeria-smartphone-apps/); [KPMG](https://kpmg.com/ng/en/insights/2026/09/nigeria-smartphone-study.html)).
- 81% of 2025 Africa smartphone shipments cost under $200 ([TechCabal](https://techcabal.com/2026/02/25/in-2025-four-in-five-smartphones-sold-in-africa-cost-under-200/)).
- Omdia expects 2026 shipments to fall because memory costs have risen ([Omdia](https://omdia.tech.informa.com/pr/2026/feb/african-smartphone-market-jumps-14percent-in-4a25-as-entry-tier-pressures-signal-2026-reset)). People will keep old phones longer.
- 107M internet users, 45.4% of the population ([DataReportal](https://datareportal.com/reports/digital-2025-nigeria)).

**Why app size and data weight matter**
- Google Play (2017): each extra 6 MB of APK size cut install conversion by about 1%, more in emerging markets ([Google Play](https://medium.com/googleplaydev/shrinking-apks-growing-installs-5d3fcba23ce2)) **(dated, secondary)**.
- Uber Lite precedent: under 5 MB, cities' top places stored offline, map loaded only on tap ([Uber](https://www.uber.com/newsroom/uberlite/); [Engadget](https://www.engadget.com/2018/06/12/uber-launches-a-low-data-lite-app-thats-just-5mb-in-size/)).

**Engineering guidance to follow**
- Android's guidance for emerging markets: "Build for Billions" ([Android](https://developer.android.com/docs/quality-guidelines/build-for-billions)) and the Data Saver API ([Android](https://developer.android.com/training/basics/network-ops/data-saver)).
- Flutter app size: `--split-debug-info`, compressed PNG and JPEG, `--analyze-size` ([Flutter](https://docs.flutter.dev/perf/app-size)).
- Flutter performance: lazy `ListView.builder` lists; use `Opacity` and `saveLayer` sparingly; fixed-size grid cells ([Flutter](https://docs.flutter.dev/perf/best-practices)).

### 4.2 Data cost

- The NCC approved tariff rises of up to 50% in January 2025 ([allAfrica](https://allafrica.com/stories/202501210127.html)), and MTN raised data prices in February 2025 ([Techpoint](https://techpoint.africa/2025/02/11/mtn-increases-tariffs-on-calls-and-data/)).
- The average 1GB price went from ₦287.50 in 2024 to ₦575 in 2025 ([TechCabal](https://techcabal.com/2026/02/09/how-nigerians-spent-%E2%82%A620-87billion-daily-on-data-in-2025/)).
- Treat every home-screen image as a real cost to the user: server-resized WebP thumbnails, caching, no autoplay video.

### 4.3 Naira and number formatting

- Format as `₦25,000`: symbol first, comma thousands separators, no kobo.
- Ranges as `₦8,000 – ₦12,000`.
- "25k" only in tight chips, never in totals.
- The bundled Inter font includes the ₦ glyph (U+20A6), verified locally (section 7).
- Phone numbers: see 1.3.

### 4.4 Location and addresses

- Deliveries in Abuja and Lagos still rely on landmarks and phone calls ([Techpoint](https://techpoint.africa/2020/08/20/challenges-ecommerce-logistics-nigeria/); [Rest of World](https://restofworld.org/2023/nigera-last-mile-logistics-ecommerce/)).
- NIPOST launched 11-character digital postcodes with APIs on 1 Oct 2026 ([Nairametrics](https://nairametrics.com/2026/10/01/fg-launches-digital-postcode-system-says-every-nigerian-deserves-to-be-found/); [Condia](https://thecondia.com/nigeria-rolls-out-digital-postcodes-for-every-building/)). Add it as an optional field later.
- Capture addresses as: district (picker) + street or estate + landmark + optional pin.
- The FCT has 6 area councils, with districts such as Wuse, Maitama, Garki, Asokoro, Jabi, Utako, Gwarinpa, Kubwa and Lugbe ([NHM](https://www.nigeriahousingmarket.com/abuja/area-councils-abuja-list-headquarters)). Validate the list with the FCTA.

### 4.5 Copy tone and literacy

- **Tone:** plain, warm Nigerian English; "artisan", local trade names; no Americanisms (zip code, cell, apartment).
- **Pidgin** is used as an accent, not a full rewrite: Sterling's Naya assistant ([Sterling](https://sterling.ng/naya-speaks-your-language-banking-in-english-pidgin-and-maybe-even-emoji-%F0%9F%98%8A%F0%9F%98%8F%F0%9F%98%8D/)), Agentpesa ([Techpoint](https://techpoint.africa/feature/agentpesa-reimagining-banking-with-ai/)).
- **Lower literacy:**
  - Jargon-heavy, English-only apps exclude users ([TechCabal 2025](https://techcabal.com/2025/08/09/inclusive-design-nigerian-unbanked/)).
  - Functionally illiterate Nigerian users struggled on banking and shopping apps; redesigned interfaces helped significantly ([Aston 2024 thesis](https://publications.aston.ac.uk/id/eprint/47850); [AfriCHI 2023](https://publications.aston.ac.uk/id/eprint/45674)).
  - Lower-literacy readers read word by word and skip dense text ([NN/g](https://www.nngroup.com/articles/writing-for-lower-literacy-users/)).
- **For artisans:** icons always paired with labels, photo-first portfolios, voice notes for job details and quotes.

### 4.6 Payments

- Bank transfers were 58% of Paystack's Nigerian transactions in 2023, cards 36% ([TechCabal](https://techcabal.com/2024/05/14/paystack-bank-transfers/)).
- Paystack's "Pay with Transfer" generates a virtual account number and confirms automatically ([Paystack](https://support.paystack.com/hc/en-us/articles/360018995019)).
- For marketplaces, Paystack offers split payments and sub-accounts with a manual settlement schedule ([split](https://paystack.com/docs/payments/split-payments); [subaccount](https://paystack.com/docs/api/subaccount/)). It is *not* a true escrow **(third-party)** ([McTaba](https://mctaba.com/learn/paystack/escrow-style-flows-on-paystack-and-their-limits)). Get a legal opinion before calling it "escrow".
- Reference model, Airtasker Pay: funds held through Stripe; the Tasker taps "Request payment"; the client releases; disputes keep funds held ([Airtasker](https://support.airtasker.com/hc/en-au/articles/360041107091-How-do-I-get-paid)).

### 4.7 Safety, fraud and how apps respond

**The local problems (mostly anecdotal):**
- Materials money short-changed: paid for 50 cartons of tiles, 40 delivered ([BusinessDay](https://businessday.ng/exclusives/article/how-dishonesty-is-ruining-lives-and-businesses-in-nigeria/)).
- A commenter on a viral plumber story warns clients not to let technicians buy parts, alleging markups ([Legit.ng](https://www.legit.ng/people/1593125-suspicious-lady-began-secret-investigation-plumber-left-house-shares-findings/)) **(anecdotal)**.
- Verified Bolt driver accounts were sold to unverified drivers ([Rest of World](https://restofworld.org/2022/bolt-drivers-in-nigeria-are-illicitly-selling-their-accounts-putting-passengers-at-risk/)).

**How platforms respond:**

| Response | Example and source |
|---|---|
| Payment held until done | Airtasker Pay; Jiji Safe Deal |
| Verified ID with selfie | Jiji "Verified ID" (ID document plus selfie through Smile ID) ([Jiji](https://jiji.co.ke/faq/153)) |
| ID checked against national records | Bolt's driver portal with YouVerify checks against BVN and NIMC records ([BusinessDay](https://businessday.ng/companies/article/bolt-enhances-security-features-introduces-identity-verification-portal-for-drivers/)) |
| Consent-based national ID check | NIMC's NINAuth requires the holder's explicit consent ([MobileIDWorld](https://mobileidworld.com/nigeria-launches-ninauth-digital-identity-verification-platform-for-government-services/)) |
| Liveness checks | QoreID ([docs](https://docs.qoreid.com/docs/liveness-check)); Smile ID ([TechCabal brand press](https://techcabal.com/2025/01/08/smile-ids-enhanced-smartselfie-technology-leads-the-fight-against-identity-fraud-with-iso-30107-3-certification/)) |
| Police character certificate | POSSAP: apply online, then fingerprinting in person ([TechCabal](https://techcabal.com/2024/07/18/how-to-obtain-nigeria-police-character-report-online-in-2024/)) |
| Guarantors | Part of Bolt's published driver requirements (Rest of World) |
| In-trip safety tools | Bolt Trusted Contacts, Share Location, Emergency Assist ([ThisDay](https://www.thisdaylive.com/2025/01/29/bolts-safety-team-launches-new-trusted-contacts-safety-feature-in-nigeria/)); trip insurance ([Guardian](https://guardian.ng/?p=1222207)) |
| Visit fee and rate cards | Urban Company (4.6 above) |

**People taking jobs off the platform:**
- In a field experiment, more trust helped better freelancers win work, but past a high trust level, extra off-platform dealing cancelled out the gains ([Gu and Zhu 2021](https://pubsonline.informs.org/doi/10.1287/mnsc.2020.3583)).
- About 30% of SweepSouth cleaners also work off-platform ([Harvard D3](https://d3.harvard.edu/platform-digit/submission/sweepsouth-the-uber-for-domestic-cleaning/)) **(student write-up)**.
- So keep giving reasons to stay on-platform: payment protection, the guarantee, rebooking, records.

**Data protection.** Biometrics count as sensitive data; consent records are required; a data protection impact assessment is expected for high-risk processing (NDPA/GAID, Mondaq above). Store verification results, not raw NINs.

### 4.8 Local landscape and lessons

**Competitors and new entrants**
- Wrkman: Lagos and Abuja; guarantee, "secure funds", "4k+ Verified Technicians" **(vendor claim)**.
- Gyara: pre-launch; identity and skill screening, badges, subscription for pros ([Gyara](https://gyara.app/)).
- Fix-am: escrow and disputes ([Fix-am](https://fix-am.app/)).
- HAGO Africa: launched October 2025 ([Premium Times](https://www.premiumtimesng.com/entertainment/naija-fashion/826676-from-plumbers-to-chefs-app-connecting-nigerians-to-trusted-service-providers-berths.html)).
- i-Serv: launched March 2025 ([BusinessDay](https://businessday.ng/life/article/job-creation-for-artisans-gets-boost-as-i-serv-app-debuts-in-nigeria/)).
- ProConnectHQ: includes Abuja ([Innovation Village](https://innovation-village.com/how-technology-is-bringing-nigerias-artisans-into-the-digital-economy/)).

**Exits and pauses**
- SweepSouth left Nigeria in November 2022, citing currency devaluation and operational problems ([TechCabal](https://techcabal.com/2023/01/20/sweepsouth-expansion-failure/)).
- Eden Life paused its Nigerian consumer services in February 2026 ([WeAreTech](https://www.wearetech.africa/fr/fils/breves/breves-simple/nigeria-eden-life-suspend-ses-services-aux-particuliers)).

**Lesson:** keep operations lean as a marketplace. Quality control and trust *are* the product. Lead with frequent, standardizable jobs: AC, generator, electrical, plumbing, cleaning.

---

## 5. Anti-patterns to avoid

1. **Swipe-through intro carousels and feature tours.** They gave no task benefit and made tasks feel harder (NN/g study).
2. **A sign-up wall before browsing** (Apple 5.1.1(v); Baymard 19%).
3. **Permission prompts at launch, or pre-prompt screens that copy the system dialog.** No "Allow" or "Not now" buttons on custom screens (Apple guidelines).
4. **Email and password sign-up, or requiring both email and phone codes.** Promo text inside code messages, which turns them into marketing traffic (Telerivet).
5. **Asking clients for NIN or BVN,** or storing raw NINs (NDPA data minimisation).
6. **Auto-rotating promo banners** (NN/g).
7. **Vague badges ("Trusted") and unprovable claims ("98% satisfaction"),** especially at launch.
8. **Rating with no review count,** or showing 5.0 from a single review (Spiegel).
9. **Prices that change at checkout:** hidden fees, unexplained materials costs (Airbnb's total-price change; Urban Company rate cards).
10. **Paying artisans directly or through links sent in chat** (Jiji's warning).
11. **Charging artisans per lead when most leads don't convert** (Thumbtack and Bark pro complaints).
12. **An empty "near you" list at launch** ("No artisans near you yet"). Seed supply first and fall back to "Post a job".
13. **Heavy hero imagery and autoplay video on first screens; large app size** (Google Play size data; Uber Lite).
14. **Icon-only controls and dense English copy** for artisans (lower-literacy research).
15. **Showing artisan phone numbers before booking.** It invites off-platform deals and harassment. Use in-app chat and masked calls.

---

## 6. Recommendations for RijHub, in priority order

P0 = before launch, P1 = first iteration, P2 = after launch. "Status" was the state of the redesign branch when this was written (October 2026).

1. **[P0] Ask the role once, on the welcome screen; no carousel.**
   - Clients go into guest browsing; artisans into a short sign-up that previews "jobs posted near you this week" (TaskRabbit showed earning potential during registration).
   - *Status: done, with role cards on the welcome screen.*
2. **[P0] Guest browsing with prompts tied to the action at the first commitment** (book, post, message, save).
   - *Status: in progress* (`AuthPrompt`, router).
3. **[P0] Phone-first, passwordless sign-up that reliably delivers the code.**
   - Normalize +234 numbers. SMS on a registered transactional route for MTN, Airtel, Glo and 9mobile, with code-only message text. WhatsApp authentication template as the second channel. Android SMS Retriever.
   - Google and Apple only as secondary options, still followed by phone verification.
   - In-app account deletion.
4. **[P0] Minimum fields.**
   - Client: phone and first name at commitment; email optional.
   - Artisan: phone, name, up to 3 trades, area; everything else goes into the checklist.
5. **[P0] Location without the permission prompt.**
   - Abuja district picker with search, plus an optional "Use my location" (approximate).
   - Booking address = district + street or estate + landmark + optional pin.
   - *Status: changing area is "coming soon".*
6. **[P0] Client home order:** area chip, then search with Nigerian synonyms and fuzzy matching, then active booking, then the 8-tile category grid, then "Post a job, get quotes", then "Book again" or "Top-rated near you".
   - *Status: mostly built; missing "Book again" and synonyms.*
7. **[P0] Full trust stack on every artisan card:**
   - verified badge with an explanation;
   - rating with review count;
   - jobs completed;
   - "usually replies in X min";
   - "from ₦X";
   - area.
   - *Status: review count and jobs completed are in the data model but not shown.*
8. **[P0] Payment protection as the headline promise.**
   - Pay into RijHub (bank transfer or virtual account first, then card), money held, released when the client confirms, with automatic release after an inspection window and a dispute path.
   - Copy along the lines of Jiji's ("never pay the artisan directly").
   - Confirm the holding mechanism (Paystack split plus manual settlement, or a licensed partner) with counsel.
9. **[P0] Artisan verification ladder, with a legend explaining each badge:**
   - phone;
   - NIN through a consent flow (NINAuth, or ID plus selfie with liveness);
   - skills check (portfolio, test or reference);
   - optional police certificate (POSSAP).
   - Re-check the selfie at job start or payout to stop account sharing.
10. **[P0] Artisan home layout (section 3.6).** Availability, requests with timers, next job, nearby jobs with client signals, earnings split into pending, held and available with a hide toggle, checklist with the "why", and metrics with definitions.
    - *Status: availability, earnings, checklist and response rate exist; missing hide toggle, client signals and definitions.*
11. **[P1] Price transparency system:**
    - fixed-price packages for standard jobs (AC per unit, generator by kVA, fumigation per room, cleaning by bedrooms);
    - inspection or visit fee credited to the final bill;
    - quotes split into workmanship and materials, with receipts;
    - total including fees before payment;
    - Abuja price guides with an "updated on" date.
12. **[P1] Permission prompts in context:**
    - clients after posting a job or booking; artisans when they first go Available;
    - one-button pre-prompt screen following Apple's rules; Android rationale only when the system says it is needed;
    - WhatsApp or SMS fallback for critical job alerts, with consent.
13. **[P1] Data-light budget:**
    - small download (shrink or remove bundled welcome photos);
    - resized WebP thumbnails, lazy lists, cached last-known home screen;
    - respect Data Saver;
    - test on 2–3 GB RAM Tecno and itel phones over throttled 3G.
14. **[P1] Copy and formatting rules:**
    - Nigerian English and local trade vocabulary;
    - `₦25,000` formatting and en-dash ranges;
    - icons always with labels;
    - voice notes for artisans;
    - Pidgin only for light touches.
15. **[P2] Safety and retention layer:**
    - share job status with a trusted contact, arrival check-in, start code, in-app emergency and report button (Bolt's model);
    - ratings in both directions;
    - seasonal maintenance nudges (Thumbtack's plans; check the timing against Abuja booking data).

---
