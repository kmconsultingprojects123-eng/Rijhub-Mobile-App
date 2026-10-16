// API base URL configuration.
// All values are read from the .env file at the project root via flutter_dotenv.
// Make sure dotenv.load() runs in main() before anything below is read.

import 'package:flutter_dotenv/flutter_dotenv.dart';

final String API_BASE_URL = dotenv.env['API_BASE_URL'] ?? '';

// Google OAuth Web Client ID (required on Android to get ID tokens).
// Set GOOGLE_WEB_CLIENT_ID in .env. The hardcoded fallback below is the
// existing project default and is safe to leave in source.
const _defaultGoogleWebClientId =
    '174728322654-6ldaocoj4idarkp03jvd5feppfgp96m2.apps.googleusercontent.com';
final String? GOOGLE_WEB_CLIENT_ID = () {
  final value = dotenv.env['GOOGLE_WEB_CLIENT_ID'] ?? '';
  return value.isNotEmpty ? value : _defaultGoogleWebClientId;
}();

