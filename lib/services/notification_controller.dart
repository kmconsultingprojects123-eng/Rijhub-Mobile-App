import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../api_config.dart';
import '../firebase_options.dart';
import 'token_storage.dart';

/// Background handler for Firebase Messaging.
///
/// Must be a top-level function for the background isolate entrypoint.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase must be initialized in the background isolate.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {
    // Ignore "already initialized" and other non-fatal init errors here.
  }

  // Ensure local notification channels exist before creating notifications.
  try {
    await NotificationController.initializeNotifications();
  } catch (_) {}

  await NotificationController.handleRemoteMessage(
    message,
    reason: 'onBackgroundMessage',
  );
}

class NotificationController {
  static String? fcmToken;
  static const String _fcmTokenKey = 'fcm_token';
  static bool _deviceRegisterInFlight = false;
  static bool _firebaseMessagingListenersReady = false;

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static const String _defaultChannelKey = 'basic_channel';
  static const Set<String> _knownChannelKeys = {
    'basic_channel',
    'scheduled_channel',
    'chat_channel',
    'call_channel',
  };

  static void _log(String message) {
    // Do not log JWT or raw tokens.
    developer.log(message, name: 'NotificationController');
  }

  /// Initialize Awesome Notifications
  static Future<void> initializeNotifications() async {
    print('🔔 [NOTIFICATION] Starting initialization...');

    // Initialize local notifications
    await AwesomeNotifications().initialize(
      null, // Use default app icon
      [
        NotificationChannel(
          channelKey: 'basic_channel',
          channelName: 'Basic Notifications',
          channelDescription: 'Notification channel for basic notifications',
          defaultColor: const Color(0xFF9D50DD),
          ledColor: Colors.white,
          importance: NotificationImportance.High,
          channelShowBadge: true,
        ),
        NotificationChannel(
          channelKey: 'scheduled_channel',
          channelName: 'Scheduled Notifications',
          channelDescription:
              'Notification channel for scheduled notifications',
          defaultColor: const Color(0xFF9D50DD),
          ledColor: Colors.white,
          importance: NotificationImportance.High,
          channelShowBadge: true,
        ),
        NotificationChannel(
          channelKey: 'chat_channel',
          channelName: 'Chat Notifications',
          channelDescription: 'Notification channel for chat messages',
          defaultColor: const Color(0xFF9D50DD),
          ledColor: Colors.white,
          importance: NotificationImportance.Max,
          channelShowBadge: true,
          playSound: true,
          enableVibration: true,
        ),
        NotificationChannel(
          channelKey: 'call_channel',
          channelName: 'Call Notifications',
          channelDescription: 'Notification channel for calls',
          defaultColor: const Color(0xFF9D50DD),
          ledColor: Colors.white,
          importance: NotificationImportance.Max,
          channelShowBadge: true,
          playSound: true,
          enableVibration: true,
          criticalAlerts: true,
        ),
      ],
      channelGroups: [
        NotificationChannelGroup(
          channelGroupKey: 'basic_group',
          channelGroupName: 'Basic Notifications',
        ),
      ],
      debug: true,
    );
    print('🔔 [NOTIFICATION] Awesome Notifications initialized');

    // Check if notifications are allowed
    bool isAllowed = await AwesomeNotifications().isNotificationAllowed();
    print('🔔 [NOTIFICATION] Notifications allowed: $isAllowed');
  }

  /// Set up notification listeners
  static Future<void> startListeningNotificationEvents() async {
    print('🔔 [NOTIFICATION] Setting up listeners...');
    AwesomeNotifications().setListeners(
      onActionReceivedMethod: onActionReceivedMethod,
      onNotificationCreatedMethod: onNotificationCreatedMethod,
      onNotificationDisplayedMethod: onNotificationDisplayedMethod,
      onDismissActionReceivedMethod: onDismissActionReceivedMethod,
    );
    print('🔔 [NOTIFICATION] Listeners set up successfully');

    if (!_firebaseMessagingListenersReady) {
      _firebaseMessagingListenersReady = true;

      // Foreground messages: show a local notification so the user still sees it.
      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        await handleRemoteMessage(message, reason: 'onMessage');
      });

      // When a user taps a system notification (app in background).
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
        _log('🔔 Notification opened (background): hasData=${message.data.isNotEmpty}');
        // TODO: Implement navigation using message.data
      });

      // When app is launched by tapping a system notification (terminated/cold start).
      try {
        final initialMessage = await _messaging.getInitialMessage();
        if (initialMessage != null) {
          _log(
              '🔔 App opened from notification (terminated): hasData=${initialMessage.data.isNotEmpty}');
          // TODO: Implement navigation using initialMessage.data
        }
      } catch (_) {}

      // Keep token updated.
      _messaging.onTokenRefresh.listen((newToken) async {
        await fcmTokenHandle(newToken);
      });
    }
  }

  /// Request notification permissions
  static Future<bool> requestNotificationPermissions() async {
    print('🔔 [NOTIFICATION] Checking notification permissions...');
    bool isAllowed = await AwesomeNotifications().isNotificationAllowed();
    print('🔔 [NOTIFICATION] Current permission status: $isAllowed');

    if (!isAllowed) {
      print('🔔 [NOTIFICATION] Requesting permissions...');
      isAllowed =
          await AwesomeNotifications().requestPermissionToSendNotifications(
        permissions: [
          NotificationPermission.Alert,
          NotificationPermission.Sound,
          NotificationPermission.Badge,
          NotificationPermission.Vibration,
          NotificationPermission.Light,
        ],
      );
      print('🔔 [NOTIFICATION] Permission request result: $isAllowed');
    }
    return isAllowed;
  }

  /// Request FCM token
  static Future<String?> requestFirebaseToken() async {
    print('🔔 [NOTIFICATION] Requesting FCM token...');
    try {
      // iOS/macOS: request permission (Android handled via POST_NOTIFICATIONS).
      try {
        final settings = await _messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        _log('🔔 FirebaseMessaging permission: ${settings.authorizationStatus}');
      } catch (_) {}

      final token = await _messaging.getToken();
      if (token != null && token.isNotEmpty) {
        fcmToken = token;
        await _saveFcmToken(token);
        print('');
        print('═══════════════════════════════════════════════════════════');
        print('🔑 FCM TOKEN OBTAINED SUCCESSFULLY');
        print('═══════════════════════════════════════════════════════════');
        print('$token');
        print('═══════════════════════════════════════════════════════════');
        print('');

        // Best-effort: if user is already signed in, register this device token
        // with the backend immediately. This covers the "returning user" case
        // where auth was restored before the FCM token existed.
        await registerDeviceWithStoredJwt(reason: 'requestFirebaseToken');
        return token;
      } else {
        print('❌ [NOTIFICATION] Token is null or empty!');
        return null;
      }
    } catch (e, stackTrace) {
      print('❌ [NOTIFICATION] Error requesting FCM token: $e');
      print('❌ [NOTIFICATION] Stack trace: $stackTrace');
      return null;
    }
  }

  /// Save FCM token to local storage
  static Future<void> _saveFcmToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_fcmTokenKey, token);
      print('🔔 [NOTIFICATION] Token saved to storage');
    } catch (e) {
      print('❌ [NOTIFICATION] Error saving FCM token: $e');
    }
  }

  /// Load FCM token from local storage
  static Future<String?> loadFcmToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      fcmToken = prefs.getString(_fcmTokenKey);
      print(
          '🔔 [NOTIFICATION] Token loaded from storage: ${fcmToken != null ? "exists" : "null"}');
      return fcmToken;
    } catch (e) {
      print('❌ [NOTIFICATION] Error loading FCM token: $e');
      return null;
    }
  }

  /// Handle FCM token changes
  @pragma("vm:entry-point")
  static Future<void> fcmTokenHandle(String token) async {
    print('');
    print('═══════════════════════════════════════════════════════════');
    print('🔄 FCM TOKEN REFRESHED');
    print('═══════════════════════════════════════════════════════════');
    print('$token');
    print('═══════════════════════════════════════════════════════════');
    print('');
    fcmToken = token;
    await _saveFcmToken(token);

    // Best-effort: register refreshed token with backend (if signed in).
    // Note: this may run while app is in background; failures are safe to ignore.
    await registerDeviceWithStoredJwt(reason: 'fcmTokenHandle');
  }

  /// Best-effort helper to register the current FCM token with the backend
  /// using the persisted JWT (if available). Uses `debugPrint` (not `print`)
  /// so logs are still visible even when `print()` is silenced by zones.
  static Future<void> registerDeviceWithStoredJwt({required String reason}) async {
    if (_deviceRegisterInFlight) {
      _log('🔔 Device register skipped (in-flight). reason=$reason');
      return;
    }
    _deviceRegisterInFlight = true;
    try {
      // Ensure we have an in-memory FCM token if it was persisted previously.
      await _hydrateFcmTokenFromPrefsIfNeeded();

      final jwt = await TokenStorage.getToken();
      if (jwt == null || jwt.isEmpty) {
        _log('🔔 Device register skipped (no JWT). reason=$reason');
        return;
      }
      if (fcmToken == null || fcmToken!.isEmpty) {
        _log('🔔 Device register skipped (no FCM token). reason=$reason');
        return;
      }

      _log('🔔 Attempting backend device register. reason=$reason');
      await registerDevice(jwt);
    } catch (e) {
      _log('❌ Device register helper error. reason=$reason error=$e');
    } finally {
      _deviceRegisterInFlight = false;
    }
  }

  static Future<void> _hydrateFcmTokenFromPrefsIfNeeded() async {
    try {
      if (fcmToken != null && fcmToken!.isNotEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_fcmTokenKey);
      if (stored != null && stored.isNotEmpty) {
        fcmToken = stored;
      }
    } catch (_) {
      // ignore
    }
  }

  /// Convert a `RemoteMessage` into a local notification (foreground + data-only pushes).
  @pragma('vm:entry-point')
  static Future<void> handleRemoteMessage(
    RemoteMessage message, {
    required String reason,
  }) async {
    try {
      // Avoid duplicate notifications when app is background/terminated:
      // - If the message contains a `notification` payload, Android will display it automatically.
      // - We only create a local notification ourselves for foreground messages OR data-only pushes.
      if (reason == 'onBackgroundMessage' && message.notification != null) {
        _log(
          '🔕 Skipping local notification (system will display). reason=$reason',
        );
        return;
      }

      final title =
          message.notification?.title ?? (message.data['title']?.toString());
      final body =
          message.notification?.body ?? (message.data['body']?.toString());

      // Avoid creating empty notifications.
      if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
        _log('🔕 Remote message ignored (no title/body). reason=$reason');
        return;
      }

      final payload = <String, String>{};
      message.data.forEach((k, v) => payload[k] = v.toString());

      // Channel key is OPTIONAL. If none (or unknown), we always fall back.
      final requestedChannelKey =
          (message.data['channelKey'] ?? message.data['channel_key'])?.toString();
      final channelKey = (requestedChannelKey != null &&
              requestedChannelKey.isNotEmpty &&
              _knownChannelKeys.contains(requestedChannelKey))
          ? requestedChannelKey
          : _defaultChannelKey;

      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
          channelKey: channelKey,
          title: title,
          body: body,
          payload: payload.isEmpty ? null : payload,
          category: NotificationCategory.Message,
          wakeUpScreen: true,
        ),
      );
    } catch (e) {
      _log('❌ Failed to create local notification. reason=$reason error=$e');
    }
  }

  /// Notification was created
  @pragma("vm:entry-point")
  static Future<void> onNotificationCreatedMethod(
    ReceivedNotification receivedNotification,
  ) async {
    print('');
    print('═══════════════════════════════════════════════════════════');
    print('📬 NOTIFICATION CREATED');
    print('═══════════════════════════════════════════════════════════');
    print('ID: ${receivedNotification.id}');
    print('Title: ${receivedNotification.title}');
    print('Body: ${receivedNotification.body}');
    print('Channel: ${receivedNotification.channelKey}');
    print('Payload: ${receivedNotification.payload}');
    print('═══════════════════════════════════════════════════════════');
    print('');
  }

  /// Notification was displayed (FOREGROUND)
  @pragma("vm:entry-point")
  static Future<void> onNotificationDisplayedMethod(
    ReceivedNotification receivedNotification,
  ) async {
    print('');
    print('═══════════════════════════════════════════════════════════');
    print('📭 NOTIFICATION DISPLAYED (FOREGROUND)');
    print('═══════════════════════════════════════════════════════════');
    print('ID: ${receivedNotification.id}');
    print('Title: ${receivedNotification.title}');
    print('Body: ${receivedNotification.body}');
    print('Channel: ${receivedNotification.channelKey}');
    print('═══════════════════════════════════════════════════════════');
    print('');
  }

  /// Notification was dismissed
  @pragma("vm:entry-point")
  static Future<void> onDismissActionReceivedMethod(
    ReceivedAction receivedAction,
  ) async {
    print('');
    print('═══════════════════════════════════════════════════════════');
    print('🗑️ NOTIFICATION DISMISSED');
    print('═══════════════════════════════════════════════════════════');
    print('ID: ${receivedAction.id}');
    print('═══════════════════════════════════════════════════════════');
    print('');
  }

  /// Notification action was received (user tapped notification)
  @pragma("vm:entry-point")
  static Future<void> onActionReceivedMethod(
    ReceivedAction receivedAction,
  ) async {
    print('');
    print('═══════════════════════════════════════════════════════════');
    print('👆 NOTIFICATION TAPPED');
    print('═══════════════════════════════════════════════════════════');
    print('ID: ${receivedAction.id}');
    print('Action Type: ${receivedAction.actionType}');
    print('Title: ${receivedAction.title}');
    print('Body: ${receivedAction.body}');
    print('Payload: ${receivedAction.payload}');
    print('═══════════════════════════════════════════════════════════');
    print('');

    // Handle notification tap
    if (receivedAction.payload != null) {
      final payload = receivedAction.payload!;
      print('🔔 [NOTIFICATION] Processing payload: $payload');

      // TODO: Implement navigation based on payload
      // Example:
      // if (payload['type'] == 'chat') {
      //   // Navigate to chat screen
      // } else if (payload['type'] == 'order') {
      //   // Navigate to order details screen
      // }
    }
  }

  /// Show a local notification (for testing)
  static Future<void> showLocalNotification({
    required int id,
    required String title,
    required String body,
    String? summary,
    Map<String, String>? payload,
    NotificationLayout layout = NotificationLayout.Default,
    String channelKey = 'basic_channel',
  }) async {
    print('🔔 [NOTIFICATION] Creating local notification: $title');
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: id,
        channelKey: channelKey,
        title: title,
        body: body,
        summary: summary,
        payload: payload,
        notificationLayout: layout,
        category: NotificationCategory.Message,
        wakeUpScreen: true,
        criticalAlert: false,
      ),
    );
    print('🔔 [NOTIFICATION] Local notification created');
  }

  /// Subscribe to FCM topic
  static Future<void> subscribeToTopic(String topic) async {
    try {
      print('🔔 [NOTIFICATION] Subscribing to topic: $topic');
      await _messaging.subscribeToTopic(topic);
      print('✅ [NOTIFICATION] Subscribed to topic: $topic');
    } catch (e) {
      print('❌ [NOTIFICATION] Error subscribing to topic: $e');
    }
  }

  /// Get initial notification action (if app was opened from notification)
  static Future<ReceivedAction?> getInitialNotificationAction() async {
    final action = await AwesomeNotifications().getInitialNotificationAction(
      removeFromActionEvents: true,
    );
    if (action != null) {
      print('🔔 [NOTIFICATION] App opened from notification: ${action.id}');
    }
    return action;
  }

  /// Test method to verify notifications are working
  static Future<void> testLocalNotification() async {
    print('🔔 [NOTIFICATION] Sending test notification...');
    await showLocalNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: 'Test Notification',
      body: 'If you see this, local notifications are working!',
      payload: {'test': 'true'},
    );
  }

  /// Register device with backend
  static Future<void> registerDevice(String? jwt) async {
    if (jwt == null || jwt.isEmpty) return;
    final token = fcmToken;
    if (token == null || token.isEmpty) {
      _log('⚠️ Cannot register device: no FCM token available');
      return;
    }

    try {
      _log('🔔 Registering device with backend...');
      final uri = Uri.parse('$API_BASE_URL/api/devices/register');
      final body = jsonEncode({
        'token': token,
        'platform':
            'flutter', // or Platform.operatingSystem if you want more specific
      });

      final resp = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $jwt',
          'Content-Type': 'application/json',
        },
        body: body,
      );

      _log('🔔 Register device response: HTTP ${resp.statusCode}');
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        _log('✅ Device registered successfully');
      } else {
        // Avoid logging response bodies to the terminal (can contain sensitive data).
        _log('❌ Failed to register device (HTTP ${resp.statusCode})');
      }
    } catch (e) {
      _log('❌ Error registering device: $e');
    }
  }

  /// Unregister device from backend
  static Future<void> unregisterDevice(String? jwt) async {
    if (jwt == null || jwt.isEmpty) return;
    final token = fcmToken;
    if (token == null) return; // Nothing to unregister if we don't have a token

    try {
      print('🔔 [NOTIFICATION] Unregistering device from backend...');
      final uri = Uri.parse('$API_BASE_URL/api/devices/unregister');
      final body = jsonEncode({
        'token': token,
      });

      final resp = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $jwt',
          'Content-Type': 'application/json',
        },
        body: body,
      );

      print('🔔 [NOTIFICATION] Unregister device response: ${resp.statusCode}');
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        print('✅ [NOTIFICATION] Device unregistered successfully');
      }
    } catch (e) {
      // Fail silently for unregister
      print('⚠️ [NOTIFICATION] Error unregistering device: $e');
    }
  }

  /// Dispose notification resources
  static Future<void> dispose() async {
    print('🔔 [NOTIFICATION] Disposing...');
    await AwesomeNotifications().dispose();
  }
}
