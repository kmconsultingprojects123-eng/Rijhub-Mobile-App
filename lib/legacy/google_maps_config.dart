import 'package:flutter_dotenv/flutter_dotenv.dart';

// Google Maps API key, read from .env at runtime.
// Set GOOGLE_MAPS_API_KEY in the .env file at the project root.
final String GOOGLE_MAPS_API_KEY = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
