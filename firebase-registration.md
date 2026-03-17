Firebase Registration Flow — Artisan Backend

Purpose
- Explain how client-side Firebase phone verification integrates with the backend registration flow.
- Provide endpoints, expected request/response shapes, environment variables, and developer notes for implementation and debugging.

Overview
- Clients use Firebase Auth (client SDK) to verify phone numbers and obtain an ID token (short-lived JWT issued by Firebase).
- The client sends that ID token (called `idToken` or `reference` depending on the endpoint) to the backend.
- The backend verifies the ID token using the Firebase Admin SDK, ensures the phone matches any pending registration payload, creates the user, and issues the application JWT.

When to use
- Use Firebase path when you want the client to perform secure SMS-based phone verification via Firebase (recommended for mobile apps using Firebase Auth).
- The server does NOT send Firebase SMS messages; the client must run Firebase phone auth and then call server endpoints with the resulting ID token.



Endpoints (existing in codebase)
1) POST /api/auth/registeruserfirebase
- Purpose: Client already verified phone via Firebase and has an ID token; use this endpoint to complete registration in a single request (client supplies name/email/password and idToken).
- Body (JSON):
  - `idToken` (string) — Firebase ID token from client
  - `name` (string), `email` (string), `password` (string), `role` ('customer'|'artisan')
- Success (201): `{ token, user: { _id, name, email, phone, role, firebaseUid, phoneVerified, createdAt } }`
- Errors: 400 for missing fields, 401 for invalid/expired Firebase token, 409 when user exists, 500 for server errors.

2) POST /api/auth/verify-registration-reference (controller: `verifyRegistrationWithReference`)
- Purpose: Used when a pending `RegistrationOtp` exists (server created OTP record) and client provides a provider `reference` instead of raw `otp`. For Firebase flows, `reference` is the Firebase ID token.
- Body (JSON):
  - `email` (string) — email used during registration (must match OTP record)
  - `reference` (string) — Firebase ID token issued by client
  - `otp` (string, optional) — required for non-Firebase providers only
- Behavior for Firebase: backend verifies ID token with Admin, optionally checks that the token phone number matches the `RegistrationOtp.payload.phone`, then finalizes user creation, sets `firebaseUid`, `phoneVerified: true`, deletes the `RegistrationOtp` record, and returns application JWT.

Server behavior details
- initFirebase(): must initialize Firebase Admin SDK successfully or endpoints return 500.
- Token verification: `admin.auth().verifyIdToken(idToken)` is used. If that throws, the endpoint responds 400 (invalid/expired token) and increments `record.attempts` on the pending OTP record.
- Phone matching: If `RegistrationOtp.payload.phone` exists, normalize numeric characters only and compare to `decoded.phone_number` from the ID token; reject on mismatch.
- User creation: create `User` document with payload from `RegistrationOtp` (ensuring `email` is set to normalized email), set `firebaseUid` and `phoneVerified=true` when available.
- Cleanup: delete the `RegistrationOtp` record after successful creation; send a welcome notification; return app JWT (signed with `JWT_SECRET`).
- Logging: endpoints should log verification attempts, mismatches, and errors — use `req.log` for diagnostics.

Client-side flow (recommended)
- Use Firebase client SDK to perform phone number sign-in or verification flow.
- On success, the client obtains an ID token (calls `currentUser.getIdToken()` or receives it from the sign-in flow).
- Option A — Single-call registration: send `idToken`, `name`, `email`, `password`, `role` to `/api/auth/registeruserfirebase`.
- Option B — OTP-backed registration: first call server `registerUser` to create a pending `RegistrationOtp` (server may create OTP when `phone` present). Then after client finishes phone verification via Firebase send the `idToken` to `/api/auth/verify-registration-reference` with the `email` used to register.

Examples
- registerUserWithFirebaseToken (curl):

```bash
curl -X POST https://your.api/api/auth/registeruserfirebase \
  -H "Content-Type: application/json" \
  -d '{"idToken":"<FIREBASE_ID_TOKEN>","name":"Alice","email":"alice@example.com","password":"secret123","role":"customer"}'
```

- verifyRegistrationWithReference (curl):

```bash
curl -X POST https://your.api/api/auth/verify-registration-reference \
  -H "Content-Type: application/json" \
  -d '{"email":"alice@example.com","reference":"<FIREBASE_ID_TOKEN>"}'
```

Developer notes and gotchas
- The server cannot initiate Firebase SMS sends — the client must perform Firebase phone auth and send the ID token to the server.
- Ensure `SERVICE_ACCOUNT_KEY_BASE64` or `GOOGLE_APPLICATION_CREDENTIALS` is set in production and that the service account has `auth` privileges.
- ID tokens expire (short TTL); verify them immediately and do not accept long-delayed tokens.
- Rate-limit verification endpoints, and increment `RegistrationOtp.attempts` on failures to avoid brute-force attempts.
- Persist provider metadata to `RegistrationOtp.delivered` (for debugging) when creating OTPs. The code already attempts to persist such metadata — watch for background task errors that prevented persistence.
- When both email and phone are provided, validate that the email in `RegistrationOtp.payload` equals the `email` param on `verifyRegistrationWithReference` to prevent reusing OTPs for other addresses.
- Add monitoring around failures where `delivered` metadata is missing — this often indicates the background sender returned non-success or an exception prevented updating the DB.
- Tests: write integration tests that simulate a Firebase ID token (use a test service account and the Admin SDK to mint tokens or use Firebase's testing utilities).

Security considerations
- Never accept arbitrary tokens as proof without verifying via Firebase Admin.
- Always normalize and compare phone numbers by digits only to avoid formatting mismatches.
- Remove `RegistrationOtp` records after successful registration to avoid replay.
- Sign app JWTs securely (`JWT_SECRET`) and avoid leaking secrets in logs.

Next steps for the developer
- Verify `src/utils/firebaseAdmin.js` initialization uses `SERVICE_ACCOUNT_KEY_BASE64` and is robust across environments.
- Confirm `src/controllers/authController.js` endpoints `registerUserWithFirebaseToken` and `verifyRegistrationWithReference` are wired in `src/routes/authRoutes.js` under `/api/auth`.
- Add automated integration tests that exercise both registration endpoints using a Firebase test project or mocked Admin SDK.

Contact
- If you want, I can also produce minimal client examples for web (Firebase Web SDK) and mobile (Android / iOS) or add a short integration test stub in `scripts/` to help validate server behavior.