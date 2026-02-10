Flutter device token integration
===============================

This document shows recommended, standard patterns for obtaining an FCM device token in Flutter and registering it with the Artisan backend so the server can send push notifications to the device.

1) Add dependencies

Add to `pubspec.yaml`:

- firebase_messaging: ^14.6.0
- http: ^0.13.6

2) Obtain FCM token (example)

```dart
import 'package:firebase_messaging/firebase_messaging.dart';

final FirebaseMessaging _messaging = FirebaseMessaging.instance;

Future<String?> getFcmToken() async {
  try {
    final token = await _messaging.getToken();
    return token;
  } catch (e) {
    // handle error
    return null;
  }
}
```

3) Send the token during auth (recommended UX)

When you call the backend `POST /api/auth/login` or `POST /api/auth/register`, include the device token in the JSON body as `deviceToken` and optional `platform` (`ios` or `android`). The server will auto-register the token on successful auth and return the user's saved tokens as `deviceTokens` in the response.

Example (using `http` package):

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;

Future<Map<String,dynamic>> login(String email, String password, String? deviceToken, String platform) async {
  final uri = Uri.parse('https://your-server.example.com/api/auth/login');
  final resp = await http.post(uri,
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'email': email,
      'password': password,
      if (deviceToken != null) 'deviceToken': deviceToken,
      if (platform != null) 'platform': platform,
    }),
  );
  return jsonDecode(resp.body) as Map<String,dynamic>;
}
```

The backend response will include `token` (JWT) and `deviceTokens` (array) on success.

4) Explicit register / unregister endpoints

If you prefer to call a dedicated endpoint after login, use:

- `POST /api/devices/register` (auth required) body: `{ token: '<fcm token>', platform: 'ios' }`
- `POST /api/devices/unregister` (auth required) body: `{ token: '<fcm token>' }`

Example register call (after obtaining JWT):

```dart
Future<bool> registerDeviceToken(String jwt, String deviceToken, String platform) async {
  final uri = Uri.parse('https://your-server.example.com/api/devices/register');
  final resp = await http.post(uri,
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $jwt'
    },
    body: jsonEncode({'token': deviceToken, 'platform': platform}),
  );
  return resp.statusCode >= 200 && resp.statusCode < 300;
}
```

5) List current device tokens

Use `GET /api/devices/my` (auth required) to retrieve the tokens registered for the logged-in user.

6) Unregister on logout

On sign-out, call `/api/devices/unregister` with the current FCM token so the server can remove it.

7) Token rotation & failures

- The server automatically upserts tokens and deduplicates by token.
- The server will clean tokens not updated for 90 days automatically (TTL index).
- When the FCM send returns `NotRegistered` or `InvalidArgument`, the server will delete the token.

8) Security & best practices

- Always call register after login, and unregister on logout.
- Protect register/unregister endpoints with the auth token.
- Do not expose other users' tokens.
- If you include `deviceToken` in auth requests, it improves UX (single call).

9) Example full flow (pseudo)

1. App starts, obtains FCM token via `getFcmToken()`.
2. User logs in — include `deviceToken` in login body.
3. Server returns JWT and `deviceTokens` list.
4. App saves JWT and proceeds.

If you want, I can prepare a small Flutter snippet that handles token retrieval, automatic re-registration when token changes, and unregister on logout — tell me if you'd like that added.
