# KYC Dojah SDK Integration — Backend Changes Required

This document is a follow-up to [current-auth-flow.md](current-auth-flow.md). It specifies the backend changes needed for the mobile app to integrate the **official Dojah Flutter SDK** (`dojah_kyc_sdk_flutter`) instead of the current direct selfie-upload flow.

---

## Why the change

The current Dojah integration (`POST /api/kyc/dojah/nin-selfie`) does **facial match against the NIN photo** — i.e. "the selfie looks like the NIN holder, with confidence ≥ 90%". This is not the same as **liveness verification**: a printed photo or a video replay can still pass facial matching.

Real liveness needs the user to perform live actions (blink, smile, head turn) and verify those actions occurred at capture time. The mobile platform doesn't have a primitive for this, and the existing `/nin-selfie` endpoint accepts only a single still image, so it can't enforce liveness even if we built it client-side.

Dojah ships an **official Flutter SDK** that solves this end-to-end:

- Opens a native Dojah widget on the device.
- User goes through configured steps (NIN entry → liveness → selfie match) inside the widget.
- Dojah's own ML pipeline verifies liveness with active prompts (smile/blink).
- SDK returns a **reference ID** to the app once the flow finishes.
- The actual verification result is then fetched server-to-server from Dojah using that reference.

References:
- [dojah_kyc_sdk_flutter on pub.dev](https://pub.dev/packages/dojah_kyc_sdk_flutter) — official native SDK (preferred)
- [Dojah Flutter SDK docs](https://docs.dojah.io/sdks/flutter-library)
- [Dojah Liveness Check product page](https://dojah.io/all-products/liveness-check)

---

## New architecture (vs. current)

### Today
```text
Mobile app -> POST /api/kyc/dojah/nin-selfie (selfie + NIN)
              RijHub backend -> Dojah /kyc/nin/verify
              Backend stores result -> returns approved/rejected
```

### After the change
```text
Mobile app -> opens Dojah SDK widget (Widget ID + reference ID)
              user completes liveness + selfie match in Dojah's UI
              SDK returns referenceId via onSuccess
Mobile app -> POST /api/kyc/dojah/verify-reference (referenceId)
              RijHub backend -> Dojah "Get Verification Details" API
              Backend stores result -> returns approved/rejected
```

The `/api/kyc/dojah/nin-selfie` endpoint stays as a **fallback** for environments where the SDK can't run (e.g. very old devices) or for admin re-verification.

---

## Required backend changes

### 1. NEW: `POST /api/kyc/dojah/verify-reference` (primary endpoint)

Accepts a Dojah reference ID returned by the Flutter SDK, calls Dojah's "Get Verification Details" API server-side, and persists the result on the user's KYC record.

```http
POST /api/kyc/dojah/verify-reference
Authorization: Bearer <jwt>
Content-Type: application/json
```

Request:

```json
{
  "referenceId": "ref_5f8a7b2c-..."
}
```

The backend should:

1. Look up the authenticated user from the JWT.
2. Call Dojah's [Get Verification Details](https://docs.dojah.io/) API with the `referenceId`. Use the existing `DOJAH_SECRET_KEY` and `DOJAH_APP_ID` env vars.
3. Inspect the returned status. Dojah's possible statuses for a verification reference are:
   - `Completed` — all steps passed (treat as **approved** if liveness + face match are both true)
   - `Pending` / `Ongoing` — user hasn't finished; treat as **pending**
   - `Failed` — at least one step failed (treat as **rejected**)
   - `Abandoned` — user closed the widget mid-flow (treat as **pending**, allow retry)
4. Update the KYC record exactly as the existing `/nin-selfie` endpoint does — same `User.kycVerified`, `User.isVerified`, `User.kycLevel`, `Artisan.verified` fields, same notification side-effects.
5. Return the same response envelope as `/nin-selfie` so the mobile client can reuse its existing parser:

Approved response:

```json
{
  "success": true,
  "message": "KYC verification approved",
  "data": {
    "status": "approved",
    "match": true,
    "confidenceValue": 98.4,
    "threshold": 90,
    "provider": "dojah",
    "verificationType": "sdk_widget",
    "referenceId": "ref_5f8a7b2c-...",
    "user": {
      "_id": "6624b1b15e0c8c2c64a00001",
      "kycVerified": true,
      "isVerified": true,
      "kycLevel": 2
    },
    "artisan": {
      "_id": "6624b1b15e0c8c2c64a00002",
      "verified": true
    }
  }
}
```

Rejected response:

```json
{
  "success": true,
  "message": "KYC verification rejected",
  "data": {
    "status": "rejected",
    "match": false,
    "confidenceValue": 41.2,
    "threshold": 90,
    "provider": "dojah",
    "verificationType": "sdk_widget",
    "referenceId": "ref_5f8a7b2c-...",
    "failureReason": "Liveness check failed",
    "user": { "...": "..." },
    "artisan": { "...": "..." }
  }
}
```

Pending / under review (Dojah still processing or webhook not yet received):

```json
{
  "success": true,
  "message": "Verification still in progress",
  "data": {
    "status": "pending",
    "provider": "dojah",
    "verificationType": "sdk_widget",
    "referenceId": "ref_5f8a7b2c-..."
  }
}
```

Validation errors:

```json
{ "success": false, "message": "referenceId is required" }
```

```json
{ "success": false, "message": "referenceId not found at Dojah" }
```

```json
{ "success": false, "message": "referenceId belongs to a different user" }
```

> Important: validate that the `referenceId` belongs to the authenticated user. Either store the reference at SDK launch time (via the config endpoint below) or use Dojah's metadata field to embed the user ID and check it on result retrieval.

---

### 2. NEW: `GET /api/kyc/dojah/config` (mobile bootstrap)

The native Flutter SDK (`dojah_kyc_sdk_flutter`) needs only **one** value to launch:

| Field | Source | Sensitivity |
|---|---|---|
| `widgetId` | Configured in Dojah dashboard (defines the steps: NIN → liveness → selfie match) | Public |

Returning it from the backend lets the team rotate or swap the widget without forcing an app release.

```http
GET /api/kyc/dojah/config
Authorization: Bearer <jwt>
```

Response:

```json
{
  "success": true,
  "data": {
    "widgetId": "wgt_xxxxxxxxxxxx",
    "environment": "sandbox"
  }
}
```

> The native SDK authenticates against Dojah using the Widget ID alone. `DOJAH_APP_ID`, `DOJAH_SECRET_KEY`, and any public key all stay server-side — they're used by the backend when it calls Dojah's REST APIs (`/verify-reference`, the webhook handler, the legacy `/nin-selfie` fallback). They are **not** returned by this endpoint and **never** shipped to the mobile app, per the existing security notes in [current-auth-flow.md](current-auth-flow.md#security-notes).
>
> If the team prefers to bake the Widget ID directly into the mobile app instead of serving it from this endpoint, that also works — the trade-off is rotating the widget then requires an app release. The endpoint is recommended but not strictly required.

---

### 3. NEW (optional but recommended): `POST /api/kyc/dojah/start-session`

Mints a `referenceId` server-side and ties it to the authenticated user before the SDK launches. The mobile app then passes that reference into `DojahKyc.launch(...)` so when Dojah reports the verification result, the backend already knows which user it belongs to.

```http
POST /api/kyc/dojah/start-session
Authorization: Bearer <jwt>
```

Response:

```json
{
  "success": true,
  "data": {
    "referenceId": "rij_kyc_67d4e9f0_6624b1b15e0c8c2c64a00001"
  }
}
```

Suggested format: `rij_kyc_<timestamp>_<userId>` so the reference is self-describing in logs without leaking PII.

If you'd rather have the SDK auto-generate the reference and skip this endpoint, that also works — the verify endpoint above can then check ownership by other means (Dojah metadata, or fetching the verification record and matching its email/phone to the authenticated user).

---

### 4. NEW (optional): `POST /api/kyc/dojah/webhook`

Dojah supports webhooks for verification completion. If you wire one up, the backend can update the KYC record asynchronously without the mobile app needing to call `verify-reference` at all.

```http
POST /api/kyc/dojah/webhook
X-Dojah-Signature: <hmac-sig-from-dojah>
Content-Type: application/json
```

Body shape is whatever Dojah sends (per their dashboard's webhook docs). Backend verifies the signature using the secret, looks up the local KYC record by `referenceId`, applies the same approval/rejection logic, and persists.

Without webhooks, the mobile client needs to poll `GET /api/kyc/status` (already exists) until status changes from `pending`. With webhooks, the client can rely on push notifications and a single status fetch on focus.

---

## What stays the same

These endpoints don't change — the mobile app keeps using them as-is:

| Endpoint | Purpose |
|---|---|
| `POST /api/auth/register` / `verify-otp` / `oauth/google` / `oauth/apple` | Auth flows (unchanged) |
| `POST /api/kyc/dojah/nin-selfie` | **Kept as fallback** for users whose device can't run the SDK. The mobile app will offer it as a manual route. |
| `POST /api/kyc/submit` | Manual KYC fallback (unchanged) |
| `GET /api/kyc/status` | Status polling (unchanged) |
| `DELETE /api/kyc/{id}/file` | File deletion (unchanged) |
| Verified Artisan Gate (`ARTISAN_VERIFICATION_REQUIRED` 403) | Server-side enforcement (unchanged) |

The `Kyc` record schema also stays the same — just two new optional fields:
- `provider` extends to include `"dojah_sdk"` (vs. `"dojah"` for the legacy direct call and `"manual"` for `/kyc/submit`).
- `verificationType` adds `"sdk_widget"`.

---

## Updated client flow (for context)

```text
1. Artisan finishes the trade & location sections of onboarding.
2. Artisan reaches the Identity Verification card and taps "Verify Now".
3. Mobile app:
   a. GET  /api/kyc/dojah/config          -> widgetId, appId, publicKey
   b. POST /api/kyc/dojah/start-session   -> referenceId (optional)
   c. DojahKyc.launch(widgetId, referenceId, email)
   d. User completes NIN entry + liveness + selfie match in the Dojah widget.
   e. Widget closes, SDK fires onSuccess(referenceId).
4. Mobile app:
   a. POST /api/kyc/dojah/verify-reference { referenceId }
   b. Reads { status, ... } from response.
   c. Updates UI: approved -> unlock features, pending -> show "in review",
      rejected -> show reason + retry CTA.
5. (Optional) Backend's Dojah webhook fires asynchronously and may update the
   record before the mobile poll resolves — that's fine, both paths write the
   same fields and `GET /api/kyc/status` will return the latest.
```

The mobile-side artisan flow gates remain identical: apply / accept / withdraw still 403 with `ARTISAN_VERIFICATION_REQUIRED` until `User.isVerified` is `true`.

---

## Dojah dashboard configuration the team needs to do

(Not strictly a backend code change, but required for the integration to work.)

1. In the Dojah dashboard, go to **EasyOnboard** and create a new **Custom Widget**. Configure the steps as: **NIN entry → Selfie/Liveness → Government ID Match**. Customize branding/notifications as needed and **publish** the widget.
2. Copy the generated **Widget ID** and add it to the backend env as `DOJAH_WIDGET_ID`. The `/api/kyc/dojah/config` endpoint returns this value to the mobile app.
3. Confirm `DOJAH_APP_ID` and `DOJAH_SECRET_KEY` are already set (they are per the existing doc) — these are used by the backend when it calls Dojah's "Get Verification Details" API for `/verify-reference`. Neither is exposed to the mobile app.
4. Configure the webhook URL pointing to `POST /api/kyc/dojah/webhook` if implementing webhooks. Note the signing secret and add it as `DOJAH_WEBHOOK_SECRET`.

Sandbox vs. production toggling stays on the backend, same as the existing `DOJAH_BASE_URL` setup. Maintain a separate Widget ID per environment.

---

## Security notes (additions to the existing list)

- `DOJAH_SECRET_KEY`, `DOJAH_APP_ID`, and `DOJAH_WEBHOOK_SECRET` stay server-side. None of them are returned by `/api/kyc/dojah/config` or any other client-facing endpoint.
- `widgetId` is the only Dojah value exposed to mobile. It is public-by-design — the SDK authenticates the flow against Dojah using the Widget ID alone, and Dojah's pipeline enforces the configured steps.
- The mobile SDK callback (`onSuccess`) is **not trusted** as a verification result. The backend always re-checks via Dojah's Verification Details API per Dojah's own guidance:
  > The final verification decision should never rely on SDK callbacks alone — always retrieve the actual verification result using the reference ID.
- Validate that a `referenceId` posted to `/verify-reference` actually belongs to the authenticated user (via stored session from `/start-session`, Dojah metadata embedded at launch, or matched contact info). Otherwise a malicious user could replay another user's successful reference.

---

## Quick endpoint summary (delta to [current-auth-flow.md](current-auth-flow.md))

| Flow | Method | Endpoint | Auth | Status |
|---|---|---|---|---|
| Dojah SDK config | GET | `/api/kyc/dojah/config` | Yes | **NEW** |
| Dojah session start | POST | `/api/kyc/dojah/start-session` | Yes | **NEW (optional)** |
| Dojah verify reference | POST | `/api/kyc/dojah/verify-reference` | Yes | **NEW** |
| Dojah webhook | POST | `/api/kyc/dojah/webhook` | Signed | **NEW (optional)** |
| Dojah NIN + selfie (legacy) | POST | `/api/kyc/dojah/nin-selfie` | Yes | Kept as fallback |
| Manual KYC submit | POST | `/api/kyc/submit` | Yes | Unchanged |
| KYC status | GET | `/api/kyc/status` | Yes | Unchanged |
