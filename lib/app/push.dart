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
