import 'package:geolocator/geolocator.dart';

import '../data/geo/places.dart';

/// Where the phone is, asked for only when someone taps "Use my location",
/// so there's never a permission prompt before they want one.
abstract interface class LocationService {
  /// Null when location is off, not allowed, or takes too long.
  Future<GeoPoint?> current();
}

/// The phone's own location.
class DeviceLocationService implements LocationService {
  @override
  Future<GeoPoint?> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      final position = await Geolocator.getCurrentPosition(
        // A neighbourhood is all we need.
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return GeoPoint(position.latitude, position.longitude);
    } on Object {
      return null;
    }
  }
}

/// A fixed spot in Wuse 2, for tests and screenshots.
class SampleLocationService implements LocationService {
  const SampleLocationService([this.point]);

  /// Null stands for location being off.
  final GeoPoint? point;

  @override
  Future<GeoPoint?> current() async => point;
}
