import 'package:flutter_test/flutter_test.dart';
import 'package:rijhub/data/geo/places.dart';

void main() {
  group('the area an address names', () {
    test('found in what people type, the longest name winning', () {
      expect(
          AbujaPlaces.areaIn(
              '12 Aminu Kano Crescent, Wuse 2, opposite Banex Plaza'),
          'Wuse 2');
      expect(AbujaPlaces.areaIn('Plot 9, Wuse Zone 4'), 'Wuse');
      expect(AbujaPlaces.areaIn('House 3, 4th Avenue, gwarinpa estate'),
          'Gwarinpa');
      expect(AbujaPlaces.areaIn('Area 11, Garki'), 'Garki Area 11');
      expect(AbujaPlaces.areaIn('CBD, near the NNPC towers'),
          'Central Business District');
    });

    test('null when none is named, never a guess', () {
      expect(AbujaPlaces.areaIn('Behind the big mosque'), isNull);
      expect(AbujaPlaces.areaIn('Kubwaville Hotel'), isNull);
    });
  });
}
