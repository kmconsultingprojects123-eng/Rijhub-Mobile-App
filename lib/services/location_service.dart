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
          if (lat != null && lon != null) return {'lat': lat, 'lon': lon, 'displayName': display};
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
}
