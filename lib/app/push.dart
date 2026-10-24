import 'dart:async';
import 'dart:io' show Platform;

import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

/// Permission to show notifications, asked for once, at a moment it's
/// plainly useful (a booking just sent), never up front.
abstract interface class PushPermission {
  /// Whether notifications are already allowed.
  Future<bool> granted();

  /// Asks; true when allowed.
  Future<bool> request();
}

/// The phone's own permission.
class DevicePushPermission implements PushPermission {
  @override
  Future<bool> granted() async {
    try {
      return (await Permission.notification.status).isGranted;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> request() async {
    try {
      return (await Permission.notification.request()).isGranted;
    } on Object {
      return false;
    }
  }
}

/// For tests and screenshots: says yes when asked.
class SamplePushPermission implements PushPermission {
  SamplePushPermission({this.allowed = false});

  bool allowed;

  @override
  Future<bool> granted() async => allowed;

  @override
  Future<bool> request() async => allowed = true;
}

/// Push notifications through Firebase Cloud Messaging, for the app on the
/// RijHub API. Asking stays with [permission]. Once someone is signed in and
/// has allowed notifications, this phone's token goes to the server through
/// [register]: on every launch, and whenever Firebase changes it. Tapping a
/// notification opens the screen it's about.
class FirebasePush implements PushPermission {
  FirebasePush({
    required this.permission,
    required this.register,
    required this.signedIn,
    required this.navigator,
  });

  final PushPermission permission;
  final Future<void> Function(String token, {required String platform})
      register;
  final Future<bool> Function() signedIn;
  final GlobalKey<NavigatorState> navigator;

  bool _started = false;

  /// The one in use, for taps on the banners it shows.
  static FirebasePush? _current;

  /// Listens for new tokens, pushes and opened notifications, then
  /// registers this phone if it can. Needs Firebase started; without it
  /// push stays off.
  Future<void> start() async {
    if (_started || Firebase.apps.isEmpty) return;
    _started = true;
    _current = this;
    try {
      final messaging = FirebaseMessaging.instance;
      messaging.onTokenRefresh.listen((_) => unawaited(sync()));
      // Firebase shows nothing while the app is open: the banner is ours.
      FirebaseMessaging.onMessage.listen((m) => unawaited(_foreground(m)));
      FirebaseMessaging.onMessageOpenedApp
          .listen((m) => unawaited(_open(appRouteOf(m.data))));
      final first = await messaging.getInitialMessage();
      if (first != null) unawaited(_open(appRouteOf(first.data)));
      await AwesomeNotifications()
          .setListeners(onActionReceivedMethod: _bannerTapped);
    } on Object {
      // Push stays off; the rest of the app carries on.
    }
    await sync();
  }

  /// A push while the app is open: shown as a banner, like one that came
  /// while it was closed. Not for the chat it's about when that's on screen,
  /// where the message has already appeared.
  Future<void> _foreground(RemoteMessage message) async {
    final route = appRouteOf(message.data);
    final title = message.notification?.title ?? message.data['title'];
    final body = message.notification?.body ?? message.data['body'];
    if (title is! String || !showsBanner(route, openChat: OpenChat.id)) return;
    try {
      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          // Positive and 31-bit; a clash only replaces an older banner.
          id: DateTime.now().millisecondsSinceEpoch.remainder(1 << 31),
          channelKey: LocalBanners.channel,
          title: title,
          body: body is String ? body : null,
          payload: {'route': route},
          category: message.data['kind'] == 'message'
              ? NotificationCategory.Message
              : NotificationCategory.Event,
          wakeUpScreen: true,
        ),
      );
    } on Object {
      // No banner, but the screens still update live.
    }
  }

  @pragma('vm:entry-point')
  static Future<void> _bannerTapped(ReceivedAction action) async {
    await _current?._open(action.payload?['route']);
  }


  /// Sends this phone's token to the server when someone is signed in and
  /// notifications are allowed. Safe to call any time; never throws.
  Future<void> sync() async {
    if (!_started) return;
    try {
      if (!await signedIn() || !await permission.granted()) return;
      final token = await _token();
      if (token != null) {
        await register(token, platform: Platform.isIOS ? 'ios' : 'android');
      }
    } on Object {
      // Offline, or Firebase unavailable: the next launch tries again.
    }
  }

  Future<String?> _token() async {
    final messaging = FirebaseMessaging.instance;
    if (Platform.isIOS) {
      // Firebase needs Apple's token first, which can take a moment.
      for (var i = 0; i < 10 && await messaging.getAPNSToken() == null; i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    return messaging.getToken();
  }

  Future<void> _open(String? route) async {
    if (route == null) return;
    // Opened from a notification at launch: wait for the first screen.
    for (var i = 0; i < 50 && navigator.currentContext == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final context = navigator.currentContext;
    if (context != null && context.mounted) {
      unawaited(GoRouter.of(context).push(route));
    }
  }

  @override
  Future<bool> granted() => permission.granted();

  @override
  Future<bool> request() async {
    final allowed = await permission.request();
    if (allowed) unawaited(sync());
    return allowed;
  }
}

/// The screen a notification opens. The server sends an in-app path, such
/// as `/booking/<id>`; anything else (a web address, nothing) is ignored.
String? appRouteOf(Map<String, dynamic> data) {
  final route = data['route'];
  if (route is! String || !route.startsWith('/') || route.startsWith('//')) {
    return null;
  }
  return route;
}

/// The conversation on screen, if any (the chat screen keeps it), so its
/// own messages, which appear in it at once, get no banner.
abstract final class OpenChat {
  static String? id;
}

/// Whether a push for [route] gets a banner while the app is open: always,
/// except a message for [openChat], the conversation on screen.
bool showsBanner(String? route, {required String? openChat}) =>
    route == null || openChat == null || route != '/chat/$openChat';

/// The banners the app shows itself, for pushes that come while it's open.
/// [channel] is the one every push names (see the API's notifications.py);
/// MainActivity creates it too, for pushes Android shows by itself.
abstract final class LocalBanners {
  static const channel = 'default';

  /// Sets the channel up. Asks for no permission: that waits for a moment
  /// it's plainly useful (see [PushPermission]).
  static Future<void> init() async {
    try {
      await AwesomeNotifications().initialize(
        'resource://drawable/ic_stat_employi',
        [
          NotificationChannel(
            channelKey: channel,
            channelName: 'Bookings and messages',
            channelDescription: 'Requests, bookings, payments and messages',
            defaultColor: const Color(0xFFA20025),
            ledColor: const Color(0xFFA20025),
            importance: NotificationImportance.High,
            channelShowBadge: true,
            playSound: true,
            enableVibration: true,
          ),
        ],
      );
    } on Object {
      // Pushes still come while the app is closed; banners are extra.
    }
  }
}

/// Firebase shows background and closed-app pushes by itself; it only
/// needs a handler registered (in main) to deliver them.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundMessage(RemoteMessage message) async {}
