// Mapbox has been removed from this project. Keep this file as a compatibility
// shim: it intentionally does not contain any credentials and will not perform
// network calls. Use `lib/google_maps_config.dart` and the Google Maps SDK
// instead.
//
/// Empty Mapbox token to avoid accidental usage.
const String MAPBOX_ACCESS_TOKEN = '';

/// Deprecated: default coords kept only for backward compatibility.
/// Prefer configuring service area coordinates via the app/user profile.
const double DEFAULT_LAT = 6.5244;
const double DEFAULT_LON = 3.3792;
