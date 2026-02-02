import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../api_config.dart';
import 'token_storage.dart';
import 'api_client.dart';
import 'package:path/path.dart' as p;
import 'upload_service.dart';
import 'user_service.dart';

class MultipartRejectedException implements Exception {
  final String message;
  MultipartRejectedException(this.message);
  @override
  String toString() => message;
}

class ArtistService {
  // Tracks whether the most recent getByUserId attempt observed any 200 response
  // from candidate endpoints. If true and getByUserId returned null, we can
  // treat that as 'no artisan exists' and avoid calling /api/artisans/me which
  // some servers do not support for GET and may return validation errors.
  static bool _lastGetByUserIdHad200 = false;

  /// Fetch artisans from backend with optional pagination and query.
  /// Accepts multiple server response shapes and returns a list of artisan maps.
  static Future<List<Map<String, dynamic>>> fetchArtisans({int page = 1, int limit = 20, String? q, String? trade, String? name, String? location, double? lat, double? lon, int? radiusKm}) async {
    final token = await TokenStorage.getToken();
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    final qParams = <String, String>{'role': 'artisan', 'page': page.toString(), 'limit': limit.toString()};
    if (q != null && q.isNotEmpty) qParams['q'] = q;
    if (trade != null && trade.isNotEmpty) qParams['trade'] = trade;
    // Only use `name` as a q fallback when `q` is not provided to avoid accidentally overriding an explicit `q`.
    if ((q == null || q.isEmpty) && name != null && name.isNotEmpty) qParams['q'] = name;
    if (location != null && location.isNotEmpty) qParams['location'] = location;
    if (lat != null) qParams['lat'] = lat.toString();
    if (lon != null) qParams['lon'] = lon.toString();
    if (radiusKm != null) qParams['radiusKm'] = radiusKm.toString();

    // Prefer the dedicated artisans endpoint per API docs
    final uri = Uri.parse('$API_BASE_URL/api/artisans').replace(queryParameters: qParams);
    if (kDebugMode) {
      try {
        debugPrint('ArtistService.fetchArtisans -> uri: ${uri.toString()}');
        debugPrint('ArtistService.fetchArtisans -> queryParams: $qParams');
      } catch (_) {}
    }
    final respMap = await ApiClient.get(uri.toString(), headers: headers);
    if ((respMap['status'] is int) && (respMap['status'] as int) >= 200 && (respMap['status'] as int) < 300) {
      dynamic body;
      try {
        body = respMap['json'] ?? (respMap['body']?.isNotEmpty == true ? jsonDecode(respMap['body'] as String) : null);
      } catch (e) {
        // If the server returned non-json (HTML error page or empty), return empty list
        // attempt a very small recovery: if body contains a JSON-like array substring, try to extract it
        final s = respMap['body'] as String? ?? '';
        final start = s.indexOf('[');
        final end = s.lastIndexOf(']');
        if (start != -1 && end != -1 && end > start) {
          try {
            body = jsonDecode(s.substring(start, end + 1));
          } catch (_) {
            return [];
          }
        } else {
          return [];
        }
      }
      if (body == null) return [];

      // If the body itself is a list
      if (body is List) return List<Map<String, dynamic>>.from(body.map((e) => Map<String, dynamic>.from(e)));

      // Common response shapes
      // 1) { success: true, data: [ ... ] }
      if (body is Map && body['data'] is List) return List<Map<String, dynamic>>.from((body['data'] as List).map((e) => Map<String, dynamic>.from(e)));

      // 2) { success: true, data: { docs: [...] } }
      if (body is Map && body['data'] is Map) {
        final d = body['data'] as Map<String, dynamic>;
        if (d['docs'] is List) return List<Map<String, dynamic>>.from((d['docs'] as List).map((e) => Map<String, dynamic>.from(e)));
        if (d['items'] is List) return List<Map<String, dynamic>>.from((d['items'] as List).map((e) => Map<String, dynamic>.from(e)));
        if (d['users'] is List) return List<Map<String, dynamic>>.from((d['users'] as List).map((e) => Map<String, dynamic>.from(e)));
      }

      // 3) { users: [...] }
      if (body is Map && body['users'] is List) return List<Map<String, dynamic>>.from((body['users'] as List).map((e) => Map<String, dynamic>.from(e)));

      // 4) sometimes server nests under 'result' or 'results'
      if (body is Map && body['result'] is List) return List<Map<String, dynamic>>.from((body['result'] as List).map((e) => Map<String, dynamic>.from(e)));
      if (body is Map && body['results'] is List) return List<Map<String, dynamic>>.from((body['results'] as List).map((e) => Map<String, dynamic>.from(e)));

      // 5) if data is an object with single array-like property, try to find first List value
      if (body is Map) {
        for (final entry in body.entries) {
          if (entry.value is List) {
            try {
              return List<Map<String, dynamic>>.from((entry.value as List).map((e) => Map<String, dynamic>.from(e)));
            } catch (_) {
              // continue
            }
          }
          if (entry.value is Map) {
            final m = entry.value as Map<String, dynamic>;
            for (final e2 in m.entries) {
              if (e2.value is List) {
                try {
                  return List<Map<String, dynamic>>.from((e2.value as List).map((e) => Map<String, dynamic>.from(e)));
                } catch (_) {}
              }
            }
          }
        }
      }

      // If we couldn't find a list in the primary response, try alternative endpoints before giving up.
      try {
        // 1) Try search endpoint
        final searchUri = Uri.parse('$API_BASE_URL/api/artisans/search').replace(queryParameters: qParams);
        final searchResp = await http.get(searchUri, headers: headers).timeout(const Duration(seconds: 15));
        if (searchResp.statusCode >= 200 && searchResp.statusCode < 300 && searchResp.body.isNotEmpty) {
          try {
            final sb = jsonDecode(searchResp.body);
            if (sb is List) return List<Map<String, dynamic>>.from(sb.map((e) => Map<String, dynamic>.from(e)));
            if (sb is Map && sb['data'] is List) return List<Map<String, dynamic>>.from((sb['data'] as List).map((e) => Map<String, dynamic>.from(e)));
          } catch (e) {
            // search decode failed
          }
        }

        // 2) Try generic users endpoint as last resort (without role filter)
        final usersUri = Uri.parse('$API_BASE_URL/api/users').replace(queryParameters: {'page': page.toString(), 'limit': (limit * 2).toString()});
        final usersResp = await http.get(usersUri, headers: headers).timeout(const Duration(seconds: 15));
        if (usersResp.statusCode >= 200 && usersResp.statusCode < 300 && usersResp.body.isNotEmpty) {
          try {
            final ub = jsonDecode(usersResp.body);
            if (ub is List) return List<Map<String, dynamic>>.from(ub.map((e) => Map<String, dynamic>.from(e)));
            if (ub is Map && ub['data'] is List) return List<Map<String, dynamic>>.from((ub['data'] as List).map((e) => Map<String, dynamic>.from(e)));
          } catch (e) {
            // users decode failed
          }
        }
      } catch (e) {
        // fallback attempts failed
      }

      return [];
    }
    // Non-2xx responses: log and try alternative endpoints before giving up
    // non-ok response
    try {
      final altSearchUri = Uri.parse('$API_BASE_URL/api/artisans/search').replace(queryParameters: qParams);
      final altResp = await http.get(altSearchUri, headers: headers).timeout(const Duration(seconds: 10));
      if (altResp.statusCode >= 200 && altResp.statusCode < 300 && altResp.body.isNotEmpty) {
        try {
          final body = jsonDecode(altResp.body);
          if (body is List) return List<Map<String, dynamic>>.from(body.map((e) => Map<String, dynamic>.from(e)));
          if (body is Map && body['data'] is List) return List<Map<String, dynamic>>.from((body['data'] as List).map((e) => Map<String, dynamic>.from(e)));
        } catch (_) {}
      }
    } catch (_) {}
    return [];
  }

  /// Fallback: fetch users without forcing role=artisan in case the server ignores that filter
  static Future<List<Map<String, dynamic>>> fetchAllUsers({int page = 1, int limit = 50, String? q}) async {
    final token = await TokenStorage.getToken();
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    final qParams = <String, String>{'page': page.toString(), 'limit': limit.toString()};
    if (q != null && q.isNotEmpty) qParams['q'] = q;

    final uri = Uri.parse('$API_BASE_URL/api/users').replace(queryParameters: qParams);
    final respMap = await ApiClient.get(uri.toString(), headers: headers);
    if ((respMap['status'] is int) && (respMap['status'] as int) >= 200 && (respMap['status'] as int) < 300) {
      final body = respMap['json'] ?? (respMap['body']?.isNotEmpty == true ? jsonDecode(respMap['body'] as String) : null);
      if (body == null) return [];
      if (body is List) return List<Map<String, dynamic>>.from(body.map((e) => Map<String, dynamic>.from(e)));
      if (body is Map && body['data'] is List) return List<Map<String, dynamic>>.from((body['data'] as List).map((e) => Map<String, dynamic>.from(e)));
      if (body is Map) {
        for (final entry in body.entries) {
          if (entry.value is List) {
            try { return List<Map<String, dynamic>>.from((entry.value as List).map((e) => Map<String, dynamic>.from(e))); } catch (_) {}
          }
        }
      }
      return [];
    }
    // non-2xx response
    return [];
  }

  /// Fetch bookings assigned to a specific artisan (protected endpoint)
  /// Returns a list of objects that may contain booking and customerUser keys (per API docs).
  static Future<List<Map<String, dynamic>>> fetchArtisanBookings(String artisanId, {int page = 1, int limit = 20, String? status}) async {
    final token = await TokenStorage.getToken();
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';

    if (token == null || token.isEmpty) {
      return [];
    }

    final qParams = <String, String>{'page': page.toString(), 'limit': limit.toString()};
    if (status != null && status.isNotEmpty) qParams['status'] = status;

    // Primary endpoint
    final primaryUri = Uri.parse('$API_BASE_URL/api/bookings/artisan/$artisanId').replace(queryParameters: qParams);
    final respMap = await ApiClient.get(primaryUri.toString(), headers: headers);
    if ((respMap['status'] is int) && (respMap['status'] as int) >= 200 && (respMap['status'] as int) < 300) {
      final body = respMap['json'] ?? (respMap['body']?.isNotEmpty == true ? jsonDecode(respMap['body'] as String) : null);
      if (body == null) return [];
      if (body is List) return List<Map<String, dynamic>>.from(body.map((e) => Map<String, dynamic>.from(e)));
      if (body is Map && body['data'] is List) return List<Map<String, dynamic>>.from((body['data'] as List).map((e) => Map<String, dynamic>.from(e)));
      // try nested shapes
      if (body is Map) {
        for (final entry in body.entries) {
          if (entry.value is List) {
            try {
              return List<Map<String, dynamic>>.from((entry.value as List).map((e) => Map<String, dynamic>.from(e)));
            } catch (_) {}
          }
        }
      }
      return [];
    }

    // If primary endpoint fails, try fallbacks: query /api/bookings?artisanId=...
    // primary endpoint non-ok; try fallbacks
    final fallbacks = [
      Uri.parse('$API_BASE_URL/api/bookings').replace(queryParameters: {'artisanId': artisanId, 'page': page.toString(), 'limit': limit.toString()}),
      Uri.parse('$API_BASE_URL/api/bookings').replace(queryParameters: {'artisan': artisanId, 'page': page.toString(), 'limit': limit.toString()}),
      Uri.parse('$API_BASE_URL/api/bookings').replace(queryParameters: {'artisan_id': artisanId, 'page': page.toString(), 'limit': limit.toString()}),
    ];

    for (final uri in fallbacks) {
      try {
        final r2 = await http.get(uri, headers: headers).timeout(const Duration(seconds: 12));
        if (r2.statusCode >= 200 && r2.statusCode < 300) {
          final body = r2.body.isNotEmpty ? jsonDecode(r2.body) : null;
          if (body == null) return [];
          if (body is List) return List<Map<String, dynamic>>.from(body.map((e) => Map<String, dynamic>.from(e)));
          if (body is Map && body['data'] is List) return List<Map<String, dynamic>>.from((body['data'] as List).map((e) => Map<String, dynamic>.from(e)));
          if (body is Map) {
            for (final entry in body.entries) {
              if (entry.value is List) {
                try { return List<Map<String, dynamic>>.from((entry.value as List).map((e) => Map<String, dynamic>.from(e))); } catch (_) {}
              }
            }
          }
          return [];
        }
      } catch (e) {
        // fallback failed
      }
    }

    return [];
  }

  /// Fetch reviews for a given artisanId (GET /api/reviews?artisanId=...)
  static Future<List<Map<String, dynamic>>> fetchReviewsForArtisan(String artisanId, {int page = 1, int limit = 10}) async {
    final token = await TokenStorage.getToken();
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';

    // Primary query params (some servers may expect targetId instead of artisanId)
    final qParams = {'artisanId': artisanId, 'page': page.toString(), 'limit': limit.toString()};
    final uri = Uri.parse('$API_BASE_URL/api/reviews').replace(queryParameters: qParams);
    if (kDebugMode) {
      try {
        debugPrint('ArtistService.fetchReviewsForArtisan -> uri: ${uri.toString()}');
        debugPrint('ArtistService.fetchReviewsForArtisan -> queryParams: $qParams');
      } catch (_) {}
    }
    // debugPrint(qParams as String?);

    final respMap = await ApiClient.get(uri.toString(), headers: headers);
    if (kDebugMode) {
      try {
        debugPrint('ArtistService.fetchReviewsForArtisan -> respMap.status=${respMap["status"]}');
      } catch (_) {}
    }
    // debugPrint(respMap as String?);String
    // Helper to coerce various response shapes into List<Map<String,dynamic>>
    List<Map<String, dynamic>> _extractListFromBody(dynamic body) {
      try {
        if (body == null) return [];
        if (body is List) return List<Map<String, dynamic>>.from(body.map((e) => Map<String, dynamic>.from(e)));
        if (body is Map && body['data'] is List) return List<Map<String, dynamic>>.from((body['data'] as List).map((e) => Map<String, dynamic>.from(e)));
        if (body is Map && body['data'] is Map) {
          final d = body['data'] as Map<String, dynamic>;
          if (d['docs'] is List) return List<Map<String, dynamic>>.from((d['docs'] as List).map((e) => Map<String, dynamic>.from(e)));
          if (d['items'] is List) return List<Map<String, dynamic>>.from((d['items'] as List).map((e) => Map<String, dynamic>.from(e)));
          if (d['results'] is List) return List<Map<String, dynamic>>.from((d['results'] as List).map((e) => Map<String, dynamic>.from(e)));
        }
        if (body is Map && body['docs'] is List) return List<Map<String, dynamic>>.from((body['docs'] as List).map((e) => Map<String, dynamic>.from(e)));
        if (body is Map && body['results'] is List) return List<Map<String, dynamic>>.from((body['results'] as List).map((e) => Map<String, dynamic>.from(e)));

        if (body is Map) {
          // Try to find the first List value in the map (fallback)
          for (final entry in body.entries) {
            if (entry.value is List) {
              try {
                return List<Map<String, dynamic>>.from((entry.value as List).map((e) => Map<String, dynamic>.from(e)));
              } catch (_) {}
            }
            if (entry.value is Map) {
              final m = entry.value as Map<String, dynamic>;
              for (final e2 in m.entries) {
                if (e2.value is List) {
                  try {
                    return List<Map<String, dynamic>>.from((e2.value as List).map((e) => Map<String, dynamic>.from(e)));
                  } catch (_) {}
                }
              }
            }
          }
        }
      } catch (_) {}
      return [];
    }

    // Filter extracted reviews so they only target the supplied artisanId.
    List<Map<String, dynamic>> _filterByArtisanId(List<Map<String, dynamic>> list, String artisanId) {
      try {
        if (list.isEmpty) return [];
        final keysToCheck = [
          'artisanId', 'targetId', 'target', 'artisan', 'artisan_id', 'target_id', 'userId', 'user_id'
        ];
        final filtered = <Map<String, dynamic>>[];
        for (final r in list) {
          try {
            bool matched = false;
            for (final k in keysToCheck) {
              if (!r.containsKey(k) || r[k] == null) continue;
              final v = r[k];
              if (v is String && v == artisanId) { matched = true; break; }
              if (v is Map && v['_id'] != null && v['_id'].toString() == artisanId) { matched = true; break; }
              // handle numeric/string mismatch
              if (v.toString() == artisanId) { matched = true; break; }
            }
            // Also check nested fields that might contain the target (e.g., r['target'] = { 'user': { '_id': ... } })
            if (!matched) {
              for (final entry in r.entries) {
                final val = entry.value;
                if (val is Map) {
                  if (val['_id'] != null && val['_id'].toString() == artisanId) { matched = true; break; }
                  for (final sub in val.values) {
                    if (sub is Map && sub['_id'] != null && sub['_id'].toString() == artisanId) { matched = true; break; }
                    if (sub is String && sub == artisanId) { matched = true; break; }
                  }
                }
              }
            }
            if (matched) filtered.add(r);
          } catch (_) {
            // ignore individual record failures
          }
        }
        return filtered;
      } catch (_) {
        return [];
      }
    }

    if ((respMap['status'] is int) && (respMap['status'] as int) >= 200 && (respMap['status'] as int) < 300) {
      dynamic body;
      try {
        body = respMap['json'] ?? (respMap['body']?.isNotEmpty == true ? jsonDecode(respMap['body'] as String) : null);
      } catch (e) {
        // attempt a small recovery for non-json HTML responses that embed an array
        final s = respMap['body'] as String? ?? '';
        final start = s.indexOf('[');
        final end = s.lastIndexOf(']');
        if (start != -1 && end != -1 && end > start) {
          try {
            body = jsonDecode(s.substring(start, end + 1));
          } catch (_) {
            // fall through
          }
        }
      }
      final extracted = _extractListFromBody(body);
      final filtered = _filterByArtisanId(extracted, artisanId);
      if (kDebugMode) {
        try {
          debugPrint('ArtistService.fetchReviewsForArtisan -> extracted ${extracted.length} reviews from primary response, filtered to ${filtered.length} by artisanId=$artisanId');
        } catch (_) {}
      }
      if (filtered.isNotEmpty) return filtered;

      // If nothing found, continue to try fallbacks below
    }

    // Try alternative query parameter names in case server expects a different key (targetId, artisan, artisan_id)
    final altParamSets = [
      {'targetId': artisanId, 'page': page.toString(), 'limit': limit.toString()},
      {'artisan': artisanId, 'page': page.toString(), 'limit': limit.toString()},
      {'artisan_id': artisanId, 'page': page.toString(), 'limit': limit.toString()},
    ];

    for (final params in altParamSets) {
      try {
        final altUri = Uri.parse('$API_BASE_URL/api/reviews').replace(queryParameters: params);
        if (kDebugMode) {
          try { debugPrint('ArtistService.fetchReviewsForArtisan -> trying alt params uri: ${altUri.toString()}'); } catch (_) {}
        }
        final r2map = await ApiClient.get(altUri.toString(), headers: headers);
        if ((r2map['status'] is int) && (r2map['status'] as int) >= 200 && (r2map['status'] as int) < 300) {
          dynamic body;
          try {
            body = r2map['json'] ?? (r2map['body']?.isNotEmpty == true ? jsonDecode(r2map['body'] as String) : null);
          } catch (_) {}
          final extracted = _extractListFromBody(body);
          final filtered = _filterByArtisanId(extracted, artisanId);
          if (filtered.isNotEmpty) return filtered;
        }
      } catch (_) {}
    }

    // As a last resort, try the generic reviews endpoint without query (may return all and we can filter client-side)
    try {
      final uriAll = Uri.parse('$API_BASE_URL/api/reviews').replace(queryParameters: {'page': page.toString(), 'limit': limit.toString()});
      if (kDebugMode) {
        try { debugPrint('ArtistService.fetchReviewsForArtisan -> falling back to unfiltered uriAll: ${uriAll.toString()}'); } catch (_) {}
      }
      final allMap = await ApiClient.get(uriAll.toString(), headers: headers);
      if ((allMap['status'] is int) && (allMap['status'] as int) >= 200 && (allMap['status'] as int) < 300) {
        dynamic body;
        try {
          body = allMap['json'] ?? (allMap['body']?.isNotEmpty == true ? jsonDecode(allMap['body'] as String) : null);
        } catch (_) {}
        final extracted = _extractListFromBody(body);
        final filtered = _filterByArtisanId(extracted, artisanId);
        if (kDebugMode) {
          try { debugPrint('ArtistService.fetchReviewsForArtisan -> uriAll extracted ${extracted.length} reviews, filtered to ${filtered.length}'); } catch (_) {}
        }
        if (filtered.isNotEmpty) return filtered;
      }
    } catch (_) {}

    return [];
  }

  /// Fetch the current user's artisan profile (GET /api/artisans/me)
  static Future<Map<String, dynamic>?> getMyProfile() async {
    // First attempt: try to find artisan by authenticated user's id. This avoids
    // servers that validate `:id` and will error on '/me' (e.g. 'params/id must match pattern').
    try {
      final userProfile = await UserService.getProfile();
      if (userProfile != null) {
        String? userId;
        final candidates = ['_id', 'id', 'userId', 'user_id', 'uid'];
        for (final k in candidates) {
          if (userProfile[k] != null) { userId = userProfile[k].toString(); break; }
        }
        if ((userId == null || userId.isEmpty) && userProfile['user'] is Map && userProfile['user']['_id'] != null) {
          userId = userProfile['user']['_id'].toString();
        }
        if (userId != null && userId.isNotEmpty) {
          if (kDebugMode) debugPrint('ArtistService.getMyProfile -> trying getByUserId($userId) first to avoid /me id validation issues');
          try {
            final found = await getByUserId(userId);
            if (found != null) return found;
            // If getByUserId returned null but one of the candidate endpoints
            // returned 200 (empty array), treat this as authoritative 'not found'
            // and avoid calling /api/artisans/me which some servers don't
            // implement for GET (and may return validation errors).
            if (_lastGetByUserIdHad200) {
              if (kDebugMode) debugPrint('ArtistService.getMyProfile -> getByUserId observed 200 but no match; skipping /api/artisans/me');
              return null;
            }
          } catch (e) {
            if (kDebugMode) debugPrint('ArtistService.getMyProfile -> getByUserId failed: $e');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('ArtistService.getMyProfile: userProfile lookup failed: $e');
    }

    // Second attempt: try the canonical /api/artisans/me endpoint (some servers support it)
    try {
      final uri = '$API_BASE_URL/api/artisans/me';
      if (kDebugMode) debugPrint('ArtistService.getMyProfile -> GET $uri');
      final resp = await ApiClient.get(uri, headers: {'Content-Type': 'application/json'});
      try {
        if (kDebugMode) debugPrint('ArtistService.getMyProfile -> resp status=${resp['status']} body=${(resp['body'] is String && (resp['body'] as String).length > 500) ? (resp['body'].toString().substring(0,500) + '...') : resp['body']}');
      } catch (_) {}
      if (resp['status'] is int && resp['status'] >= 200 && resp['status'] < 300) {
        final body = (resp['body'] != null && resp['body'] is String && (resp['body'] as String).isNotEmpty) ? jsonDecode(resp['body']) : resp['json'];
        if (kDebugMode) debugPrint('ArtistService.getMyProfile -> parsed body type=${body.runtimeType}');
        if (body is Map && body['data'] is Map) return Map<String, dynamic>.from(body['data']);
        if (body is Map) return Map<String, dynamic>.from(body);
      } else {
        if (kDebugMode) debugPrint('ArtistService.getMyProfile -> non-2xx response or empty body from /api/artisans/me');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('ArtistService.getMyProfile -> exception when calling /api/artisans/me: $e');
    }

    return null;
  }

  /// Create a new artisan profile (POST /api/artisans).
  /// If [fileMap] is provided the files will be uploaded via JSON/base64 using
  /// `uploadFilesToAttachments` and the returned URLs will be injected into the
  /// payload before sending a JSON request to the server.
  static Future<Map<String, dynamic>?> createMyProfile(Map<String, dynamic> payload, {Map<String, List<String>>? fileMap}) async {
    try {
      // Instead of attempting multipart which may be rejected by nginx with 413
      // (Request Entity Too Large), upload local files via the attachments
      // endpoints or direct Cloudinary signed uploads and inject the returned
      // URLs into the JSON payload. This avoids sending big multipart payloads
      // to the backend.
      if (fileMap != null && fileMap.isNotEmpty) {
        // If caller provided a fileMap and wants multipart/form-data, send a
        // multipart request per API docs so the server will stream files to Cloudinary.
        try {
          // Before building multipart fields, strip any embedded data URIs from
          // the payload so we don't accidentally send base64 blobs as form fields
          // while also sending files via multipart. The file uploads are carried
          // in `fileMap` so we don't need embedded base64 image strings in fields.
          _stripDataUrisFromPayload(payload);

          // Convert payload values to string fields for multipart form
          final fields = <String, String>{};
          payload.forEach((k, v) {
            try {
              if (v == null) return;
              if (v is String || v is num || v is bool) fields[k] = v.toString();
              else fields[k] = jsonEncode(v);
            } catch (_) {}
          });

          final uri = '$API_BASE_URL/api/artisans';
          if (kDebugMode) debugPrint('createMyProfile -> sending multipart to $uri fields=${fields.keys.toList()} fileMapKeys=${fileMap.keys.toList()}');
          final resp = await ApiClient.postMultipart(uri, headers: {'Content-Type': 'multipart/form-data'}, fields: fields, fileMap: fileMap, method: 'POST');
          final int? status = (resp['status'] is int) ? resp['status'] as int : null;
          if (kDebugMode) debugPrint('ArtistService.createMyProfile (multipart) -> $uri status=$status body=${resp['body']}');
          if (status != null && status >= 200 && status < 300) {
            final body = resp['body'] != null && (resp['body'] is String) && (resp['body'] as String).isNotEmpty ? jsonDecode(resp['body']) : resp['json'];
            if (body is Map && body['data'] is Map) return Map<String, dynamic>.from(body['data']);
            if (body is Map) return Map<String, dynamic>.from(body);
          } else {
            // Fall through to existing JSON path as a fallback
            if (kDebugMode) debugPrint('createMyProfile multipart failed, falling back to JSON path');
          }
        } catch (e) {
          if (kDebugMode) debugPrint('createMyProfile multipart exception: $e');
          // continue to JSON flow below
        }
        for (final entry in fileMap.entries) {
          final fieldName = entry.key;
          final paths = entry.value.where((s) => s.isNotEmpty).toList();
          if (paths.isEmpty) continue;
          try {
            final uploaded = await uploadFilesToAttachments(paths);
            if (kDebugMode) debugPrint('createMyProfile: uploaded results for $fieldName -> $uploaded');
            final urls = uploaded.map((it) => (it['url'] ?? '').toString()).where((u) => u.isNotEmpty).toList();
            if (urls.isEmpty) continue;
            if (fieldName.toLowerCase().contains('portfolio')) {
              payload['portfolio'] = urls.map((u) => {'title': '', 'images': [u]}).toList();
            } else {
              payload[fieldName] = urls;
            }
          } catch (e) {
            if (kDebugMode) debugPrint('createMyProfile: upload for $fieldName failed: $e');
          }
        }
      }

      // Detect any embedded data URI images in payload['portfolio'], write them to
      /// temporary files, upload them using attachments/direct upload, and replace
      /// the embedded data URIs with returned URLs in-place. This prevents sending
      /// raw base64 data to the server.
      await _processEmbeddedDataUris(payload);

      // Recursively walk payload and remove any string values that are data URIs (start with 'data:')
      _stripDataUrisFromPayload(payload);

      // Ensure portfolio doesn't contain raw/base64 strings before sending
      _sanitizePortfolio(payload);
      if (kDebugMode) debugPrint('createMyProfile: payload after sanitization -> ${payload['portfolio']}');
      final uri = '$API_BASE_URL/api/artisans';
      final resp = await ApiClient.post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload));
      final int? status = (resp['status'] is int) ? resp['status'] as int : null;
      if (kDebugMode) debugPrint('ArtistService.createMyProfile -> $uri status=$status body=${resp['body']}');
      if (status != null && status >= 200 && status < 300) {
        final body = jsonDecode(resp['body']);
        if (body is Map && body['data'] is Map) return Map<String, dynamic>.from(body['data']);
        if (body is Map) return Map<String, dynamic>.from(body);
      } else {
        final b = resp['body']?.toString() ?? '';
        String msg = 'Server responded with status ${status ?? 'unknown'}';
        try {
          final parsed = b.isNotEmpty ? jsonDecode(b) : null;
          if (parsed is Map && (parsed['message'] != null || parsed['error'] != null)) msg = (parsed['message'] ?? parsed['error']).toString();
          else if (b.isNotEmpty) msg = b;
        } catch (_) {
          if (b.isNotEmpty) msg = b;
        }
        var friendly = 'Failed to create artisan profile.';
        if (msg.isNotEmpty) friendly = '$friendly ${msg.toString()}';
        throw Exception(friendly);
      }
    } catch (e) {
      throw Exception('Network error while creating artisan profile: $e');
    }

    return null;
  }

  /// Update the artisan profile for the authenticated user (PUT /api/artisans/me)
  static Future<Map<String, dynamic>?> updateMyProfile(Map<String, dynamic> payload, {Map<String, List<String>>? fileMap}) async {
    try {
      // If files provided, upload them (JSON/base64) and attach returned URLs
      if (fileMap != null && fileMap.isNotEmpty) {
        // If a fileMap is provided, prefer sending a multipart/form-data request
        // per the API docs so the server uploads the files directly to Cloudinary.
        try {
          final fields = <String, String>{};
          payload.forEach((k, v) {
            try {
              if (v == null) return;
              if (v is String || v is num || v is bool) fields[k] = v.toString();
              else fields[k] = jsonEncode(v);
            } catch (_) {}
          });
          final uri = '$API_BASE_URL/api/artisans/me';
          if (kDebugMode) debugPrint('updateMyProfile -> sending multipart to $uri fields=${fields.keys.toList()} fileMapKeys=${fileMap.keys.toList()}');
          final resp = await ApiClient.postMultipart(uri, headers: {'Content-Type': 'multipart/form-data'}, fields: fields, fileMap: fileMap, method: 'PUT');
          final int? status = (resp['status'] is int) ? resp['status'] as int : null;
          if (kDebugMode) debugPrint('ArtistService.updateMyProfile (multipart) -> $uri status=$status body=${resp['body']}');
          if (status != null && status >= 200 && status < 300) {
            final body = resp['body'] != null && (resp['body'] is String) && (resp['body'] as String).isNotEmpty ? jsonDecode(resp['body']) : resp['json'];
            if (body is Map && body['data'] is Map) return Map<String, dynamic>.from(body['data']);
            if (body is Map) return Map<String, dynamic>.from(body);
          } else {
            if (kDebugMode) debugPrint('updateMyProfile multipart failed, falling back to JSON path');
          }
        } catch (e) {
          if (kDebugMode) debugPrint('updateMyProfile multipart exception: $e');
        }
        for (final entry in fileMap.entries) {
          final fieldName = entry.key;
          final paths = entry.value.where((s) => s.isNotEmpty).toList();
          if (paths.isEmpty) continue;
          try {
            final uploaded = await uploadFilesToAttachments(paths);
            if (kDebugMode) debugPrint('updateMyProfile: uploaded results for $fieldName -> $uploaded');
            final urls = uploaded.map((it) => (it['url'] ?? '').toString()).where((u) => u.isNotEmpty).toList();
            if (urls.isEmpty) continue;
            if (fieldName.toLowerCase().contains('portfolio')) {
              payload['portfolio'] = urls.map((u) => {'title': '', 'images': [u]}).toList();
            } else {
              payload[fieldName] = urls;
            }
          } catch (e) {
            if (kDebugMode) debugPrint('updateMyProfile: upload for $fieldName failed: $e');
          }
        }
      }

      // Detect any embedded data URI images in payload['portfolio'], write them to
      /// temporary files, upload them using attachments/direct upload, and replace
      /// the embedded data URIs with returned URLs in-place. This prevents sending
      /// raw base64 data to the server.
      await _processEmbeddedDataUris(payload);

      // Recursively walk payload and remove any string values that are data URIs (start with 'data:')
      _stripDataUrisFromPayload(payload);

      // Ensure portfolio doesn't contain raw/base64 strings before sending
      _sanitizePortfolio(payload);
      if (kDebugMode) debugPrint('updateMyProfile: payload after sanitization -> ${payload['portfolio']}');
      final uri = '$API_BASE_URL/api/artisans/me';
      final resp = await ApiClient.put(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload));
       final int? status = (resp['status'] is int) ? resp['status'] as int : null;
      if (kDebugMode) debugPrint('ArtistService.updateMyProfile -> $uri status=$status body=${resp['body']}');
      if (status != null && status >= 200 && status < 300) {
        final body = jsonDecode(resp['body']);
        if (body is Map && body['data'] is Map) return Map<String, dynamic>.from(body['data']);
        if (body is Map) return Map<String, dynamic>.from(body);
      } else {
        // Non-successful response: attempt to parse friendly message and if resource
        // is missing, fall back to creating the artisan profile.
        final b = resp['body']?.toString() ?? '';
        String friendly = 'Server responded with status ${status ?? 'unknown'}';
        try {
          final parsed = b.isNotEmpty ? jsonDecode(b) : null;
          if (parsed is Map && (parsed['message'] != null || parsed['error'] != null)) friendly = (parsed['message'] ?? parsed['error']).toString();
          else if (b.isNotEmpty) friendly = b;
        } catch (_) {
          if (b.isNotEmpty) friendly = b;
        }

        // If server indicates that the artisan profile does not exist, attempt to create it
        if (status == 404 || friendly.toLowerCase().contains('artisan profile not found') || friendly.toLowerCase().contains('artisan not found')) {
          if (kDebugMode) debugPrint('ArtistService.updateMyProfile -> profile not found, attempting to create artisan profile... payload=$payload');
          try {
            final createUri = '$API_BASE_URL/api/artisans';
            final createResp = await ApiClient.post(createUri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload));
            final int? createStatus = (createResp['status'] is int) ? createResp['status'] as int : null;
            if (kDebugMode) debugPrint('ArtistService.createMyProfile -> $createUri status=$createStatus body=${createResp['body']}');
            if (createStatus != null && createStatus >= 200 && createStatus < 300) {
              final createdBody = jsonDecode(createResp['body']);
              if (createdBody is Map && createdBody['data'] is Map) return Map<String, dynamic>.from(createdBody['data']);
              if (createdBody is Map) return Map<String, dynamic>.from(createdBody);
            }
            final cb = createResp['body']?.toString() ?? '';
            String cmsg = 'Failed to create artisan profile';
            try {
              final parsed = cb.isNotEmpty ? jsonDecode(cb) : null;
              if (parsed is Map && (parsed['message'] != null || parsed['error'] != null)) cmsg = (parsed['message'] ?? parsed['error']).toString();
              else if (cb.isNotEmpty) cmsg = cb;
            } catch (_) {
              if (cb.isNotEmpty) cmsg = cb;
            }
            throw Exception(cmsg);
          } catch (e) {
            throw Exception('Failed to create artisan profile: $e');
          }
        }

        // Not a not-found case: rethrow server error for UI to humanize
        throw Exception('Failed to update artisan profile: $friendly');
      }
    } catch (e) {
      // Rethrow as Exception so callers can humanize and display the message
      throw Exception('Network error while updating artisan profile: $e');
    }

    return null;
   }

  /// Upload local files to a dedicated attachments endpoint. Tries common
  /// candidate endpoints and returns a list of maps { 'localPath': ..., 'url': ... }
  /// Throws MultipartRejectedException if server consistently rejects multipart.
  static Future<List<Map<String, String>>> uploadFilesToAttachments(List<String> localPaths, {int maxFileSizeBytes = 10 * 1024 * 1024}) async {
    final token = await TokenStorage.getToken();
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';

    final candidateEndpoints = [
      '$API_BASE_URL/api/uploads',
      '$API_BASE_URL/api/uploads/images',
      '$API_BASE_URL/api/attachments',
      '$API_BASE_URL/api/files'
    ];

    // Prepare file payloads for attachments endpoints (small files only). Also
    // collect all existing local files to attempt direct signed uploads if
    // attachments endpoints reject multipart.
    final filesPayload = <Map<String, String>>[]; // for JSON POST to attachments endpoints
    final allExistingFiles = <String>[]; // used for direct Cloudinary uploads
    for (final path in localPaths) {
      try {
        final f = File(path);
        if (!await f.exists()) continue;
        allExistingFiles.add(path);
        final bytes = await f.readAsBytes();
        if (bytes.lengthInBytes > maxFileSizeBytes) {
          if (kDebugMode) debugPrint('uploadFilesToAttachments: will skip attachments JSON for $path - size ${bytes.lengthInBytes} bytes > $maxFileSizeBytes, but will try direct signed upload');
          continue; // don't add to JSON payload, but keep for direct upload
        }
        final b64 = base64Encode(bytes);
        filesPayload.add({'name': p.basename(path), 'content': b64});
      } catch (e) {
        if (kDebugMode) debugPrint('uploadFilesToAttachments: failed to prepare $path: $e');
      }
    }
    if (kDebugMode) debugPrint('uploadFilesToAttachments -> prepared filesPayload count=${filesPayload.length} allExistingFiles count=${allExistingFiles.length}');

    // If we have no small files for attachments endpoints, we still may
    // attempt direct signed uploads below using allExistingFiles.
    if (filesPayload.isEmpty && allExistingFiles.isEmpty) return [];

    final endpointErrors = <String>[];
    // Try candidate endpoints first (server-side attachments endpoints)
    for (final endpoint in candidateEndpoints) {
      try {
        final body = jsonEncode({'files': filesPayload});
        final resp = await ApiClient.post(endpoint, headers: headers, body: body);
        final int? status = (resp['status'] is int) ? resp['status'] as int : null;
        if (status != null && status >= 200 && status < 300) {
          final respBody = resp['body']?.toString() ?? '';
          if (respBody.isEmpty) return [];
          dynamic parsed;
          try {
            parsed = jsonDecode(respBody);
          } catch (e) {
            // server returned non-json; skip
            endpointErrors.add('$endpoint -> non-json response');
            continue;
          }

          // Normalize many possible response shapes to list of {url}
          final result = <Map<String, String>>[];
          if (parsed is List) {
            for (final it in parsed) {
              if (it is String) {
                final s = it.trim();
                // Accept only http(s) or server-relative paths; reject raw base64/data strings
                if (s.startsWith('http://') || s.startsWith('https://')) {
                  result.add({'url': s});
                } else if (s.startsWith('/')) {
                  // prefix with API_BASE_URL
                  result.add({'url': API_BASE_URL + s});
                } else {
                  // not a valid URL - treat as unexpected
                  endpointErrors.add('$endpoint -> returned non-url string (possibly base64)');
                }
              } else if (it is Map && it['url'] != null) {
                final s = it['url'].toString().trim();
                if (s.startsWith('http://') || s.startsWith('https://')) result.add({'url': s});
                else if (s.startsWith('/')) result.add({'url': API_BASE_URL + s});
                else endpointErrors.add('$endpoint -> returned non-url in map.url');
              } else if (it is Map && it['path'] != null) {
                final s = it['path'].toString().trim();
                if (s.startsWith('http://') || s.startsWith('https://')) result.add({'url': s});
                else if (s.startsWith('/')) result.add({'url': API_BASE_URL + s});
                else endpointErrors.add('$endpoint -> returned non-url in map.path');
              }
            }
          } else if (parsed is Map) {
             // common: { data: [ { url: ... } ] }
             if (parsed['data'] is List) {
               for (final it in parsed['data']) {
                 if (it is Map && it['url'] != null) {
                   final s = it['url'].toString().trim();
                   if (s.startsWith('http://') || s.startsWith('https://')) result.add({'url': s});
                   else if (s.startsWith('/')) result.add({'url': API_BASE_URL + s});
                 } else if (it is Map && it['path'] != null) {
                   final s = it['path'].toString().trim();
                   if (s.startsWith('http://') || s.startsWith('https://')) result.add({'url': s});
                   else if (s.startsWith('/')) result.add({'url': API_BASE_URL + s});
                 }
               }
             } else if (parsed['urls'] is List) {
               for (final u in parsed['urls']) {
                 if (u is String) {
                   final s = u.trim();
                   if (s.startsWith('http://') || s.startsWith('https://')) result.add({'url': s});
                   else if (s.startsWith('/')) result.add({'url': API_BASE_URL + s});
                   else endpointErrors.add('$endpoint -> returned non-url in urls list');
                 }
               }
              } else if (parsed['url'] is String) {
               final s = parsed['url'].toString().trim();
               if (s.startsWith('http://') || s.startsWith('https://')) result.add({'url': s});
               else if (s.startsWith('/')) result.add({'url': API_BASE_URL + s});
              } else if (parsed['path'] is String) {
               final s = parsed['path'].toString().trim();
               if (s.startsWith('http://') || s.startsWith('https://')) result.add({'url': s});
               else if (s.startsWith('/')) result.add({'url': API_BASE_URL + s});
             }
           }

          if (result.isNotEmpty) return result;
          endpointErrors.add('$endpoint -> unexpected JSON shape');
        } else {
          final b = resp['body']?.toString() ?? '';
          endpointErrors.add('$endpoint -> status ${status ?? 'unknown'} body: ${b.length > 200 ? b.substring(0,200) + "..." : b}');
          if (b.contains('502') || b.contains('Bad Gateway') || b.contains('<html')) {
            continue;
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('uploadFilesToAttachments: endpoint $endpoint failed: $e');
        endpointErrors.add('$endpoint -> exception: $e');
        // try next endpoint
        continue;
      }
    }

    // If server endpoints failed, attempt direct signed uploads to Cloudinary using UploadService
    // This requires the backend to implement POST /api/uploads/sign that returns signature/timestamp and optionally upload_url
    final directResults = <Map<String, String>>[];
    final fileErrors = <String>[];
    for (final localPath in allExistingFiles) {
      try {
        final file = File(localPath);
        if (!file.existsSync()) { fileErrors.add('$localPath -> file not found'); continue; }
        // request signature from server (UploadService takes care of the POST)
        Map<String, dynamic> signData;
        try {
          signData = await UploadService.requestSignature(folder: 'artisans');
        } catch (e) {
          if (kDebugMode) debugPrint('uploadFilesToAttachments: signature request failed: $e');
          fileErrors.add('signature request failed: $e');
          break; // no point continuing if signature request fails
        }
        // attempt direct upload
        final uploaded = await UploadService.uploadFileDirect(file: file, signData: signData);
        final url = (uploaded['url'] as String?) ?? (uploaded['raw']?['secure_url'] as String?);
        final publicId = (uploaded['public_id'] as String?) ?? (uploaded['raw']?['public_id'] as String?);
        if (url != null && url.isNotEmpty) {
          directResults.add({'url': url, 'public_id': publicId ?? ''});
        } else {
          fileErrors.add('$localPath -> cloud upload returned no url');
        }
      } catch (e) {
        if (kDebugMode) debugPrint('uploadFilesToAttachments: direct upload for $localPath failed: $e');
        fileErrors.add('$localPath -> $e');
        // continue to next file
        continue;
      }
    }

    if (directResults.isNotEmpty) return directResults;

    // If we get here, no endpoint succeeded - construct a helpful message
    final details = <String>[];
    if (endpointErrors.isNotEmpty) details.add('endpoint errors:\n' + endpointErrors.join('\n'));
    if (fileErrors.isNotEmpty) details.add('file errors:\n' + fileErrors.join('\n'));
    final combined = details.isNotEmpty ? details.join('\n') : 'unknown error';
    throw MultipartRejectedException('Failed to upload files to attachments endpoints. Details: $combined');
  }

  /// Detect any embedded data URI images in payload['portfolio'], write them to
  /// temporary files, upload them using attachments/direct upload, and replace
  /// the embedded data URIs with returned URLs in-place. This prevents sending
  /// raw base64 data to the server.
  static Future<void> _processEmbeddedDataUris(Map<String, dynamic> payload) async {
     try {
       if (payload['portfolio'] is! List) return;
       final list = payload['portfolio'] as List;
       final tempFiles = <String>[]; // list of temp file paths we create
       final mapping = <String, String>{}; // tempPath -> uploadedUrl

       // Collect all data URI images and write to temp files
       for (var itemIndex = 0; itemIndex < list.length; itemIndex++) {
         final item = list[itemIndex];
         if (item is! Map) continue;
         if (item['images'] is! List) continue;
         final images = item['images'] as List;
         for (var imgIndex = 0; imgIndex < images.length; imgIndex++) {
           final img = images[imgIndex];
           if (img is String && img.trim().startsWith('data:')) {
             final s = img.trim();
             try {
               // data:[<mime type>][;base64],<data>
               final parts = s.split(',');
               if (parts.length < 2) continue;
               final meta = parts[0];
               final b64 = parts.sublist(1).join(',');
               final data = base64Decode(b64);
               // determine extension from mime
               String ext = '.jpg';
               if (meta.contains('image/png')) ext = '.png';
               else if (meta.contains('image/webp')) ext = '.webp';
               else if (meta.contains('image/gif')) ext = '.gif';
               else if (meta.contains('image/svg+xml')) ext = '.svg';

               final tmp = File('${Directory.systemTemp.path}/rijhub_datauri_${DateTime.now().microsecondsSinceEpoch}_${tempFiles.length}$ext');
               await tmp.writeAsBytes(data, flush: true);
               tempFiles.add(tmp.path);

               // replace the data URI in-place with a temporary placeholder (we will replace again with URL)
               images[imgIndex] = tmp.path;
             } catch (e) {
               if (kDebugMode) debugPrint('Failed to process embedded data URI: $e');
               // Leave the original data URI for now; it will be sanitized out later
             }
           }
         }
       }

       if (tempFiles.isEmpty) return;

       // Attempt to upload all created temp files using existing attachment/direct upload flow
       List<Map<String, String>> uploaded = [];
       try {
         uploaded = await uploadFilesToAttachments(tempFiles);
       } catch (e) {
         if (kDebugMode) debugPrint('uploadFilesToAttachments for embedded data URIs failed: $e');
         // Attempt per-file direct upload as a last resort
         for (final pth in tempFiles) {
           try {
             final file = File(pth);
             if (!file.existsSync()) continue;
             final signData = await UploadService.requestSignature(folder: 'artisans');
             final up = await UploadService.uploadFileDirect(file: file, signData: signData);
             final url = (up['url'] as String?) ?? (up['raw']?['secure_url'] as String?);
             if (url != null && url.isNotEmpty) uploaded.add({'url': url});
           } catch (e2) {
             if (kDebugMode) debugPrint('Direct upload for embedded file $pth failed: $e2');
           }
         }
       }

       // Map uploaded results back to temp files. uploadFilesToAttachments preserves order
       // in most cases; we map by index.
       for (var i = 0; i < tempFiles.length && i < uploaded.length; i++) {
         final t = tempFiles[i];
         final u = uploaded[i];
         final url = (u['url'] ?? '').toString();
         if (url.isNotEmpty) mapping[t] = url;
       }

       // Replace temporary file paths in payload (we previously replaced data URIs with tmp paths)
       for (var itemIndex = 0; itemIndex < list.length; itemIndex++) {
         final item = list[itemIndex];
         if (item is! Map) continue;
         if (item['images'] is! List) continue;
         final images = item['images'] as List;
         for (var imgIndex = 0; imgIndex < images.length; imgIndex++) {
           final img = images[imgIndex];
           if (img is String && mapping.containsKey(img)) {
             images[imgIndex] = mapping[img];
           } else if (img is String && img.startsWith(Directory.systemTemp.path) && !mapping.containsKey(img)) {
             // upload failed for this temp file -> remove it from list to avoid sending base64
             images[imgIndex] = null;
           }
         }
         // Remove null entries and non-string entries
         item['images'] = images.whereType<String>().where((e) => e.isNotEmpty).toList();
       }

       // Clean up temp files
       for (final t in tempFiles) {
         try {
           final f = File(t);
           if (await f.exists()) await f.delete();
         } catch (_) {}
       }
     } catch (e) {
       if (kDebugMode) debugPrint('Error in _processEmbeddedDataUris: $e');
     }
   }

  // Helper: keep only valid URLs in payload['portfolio'] to avoid sending raw base64 strings
  static void _sanitizePortfolio(Map<String, dynamic> payload) {
     try {
       if (payload['portfolio'] is List) {
         final list = payload['portfolio'] as List;
         final sanitized = <Map<String, dynamic>>[];
         for (final item in list) {
           try {
             if (item is Map) {
               final title = item['title']?.toString() ?? '';
               final images = <String>[];
               if (item['images'] is List) {
                 for (final img in item['images']) {
                   if (img is String) {
                     final s = img.trim();
                     // Accept: absolute http(s) URLs or server-relative paths
                     final looksLikeUrl = s.startsWith('http://') || s.startsWith('https://') || s.startsWith('/');
                     // Detect obvious base64/data-URI patterns: data:*;base64, or long strings composed only of base64 chars
                     final isDataUri = s.startsWith('data:') || s.contains('base64,');
                     final base64Only = RegExp(r'^[A-Za-z0-9+/=\r\n]+$');
                     final looksLikeLongBase64 = s.length > 300 && base64Only.hasMatch(s.replaceAll('\n', ''));
                     final looksLikeBase64 = isDataUri || looksLikeLongBase64;
                     if (looksLikeUrl && !looksLikeBase64) {
                       if (s.startsWith('/')) images.add(API_BASE_URL + s);
                       else images.add(s);
                     }
                   }
                 }
               }
               sanitized.add({'title': title, 'images': images});
             }
           } catch (_) {}
         }
         payload['portfolio'] = sanitized;
       }
     } catch (_) {}
   }

  // Recursively walk payload and remove any string values that are data URIs (start with 'data:')
  static void _stripDataUrisFromPayload(dynamic node) {
    try {
      if (node is Map) {
        final keys = node.keys.toList();
        for (final k in keys) {
          final v = node[k];
          if (v is String) {
            if (v.trim().startsWith('data:')) {
              node.remove(k);
            }
          } else if (v is List || v is Map) {
            _stripDataUrisFromPayload(v);
          }
        }
      } else if (node is List) {
        for (var i = node.length - 1; i >= 0; i--) {
          final v = node[i];
          if (v is String) {
            if (v.trim().startsWith('data:')) {
              node.removeAt(i);
            }
          } else if (v is List || v is Map) {
            _stripDataUrisFromPayload(v);
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error stripping data URIs from payload: $e');
    }
  }

  /// Try to locate an artisan profile by the user id. This is a best-effort
  /// fallback for servers that don't support /api/artisans/me or when the
  /// authenticated token doesn't map. Tries several endpoints and returns the
  /// first matching artisan map or null.
  static Future<Map<String, dynamic>?> getByUserId(String userId) async {
     if (userId.isEmpty) return null;
     _lastGetByUserIdHad200 = false;
     final candidates = [
       '$API_BASE_URL/api/artisans?userId=$userId',
       '$API_BASE_URL/api/artisans/user/$userId',
       '$API_BASE_URL/api/artisans/$userId',
     ];
     for (final url in candidates) {
       try {
         if (kDebugMode) debugPrint('ArtistService.getByUserId -> trying $url');
         final resp = await ApiClient.get(url, headers: {'Content-Type': 'application/json'});
         if (kDebugMode) debugPrint('ArtistService.getByUserId -> resp status=${resp['status']}');
         if (resp['status'] is int && resp['status'] >= 200 && resp['status'] < 300) {
           dynamic body = (resp['body'] != null && resp['body'] is String && (resp['body'] as String).isNotEmpty) ? jsonDecode(resp['body']) : resp['json'];
           if (body == null) continue;

           // helper to check whether an artisan/map belongs to the requested userId
           bool _matchesRequestedUser(dynamic candidate) {
             try {
               if (candidate == null || candidate is! Map) return false;
               final m = Map<String, dynamic>.from(Map.castFrom(candidate));
               final ids = <String>[];
               if (m.containsKey('userId') && m['userId'] != null) ids.add(m['userId'].toString());
               if (m.containsKey('user_id') && m['user_id'] != null) ids.add(m['user_id'].toString());
               if (m.containsKey('_id') && m['_id'] != null) ids.add(m['_id'].toString());
               if (m['user'] is Map && m['user']['_id'] != null) ids.add(m['user']['_id'].toString());
               return ids.any((id) => id == userId);
             } catch (_) {
               return false;
             }
           }

           // If the body is a List, search for a matching artisan by user id.
           if (body is List) {
             if (body.isEmpty) continue; // explicit: empty list => not found
             for (final it in body) {
               try {
                 if (it is Map && _matchesRequestedUser(it)) return Map<String, dynamic>.from(Map.castFrom(it));
               } catch (_) {}
             }
             // No matching entry found in the returned list -> try next candidate endpoint
             continue;
           }

           // If body has a data wrapper
           if (body is Map && body['data'] is List) {
             final lst = (body['data'] as List);
             if (lst.isEmpty) continue;
             for (final it in lst) {
               try {
                 if (it is Map && _matchesRequestedUser(it)) return Map<String, dynamic>.from(Map.castFrom(it));
               } catch (_) {}
             }
             continue;
           }

           // If data is a single object inside 'data', verify ownership before returning
           if (body is Map && body['data'] is Map) {
             final d = Map<String, dynamic>.from(body['data']);
             if (_matchesRequestedUser(d)) return d;
             // not a match -> continue to other endpoints
             continue;
           }

           // If the response is a plain Map that looks like an artisan object, ensure it matches the userId
           if (body is Map) {
             final m = Map<String, dynamic>.from(body);
             if (_matchesRequestedUser(m)) return m;
             // If it doesn't match, skip and try next candidate
             continue;
           }
         }
       } catch (e) {
         if (kDebugMode) debugPrint('ArtistService.getByUserId -> candidate $url failed: $e');
       }
     }
     return null;
   }
}
