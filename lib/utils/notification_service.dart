import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

/// Centralized notification wrapper. Currently uses ScaffoldMessenger under the hood,
/// but callers should use this service so we can swap to a different plugin later.
class NotificationService {
  static void showSuccess(BuildContext context, String message, {Duration duration = const Duration(seconds: 3)}) {
    _showSnackBar(context, message, backgroundColor: Colors.green.shade600, duration: duration);
  }

  static void showError(BuildContext context, String message, {Duration duration = const Duration(seconds: 4)}) {
    _showSnackBar(context, message, backgroundColor: Colors.red.shade700, duration: duration);
  }

  static void showInfo(BuildContext context, String message, {Duration duration = const Duration(seconds: 3)}) {
    _showSnackBar(context, message, backgroundColor: Colors.grey.shade800, duration: duration);
  }

  static void _showSnackBar(BuildContext context, String message, {Color? backgroundColor, Duration duration = const Duration(seconds: 3)}) {
    try {
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: duration,
      ));
    } catch (e) {
      // If showing via ScaffoldMessenger fails (context not ready), try a fallback: debug-only print
      if (kDebugMode) debugPrint('NotificationService: failed to show snack: $e');
    }
  }
}
