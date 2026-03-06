# Apple Sign-In Integration Guide (Flutter + Server)

This document shows two client flows and server guidance for Sign in with Apple.

## Summary
- Identity-token flow (mobile obtains `id_token` and sends raw `nonce` to server). Quick and common for mobile apps.
- Authorization-code flow (mobile obtains `authorizationCode`, server exchanges it with Apple using a signed client-secret JWT — requires `.p8` private key).

## Required server env vars
Add to your `.env` (or use secrets manager):

```
APPLE_TEAM_ID=YUDLHJDZDC
APPLE_KEY_ID=4GPW9GAZQR
APPLE_BUNDLE_ID=com.your.bundle.id
APPLE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...contents of .p8...\n-----END PRIVATE KEY-----"
```

## NPM packages (server)

```
npm install jose jsonwebtoken node-fetch
```

`jose` is used to verify Apple `id_token` via Apple's JWKS; `jsonwebtoken` is used to sign the client-secret JWT (ES256). `node-fetch` is used if `fetch` is not available in Node.

## Server endpoint (this project)
- `POST /api/auth/oauth/apple`
  - Accepts either:
    - `{ identityToken, nonce, name?, email?, role? }` OR
    - `{ authorizationCode, name?, email?, role? }`
  - Response: `{ success: true, user, token }` (JWT, same as other OAuth flows)

---

## Identity-token flow (recommended for mobile)

Client (Flutter) steps:

1. Generate a cryptographically-random raw nonce in the app.
2. Hash the nonce with SHA-256 and pass the hashed nonce to Apple SDK.
3. Apple returns `identityToken` (JWT) containing the hashed nonce.
4. Send the raw nonce + `identityToken` to your server. Server will hash raw nonce and compare to `payload.nonce`.

Flutter example (using `sign_in_with_apple`, `crypto`, `http`):

```dart
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:http/http.dart' as http;

String _randomNonce([int length = 32]) {
  final rand = Random.secure();
  final bytes = List<int>.generate(length, (_) => rand.nextInt(256));
  return base64UrlEncode(bytes);
}

String _sha256ofString(String input) {
  final bytes = utf8.encode(input);
  return sha256.convert(bytes).toString();
}

Future<void> signInWithAppleIdentityToken() async {
  final rawNonce = _randomNonce();
  final hashedNonce = _sha256ofString(rawNonce);

  final credential = await SignInWithApple.getAppleIDCredential(
    scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
    nonce: hashedNonce,
  );

  final idToken = credential.identityToken;
  final givenName = credential.givenName;
  final email = credential.email;

  final res = await http.post(
    Uri.parse('https://your-api.example.com/api/auth/oauth/apple'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'identityToken': idToken,
      'nonce': rawNonce,
      'name': givenName,
      'email': email,
    }),
  );
  // handle response
}
```

Server notes:
- Verify `id_token` against Apple's JWKS (`https://appleid.apple.com/auth/keys`).
- Hash raw nonce server-side with SHA-256 and compare to `payload.nonce`.

---

## Authorization-code flow (server exchange)

Client (Flutter): ask for `authorizationCode` and send it to your server.

```dart
final credential = await SignInWithApple.getAppleIDCredential(
  scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
);

final code = credential.authorizationCode;
await http.post(Uri.parse('https://your-api.example.com/api/auth/oauth/apple'),
  headers: {'Content-Type': 'application/json'},
  body: jsonEncode({'authorizationCode': code, 'name': credential.givenName, 'email': credential.email}),
);
```

Server exchange (Node.js example — was implemented in this repo):

```javascript
import jwt from 'jsonwebtoken';
import fetch from 'node-fetch';

function makeAppleClientSecret() {
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    iss: process.env.APPLE_TEAM_ID,
    iat: now,
    exp: now + 60 * 60 * 24 * 180,
    aud: 'https://appleid.apple.com',
    sub: process.env.APPLE_BUNDLE_ID,
  };
  const privateKey = (process.env.APPLE_PRIVATE_KEY || '').replace(/\\n/g,'\n');
  return jwt.sign(payload, privateKey, { algorithm: 'ES256', keyid: process.env.APPLE_KEY_ID });
}

async function exchangeCode(code) {
  const clientSecret = makeAppleClientSecret();
  const params = new URLSearchParams({
    grant_type: 'authorization_code',
    code,
    client_id: process.env.APPLE_BUNDLE_ID,
    client_secret: clientSecret,
  });
  const res = await fetch('https://appleid.apple.com/auth/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: params.toString(),
  });
  const body = await res.json();
  return body; // contains id_token, access_token, refresh_token
}
```

Server will then verify `id_token` and proceed with user lookup/creation as with the identity-token flow.

---

## Nonce handling (important)
- App: send hashed nonce to Apple SDK (Apple embeds hashed nonce in `id_token`).
- Server: receive raw nonce from client, compute SHA-256 hex, and compare to `payload.nonce` inside the `id_token`.

## Security & notes
- Keep `APPLE_PRIVATE_KEY` (.p8) secret — use a secrets manager in production.
- Use `ES256` when signing the client-secret JWT.
- Name/email: Apple sends name only on first sign-in — capture and store it then.
- Email may be a private relay address — it is still unique.

## Quick curl examples

- Identity token flow (if you have id_token + raw nonce):

```bash
curl -X POST https://api.example.com/api/auth/oauth/apple \
  -H 'Content-Type: application/json' \
  -d '{"identityToken":"<ID_TOKEN>","nonce":"<RAW_NONCE>","name":"John Doe"}'
```

- Authorization code flow:

```bash
curl -X POST https://api.example.com/api/auth/oauth/apple \
  -H 'Content-Type: application/json' \
  -d '{"authorizationCode":"<AUTH_CODE>","name":"John Doe"}'
```

## Checklist
- [ ] Add `APPLE_*` env vars to server
- [ ] Install `jose`, `jsonwebtoken`, `node-fetch` on server
- [ ] Test identity-token flow on device/simulator
- [ ] If using authorization-code flow, ensure `.p8` key is stored securely

---

If you want I can add a short `curl` test script under `scripts/` that calls the new endpoint — say the word and I'll create it.
