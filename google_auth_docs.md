# Authentication & Google OAuth — Developer Guide

This document explains how the server handles authentication and how mobile apps (Flutter / Android / iOS) should integrate Google Sign-In using ID tokens. It includes configuration, endpoints, example client snippets, security notes, and troubleshooting.

---

## Summary

- Mobile app obtains a Google ID token from Google Sign-In SDK.
- Mobile app POSTs the ID token to the server endpoint `POST /api/auth/oauth/google`.
- Server verifies the ID token using `google-auth-library` (`OAuth2Client.verifyIdToken`) and issues the application JWT.

The server already implements registration, login, guest login, and Google OAuth handlers in `src/controllers/authController.js`.

---

## Required Google Console Setup

1. Create a Google Cloud Project. Configure OAuth Consent Screen.
2. Create OAuth 2.0 Client ID:
   - For mobile use: create Android or iOS credentials with package name / bundle id and SHA-1 (Android) as required.
   - For web or Identity SDK usage: create a Web client and copy the **Client ID**.
3. If you need server-side code-exchange for refresh tokens, also copy the **Client Secret** and configure redirect URIs.

Store values in the server `.env`:

```
GOOGLE_CLIENT_ID=<your-client-id>
GOOGLE_CLIENT_SECRET=<your-client-secret> # optional; only for auth-code flow
```

The repo already expects these variables (see `src/controllers/authController.js`).

---

## Server Behavior (what it does)

- Exposes endpoint: `POST /api/auth/oauth/google`
  - Request body: `{ "idToken": "<GOOGLE_ID_TOKEN>" }`
  - Response (success): `{ success: true, user, token }` where `token` is your app JWT (7d expiry by default).
- Verification steps on the server:
  1. Calls `googleClient.verifyIdToken({ idToken, audience: process.env.GOOGLE_CLIENT_ID })`.
  2. Reads `ticket.getPayload()` for claims: `sub` (Google id), `email`, `email_verified`, `name`, `picture`.
  3. Finds existing `User` by `googleId` or `email`.
     - If found and missing `googleId`, it links the account (sets `googleId` and `provider: 'google'`).
     - If not found, creates a new `User` record with `googleId` and profile image (if present).
  4. Issues app JWT and returns `user` + `token`.

- Registration endpoint `POST /api/auth/register` also accepts `googleIdToken` for combined register+oauth flow.

---

## Mobile Integration (Recommended: ID token flow)

This is the simplest flow for mobile apps. The mobile app obtains an ID token from the Google SDK and sends it to the server.

### Android (Kotlin) - high level

1. Configure `GoogleSignInOptions` with `requestIdToken(<GOOGLE_CLIENT_ID>)`.
2. After sign-in, obtain `account.idToken`.
3. POST `idToken` to server endpoint.

### iOS (Swift) - high level

1. Use the GoogleSignIn SDK and configure with your client ID.
2. After sign-in, read `user.authentication.idToken`.
3. POST `idToken` to server endpoint.

### Flutter example (using `google_sign_in`):

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';

final GoogleSignIn googleSignIn = GoogleSignIn(
  scopes: ['email', 'profile'],
  // optional: set clientId if required by platform
);

Future<void> signInWithGoogle() async {
  final account = await googleSignIn.signIn();
  final auth = await account?.authentication;
  final idToken = auth?.idToken;
  final res = await http.post(
    Uri.parse('https://api.yourdomain.com/api/auth/oauth/google'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'idToken': idToken}),
  );
  final body = jsonDecode(res.body);
  final jwt = body['token'];
  // store jwt securely (flutter_secure_storage)
}
```

### Important mobile notes

- Ensure your OAuth client is configured for the app platform (Android package name + SHA-1 or iOS bundle id). If you use the web client for Identity SDK, ensure origins are allowed.
- Use HTTPS for all server requests.
- Store the returned JWT securely (Keychain / Keystore / flutter_secure_storage).

---

## Server Test Example (curl)

To test the server endpoint manually, use a valid `id_token` (from a Google SDK or OAuth Playground):

```bash
curl -X POST https://api.yourdomain.com/api/auth/oauth/google \
  -H "Content-Type: application/json" \
  -d '{"idToken":"<GOOGLE_ID_TOKEN>"}'
```

Successful response:

```json
{ "success": true, "user": { ... }, "token": "<APP_JWT>" }
```

---

## Security Best Practices

- Always verify the ID token server-side (do not trust client-side validation).
- Confirm token `aud` matches your `GOOGLE_CLIENT_ID` and check `exp` claim.
- Prefer `email_verified === true` before automatically trusting/using the email.
- When linking accounts by email, prompt the user when an existing non-Google account exists (avoid silent merges).
- Use HTTPS and secure storage for JWTs.
- If you need refresh tokens or offline access, implement the authorization-code flow (requires `GOOGLE_CLIENT_SECRET` and server-side code exchange); be aware of extra consent and app verification requirements for sensitive scopes.

---

## Authorization-Code Flow (Optional — server-side)

If you need refresh tokens or long-lived access, implement the auth-code flow:

1. Mobile app obtains an authorization code from Google (requires redirect URI or native flow).
2. Send the code to the server.
3. Server exchanges the code at `https://oauth2.googleapis.com/token` using `CLIENT_ID` and `CLIENT_SECRET`.
4. Server stores refresh token securely (if returned) and issues app JWTs to the mobile client.

This requires additional server routes and storing client secret in `.env`.

---

## Troubleshooting

- `Invalid Google token` from server:
  - Ensure `idToken` is a valid Google ID token (not an access token).
  - Ensure `GOOGLE_CLIENT_ID` in server `.env` matches the client used to request the token.
  - Check token expiry.

- No `email` in payload:
  - Some sign-in configurations do not return an email; request `email` scope on client.

- Duplicate accounts:
  - If a user previously registered with email/password, decide whether to prompt for linking or require prior sign-in to link accounts.

---

## Repo pointers

- Server Google verification + handlers: `src/controllers/authController.js` (uses `google-auth-library`).
- Dependency: `google-auth-library` is in `package.json`.
- Env: `.env` keys `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET`.

---

## Example: Full mobile QA test plan

1. Configure OAuth client for your mobile app (package name / SHA-1 or bundle id).
2. Build app, sign in via Google, capture `idToken`.
3. POST token to `/api/auth/oauth/google`.
4. Confirm server returns `{ success: true, user, token }` and that the user is created/linked in the DB.
5. Use returned JWT to call a protected endpoint and confirm authorization.

---

If you want, I can also:
- Add a complete Flutter example widget + storage integration, or
- Implement server-side authorization-code exchange routes to support refresh tokens.


