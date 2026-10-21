import 'dart:async';
import 'dart:io' show Platform;

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

  /// Listens for new tokens and opened notifications, then registers this
  /// phone if it can. Needs Firebase started; without it push stays off.
  Future<void> start() async {
    if (_started || Firebase.apps.isEmpty) return;
    _started = true;
    try {
      final messaging = FirebaseMessaging.instance;
      messaging.onTokenRefresh.listen((_) => unawaited(sync()));
      FirebaseMessaging.onMessageOpenedApp.listen((m) => unawaited(_open(m)));
      final first = await messaging.getInitialMessage();
      if (first != null) unawaited(_open(first));
    } on Object {
      // Push stays off; the rest of the app carries on.
    }
    await sync();
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

  Future<void> _open(RemoteMessage message) async {
    final route = appRouteOf(message.data);
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
