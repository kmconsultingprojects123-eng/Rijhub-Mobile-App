# Firebase Cloud Messaging (FCM) — Integration Guide

I did this document to explain how to use the repository's Firebase Cloud Messaging integration (server-side) to send push notifications to mobile devices. It covers environment setup, device token lifecycle, server endpoints, testing, and troubleshooting.

---

## Summary

- The server uses `firebase-admin` (initialized from a service account) to send FCM pushes.
- Device tokens are stored in the `DeviceToken` collection (model: `src/models/DeviceToken.js`).
- Mobile apps should obtain an FCM token and POST it to the server `POST /api/devices/register` with the user's JWT.
- The server sends notifications from `src/utils/notifier.js` which now attempts FCM first and falls back to email when configured.


## Device token lifecycle (recommended)

- On app start or after successful login/registration:
  1. Mobile app obtains FCM token from Firebase SDK (`FirebaseMessaging.getToken()` / `onTokenRefresh`).
  2. If token exists, POST to `POST /api/devices/register` with header `Authorization: Bearer <JWT>` and JSON body `{ "token": "<fcm-token>", "platform": "android|ios|flutter" }`.
- On token refresh: re-send to `/api/devices/register`.
- On logout/uninstall (if possible): call `POST /api/devices/unregister` with `{ token }`.

Server behavior: tokens are upserted by token value and associated with the authenticated user. Multiple tokens per user are supported for multi-device.

---

## Mobile client snippets

Flutter (example):
### Mobile client snippets

Flutter (example):

```dart
final fcm = FirebaseMessaging.instance;
final idToken = await fcm.getToken();
await http.post(
  Uri.parse('https://rijhub.com/api/devices/register'),
  headers: {'Authorization': 'Bearer $jwt', 'Content-Type': 'application/json'},
  body: jsonEncode({'token': idToken, 'platform': 'flutter'}),
);

// handle token refresh
FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
  // POST newToken to /api/devices/register
});
```


ummm i hope this is detailed enough.