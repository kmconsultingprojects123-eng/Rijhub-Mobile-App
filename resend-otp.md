**Resend OTP**

**Overview:**
- **Purpose:** Endpoint to regenerate and re-deliver a verification OTP for pending registrations.
- **Behavior:** Regenerates a 6-digit OTP, stores a server-side SHA-256 hash, enforces a resend throttle window, and attempts delivery via the configured OTP provider (phone) with an email fallback.

**Endpoint:**
- **Method & Path:** POST /api/auth/resend-otp

**Request Body:**
- **email:** (required) The user's email for the pending registration.
- **phone:** (optional) Override or supply phone number to target provider delivery. If omitted, server will try the phone in the pending payload.

**Responses:**
- **200 OK:** Resend request accepted; code will be sent shortly. (When delivery is backgrounded.)
  - Example: { "success": true, "message": "Resend request accepted. You will receive the code shortly." }
- **429 Too Many Requests:** Throttled. Wait at least `RESEND_OTP_WINDOW_SECONDS` (default 60s) between sends.
  - Example: { "success": false, "message": "Please wait before requesting a new code (60s)" }
- **400 Bad Request:** Missing required `email` or invalid payload.
- **500 Internal Server Error:** Server-side error while generating/persisting OTP.

**Throttle / Rate-Limit:**
- Configurable by env var `RESEND_OTP_WINDOW_SECONDS` (default: 60 seconds). The endpoint checks the `createdAt` on the `RegistrationOtp` record and rejects requests made within the window.

**Delivery Flow & Providers:**
- The server decides delivery channel based on `OTP_PROVIDER` environment and availability of a phone number:
  - If `OTP_PROVIDER` is `sendchamp`, `termii`, `twilio`, etc., the server will call the provider via the `providerSendOtp` abstraction.
  - If provider send fails or provider returns non-success, the server falls back to email delivery via the notifier (`sendEmail`).
- Delivery is performed in the background; the endpoint returns immediately once the resend is accepted.

**Persisted Metadata:**
- The `RegistrationOtp` document stores `codeHash`, `expiresAt`, `attempts`, and `delivered` metadata. `delivered` contains `{ method, result, timestamp }` and helps the verification flow decide whether to use provider-side verification or local hash-check.

**Verification:**
- After receiving an OTP, clients should call `POST /api/auth/verify-otp` with `{ email, otp }` to complete verification.
- If `RegistrationOtp.delivered.method` indicates a provider that supports server-side verification, the server will attempt provider verification first, otherwise it falls back to comparing the SHA-256 hash of the provided OTP with the stored `codeHash`.

**Env Vars (relevant):**
- `RESEND_OTP_WINDOW_SECONDS` — throttle window in seconds (default 60).
- `OTP_PROVIDER` — provider to use (e.g., `sendchamp`, `twilio`, `termii`, `firebase`, `email`).
- Provider-specific vars: see existing docs for `TERMII_API_KEY`, `SENDCHAMP_API_KEY`, `TWILIO_*`, etc.

**Client Guidance:**
- No change required to client endpoints beyond calling this new route to request a resend.
- Prefer calling with `phone` only if you need to override the pending payload phone.
- Handle 429 responses by showing a retry timer based on `RESEND_OTP_WINDOW_SECONDS`.

**Curl Examples:**

- Basic (email-only fallback):

```bash
curl -X POST 'https://your-server.example.com/api/auth/resend-otp' \
  -H 'Content-Type: application/json' \
  -d '{ "email": "user@example.com" }'
```

- Preferred (provide phone to force provider delivery):

```bash
curl -X POST 'https://your-server.example.com/api/auth/resend-otp' \
  -H 'Content-Type: application/json' \
  -d '{ "email": "user@example.com", "phone": "+2348012345678" }'
```

**Notes & Next Steps:**
- To fully validate third-party provider behavior (Termii/SendChamp/Twilio), run smoke tests with real provider credentials and phones.
- Consider adding a `Retry-After` header on 429 responses and server-side rate-limiting middleware if stricter protection is required.

