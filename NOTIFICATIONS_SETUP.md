# Awesome Notifications Setup - Rijhub Mobile App

## ✅ Setup Complete

Push notifications have been successfully configured using Awesome Notifications and Firebase Cloud Messaging (FCM).

## 📦 Dependencies Added

- `awesome_notifications: ^0.10.0` - Local and push notifications
- `firebase_messaging` - Firebase Cloud Messaging integration (foreground/background/terminated)
- Removed `flutter_local_notifications` (replaced by awesome_notifications)
- Removed `awesome_notifications_fcm` (replaced by firebase_messaging)

## 🔧 Configuration Files Modified

### Android (`android/app/src/main/AndroidManifest.xml`)
Added permissions:
- `VIBRATE` - Vibration support
- `RECEIVE_BOOT_COMPLETED` - Reschedule notifications after reboot
- `SCHEDULE_EXACT_ALARM` - Precise notification timing
- `USE_FULL_SCREEN_INTENT` - Full screen notifications
- `WAKE_LOCK` - Wake up screen
- `FOREGROUND_SERVICE` - Background services
- `POST_NOTIFICATIONS` - Android 13+ notification permission

Added receivers:
- `ScheduledNotificationReceiver` - Handle scheduled notifications
- `RefreshSchedulesReceiver` - Reschedule on boot
- `ForegroundService` - Support foreground services

### iOS (`ios/Podfile`)
Added Awesome Notifications pod configuration for proper iOS support.

## 📝 Created Files

### `lib/services/notification_controller.dart`
Complete notification controller with:
- ✅ Initialization
- ✅ Permission management
- ✅ FCM token handling
- ✅ Token refresh logic
- ✅ Background notification handling
- ✅ Foreground notification handling
- ✅ Action handlers
- ✅ Topic subscription
- ✅ Local notification support

## 🔑 FCM Token Management

The FCM token is:
1. **Automatically requested** on app startup
2. **Printed to console** for debugging (look for `🔑 FCM TOKEN:`)
3. **Saved locally** using SharedPreferences
4. **Automatically refreshed** when it changes
5. **Available globally** via `NotificationController.fcmToken`

### Getting the Token

```dart
// Get current token
String? token = NotificationController.fcmToken;

// Or load from storage
String? token = await NotificationController.loadFcmToken();

// Or request a fresh token
String? token = await NotificationController.requestFirebaseToken();
```

### TODO: Send Token to Backend

When you implement your login endpoint, add this code to send the token:

```dart
// In your login function, after successful authentication:
String? fcmToken = await NotificationController.requestFirebaseToken();
if (fcmToken != null) {
  // Send to your backend
  await yourApiService.sendFcmToken(fcmToken);
}
```

## 📱 Notification Channels

Four notification channels are configured:

1. **basic_channel** - Basic notifications
2. **scheduled_channel** - Scheduled notifications
3. **chat_channel** - Chat messages (High priority)
4. **call_channel** - Call notifications (Max priority, critical alerts)

## 🎯 Usage Examples

### Show Local Notification

```dart
await NotificationController.showLocalNotification(
  id: 1,
  title: 'Hello!',
  body: 'This is a test notification',
  payload: {'type': 'test', 'data': 'value'},
);
```

### Subscribe to Topic

```dart
await NotificationController.subscribeToTopic('all_users');
```

### Check Initial Notification

```dart
// Check if app was opened from a notification
ReceivedAction? action = await NotificationController.getInitialNotificationAction();
if (action != null) {
  // Handle the notification action
  print('App opened from notification: ${action.payload}');
}
```

## 🔔 Sending Push Notifications

### From Firebase Console

Send a message with this JSON structure:

```json
{
  "to": "FCM_TOKEN_HERE",
  "mutableContent": true,
  "contentAvailable": true,
  "priority": "high",
  "data": {
    "content": {
      "id": 100,
      "channelKey": "basic_channel",
      "title": "Test Notification",
      "body": "This is from Firebase!",
      "notificationLayout": "Default",
      "payload": {
        "type": "order",
        "orderId": "12345"
      }
    }
  }
}
```

### From Your Backend

Use Firebase Admin SDK to send notifications:

```javascript
// Node.js example
const admin = require('firebase-admin');

await admin.messaging().send({
  token: fcmToken,
  data: {
    content: JSON.stringify({
      id: 100,
      channelKey: 'chat_channel',
      title: 'New Message',
      body: 'You have a new message!',
      payload: {
        type: 'chat',
        chatId: 'chat123'
      }
    })
  },
  android: {
    priority: 'high',
  },
  apns: {
    headers: {
      'apns-priority': '10',
    },
  },
});
```

## 🎬 Notification Events

The following events are automatically handled:

1. **onNotificationCreatedMethod** - When notification is created
2. **onNotificationDisplayedMethod** - When notification is shown
3. **onActionReceivedMethod** - When user taps notification
4. **onDismissActionReceivedMethod** - When user dismisses notification

Implement custom logic in `lib/services/notification_controller.dart`.

## 🔐 Permissions

Permissions are automatically requested on app startup for:
- Alert/Banner display
- Sound
- Badge counter
- Vibration
- LED lights (Android)

## 📍 Current Token Location

When the app starts, the FCM token will be:
1. Printed to the console/terminal
2. Logged with prefix `🔑 FCM TOKEN:`
3. Saved to SharedPreferences

Look for this output when running your app:
```
🔑 FCM TOKEN: fX8j9K2m...rest_of_token...
```

## 🚀 Testing

### Test Local Notification

Add a test button in your UI:

```dart
ElevatedButton(
  onPressed: () async {
    await NotificationController.showLocalNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: 'Test Notification',
      body: 'Tap me to test action handling!',
      payload: {'screen': 'home'},
    );
  },
  child: Text('Test Notification'),
)
```

### Test Token Retrieval

```dart
ElevatedButton(
  onPressed: () async {
    String? token = await NotificationController.requestFirebaseToken();
    print('Current FCM Token: $token');
    // Copy this token to send test notifications from Firebase Console
  },
  child: Text('Get FCM Token'),
)
```

## 🐛 Troubleshooting

### Token is null
- Check internet connection
- Verify Firebase configuration
- Check Google Services files are in place
- Android: Ensure `google-services.json` exists
- iOS: Ensure `GoogleService-Info.plist` exists

### Notifications not showing
- Check notification permissions
- Verify channel configuration
- Check device Do Not Disturb settings
- Android: Disable battery optimization for your app

### Background notifications not working
- Ensure app has background permission
- Check Android battery optimization settings
- iOS: Enable background modes in Xcode

## 📚 Additional Resources

- [Awesome Notifications Docs](https://pub.dev/packages/awesome_notifications)
- [Firebase Messaging (Flutter)](https://firebase.google.com/docs/cloud-messaging/flutter/client)
- [Firebase Console](https://console.firebase.google.com)

## ⚠️ Important Notes

1. **Do NOT use** `flutter_local_notifications` alongside awesome_notifications
2. Prefer sending **notification** (or notification+data) payloads for Android “app closed” delivery. Use **data-only** payloads only if you handle them via `FirebaseMessaging.onBackgroundMessage`.
3. Test on **real devices** for best results (especially for FCM)
4. iOS requires physical device for push notifications (simulator won't work)
5. Always request permissions before sending notifications

## ✅ Channel key is optional

When sending **data-only** pushes from your backend, you **do not need** to include a `channelKey`.

- If `channelKey` is missing (or unknown), the app will use `basic_channel`.
- You can optionally send `channelKey` as one of: `basic_channel`, `scheduled_channel`, `chat_channel`, `call_channel`.

## 🎉 You're All Set!

Your push notification system is now fully configured and ready to use. The FCM token will be printed to the console on app startup. Use that token to test push notifications from the Firebase Console.
