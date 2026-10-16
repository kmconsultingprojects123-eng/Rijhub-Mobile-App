# Registration OTP (email verification for non-OAuth signups)

Overview

Normal (non-OAuth) registrations now require email verification via an OTP before the user account is created.

Flow
1. Client POSTs to `POST /api/auth/register` with registration data (email, password, name...).
2. Server stores a pending `RegistrationOtp` record containing a hashed OTP and a `payload` (the pending user data), and sends a 6-character OTP to the user's email.
3. Client submits `POST /api/auth/verify-otp` with `{ email, otp }`.
4. Server verifies the OTP, creates the `User` from the stored payload, deletes the pending OTP record, and returns a JWT.

Details
- OTP format: 6-character modern alphanumeric string.
- Expiry: 15 minutes.
- Attempts are tracked and incremented on invalid submissions.

Endpoints
- `POST /api/auth/register` — starts registration and sends OTP (for non-OAuth flows).
- `POST /api/auth/verify-otp` — verify and finalize registration. Body: `{ email, otp }`.
