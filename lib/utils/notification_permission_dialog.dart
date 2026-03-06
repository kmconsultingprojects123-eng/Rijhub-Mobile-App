import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../flutter_flow/flutter_flow_theme.dart';
import '../services/notification_controller.dart';

const String _kPrePromptShownKey = 'notification_pre_prompt_shown';

/// Shows a friendly pre-permission dialog explaining notification benefits.
/// Only calls the system permission when user taps "Enable".
/// Skips if user already granted, or already declined our pre-prompt.
/// Returns true if user chose Enable, false if Not now or skipped.
Future<bool> showNotificationPermissionDialog(
  BuildContext context, {
  required String role,
}) async {
  // Skip if user already granted (just register device in background)
  final alreadyAllowed = await NotificationController.isNotificationAllowed();
  if (alreadyAllowed) {
    await NotificationController.requestFirebaseToken();
    return true;
  }

  // Skip if user already saw and declined our pre-prompt
  if (!await shouldShowNotificationPrePrompt()) {
    return false;
  }
  final theme = FlutterFlowTheme.of(context);
  final isArtisan = role.toLowerCase().contains('artisan');

  // Role-specific messaging
  final String title = isArtisan
      ? 'Stay on top of your work'
      : 'Never miss an update';
  final String description = isArtisan
      ? 'Get notified when new jobs match your skills, when clients send quotes, and when you receive important messages.'
      : 'Get notified about booking updates, when artisans respond to your quotes, and important messages about your jobs.';

  final completer = Completer<bool>();

  final dialogWidth = min(MediaQuery.of(context).size.width * 0.92, 420.0);

  showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withAlpha((0.4 * 255).round()),
    builder: (ctx) {
      return Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: dialogWidth,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.primaryBackground,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha((0.15 * 255).round()),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: theme.primary.withAlpha((0.12 * 255).round()),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.notifications_active_rounded,
                        color: theme.primary,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        title,
                        style: theme.headlineSmall.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  description,
                  style: theme.bodyMedium.copyWith(
                    color: theme.secondaryText,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _markPrePromptShown();
                        if (!completer.isCompleted) completer.complete(false);
                      },
                      child: Text(
                        'Not now',
                        style: theme.bodyLarge.copyWith(
                          color: theme.secondaryText,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.primary,
                        foregroundColor: theme.onPrimary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                        shadowColor: Colors.transparent,
                      ),
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        // Do NOT mark as shown here — only mark when user taps "Not now".
                        // If they tap Enable but deny/dismiss the OS dialog, we'll ask again next login.
                        if (!completer.isCompleted) completer.complete(true);

                        // Now request system permission and register device
                        await NotificationController.requestNotificationPermissions();
                        await NotificationController.requestFirebaseToken();
                      },
                      child: const Text(
                        'Enable notifications',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  return completer.future;
}

/// Check if we should show the pre-prompt (user hasn't seen it yet this install).
Future<bool> shouldShowNotificationPrePrompt() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_kPrePromptShownKey) ?? false);
  } catch (_) {
    return true;
  }
}

void _markPrePromptShown() {
  SharedPreferences.getInstance().then((prefs) {
    prefs.setBool(_kPrePromptShownKey, true);
  });
}
