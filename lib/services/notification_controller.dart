import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:awesome_notifications_fcm/awesome_notifications_fcm.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../api_config.dart';

class NotificationController {
  static String? fcmToken;
  static const String _fcmTokenKey = 'fcm_token';

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

    // Initialize FCM
    print('🔔 [NOTIFICATION] Initializing FCM...');
    await AwesomeNotificationsFcm().initialize(
      onFcmSilentDataHandle: silentDataHandle,
      onFcmTokenHandle: fcmTokenHandle,
      onNativeTokenHandle: nativeTokenHandle,
      licenseKeys: null, // Add license keys if you have them
      debug: true,
    );
    print('🔔 [NOTIFICATION] FCM initialized');

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
      // Check if FCM is available
      bool isFirebaseAvailable =
          await AwesomeNotificationsFcm().isFirebaseAvailable;
      print('🔔 [NOTIFICATION] Firebase available: $isFirebaseAvailable');

      if (!isFirebaseAvailable) {
        print('❌ [NOTIFICATION] Firebase is NOT available on this device');
        return null;
      }

      // Request FCM token
      print('🔔 [NOTIFICATION] Calling requestFirebaseAppToken()...');
      String? token = await AwesomeNotificationsFcm().requestFirebaseAppToken();

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
      } else {
        print('❌ [NOTIFICATION] Token is null or empty!');
      }

      return token;
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
  }

  /// Handle native token (APNS for iOS)
  @pragma("vm:entry-point")
  static Future<void> nativeTokenHandle(String token) async {
    print('🍎 [NOTIFICATION] Native Token (APNS): $token');
  }

  /// Handle silent data messages (BACKGROUND PUSH)
  @pragma("vm:entry-point")
  static Future<void> silentDataHandle(FcmSilentData silentData) async {
    print('');
    print('═══════════════════════════════════════════════════════════');
    print('📩 SILENT/BACKGROUND PUSH RECEIVED');
    print('═══════════════════════════════════════════════════════════');
    print('Data: ${silentData.data}');
    print('Created Lifecycle: ${silentData.createdLifeCycle}');
    print('═══════════════════════════════════════════════════════════');
    print('');

    // Handle silent push notification data here
    if (silentData.data != null) {
      // If the data contains notification content, create a local notification
      try {
        final data = silentData.data!;
        print('🔔 [NOTIFICATION] Processing silent data: $data');

        // Check if there's a 'content' field (Awesome Notifications format)
        if (data.containsKey('content')) {
          print(
              '🔔 [NOTIFICATION] Found content field, notification should auto-display');
        }

        // If you want to manually create a notification from silent data:
        // await showLocalNotification(
        //   id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        //   title: data['title'] ?? 'Notification',
        //   body: data['body'] ?? data['message'] ?? '',
        // );
      } catch (e) {
        print('❌ [NOTIFICATION] Error processing silent data: $e');
      }
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
      await AwesomeNotificationsFcm().subscribeToTopic(topic);
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
      print('⚠️ [NOTIFICATION] Cannot register device: No FCM token available');
      return;
    }

    try {
      print('🔔 [NOTIFICATION] Registering device with backend...');
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

      print('🔔 [NOTIFICATION] Register device response: ${resp.statusCode}');
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        print('✅ [NOTIFICATION] Device registered successfully');
      } else {
        print('❌ [NOTIFICATION] Failed to register device: ${resp.body}');
      }
    } catch (e) {
      print('❌ [NOTIFICATION] Error registering device: $e');
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
