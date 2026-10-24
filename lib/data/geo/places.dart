import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// A point on the map.
@immutable
class GeoPoint {
  const GeoPoint(this.lat, this.lng);

  final double lat;
  final double lng;

  /// Straight-line distance to [other], in km.
  double kmTo(GeoPoint other) {
    double radians(double degrees) => degrees * math.pi / 180;
    final x =
        radians(other.lng - lng) * math.cos(radians((lat + other.lat) / 2));
    final y = radians(other.lat - lat);
    return 6371 * math.sqrt(x * x + y * y);
  }

  /// The point [eastKm] east and [northKm] north of this one.
  GeoPoint offset(double eastKm, double northKm) => GeoPoint(
        lat + northKm / 110.574,
        lng + eastKm / (111.320 * math.cos(lat * math.pi / 180)),
      );
}

/// Where Abuja's districts and neighbourhoods are: rough centres, enough to
/// place people and jobs on a map and to work out distances.
abstract final class AbujaPlaces {
  /// The city centre (Central Business District).
  static const city = GeoPoint(9.0550, 7.4900);

  static const centres = <String, GeoPoint>{
    'Apo': GeoPoint(8.9850, 7.5020),
    'Asokoro': GeoPoint(9.0430, 7.5250),
    'Bwari': GeoPoint(9.2820, 7.3790),
    'Central Business District': GeoPoint(9.0550, 7.4900),
    'Dakibiyu': GeoPoint(9.0530, 7.4130),
    'Dakwo': GeoPoint(8.9830, 7.4640),
    'Dawaki': GeoPoint(9.1230, 7.4300),
    'Dei-Dei': GeoPoint(9.1130, 7.2840),
    'Durumi': GeoPoint(9.0230, 7.4680),
    'Dutse': GeoPoint(9.1450, 7.3950),
    'Galadimawa': GeoPoint(8.9960, 7.4300),
    'Garki': GeoPoint(9.0330, 7.4880),
    'Garki Area 11': GeoPoint(9.0420, 7.4930),
    'Gudu': GeoPoint(9.0080, 7.4780),
    'Guzape': GeoPoint(9.0270, 7.5100),
    'Gwagwalada': GeoPoint(8.9430, 7.0830),
    'Gwarinpa': GeoPoint(9.1100, 7.4060),
    'Idu': GeoPoint(9.0250, 7.3480),
    'Jabi': GeoPoint(9.0660, 7.4230),
    'Jahi': GeoPoint(9.0930, 7.4380),
    'Jikwoyi': GeoPoint(9.0020, 7.5880),
    'Kado': GeoPoint(9.0860, 7.4230),
    'Karmo': GeoPoint(9.0640, 7.3570),
    'Karu': GeoPoint(9.0230, 7.5760),
    'Katampe': GeoPoint(9.1120, 7.4620),
    'Kaura': GeoPoint(8.9990, 7.4560),
    'Kubwa': GeoPoint(9.1560, 7.3280),
    'Kuje': GeoPoint(8.8790, 7.2290),
    'Life Camp': GeoPoint(9.0760, 7.4010),
    'Lokogoma': GeoPoint(8.9800, 7.4480),
    'Lugbe': GeoPoint(8.9760, 7.3800),
    'Mabushi': GeoPoint(9.0800, 7.4500),
    'Maitama': GeoPoint(9.0880, 7.4930),
    'Mpape': GeoPoint(9.1240, 7.4920),
    'Nyanya': GeoPoint(9.0110, 7.5640),
    'Utako': GeoPoint(9.0710, 7.4410),
    'Wuse': GeoPoint(9.0640, 7.4650),
    'Wuse 2': GeoPoint(9.0790, 7.4760),
    'Wuse Market': GeoPoint(9.0660, 7.4620),
    'Wuye': GeoPoint(9.0610, 7.4470),
  };

  /// The centre of [area], or of the city when it is unknown or null.
  static GeoPoint centreOf(String? area) => centres[area] ?? city;

  /// Other ways people write an area.
  static const _aliases = <String, String>{
    'cbd': 'Central Business District',
    'area 11': 'Garki Area 11',
    'wuse ii': 'Wuse 2',
    'wuse zone': 'Wuse',
    'lifecamp': 'Life Camp',
  };

  /// The area an address names ("12 Aminu Kano Crescent, Wuse 2" gives
  /// "Wuse 2"), the longest when several fit ("Wuse 2", not "Wuse"), or
  /// null, so nobody is asked for what they already typed.
  static String? areaIn(String address) {
    final text = address.toLowerCase();
    bool names(String name) =>
        RegExp('(^|[^a-z0-9])${RegExp.escape(name.toLowerCase())}(?![a-z0-9])')
            .hasMatch(text);
    String? best;
    for (final (written, area) in [
      for (final a in centres.keys) (a, a),
      for (final e in _aliases.entries) (e.key, e.value),
    ]) {
      if (names(written) && (best == null || area.length > best.length)) {
        best = area;
      }
    }
    return best;
  }

  /// Named places near [point], nearest first, for map labels.
  static List<(String, GeoPoint)> near(GeoPoint point, {double withinKm = 4}) {
    final list = [
      for (final e in centres.entries)
        if (e.value.kmTo(point) <= withinKm) (e.key, e.value),
    ]..sort((a, b) => a.$2.kmTo(point).compareTo(b.$2.kmTo(point)));
    return list;
  }
}
