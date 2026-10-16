import 'dart:convert';

import 'api_client.dart';

class AnnouncementService {
  static String? _cached;

  /// Attempts to fetch a marquee/announcement text from several common endpoints.
  /// Returns null if none available.
  static Future<String?> getMarqueeText() async {
    if (_cached != null) return _cached;

    final base = const String.fromEnvironment('API_BASE_URL', defaultValue: '');
    // If API_BASE_URL env var not set at compile time, rely on runtime config elsewhere.
    // We'll try common endpoints in order. You can add/remove based on your backend.
    final endpoints = [
      if (base.isNotEmpty) '$base/api/announcements/latest',
      if (base.isNotEmpty) '$base/api/announcements',
      if (base.isNotEmpty) '$base/api/ads/marquee',
      if (base.isNotEmpty) '$base/api/meta/announcements',
      // fallback to absolute fallback: no network
    ];

    for (final url in endpoints) {
      try {
        final resp = await ApiClient.get(url, headers: {'Content-Type': 'application/json'});
        final status = resp['status'] as int? ?? 0;
        final body = resp['body']?.toString() ?? '';
        if (status >= 200 && status < 300 && body.isNotEmpty) {
          try {
            final decoded = jsonDecode(body);
            // common shapes: { success: true, data: { text: '...' } }
            if (decoded is Map) {
              if (decoded['data'] is String) {
                _cached = decoded['data'] as String;
                return _cached;
              }
              if (decoded['data'] is Map && (decoded['data']['text'] is String || decoded['data']['message'] is String)) {
                _cached = decoded['data']['text']?.toString() ?? decoded['data']['message']?.toString();
                return _cached;
              }
              if (decoded['message'] is String) {
                _cached = decoded['message'] as String;
                return _cached;
              }
              // if data is array, try first element's text
              if (decoded['data'] is List && (decoded['data'] as List).isNotEmpty) {
                final first = decoded['data'][0];
                if (first is Map && (first['text'] is String || first['message'] is String)) {
                  _cached = first['text']?.toString() ?? first['message']?.toString();
                  return _cached;
                }
                if (first is String) {
                  _cached = first;
                  return _cached;
                }
              }
            }
            // If response body is a plain string
            if (decoded is String) {
              _cached = decoded;
              return _cached;
            }
          } catch (e) {
            // ignore JSON parse errors and try next endpoint
          }
        }
      } catch (e) {
        // Try next endpoint
      }
    }

    return null;
  }
}

