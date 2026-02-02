import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class LocationPermissionService {
  /// Ensure the app has location services enabled and permissions granted.
  /// Shows dialogs to guide the user to enable services or grant permissions.
  static Future<bool> ensureLocationPermissions(BuildContext context, {bool forcePrompt = false}) async {
    try {
      // First check if location services are enabled at device level
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // Ask the user to enable location services
        final enable = await _showEnableLocationDialog(context);
        if (enable == true) {
          await Geolocator.openLocationSettings();
          // Give the user a moment, then re-check
          serviceEnabled = await Geolocator.isLocationServiceEnabled();
          if (!serviceEnabled) return false;
        } else {
          return false;
        }
      }

      // Check permission status
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || (permission == LocationPermission.deniedForever && forcePrompt)) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        // Denied by user, show a rationale dialog
        await _showPermissionDeniedDialog(context);
        return false;
      }

      if (permission == LocationPermission.deniedForever) {
        // Denied permanently, ask user to open app settings
        final open = await _showOpenAppSettingsDialog(context);
        if (open == true) await Geolocator.openAppSettings();
        return false;
      }

      // At this point permission should be allowed
      if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
        return true;
      }

      // Fallback: request permission again
      final perm2 = await Geolocator.requestPermission();
      return perm2 == LocationPermission.always || perm2 == LocationPermission.whileInUse;
    } catch (e) {
      // In case of any unexpected error, return false
      return false;
    }
  }

  static Future<bool?> _showEnableLocationDialog(BuildContext context) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          title: Text('Enable location services'),
          content: Text('To use this app please enable location services on your device.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Not now', style: TextStyle(color: theme.colorScheme.primary)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('Open settings'),
            ),
          ],
        );
      },
    );
  }

  static Future<void> _showPermissionDeniedDialog(BuildContext context) async {
    try {
      final theme = Theme.of(context);
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => AlertDialog(
          title: Text('Location permission required'),
          content: Text('This app requires location permission to work properly. Please grant location permission.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('OK', style: TextStyle(color: theme.colorScheme.primary)),
            )
          ],
        ),
      );
    } catch (_) {}
  }

  static Future<bool?> _showOpenAppSettingsDialog(BuildContext context) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          title: Text('Location permission blocked'),
          content: Text('Location permission is permanently denied. Open app settings to enable it.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel', style: TextStyle(color: theme.colorScheme.primary)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('Open settings'),
            ),
          ],
        );
      },
    );
  }
}

