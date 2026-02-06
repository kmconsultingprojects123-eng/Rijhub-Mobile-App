// API base URL configuration.
// This file chooses a sensible default per platform for development:
// - Android emulator: use 10.0.2.2 to reach the host machine.
// - iOS simulator / macOS: use localhost.
// - Web / other: fall back to a configured LAN IP.
// You can override at runtime by setting the environment variable
// `API_BASE_URL_OVERRIDE` (useful for CI or temporary testing).

import 'package:flutter/foundation.dart' show kIsWeb;

final String API_BASE_URL = () {
  // Allow explicit override using dart-define or environment
  const envKey = 'API_BASE_URL_OVERRIDE';
  // When building/running you can pass: --dart-define=API_BASE_URL_OVERRIDE=https://myhost:5000
  final override = const String.fromEnvironment(envKey);
  if (override.isNotEmpty) return override;

  // Platform-specific defaults: use the server IP you provided (LAN IP)
  // Your backend host is running at https://rijhub.com
  // so we default all platforms to that host to make local testing straightforward.
  if (kIsWeb) return 'https://rijhub.com';
  try {
    // For emulators/simulators running on your dev machine, use the LAN IP
    // since the backend is on a different PC on the same network.
    return 'https://rijhub.com';
    // return 'https://rijhub.com/';
  } catch (e) {
    // If Platform is not available for some reason, use the LAN IP anyway
    return 'https://rijhub.com';
  }
}();

// Cloudinary configuration (optional). Set via --dart-define when building/running.
const _cloudNameKey = 'CLOUDINARY_CLOUD_NAME';
const _uploadPresetKey = 'CLOUDINARY_UPLOAD_PRESET';

final String CLOUDINARY_CLOUD_NAME =
    const String.fromEnvironment(_cloudNameKey);
final String CLOUDINARY_UPLOAD_PRESET =
    const String.fromEnvironment(_uploadPresetKey);

// Example: flutter run --dart-define=API_BASE_URL_OVERRIDE=http://10.85.1.119:5000
// Note: you can override at runtime using --dart-define if you need to point to a different host.

// Google OAuth configuration. The Web Client ID is required on Android to get ID tokens.
// Obtain this from Google Cloud Console > APIs & Services > Credentials > OAuth 2.0 Client IDs (Web client)
// Pass via: flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=<your-web-client-id>.apps.googleusercontent.com
const _googleWebClientIdKey = 'GOOGLE_WEB_CLIENT_ID';
const _defaultGoogleWebClientId =
    '174728322654-6ldaocoj4idarkp03jvd5feppfgp96m2.apps.googleusercontent.com';
final String? GOOGLE_WEB_CLIENT_ID = () {
  final value = const String.fromEnvironment(_googleWebClientIdKey);
  return value.isNotEmpty ? value : _defaultGoogleWebClientId;
}();
