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

  /// Minimal hardcoded dataset for Nigeria states and a few LGAs.
  static const Map<String, List<String>> _nigeriaData = {
    'Lagos': ['Ikeja', 'Surulere', 'Epe', 'Eti-Osa', 'Kosofe'],
    'Abia': ['Aba North', 'Aba South', 'Umuahia North', 'Isiala Ngwa North'],
    'Kano': ['Nasarawa', 'Tarauni', 'Gwale', 'Dala'],
    'Rivers': ['Port Harcourt', 'Obio-Akpor', 'Bonny', 'Ogu-Bolo'],
    'Abuja FCT': ['Abuja Municipal', 'Gwagwalada', 'Kwali', 'Kuje'],
    'Anambra': ['Awka South', 'Onitsha North', 'Oyi', 'Nnewi North'],
    'Akwa Ibom': ['Uyo', 'Eket', 'Ikot Ekpene', 'Oron'],
    'Bauchi': ['Bauchi', 'Toro', 'Ningi', 'Darazo'],
    'Benue': ['Makurdi', 'Gboko', 'Buruku', 'Vandeikya'],
    'Borno': ['Maiduguri', 'Jere', 'Bama', 'Dikwa'],
    'Bayelsa': ['Yenagoa', 'Brass', 'Nembe', 'Sagbama'],
    'Cross River': ['Calabar Municipal', 'Odukpani', 'Ikom', 'Bakassi'],
    'Delta': ['Asaba', 'Warri North', 'Sapele', 'Ughelli North'],
    'Edo': ['Benin City', 'Oredo', 'Ovia North-East', 'Ikpoba-Okha'],
    'Ekiti': ['Ado-Ekiti', 'Ikere', 'Ise/Orun', 'Efon'],
    'Enugu': ['Enugu North', 'Enugu South', 'Nsukka', 'Udi'],
    'Gombe': ['Gombe', 'Akko', 'Balanga', 'Yamaltu/Deba'],
    'Imo': ['Owerri North', 'Orlu', 'Okigwe', 'Mbaitoli'],
    'Jigawa': ['Dutse', 'Hadejia', 'Kiyawa', 'Gumel'],
    'Kaduna': ['Kaduna North', 'Kaduna South', 'Zaria', 'Kachia'],
    'Kebbi': ['Birnin Kebbi', 'Argungu', 'Zuru', 'Sakaba'],
    'Kogi': ['Lokoja', 'Okene', 'Ajaokuta', 'Anyigba'],
    'Kwara': ['Ilorin East', 'Ilorin West', 'Offa', 'Edu'],
    'Nasarawa': ['Lafia', 'Akwanga', 'Keffi', 'Doma'],
    'Niger': ['Minna', 'Kontagora', 'Suleja', 'Bida'],
    'Ogun': ['Abeokuta North', 'Abeokuta South', 'Ifo', 'Sagamu'],
    'Ondo': ['Akure South', 'Owo', 'Ikare', 'Ondo West'],
    'Osun': ['Osogbo', 'Ilesa', 'Ife North', 'Ede North'],
    'Oyo': ['Ibadan North', 'Ibadan South-West', 'Ogbomosho', 'Iseyin'],
    'Plateau': ['Jos North', 'Bassa', 'Bokkos', 'Langtang North'],
    'Sokoto': ['Sokoto North', 'Sokoto South', 'Gwadabawa', 'Wurno'],
    'Taraba': ['Jalingo', 'Wukari', 'Ibi', 'Gashaka'],
    'Yobe': ['Damaturu', 'Borsari', 'Yusufari', 'Potiskum'],
    'Zamfara': ['Gusau', 'Talata Mafara', 'Shinkafi', 'Anka'],
  };

  /// Returns the list of Nigeria states. Prefers asset data if present, otherwise uses the static dataset.
  static Future<List<String>> fetchNigeriaStates() async {
    // try asset first
    await _loadNigeriaDataFromAsset();
    if (_assetNigeriaData != null && _assetNigeriaData!.isNotEmpty) {
      final keys = _assetNigeriaData!.keys.toList()..sort();
      return keys;
    }
    // fallback
    await Future.delayed(const Duration(milliseconds: 120));
    return _nigeriaData.keys.toList()..sort();
  }

  /// Returns the list of LGAs for the provided `state`. Prefers asset data if present.
  static Future<List<String>> fetchNigeriaLgas(String state) async {
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
}
