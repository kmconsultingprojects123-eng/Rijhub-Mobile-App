import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../api_config.dart';
import 'token_storage.dart';

class UserService {
  /// Fetch the authenticated user's profile. Tries several candidate endpoints
  /// (preferring /api/users/me). Returns the user map or null on failure.
  static Future<Map<String, dynamic>?> getProfile() async {
    final token = await TokenStorage.getToken();
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null && token.isNotEmpty)
      headers['Authorization'] = 'Bearer $token';

    // If there's no token, skip authenticated fetch.
    if (token == null || token.isEmpty) return null;

    final candidates = [
      '$API_BASE_URL/api/users/me',
      '$API_BASE_URL/api/auth/verify',
      '$API_BASE_URL/api/users/profile',
      '$API_BASE_URL/api/auth/profile',
    ];

    for (final url in candidates) {
      int attempts = 0;
      try {
        http.Response resp;
        // retry loop for transient network issues
        while (true) {
          try {
            attempts++;
            // ┌──────────────────────────────────────────────────────────────────────────────
            // │ API Logger - Request (UserService)
            // └──────────────────────────────────────────────────────────────────────────────
            // ignore: avoid_print
            print(
                '┌──────────────────────────────────────────────────────────────────────────────');
            // ignore: avoid_print
            print('│ [API Request] GET $url');
            if (headers.isNotEmpty) {
              // ignore: avoid_print
              print('│ Headers:');
              // ignore: avoid_print
              headers.forEach((k, v) => print('│   $k: $v'));
            }
            // ignore: avoid_print
            print(
                '└──────────────────────────────────────────────────────────────────────────────');

            resp = await http
                .get(Uri.parse(url), headers: headers)
                .timeout(const Duration(seconds: 15));

            // ┌──────────────────────────────────────────────────────────────────────────────
            // │ API Logger - Response (UserService)
            // └──────────────────────────────────────────────────────────────────────────────
            // ignore: avoid_print
            print(
                '┌──────────────────────────────────────────────────────────────────────────────');
            // ignore: avoid_print
            print('│ [API Response] ${resp.statusCode} $url');
            // ignore: avoid_print
            print('│ Body: ${resp.body}');
            // ignore: avoid_print
            print(
                '└──────────────────────────────────────────────────────────────────────────────');

            break; // success
          } on SocketException catch (se) {
            // Connection reset by peer / network error — retry a couple times
            if (attempts >= 3) rethrow;
            await Future.delayed(Duration(milliseconds: 300 * attempts));
            continue;
          } on http.ClientException catch (ce) {
            if (attempts >= 3) rethrow;
            await Future.delayed(Duration(milliseconds: 300 * attempts));
            continue;
          }
        }
        // If we somehow made another call, check status
        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          if (resp.body.isEmpty) return null;
          final decoded = jsonDecode(resp.body);
          if (decoded is Map) {
            Map<String, dynamic>? candidate;
            if (decoded['data'] is Map)
              candidate = Map<String, dynamic>.from(decoded['data']);
            else if (decoded['payload'] is Map)
              candidate = Map<String, dynamic>.from(decoded['payload']);
            else if (decoded['user'] is Map)
              candidate = Map<String, dynamic>.from(decoded['user']);
            else if (decoded['profile'] is Map)
              candidate = Map<String, dynamic>.from(decoded['profile']);
            else
              candidate = Map<String, dynamic>.from(decoded);

            // Persist role and kyc status if present so UI can use cached values
            try {
              final role = _extractRole(candidate);
              if (role != null && role.isNotEmpty)
                await TokenStorage.saveRole(role);
            } catch (_) {}
            try {
              final kyc = _extractKyc(candidate);
              if (kyc != null) await TokenStorage.saveKycVerified(kyc);
            } catch (_) {}
            // Persist location info (address + coords) into TokenStorage for global use
            try {
              String? addr;
              double? lat;
              double? lon;
              if (candidate['serviceArea'] is Map) {
                final sa = Map<String, dynamic>.from(candidate['serviceArea']);
                addr = sa['address']?.toString() ?? addr;
                final coords =
                    sa['coordinates'] ?? sa['center'] ?? sa['location'];
                if (coords is List && coords.length >= 2) {
                  lon = (coords[0] is num)
                      ? coords[0].toDouble()
                      : double.tryParse(coords[0].toString());
                  lat = (coords[1] is num)
                      ? coords[1].toDouble()
                      : double.tryParse(coords[1].toString());
                }
                if (sa['lat'] != null && sa['lon'] != null) {
                  lat = (sa['lat'] is num)
                      ? sa['lat'].toDouble()
                      : double.tryParse(sa['lat'].toString());
                  lon = (sa['lon'] is num)
                      ? sa['lon'].toDouble()
                      : double.tryParse(sa['lon'].toString());
                }
              }
              if (candidate['location'] != null && addr == null)
                addr = candidate['location']?.toString();
              if (candidate['latitude'] != null && lat == null)
                lat = (candidate['latitude'] is num)
                    ? candidate['latitude'].toDouble()
                    : double.tryParse(candidate['latitude'].toString());
              if (candidate['longitude'] != null && lon == null)
                lon = (candidate['longitude'] is num)
                    ? candidate['longitude'].toDouble()
                    : double.tryParse(candidate['longitude'].toString());
              if (addr != null || lat != null || lon != null) {
                try {
                  await TokenStorage.saveLocation(
                      address: addr, latitude: lat, longitude: lon);
                } catch (_) {}
              }
            } catch (_) {}

            return candidate;
          }
        } else if (resp.statusCode == 401 || resp.statusCode == 403) {
          // authentication issue; cannot proceed further
          return null;
        } else {
          // server-side error: try next candidate
          continue;
        }
      } catch (e) {
        // For network errors after retries, continue to next candidate
        continue;
      }
    }

    return null;
  }

  /// Update authenticated user's profile.
  /// fields: a map of simple string fields (name, email, phone, location, ...)
  /// imagePath: optional local file path to upload as 'profileImage'. If imagePath
  /// is a remote URL (startsWith http) it will be ignored and not uploaded.
  /// imageBytes: optional raw bytes for web upload.
  /// imageFilename: optional filename for imageBytes upload.
  /// Returns the updated user map on success or throws an exception.
  static Future<Map<String, dynamic>> updateProfile(Map<String, String> fields,
      {String? imagePath,
      Uint8List? imageBytes,
      String? imageFilename,
      bool forceUserPath = false}) async {
    final token = await TokenStorage.getToken();
    if (token == null || token.isEmpty) throw Exception('Missing auth token');

    // If the user is an artisan, the API uses a separate artisan route.
    // Prefer the cached role from TokenStorage; fall back to /api/users/me.
    String basePath = '/api/users/me';
    try {
      final role = await TokenStorage.getRole();
      if (!forceUserPath && role != null && role.toLowerCase() == 'artisan') {
        basePath = '/api/artisans/me';
      }
    } catch (_) {}
    final uri = Uri.parse('$API_BASE_URL$basePath');

    // If there's an image (local path or bytes) we must send multipart/form-data.
    // Otherwise, send a simple JSON PUT which is lighter and avoids multipart handling.
    http.Response resp;
    if ((imageBytes != null && imageBytes.isNotEmpty) ||
        (imagePath != null &&
            imagePath.isNotEmpty &&
            !imagePath.startsWith(RegExp(r'https?://')))) {
      final req = http.MultipartRequest('PUT', uri);
      req.headers['Authorization'] = 'Bearer $token';
      // attach text fields
      fields.forEach((k, v) => req.fields[k] = v);

      // attach file if provided
      if (imageBytes != null && imageBytes.isNotEmpty) {
        final filename = imageFilename ?? 'profile_image.jpg';
        final multipartFile = http.MultipartFile.fromBytes(
            'profileImage', imageBytes,
            filename: filename);
        req.files.add(multipartFile);
      } else if (imagePath != null &&
          imagePath.isNotEmpty &&
          !imagePath.startsWith(RegExp(r'https?://'))) {
        final file = File(imagePath);
        if (!await file.exists())
          throw Exception('Profile image file not found');
        final stream = http.ByteStream(file.openRead());
        final length = await file.length();
        final multipartFile = http.MultipartFile('profileImage', stream, length,
            filename: file.path.split(Platform.pathSeparator).last);
        req.files.add(multipartFile);
      }

      // ┌──────────────────────────────────────────────────────────────────────────────
      // │ API Logger - Request (UserService Multipart)
      // └──────────────────────────────────────────────────────────────────────────────
      // ignore: avoid_print
      print(
          '┌──────────────────────────────────────────────────────────────────────────────');
      // ignore: avoid_print
      print('│ [API Request] PUT (Multipart) $uri');
      req.headers.forEach((k, v) => print('│ Header $k: $v'));
      req.fields.forEach((k, v) => print('│ Field $k: $v'));
      req.files.forEach(
          (f) => print('│ File ${f.field}: ${f.filename} (${f.length} bytes)'));
      // ignore: avoid_print
      print(
          '└──────────────────────────────────────────────────────────────────────────────');

      final streamed = await req.send().timeout(const Duration(seconds: 60));
      resp = await http.Response.fromStream(streamed);

      // ┌──────────────────────────────────────────────────────────────────────────────
      // │ API Logger - Response (UserService Multipart)
      // └──────────────────────────────────────────────────────────────────────────────
      // ignore: avoid_print
      print(
          '┌──────────────────────────────────────────────────────────────────────────────');
      // ignore: avoid_print
      print('│ [API Response] ${resp.statusCode} $uri');
      // ignore: avoid_print
      print('│ Body: ${resp.body}');
      // ignore: avoid_print
      print(
          '└──────────────────────────────────────────────────────────────────────────────');
    } else {
      // send JSON
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token'
      };

      // ┌──────────────────────────────────────────────────────────────────────────────
      // │ API Logger - Request (UserService JSON)
      // └──────────────────────────────────────────────────────────────────────────────
      // ignore: avoid_print
      print(
          '┌──────────────────────────────────────────────────────────────────────────────');
      // ignore: avoid_print
      print('│ [API Request] PUT $uri');
      // ignore: avoid_print
      print('│ Headers: $headers');
      // ignore: avoid_print
      print('│ Body: ${jsonEncode(fields)}');
      // ignore: avoid_print
      print(
          '└──────────────────────────────────────────────────────────────────────────────');

      resp = await http
          .put(uri, headers: headers, body: jsonEncode(fields))
          .timeout(const Duration(seconds: 30));

      // ┌──────────────────────────────────────────────────────────────────────────────
      // │ API Logger - Response (UserService JSON)
      // └──────────────────────────────────────────────────────────────────────────────
      // ignore: avoid_print
      print(
          '┌──────────────────────────────────────────────────────────────────────────────');
      // ignore: avoid_print
      print('│ [API Response] ${resp.statusCode} $uri');
      // ignore: avoid_print
      print('│ Body: ${resp.body}');
      // ignore: avoid_print
      print(
          '└──────────────────────────────────────────────────────────────────────────────');

      // If server refuses JSON with a multipart requirement, retry using multipart/form-data (fields-only)
      if (resp.statusCode == 406 ||
          (resp.body != null &&
              resp.body.toLowerCase().contains('not multipart'))) {
        try {
          final retryReq = http.MultipartRequest('PUT', uri);
          retryReq.headers['Authorization'] = 'Bearer $token';
          fields.forEach((k, v) => retryReq.fields[k] = v);
          final streamedRetry =
              await retryReq.send().timeout(const Duration(seconds: 60));
          resp = await http.Response.fromStream(streamedRetry);
        } catch (e) {
          // Preserve original response if retry fails
        }
      }
    }
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final decoded = jsonDecode(resp.body);
      // Persist canonical location info to TokenStorage if present in response
      try {
        Map<String, dynamic>? candidate;
        if (decoded is Map && decoded['data'] is Map)
          candidate = Map<String, dynamic>.from(decoded['data']);
        else if (decoded is Map) candidate = Map<String, dynamic>.from(decoded);
        if (candidate != null) {
          // Look for serviceArea or location fields
          String? addr;
          double? lat;
          double? lon;
          if (candidate['serviceArea'] is Map) {
            final sa = Map<String, dynamic>.from(candidate['serviceArea']);
            addr = sa['address']?.toString() ?? addr;
            final coords = sa['coordinates'] ?? sa['center'] ?? sa['location'];
            if (coords is List && coords.length >= 2) {
              // server might send [lon, lat]
              lon = (coords[0] is num)
                  ? coords[0].toDouble()
                  : double.tryParse(coords[0].toString());
              lat = (coords[1] is num)
                  ? coords[1].toDouble()
                  : double.tryParse(coords[1].toString());
            }
            if (sa['lat'] != null && sa['lon'] != null) {
              lat = (sa['lat'] is num)
                  ? sa['lat'].toDouble()
                  : double.tryParse(sa['lat'].toString());
              lon = (sa['lon'] is num)
                  ? sa['lon'].toDouble()
                  : double.tryParse(sa['lon'].toString());
            }
          }
          if (candidate['location'] != null && addr == null)
            addr = candidate['location']?.toString();
          if (candidate['latitude'] != null && lat == null)
            lat = (candidate['latitude'] is num)
                ? candidate['latitude'].toDouble()
                : double.tryParse(candidate['latitude'].toString());
          if (candidate['longitude'] != null && lon == null)
            lon = (candidate['longitude'] is num)
                ? candidate['longitude'].toDouble()
                : double.tryParse(candidate['longitude'].toString());
          if (addr != null || lat != null || lon != null) {
            try {
              await TokenStorage.saveLocation(
                  address: addr, latitude: lat, longitude: lon);
            } catch (_) {}
          }
        }
      } catch (_) {}
      if (decoded is Map && decoded['data'] is Map)
        return Map<String, dynamic>.from(decoded['data']);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      throw Exception('Unexpected response format');
    } else {
      throw Exception(
          'Failed to update profile: ${resp.statusCode} ${resp.body}');
    }
  }

  // --- Helpers & privilege API ---

  /// Extract a canonical role string from a profile map. Handles many shapes.
  static String? _extractRole(Map<String, dynamic>? profile) {
    if (profile == null) return null;
    try {
      final candidates = <dynamic>[
        profile['role'],
        profile['user'] is Map ? profile['user']['role'] : null,
        profile['data'] is Map ? profile['data']['role'] : null,
        profile['profile'] is Map ? profile['profile']['role'] : null,
        profile['type'],
        profile['accountType'],
        profile['authProvider'],
      ];
      for (final c in candidates) {
        if (c == null) continue;
        final s = c.toString().toLowerCase();
        if (s.contains('artisan')) return 'artisan';
        if (s.contains('customer') ||
            s.contains('client') ||
            s.contains('user')) return 'customer';
        if (s.contains('guest')) return 'guest';
      }
      // Some APIs return nested structures with role key variations
      final roleFields = ['role', 'roles', 'userRole', 'user_type'];
      for (final k in roleFields) {
        if (profile[k] != null) {
          final s = profile[k].toString().toLowerCase();
          if (s.contains('artisan')) return 'artisan';
          if (s.contains('customer') ||
              s.contains('client') ||
              s.contains('user')) return 'customer';
          if (s.contains('guest')) return 'guest';
        }
      }
    } catch (_) {}
    return null;
  }

  static bool? _extractKyc(Map<String, dynamic>? profile) {
    if (profile == null) return null;
    try {
      final candidates = [
        profile['kycVerified'],
        profile['kyc']?['verified'],
        profile['kycVerifiedFlag'],
        profile['isVerified']
      ];
      for (final c in candidates) {
        if (c == null) continue;
        if (c is bool) return c;
        final s = c.toString().toLowerCase();
        if (s == 'true' || s == '1') return true;
        if (s == 'false' || s == '0') return false;
      }
    } catch (_) {}
    return null;
  }

  /// Returns cached role (if any) or attempts to fetch profile and derive role.
  static Future<String?> getRole() async {
    final cached = await TokenStorage.getRole();
    if (cached != null && cached.isNotEmpty) return cached;
    final profile = await getProfile();
    final r = _extractRole(profile);
    if (r != null && r.isNotEmpty) await TokenStorage.saveRole(r);
    return r;
  }

  /// Returns a canonical location object for the current user used across the app.
  /// It prefers the cached TokenStorage location and falls back to fetching the
  /// profile and extracting address/coordinates.
  static Future<Map<String, dynamic>> getCanonicalLocation() async {
    try {
      final cached = await TokenStorage.getLocation();
      if ((cached['address'] as String?)?.isNotEmpty == true ||
          cached['latitude'] != null ||
          cached['longitude'] != null) {
        return cached;
      }
      final profile = await getProfile();
      if (profile == null)
        return {'address': null, 'latitude': null, 'longitude': null};
      String? addr;
      double? lat;
      double? lon;
      try {
        if (profile['serviceArea'] is Map) {
          final sa = Map<String, dynamic>.from(profile['serviceArea']);
          addr = sa['address']?.toString() ?? addr;
          final coords = sa['coordinates'] ?? sa['center'] ?? sa['location'];
          if (coords is List && coords.length >= 2) {
            lon = (coords[0] is num)
                ? coords[0].toDouble()
                : double.tryParse(coords[0].toString());
            lat = (coords[1] is num)
                ? coords[1].toDouble()
                : double.tryParse(coords[1].toString());
          }
          if (sa['lat'] != null && sa['lon'] != null) {
            lat = (sa['lat'] is num)
                ? sa['lat'].toDouble()
                : double.tryParse(sa['lat'].toString());
            lon = (sa['lon'] is num)
                ? sa['lon'].toDouble()
                : double.tryParse(sa['lon'].toString());
          }
        }
        if (profile['location'] != null && addr == null)
          addr = profile['location']?.toString();
        if (profile['latitude'] != null && lat == null)
          lat = (profile['latitude'] is num)
              ? profile['latitude'].toDouble()
              : double.tryParse(profile['latitude'].toString());
        if (profile['longitude'] != null && lon == null)
          lon = (profile['longitude'] is num)
              ? profile['longitude'].toDouble()
              : double.tryParse(profile['longitude'].toString());
      } catch (_) {}
      // cache for later
      try {
        await TokenStorage.saveLocation(
            address: addr, latitude: lat, longitude: lon);
      } catch (_) {}
      return {'address': addr, 'latitude': lat, 'longitude': lon};
    } catch (_) {
      return {'address': null, 'latitude': null, 'longitude': null};
    }
  }

  /// Convenience checks
  static Future<bool> isLoggedIn() async {
    final t = await TokenStorage.getToken();
    return t != null && t.isNotEmpty;
  }

  static Future<bool> isGuest() async {
    final logged = await isLoggedIn();
    if (!logged) return true; // not authenticated = guest
    final r = await getRole();
    return r == null || r == 'guest';
  }

  static Future<bool> isClient() async {
    final r = await getRole();
    if (r == null) return false;
    return r == 'customer' || r == 'client' || r == 'user';
  }

  static Future<bool> isArtisan() async {
    final r = await getRole();
    if (r == null) return false;
    return r == 'artisan';
  }

  /// Clear cached auth artifacts
  static Future<void> clearCachedAuth() async {
    await TokenStorage.deleteToken();
    await TokenStorage.deleteRole();
    await TokenStorage.deleteKycVerified();
  }
}
