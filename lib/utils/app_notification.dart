import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

/// Lightweight wrapper for showing snackbars and notifications.
/// Use AppNotification.showSuccess/showError/showInfo across the app.
class AppNotification {
  static void showSuccess(BuildContext context, String message, {Duration duration = const Duration(seconds: 3)}) {
    try {
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          duration: duration,
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('AppNotification.showSuccess failed: $e');
    }
  }

  static void showError(BuildContext context, String message, {Duration duration = const Duration(seconds: 4)}) {
    _show(context, message, Colors.red.shade700, duration);
  }

  static void showInfo(BuildContext context, String message, {Duration duration = const Duration(seconds: 3)}) {
    _show(context, message, Colors.grey.shade800, duration);
  }

  static void _show(BuildContext context, String message, Color backgroundColor, Duration duration) {
    try {
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(message), backgroundColor: backgroundColor, duration: duration));
    } catch (e) {
      if (kDebugMode) debugPrint('AppNotification failed: $e');
    }
  }
}
