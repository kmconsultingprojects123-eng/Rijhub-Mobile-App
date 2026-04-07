import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show rootBundle;

/// Simple location lookup using OpenStreetMap's Nominatim API.
/// Note: Nominatim is free but rate-limited. For production use consider a paid
/// geocoding provider or caching results on your backend.
class LocationService {
  /// Geocode a place name (e.g. "Kubwa, Abuja, Nigeria") and return a map
  /// { 'lat': double, 'lon': double, 'displayName': string } or null on failure.
  static Future<Map<String, dynamic>?> geocodePlace(String place, {int limit = 1}) async {
    if (place.trim().isEmpty) return null;
    final q = Uri.encodeQueryComponent(place);
    final url = 'https://nominatim.openstreetmap.org/search?q=$q&format=json&limit=$limit&addressdetails=1';
    try {
      final resp = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'rijhub-app/1.0 (+https://example.com)',
        'Accept-Language': 'en'
      }).timeout(Duration(seconds: 10));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final body = resp.body;
        if (body.isEmpty) return null;
        final json = jsonDecode(body);
        if (json is List && json.isNotEmpty) {
          final item = json.first;
          final lat = double.tryParse(item['lat']?.toString() ?? '');
          final lon = double.tryParse(item['lon']?.toString() ?? '');
          final display = item['display_name']?.toString() ?? place;
          // boundingbox comes as [south, north, west, east]
          List<double>? bbox;
          try {
            if (item['boundingbox'] is List) {
              final bb = (item['boundingbox'] as List).map((e) => double.tryParse(e?.toString() ?? '')).where((e) => e != null).map((e) => e!).toList();
              if (bb.length == 4) bbox = bb;
            }
          } catch (_) {}
          if (lat != null && lon != null) {
            final res = {'lat': lat, 'lon': lon, 'displayName': display};
            if (bbox != null) res['boundingbox'] = bbox;
            return res;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  // --- Helpers for Nigeria states/LGAs ---
  // Optional cached data loaded from asset (assets/jsons/nigeria_states_lgas.json)
  static Map<String, List<String>>? _assetNigeriaData;

  static Future<void> _loadNigeriaDataFromAsset() async {
    if (_assetNigeriaData != null) return;
    try {
      final s = await rootBundle.loadString('assets/jsons/nigeria_states_lgas.json');
      final jsonMap = jsonDecode(s) as Map<String, dynamic>;
      final mapped = <String, List<String>>{};
      jsonMap.forEach((k, v) {
        if (v is List) mapped[k] = v.map((e) => e.toString()).toList();
      });
      _assetNigeriaData = mapped;
    } catch (_) {
      // asset not present or failed to parse — leave null to fall back to built-in map
      _assetNigeriaData = null;
    }
  }

  /// Allowed (and only supported) country/state for now.
  static const String allowedCountry = 'Nigeria';
  static const String allowedState = 'Abuja FCT';
  static const List<String> _abujaLgas = [
    'Abaji',
    'Abuja Municipal',
    'Bwari',
    'Gwagwalada',
    'Kuje',
    'Kwali',
  ];

  /// Minimal hardcoded dataset for Nigeria states (restricted to Abuja FCT only).
  static const Map<String, List<String>> _nigeriaData = {
    allowedState: _abujaLgas,
  };

  /// Returns the list of Nigeria states. Prefers asset data if present, otherwise uses the static dataset.
  /// NOTE: will only return the configured allowed state (Abuja FCT).
  static Future<List<String>> fetchNigeriaStates() async {
    // try asset first
    await _loadNigeriaDataFromAsset();
    if (_assetNigeriaData != null && _assetNigeriaData!.isNotEmpty) {
      final keys = _assetNigeriaData!.keys.where((k) => k == allowedState).toList()..sort();
      return keys;
    }
    // fallback
    await Future.delayed(const Duration(milliseconds: 120));
    return [allowedState];
  }

  /// Returns the list of LGAs for the provided `state`. Prefers asset data if present.
  /// NOTE: Only `Abuja FCT` is supported. Other states return an empty list.
  static Future<List<String>> fetchNigeriaLgas(String state) async {
    if (state != allowedState) return <String>[];

    await _loadNigeriaDataFromAsset();
    if (_assetNigeriaData != null) {
      final l = _assetNigeriaData![state];
      if (l != null) {
        final copy = List<String>.from(l);
        copy.sort();
        return copy;
      }
      return <String>[];
    }

    await Future.delayed(const Duration(milliseconds: 120));
    final lgas = _nigeriaData[state];
    if (lgas == null) return <String>[];
    final copy = List<String>.from(lgas);
    copy.sort();
    return copy;
  }

  /// Helper to validate that a given country/state/lga is allowed by the client.
  static bool isAllowedLocation({required String country, required String state, required String lga}) {
    if (country.trim().toLowerCase() != allowedCountry.toLowerCase()) return false;
    if (state.trim() != allowedState) return false;
    return _abujaLgas.map((e) => e.toLowerCase()).contains(lga.trim().toLowerCase());
  }

  /// Reverse geocode coordinates (lat, lon) to a human-readable address.
  /// Returns the display name (address) or null on failure.
  static Future<String?> reverseGeocode(double latitude, double longitude) async {
    final url = 'https://nominatim.openstreetmap.org/reverse?format=json&lat=$latitude&lon=$longitude&zoom=18&addressdetails=1';
    try {
      final resp = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'rijhub-app/1.0 (+https://example.com)',
        'Accept-Language': 'en'
      }).timeout(Duration(seconds: 10));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final body = resp.body;
        if (body.isEmpty) return null;
        final json = jsonDecode(body);
        if (json is Map) {
          final displayName = json['display_name']?.toString();
          return displayName;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Detects if a string contains coordinates (lat,lon or lat lon format) and attempts
  /// to reverse geocode them. If successful, returns the human-readable address.
  /// If it's not a coordinate string or geocoding fails, returns the original string.
  static Future<String> getHumanReadableLocation(String? locationStr) async {
    if (locationStr == null || locationStr.trim().isEmpty) return 'Unknown location';

    final trimmed = locationStr.trim();

    // Pattern 1: "lat,lon" (e.g., "6.5244,-7.4895")
    // Pattern 2: "lat lon" (e.g., "6.5244 -7.4895")
    // Pattern 3: "{lat: x, lon: y}" JSON format
    double? lat, lon;

    // Try comma-separated format first
    if (trimmed.contains(',') && !trimmed.contains('{')) {
      final parts = trimmed.split(',');
      if (parts.length == 2) {
        lat = double.tryParse(parts[0].trim());
        lon = double.tryParse(parts[1].trim());
      }
    }

    // Try space-separated format
    if (lat == null && lon == null && !trimmed.contains('{')) {
      final parts = trimmed.split(' ');
      if (parts.length >= 2) {
        lat = double.tryParse(parts[0].trim());
        lon = double.tryParse(parts[1].trim());
      }
    }

    // Try JSON-like format {lat: x, lon: y}
    if (lat == null && lon == null && trimmed.contains('{')) {
      try {
        final jsonMatch = RegExp(r'"?lat"?\s*:\s*([\d.-]+).*?"?lon"?\s*:\s*([\d.-]+)', dotAll: true).firstMatch(trimmed);
        if (jsonMatch != null) {
          lat = double.tryParse(jsonMatch.group(1)!);
          lon = double.tryParse(jsonMatch.group(2)!);
        }
      } catch (_) {}
    }

    // If we extracted coordinates, attempt to reverse geocode
    if (lat != null && lon != null && lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180) {
      try {
        final address = await reverseGeocode(lat, lon);
        if (address != null && address.isNotEmpty) {
          return address;
        }
      } catch (_) {}
    }

    // Return original string if not coordinates or geocoding failed
    return trimmed;
  }
}
