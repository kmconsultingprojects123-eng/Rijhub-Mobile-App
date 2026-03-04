# SendChamp Registration (Verify‑then‑Create)

This document explains the registration flow used by the server: the app sends an OTP with SendChamp and only creates the final `User` after the phone is verified.

**Files**
- Controller: [src/controllers/authController.js](src/controllers/authController.js)
- Pending record model: [src/models/RegistrationOtp.js](src/models/RegistrationOtp.js)
- SendChamp client: [src/utils/sendchamp.js](src/utils/sendchamp.js)

**Overview**
1. Client POSTs `name`, `email`, `phone` to `POST /api/auth/register`.
2. Server saves the submitted data in a pending OTP record (`RegistrationOtp`) and sends an OTP via SendChamp (SMS) when `SENDCHAMP_API_KEY` is configured.
3. The SendChamp response may include a `reference`. The server saves this reference to `RegistrationOtp.delivered.reference` and returns it to the client.
4. Client submits `{ email, reference, otp }` to `POST /api/auth/verify-sendchamp` (or `{ email, otp }` to `/api/auth/verify-otp` if no reference).
5. Server verifies the OTP via SendChamp `/verification/confirm` when a `reference` is present; otherwise it validates the local hashed OTP.
6. On success the server creates the `User`, deletes the pending record, issues a JWT and optionally sends a welcome notification.

**Environment**
- `SENDCHAMP_API_KEY` — required to use SendChamp OTP API.
- `SENDCHAMP_DEFAULT_SENDER` — optional default sender id.
- `SMTP_*` / `SMTP_FROM` — fallback email delivery.
- `JWT_SECRET` — auth token signing secret.

**Endpoints (server)**
- `POST /api/auth/register` — start registration; body: `{ name, email, phone, password?, role? }`. Response on SendChamp success includes `reference` when available.
- `POST /api/auth/verify-sendchamp` — finalize registration using provider reference; body: `{ email, reference, otp }`.
- `POST /api/auth/verify-otp` — fallback verification using server-side hash; body: `{ email, otp }`.

Example: register request (client)

```http
POST /api/auth/register
Content-Type: application/json

{
  "name": "Jane Doe",
  "email": "jane@example.com",
  "phone": "2348012345678",
  "password": "s3cret"
}
```

Successful register response (SendChamp used)

```json
{
  "success": true,
  "message": "Verification code sent via SMS (SendChamp). Use /api/auth/verify-otp to complete registration.",
  "reference": "MN-OTP-b638c07d-bf0b-4174-bbef-432ecc082cd3"
}
```

Example: verify with provider reference (client)

```http
POST /api/auth/verify-sendchamp
Content-Type: application/json

{
  "email": "jane@example.com",
  "reference": "MN-OTP-b638c07d-bf0b-4174-bbef-432ecc082cd3",
  "otp": "123456"
}
```

Successful verify response

```json
{
  "success": true,
  "message": "Registration completed",
  "user": { /* user record */ },
  "token": "<jwt>"
}
```

If no `reference` is available (email fallback or provider didn't return a reference), the client should call `POST /api/auth/verify-otp` with `{ email, otp }`. The server will compare the hashed OTP stored in `RegistrationOtp.codeHash`.

**Implementation notes & best practices**
- Always normalize phone numbers to international format (E.164 without plus, e.g. `2348012345678`).
- Rate-limit `POST /api/auth/register` per IP and per phone/email to prevent abuse and SMS cost spikes.
- Persist the SendChamp `reference` returned by the provider so you can call `/verification/confirm` reliably.
- Keep `RegistrationOtp` records short-lived (the code uses a 15 minute expiry by default).
- Log provider responses in `RegistrationOtp.delivered.result` for debugging but avoid storing sensitive plaintext codes.

**Where to look in the codebase**
- Register & OTP send: [src/controllers/authController.js](src/controllers/authController.js)
- Provider client and confirm call: [src/utils/sendchamp.js](src/utils/sendchamp.js)
- Pending OTP schema: [src/models/RegistrationOtp.js](src/models/RegistrationOtp.js)

If you want, I can also:
- add a short client example (fetch/axios) showing register → verify-sendchamp flow,
- add basic rate-limiting middleware to `POST /api/auth/register`, or
- write a small test script to exercise the flow locally (requires `SENDCHAMP_API_KEY`).
