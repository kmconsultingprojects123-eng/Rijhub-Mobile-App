# Artisan Onboarding Redesign

Proposal to streamline the artisan signup/onboarding flow. Client flow is already lean and is **not** changing.

---

## Problems with the current flow

After OTP verification, artisans hit a chain of mandatory/semi-mandatory location and profile prompts before the dashboard becomes fully usable:

1. [lib/pages/artisan_complete_profile/artisan_complete_profile_widget.dart](lib/pages/artisan_complete_profile/artisan_complete_profile_widget.dart) — 3 steps (Step 2 collects service area address)
2. [lib/pages/artisan_kyc_page/artisan_kyc_page_widget.dart](lib/pages/artisan_kyc_page/artisan_kyc_page_widget.dart) — 3 steps (Step 1 collects State + LGA)
3. [lib/pages/artisan_dashboard_page/artisan_dashboard_page_widget.dart:333](lib/pages/artisan_dashboard_page/artisan_dashboard_page_widget.dart#L333) — `_maybeShowOnboardReminder()` pops a "Complete your setup" dialog 3 seconds after the dashboard loads, which routes to `_openLocationBottomSheet()` at [line 2924](lib/pages/artisan_dashboard_page/artisan_dashboard_page_widget.dart#L2924) (GPS → reverse geocode → save to `TokenStorage`).

### Confirmed duplications

| Data | Asked in | Asked again in | And again in |
|---|---|---|---|
| Name, email, phone | [create_account2_widget.dart](lib/pages/create_account2/create_account2_widget.dart) | Profile Step 1 (re-entered, not just pre-filled read-only) | — |
| **Location** | Profile Step 2 (free-text address + geocode) | KYC Step 1 (**State + LGA** dropdowns) | Dashboard "Set location" sheet (GPS → reverse geocode → `TokenStorage._keyLocationAddress/Lat/Lon`) |
| Services | Profile (free-text chips: `_serviceItems`) | KYC ("Service Category" dropdown from `JobService`) | — |
| Profile image | — | KYC Step 2 (only place collected, oddly) | — |
| Years of experience | Profile Step 1 (text) | KYC Step 1 (numeric) | — |

The location triplication is the worst offender — three different UIs, three different storage shapes, same intent:

| # | Where | Shape | Stored as |
|---|---|---|---|
| 1 | Profile Step 2 | Free-text address + lat/lon + service radius | Sent to artisan profile API |
| 2 | KYC Step 1 | State + LGA dropdowns | Sent to KYC API |
| 3 | Dashboard reminder sheet | GPS → reverse-geocoded address + lat/lon | Local `TokenStorage` keys |

The dashboard prompt (#3) is the most jarring because the artisan has *just* finished entering location twice in profile + KYC, then gets a popup asking them to set location *again* — because the local `TokenStorage` keys it checks (`_model.userLocation`) aren't populated by the profile/KYC submissions. That's a backend/state-sync bug as much as a UX one.

### Time to first value
- **Today:** ~10–15 min, 6 form steps across 2 mandatory screens, then the dashboard.
- **Goal:** ~60 seconds to a usable dashboard, with everything else as progressive unlocks.

---

## Proposed flow

Split onboarding into **one tiny mandatory pass + progressive unlocks** instead of two big mandatory screens.

### Signup (unchanged)
Name, email, phone, password, role, OTP. Same as today.

### Phase 1 — "Get set up"
**Mandatory. ~3 minutes. One scrolling screen with collapsing sections, not separate pages.**

The artisan needs to be discoverable, bookable at known prices, and ID-verified before they can transact. Phase 1 covers all three. Everything else is deferred to action-triggered prompts.

#### Section 1 — Trade, services & prices

| Field | Notes |
|---|---|
| Primary category | Single dropdown from `JobService.getJobCategories()` (e.g., "Plumbing"). |
| Services I offer + price | After category, show subcategory chips from `/api/job-subcategories?categoryId=...`. When one is ticked, a price field appears inline beside it, **pre-filled with the category-median suggestion** (e.g., "Pipe Repair — ₦5,000"). Artisan confirms or adjusts. At least one service required. Bulk-write to `/api/artisan-services` on submit. |

#### Section 2 — Where you work & how you look

| Field | Notes |
|---|---|
| Service location | **One** map/address picker. Auto-derives State + LGA + lat/lon. Radius slider, default 10 km. Writes to profile API, KYC State+LGA, and `TokenStorage` in one shot. |
| Profile photo | Camera or gallery, one tap. Becomes both profile pic and dashboard avatar. |

#### Section 3 — Verify your ID (KYC via Dojah NIN + selfie)

| Field | Notes |
|---|---|
| Document type | Dropdown — defaults to NIN (only option supported by Dojah today). Other types fall through to manual KYC. |
| ID number | 11-digit NIN. |
| Liveness selfie | Tap "Verify Now" → opens a separate liveness-check screen with face frame and capture button. Selfie is sent with the NIN to `POST /api/kyc/dojah/nin-selfie`. |

No ID front / back photo upload. No State/LGA. No business name. No experience years. The whole step is: pick type → type number → snap a selfie.

> **KYC approval is fast.** Dojah verification is automatic — when match confidence ≥ 90, the artisan is approved within seconds and apply/accept unlock immediately. Only when Dojah is unavailable or confidence is borderline does it fall through to `pending_review` and the "<24 hours" manual path. The dashboard pill should reflect the actual state from `GET /api/kyc/status`:
>
> - `approved` → no pill, full access
> - `pending` → "Verifying your ID..." (auto, usually seconds)
> - `pending_review` → "ID under manual review — usually approved within 24 hours"
> - `rejected` → "Verification didn't match — tap to retry" (re-enters this section)
>
> **Optional escape hatch:** "Skip ID for now" link with consequence label — *"You won't be able to apply for jobs or accept bookings until verified."* The artisan can return to this section from the dashboard completion overview anytime.

#### Friction-reducing UX moves
These are what make a 3-minute flow feel light instead of heavy. Non-negotiable for the redesign to land:

- **Single scrolling page.** Sections expand on tap, collapse + checkmark when complete. One progress bar at the top. Not 3 stepper screens.
- **Pre-filled price suggestions** from a backend category-median endpoint — the artisan taps through agreement, only outliers type.
- **Auto-derive everything possible:** State + LGA from location, default radius, photo doubles as avatar, "country = Nigeria" hardcoded.
- **Liveness-check selfie via Dojah** — face frame, single capture, no front/back ID photos. Match runs automatically; artisan sees an immediate result in most cases.
- **Resumable.** Save partial state per section. If they close the app, resume from the same section next launch — no lost work.
- **Async KYC.** Never block the dashboard on backend verification.

After Phase 1 the dashboard `_maybeShowOnboardReminder()` is gone — there's nothing left to nag about that's actually mandatory.

### Phase 2 — Action-triggered prompts (just-in-time)
**The dashboard does not nag.** Instead, prompts fire at the exact moment the artisan tries to do something that requires the missing data. They understand *why* they're being asked because they're already trying to do the thing the data unlocks.

A small, passive **completion overview** (collapsible, dismissible) lives on the dashboard for artisans who want to fill things out proactively — but it's not the primary mechanism. The primary mechanism is the prompts below.

#### Where each prompt fires

| Trigger action | Currently in code | What's missing → what to prompt for | Type |
|---|---|---|---|
| Tap **"Apply Now" / "Send Quote"** on a job | [job_detail_page_widget.dart:1388](lib/pages/job_detail_page/job_detail_page_widget.dart#L1388), `submitQuote()` at [line 1128](lib/pages/job_detail_page/job_detail_page_widget.dart#L1128) | If bio / per-job rate / per-hour rate missing → bottom sheet: "Add a quick bio and your rates so clients know what to expect." Save and continue to quote submit. | **Blocking** |
| Tap **"Accept"** on a booking | [booking_page_widget.dart:1201](lib/pages/booking_page/booking_page_widget.dart#L1201), `_acceptBooking()` | If bio/rates missing → same prompt as above before calling `POST /api/bookings/{id}/accept`. | **Blocking** |
| Tap booking notification → accept | [notification_page_widget.dart:175](lib/pages/notification_page/notification_page_widget.dart#L175) (routes into `_acceptBooking`) | Same gate — runs through `_acceptBooking`, so the prompt above covers this path too. | **Blocking** |
| Tap **"Mark Complete"** on a job | [message_client_widget.dart:3043](lib/pages/message_client/message_client_widget.dart#L3043), `_markJobComplete()` | If KYC still pending or rejected → "Your ID verification is still pending. Payment will be held until approved" (no action needed; informational). | **Soft, informational** |
| Tap **"Edit Payout Details" / Withdraw** | [user_walletpage_widget.dart:863](lib/pages/user_walletpage/user_walletpage_widget.dart#L863), `_showPayoutDetailsSheet()` | If KYC rejected → re-open the simplified KYC sheet with reason from the backend. If still pending → message "Verification in progress, payouts unlock automatically once approved." | **Blocking when rejected, informational when pending** |
| First time location is needed for a feature (browse nearby jobs, distance match on apply) | [home_page_widget.dart:377](lib/pages/home_page/home_page_widget.dart#L377) (existing "Set location" entry — repurpose) | If `TokenStorage` location is empty → use the existing bottom sheet, but only when needed, not as a dashboard popup. | **Blocking for the action only** |
| Open own profile / public preview | [artisan_profile_page_widget.dart:125](lib/pages/artisan_profile/artisan_profile_page_widget.dart#L125) (empty portfolio check already exists) | If portfolio empty → inline empty-state CTA: "Add work samples to stand out in search." | **Soft** |
| First reply to an incoming chat | [message_client_widget.dart:1790](lib/pages/message_client/message_client_widget.dart#L1790), `_sendMessage()` | If profile photo or bio missing → one-time banner above composer: "Clients trust profiles with a photo and short bio." Tap to fill, dismissable. | **Soft** |
| Accepting first booking | [booking_page_widget.dart:1201](lib/pages/booking_page/booking_page_widget.dart#L1201) | After successful accept, soft prompt: "Set your availability so clients book you at the right times." | **Soft, post-action** |
| Tap **"Apply Now"** before KYC approval | [job_detail_page_widget.dart:1388](lib/pages/job_detail_page/job_detail_page_widget.dart#L1388) | If KYC pending → "ID verification still in progress. You'll be able to apply once approved (usually under 1 hour)." If rejected → reason + retake CTA. | **Blocking, informational** |
| Tap **"Accept"** before KYC approval | [booking_page_widget.dart:1201](lib/pages/booking_page/booking_page_widget.dart#L1201) | Same as above. | **Blocking, informational** |

#### Why action-triggered beats dashboard cards

- **Motivation is highest at the moment of action.** "Fill your rates to apply for this ₦50,000 job" converts; "complete your profile" gets ignored.
- **No upfront paperwork tax.** Artisan never sees a form for something they haven't tried to do yet.
- **Each prompt is small and focused.** Two or three fields max, in a bottom sheet, then continue the original action they were trying to do.
- **Same data ends up collected** — just contextualised, not batched.

#### Prompt UX rules

- **Never lose the original action.** After the artisan fills the prompt, automatically resume what they tapped (apply, accept, withdraw). Don't dump them back to the dashboard.
- **One prompt at a time.** If multiple fields are missing, ask only for what this specific action requires. Bio/rates for apply, ID for withdraw — never combine.
- **Soft prompts dismiss permanently per device.** Don't re-show the same soft banner if dismissed. Track per-prompt in `TokenStorage`.
- **Replace the existing dashboard `_maybeShowOnboardReminder()` popup** ([artisan_dashboard_page_widget.dart:333](lib/pages/artisan_dashboard_page/artisan_dashboard_page_widget.dart#L333)) — the action-triggered prompts make it obsolete.

---

## Why this works

- **Time-to-first-value drops from ~10 min to ~1 min.** Artisan sees the platform working before being asked for paperwork.
- **No data is lost.** Same fields, collected when they matter. KYC only blocks payouts, which is the natural moment a user understands why they're handing over an ID.
- **Platform integrity preserved.** Artisans still can't accept jobs without bio + rates, can't get paid without KYC. The gates remain — they're just **feature-gates instead of access-gates.**
- **Removes the location double-entry.** Single address picker derives everything.

### Tradeoff
Artisans browsing the dashboard with thin profiles could feel "empty" early on. Mitigate by:
- Ranking incomplete profiles lower in search.
- Showing a clear "complete your profile to appear here" empty state on their own listing preview.
- The action-triggered prompts catch them at the right moment without an upfront wall.

---

## Quick wins (ship today, no flow restructure)

Low-risk improvements that don't require redesigning navigation. Useful as a stepping stone.

1. **Pre-fill + lock** name/email/phone in [artisan_complete_profile_widget.dart](lib/pages/artisan_complete_profile/artisan_complete_profile_widget.dart) Step 1 — read from `AuthNotifier`, no re-entry.
2. **Auto-derive State + LGA** in KYC from the address entered in profile (geocode → reverse-lookup). Pre-select dropdowns; user just confirms.
3. **Sync location to `TokenStorage`** when the profile is saved — call `TokenStorage.saveLocation({address, latitude, longitude})` from the profile submit handler so [`_maybeShowOnboardReminder()`](lib/pages/artisan_dashboard_page/artisan_dashboard_page_widget.dart#L333) doesn't fire the redundant "Set location" popup. This kills the third prompt with a one-line change.
4. **Move profile photo** to the profile screen (or signup), out of KYC.
5. **Pick one services field.** Use `JobService` category as canonical; drop the free-text chip list (or keep it as optional "specializations").
6. **Collapse KYC Step 3 (Review)** into a confirmation dialog on submit.

---

## Feature-gating matrix

What each artisan can do at each completion level:

Phase 1 now bundles services + prices + KYC submission, so the gating collapses around two events: **finishing Phase 1** and **KYC approval**.

| Capability | Signup only | + Phase 1 submitted (KYC pending) | + KYC approved |
|---|:---:|:---:|:---:|
| Browse jobs | x | x | x |
| See artisans / clients in area | x | x | x |
| Appear in search (category + service + price) |  | x | x |
| Receive booking requests |  | x | x |
| Apply to open jobs |  |  | x |
| Accept bookings |  |  | x |
| Mark jobs complete |  |  | x |
| Withdraw earnings |  |  | x |
| Verified badge |  |  | x |

The "bio" prompt isn't a gate anymore — it's a soft prompt at first apply (with a suggested auto-bio from the data already collected). Same for portfolio and availability.

---

## Files affected

| File | Change |
|---|---|
| [lib/pages/splash_screen_page2/splash_screen_page2_widget.dart](lib/pages/splash_screen_page2/splash_screen_page2_widget.dart) | No change — role selection stays. |
| [lib/pages/create_account2/create_account2_widget.dart](lib/pages/create_account2/create_account2_widget.dart) | No change. |
| [lib/pages/verification_page/verification_page_widget.dart](lib/pages/verification_page/verification_page_widget.dart) | After artisan OTP success, route to new Phase 1 screen instead of straight to dashboard. |
| **NEW** `lib/pages/artisan_onboarding_phase1/...` | Single screen with category + location + photo. |
| [lib/pages/artisan_complete_profile/artisan_complete_profile_widget.dart](lib/pages/artisan_complete_profile/artisan_complete_profile_widget.dart) | Decompose into small focused sheets that fire from action triggers (bio/rates sheet, portfolio sheet, availability sheet). The current 3-step stepper goes away. |
| [lib/pages/artisan_kyc_page/artisan_kyc_page_widget.dart](lib/pages/artisan_kyc_page/artisan_kyc_page_widget.dart) | Replace with the Phase 1 Section 3 inline UI (NIN + liveness selfie via `POST /api/kyc/dojah/nin-selfie`). Drop ID front/back, State/LGA, business name, experience. Add a separate liveness-check screen reachable from "Verify Now". Old screen reachable from the dashboard completion overview if the artisan tapped "Skip ID for now". |
| [lib/pages/artisan_dashboard_page/artisan_dashboard_page_widget.dart](lib/pages/artisan_dashboard_page/artisan_dashboard_page_widget.dart) | **Remove `_maybeShowOnboardReminder()` ([line 333](lib/pages/artisan_dashboard_page/artisan_dashboard_page_widget.dart#L333)) and `_openLocationBottomSheet()` ([line 2924](lib/pages/artisan_dashboard_page/artisan_dashboard_page_widget.dart#L2924))** — replaced by action-triggered prompts. Add a small, dismissible completion overview as a passive option for proactive artisans. |
| [lib/pages/job_detail_page/job_detail_page_widget.dart](lib/pages/job_detail_page/job_detail_page_widget.dart) | Wrap `submitQuote()` ([line 1128](lib/pages/job_detail_page/job_detail_page_widget.dart#L1128)) with a bio/rates check that opens the bio/rates sheet first, then resumes the quote submission. |
| [lib/pages/booking_page/booking_page_widget.dart](lib/pages/booking_page/booking_page_widget.dart) | Wrap `_acceptBooking()` ([line 1201](lib/pages/booking_page/booking_page_widget.dart#L1201)) with the same bio/rates check. After first successful accept, surface a soft availability prompt. |
| [lib/pages/message_client/message_client_widget.dart](lib/pages/message_client/message_client_widget.dart) | Wrap `_markJobComplete()` ([line 3043](lib/pages/message_client/message_client_widget.dart#L3043)) with a KYC check when payment mode is "after-completion". Add a one-time soft profile banner in `_sendMessage()` ([line 1790](lib/pages/message_client/message_client_widget.dart#L1790)) on first chat reply. |
| [lib/pages/user_walletpage/user_walletpage_widget.dart](lib/pages/user_walletpage/user_walletpage_widget.dart) | Wrap `_showPayoutDetailsSheet()` ([line 863](lib/pages/user_walletpage/user_walletpage_widget.dart#L863)) with a KYC check; open the simplified KYC sheet first if needed. |
| [lib/pages/home_page/home_page_widget.dart](lib/pages/home_page/home_page_widget.dart) | Repurpose the existing "Set location" entry ([line 377](lib/pages/home_page/home_page_widget.dart#L377)) — only show it when an action requires location, not as a passive prompt. |
| [lib/pages/artisan_profile/artisan_profile_page_widget.dart](lib/pages/artisan_profile/artisan_profile_page_widget.dart) | Improve the existing empty-portfolio state ([line 125](lib/pages/artisan_profile/artisan_profile_page_widget.dart#L125)) into an inline soft CTA. Add a parallel soft CTA when `/api/artisan-services` returns empty: "Add services with prices so clients can find you" → routes to existing `MyServicePage`. |
| `lib/pages/my_service_page/...` (existing) | No change. Stays as the canonical place to manage services + pricing. Reachable from the soft prompts above and from the dashboard completion overview. |
| [lib/services/auth_service.dart](lib/services/auth_service.dart) | No change to register/verify. |

---

## Backend dependencies

Most of the revamp ships without backend work. A few specific pieces do need server changes — call them out early so they can be coordinated.

### No backend changes needed

All client-only — can ship in isolation:

- All 6 quick wins (pre-fill basic info, auto-derive State+LGA via [`geocoding_service.dart`](lib/services/geocoding_service.dart), sync to `TokenStorage` on profile save, move photo, single services field, collapse KYC review).
- Phase 1 screen wiring — uses existing `POST /api/artisans` ([artist_service.dart:792](lib/services/artist_service.dart#L792)) and `PUT /api/artisans/me` ([artist_service.dart:967](lib/services/artist_service.dart#L967)).
- Decomposing screens into bottom-sheet cards.
- Removing `_maybeShowOnboardReminder()` / `_openLocationBottomSheet()` from the artisan dashboard.
- KYC stays atomic — `POST /api/kyc/submit` ([kyc_service.dart:184](lib/services/kyc_service.dart#L184)) is one-shot multipart and fits the new single-sheet UI as-is.

### Backend changes very likely needed

| # | Change | Why | Impact if skipped |
|---|---|---|---|
| 1 | **Confirm `PUT /api/artisans/me` accepts partial updates** (missing fields = "leave unchanged", not "null out"). If strict, add `PATCH /api/artisans/me` or relax PUT semantics. | Phase 1 sends only 3 fields; later updates also send subsets via the dashboard cards. | Phase 1 wipes profile data on subsequent saves. Blocking. |
| 2 | **Server-side feature gates** on apply / accept-job and wallet withdraw endpoints. Return 403 when prerequisites are unmet (e.g., bio + rates missing → no apply; KYC not approved → no withdraw). | Client-side gates can be bypassed; the matrix above is only meaningful if enforced server-side. | Security/integrity gap — artisans could circumvent the gating. |
| 3 | **Search ranking by completion** on `GET /api/artisans/search` ([artist_service.dart:51](lib/services/artist_service.dart#L51)) — sort by completion score, optionally filter incomplete profiles. | Mitigates the "thin profiles flood the search" tradeoff called out above. | New artisans with empty profiles dilute search quality. |
| 4 | **Category-median price suggestions endpoint** — e.g., `GET /api/job-subcategories?categoryId=...&includeMedianPrice=true`. Returns median/typical price per subcategory based on existing artisan data, so Phase 1 can pre-fill suggested prices instead of giving the artisan a blank field. | Pricing is the most cognitively expensive step in Phase 1. Pre-filled medians collapse it from "thinking" to "tapping confirm." | Artisan stares at empty price fields, time-on-task balloons, abandonment spikes. |
| 5 | ~~KYC approval status endpoint + push~~ — **already shipped.** `GET /api/kyc/status` ([current-auth-flow.md](current-auth-flow.md#check-kyc-status)) returns `pending | pending_review | approved | rejected` with `failureReason`. Just need a push notification when state changes (or polling on dashboard focus) so the apply/accept gates auto-unlock. | Phase 1 submits KYC; client needs to know when state flips. | Artisan re-checks manually, perceives flow as broken. |

### Already shipped (per [current-auth-flow.md](current-auth-flow.md))

These no longer require backend work — the new auth/KYC spec the backend produced already covers them:

- **Dojah NIN + selfie verification** (`POST /api/kyc/dojah/nin-selfie`) — auto-approval when match confidence ≥ 90, with fallback to manual review. Removes the entire ID front/back photo step from the design.
- **`GET /api/kyc/status`** — single source of truth for the dashboard pill and gate logic.
- **Verified-artisan gate** — server-side guard already returns `ARTISAN_VERIFICATION_REQUIRED` (403) on apply/accept/quote/booking endpoints when KYC isn't approved. This is dependency #2 from the original list — already done.
- **Manual KYC fallback** (`POST /api/kyc/submit`) — preserved for the Dojah-unavailable case.

### Worth confirming (probably fine)

- **`POST /api/artisans` with sparse payload** — does the create endpoint accept `{category, location, photo}` only, or does it require the full profile shape? If it enforces required fields beyond those three, backend needs to relax validation for Phase 1.
- **Bulk service insert with prices** — `POST /api/artisan-services` likely takes one service at a time today. Phase 1's multi-select inserts several at once with prices. Either client loops the calls (fine) or backend adds a bulk endpoint (cleaner).
- **KYC status push notification** — confirm there's an FCM hook when status flips to `approved` / `rejected` / `pending_review`, otherwise the dashboard polls on focus.

---

## Suggested rollout

Sequenced so client-only work ships first and isn't blocked on backend coordination.

1. **Phase A — Quick wins (1 PR, client only).** Pre-fill basic info, single services field, auto-derive State/LGA, sync location to `TokenStorage`, move photo, collapse KYC review. Validates the direction with minimal risk and no backend dependency.
2. **Backend conversation.** Confirm partial-update semantics on `PUT /api/artisans/me` (#1 above). If strict, request PATCH support or relaxed PUT.
3. **Phase B — Phase 1 screen (1 PR, depends on #2).** New combined onboarding screen, route artisans to it after OTP, keep existing profile/KYC screens reachable from dashboard.
4. **Backend work — feature gates + search ranking (#2 and #3 above).** Should land before Phase C exposes the gating matrix to users.
5. **Phase C — Dashboard cards + feature gates (1 PR, depends on backend gates).** Convert old screens into focused sheets, wire up the gating matrix.
6. **Phase D — Cleanup (1 PR).** Remove old multi-step stepper code paths once metrics confirm the new flow performs.
