import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import '../api_config.dart';

String _toSnakeCase(String s) {
  // very small converter for common camelCase -> snake_case
  return s.replaceAllMapped(
      RegExp(r'[A-Z]'), (m) => '_${m.group(0)!.toLowerCase()}');
}

String _toCamelCase(String s) {
  if (!s.contains('_')) return s;
  final parts = s.split('_');
  return parts.first +
      parts.skip(1).map((p) => p[0].toUpperCase() + p.substring(1)).join();
}

/// Parse common validation error shapes from server responses into a simple
/// Map<field, message>. The function attempts to handle several shapes:
/// - { errors: { field: 'message' } }
/// - { errors: [ { field, message }, ... ] }
/// - { message: '...', details: { field: 'message' } }
/// - { error: { field: 'message' } }
Map<String, String> parseFieldErrors(http.Response resp) {
  final Map<String, String> out = {};
  try {
    if (resp.body.isEmpty) return out;
    final body = jsonDecode(resp.body);
    if (body is Map) {
      // shape: { errors: { field: msg } }
      if (body['errors'] is Map) {
        (body['errors'] as Map).forEach((k, v) {
          final key = k.toString();
          final msg = v == null ? '' : v.toString();
          out[key] = msg;
          out[_toSnakeCase(key)] = msg;
          out[_toCamelCase(key)] = msg;
        });
        return out;
      }

      // shape: { errors: [ { field, message }, ... ] }
      if (body['errors'] is List) {
        for (final item in (body['errors'] as List)) {
          if (item is Map && item['field'] != null) {
            final key = item['field'].toString();
            final msg = (item['message'] ?? item['msg'] ?? '').toString();
            out[key] = msg;
            out[_toSnakeCase(key)] = msg;
            out[_toCamelCase(key)] = msg;
          }
        }
        return out;
      }

      // shape: { details: { field: message } }
      if (body['details'] is Map) {
        (body['details'] as Map).forEach((k, v) {
          final key = k.toString();
          final msg = v == null ? '' : v.toString();
          out[key] = msg;
          out[_toSnakeCase(key)] = msg;
          out[_toCamelCase(key)] = msg;
        });
        return out;
      }

      // shape: { error: { field: msg } }
      if (body['error'] is Map) {
        (body['error'] as Map).forEach((k, v) {
          final key = k.toString();
          final msg = v == null ? '' : v.toString();
          out[key] = msg;
          out[_toSnakeCase(key)] = msg;
          out[_toCamelCase(key)] = msg;
        });
        return out;
      }
    }
  } catch (e) {
    // ignore parse errors; return empty map
  }
  return out;
}

/// Custom exception that contains a short, user-friendly message that can
/// be safely shown in the UI. The developerMessage field contains full
/// technical details and is intended for logging only.
class UserFriendlyException implements Exception {
  final String userMessage;
  final String? developerMessage;

  UserFriendlyException(this.userMessage, {this.developerMessage});

  @override
  String toString() => 'UserFriendlyException: $userMessage';
}

/// Centralized error mapper: maps HTTP responses and network exceptions
/// to short, human-readable messages suitable for display to end users.
class ErrorMapper {
  /// Map status codes to friendly messages.
  static String mapStatusCode(int statusCode) {
    switch (statusCode) {
      case 400:
        return 'Some of the information you entered is incorrect.';
      case 401:
        return 'Your session has expired. Please log in again.';
      case 403:
        return 'You don\'t have permission to do this.';
      case 404:
        return 'We couldn\'t find what you were looking for.';
      case 413:
        // Special user-facing message for large uploads (per request)
        return 'One or more uploaded files are too large. Please reduce the image size and try again.';
      case 422:
        return 'Some of your input is invalid.';
      case 429:
        return 'You are sending too many requests. Please wait a moment.';
      case 500:
        return 'Something went wrong on our side.';
      case 502:
      case 503:
      case 504:
        return 'Our service is temporarily unavailable. Please try again.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }

  /// Detects HTML responses and returns a mapped message. If the status
  /// code indicates a file-size issue (413) prefer that message.
  static String messageForResponse(http.Response resp) {
    final status = resp.statusCode;
    final body = resp.body;

    // If body looks like HTML, do NOT show raw HTML. Map via status code.
    if (body.trimLeft().toLowerCase().startsWith('<') ||
        body.toLowerCase().contains('<html')) {
      // If the html contains explicit 413 text, we still map to the 413 message.
      if (status == 413 ||
          body.toLowerCase().contains('request entity too large') ||
          body.toLowerCase().contains('413')) {
        return mapStatusCode(413);
      }
      return mapStatusCode(status);
    }

    // If body is JSON, we still do not expose raw backend messages to users.
    // Prefer status-based messages. For 400/422 we might show a more helpful
    // hint, but still generic.
    return mapStatusCode(status);
  }

  /// Converts exceptions (SocketException, TimeoutException, etc) into a
  /// friendly message. Also logs the technical message for developers.
  static String messageForException(Object e) {
    if (e is SocketException) {
      return 'No internet connection. Please check your network and try again.';
    }
    if (e is TimeoutException) {
      return 'Request timed out. Please try again.';
    }
    // Fallback
    return 'Something went wrong. Please try again.';
  }
}

class KycService {
  // Submits KYC via multipart/form-data.
  // filesByFieldName: map field -> list of File (to support multi files)
  // On success returns http.Response (2xx). On failure throws UserFriendlyException
  // with a short message safe for showing to end users. Full technical details
  // are logged using developer.log() and printed.
  static Future<http.Response> submitKyc(
    Map<String, String> fields,
    Map<String, List<File>> filesByFieldName, {
    String? token,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final uri = Uri.parse('$API_BASE_URL/api/kyc/submit');
    final req = http.MultipartRequest('POST', uri);

    if (token != null) {
      req.headers['Authorization'] = 'Bearer $token';
    }

    // Add simple fields
    fields.forEach((k, v) {
      req.fields[k] = v;
    });

    // Add files
    for (final entry in filesByFieldName.entries) {
      final field = entry.key;
      final files = entry.value;
      for (final f in files) {
        try {
          final multipart = await http.MultipartFile.fromPath(field, f.path);
          req.files.add(multipart);
        } catch (e, st) {
          // Log technical file read errors for debugging
          developer.log('Failed to read file for multipart: ${f.path}',
              error: e, stackTrace: st);
          // We don't expose these details to users; throw a friendly message
          throw UserFriendlyException(
              'Failed to attach selected files. Please try again.');
        }
      }
    }

    try {
      final streamed = await req.send().timeout(timeout);
      final resp = await http.Response.fromStream(streamed).timeout(timeout);

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return resp;
      }

      // Non-2xx responses -> map to friendly message and throw
      final developerMessage =
          'KYC submit failed: status=${resp.statusCode} body=${resp.body} headers=${resp.headers}';
      developer.log(developerMessage, name: 'KycService.submitKyc');
      final userMsg = ErrorMapper.messageForResponse(resp);
      throw UserFriendlyException(userMsg, developerMessage: developerMessage);
    } on SocketException catch (e, st) {
      developer.log('Network error during submitKyc',
          error: e, stackTrace: st, name: 'KycService.submitKyc');
      final userMsg = ErrorMapper.messageForException(e);
      throw UserFriendlyException(userMsg, developerMessage: e.toString());
    } on TimeoutException catch (e, st) {
      developer.log('Timeout during submitKyc',
          error: e, stackTrace: st, name: 'KycService.submitKyc');
      final userMsg = ErrorMapper.messageForException(e);
      throw UserFriendlyException(userMsg, developerMessage: e.toString());
    } catch (e, st) {
      developer.log('Unexpected error during submitKyc',
          error: e, stackTrace: st, name: 'KycService.submitKyc');
      // Generic friendly message
      throw UserFriendlyException('Something went wrong. Please try again.');
    }
  }

  /// Submits KYC via direct multipart/form-data to POST /api/kyc/submit.
  /// Files are sent as multipart; backend streams them to Cloudinary.
  /// Throws UserFriendlyException on failure.
  static Future<http.Response> submitKycEnhanced(
    Map<String, String> fields,
    Map<String, List<File>> filesByFieldName, {
    String? token,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    return submitKyc(fields, filesByFieldName, token: token, timeout: timeout);
  }

  /// Dojah NIN + selfie verification.
  /// POST /api/kyc/dojah/nin-selfie (multipart)
  /// Returns the parsed JSON body with shape:
  /// { success, message, data: { status, match, confidenceValue, threshold, user, artisan } }
  /// Possible statuses: 'approved' | 'rejected' | 'pending_review'
  static Future<Map<String, dynamic>> submitDojahNinSelfie({
    required String nin,
    required File selfie,
    String? firstName,
    String? lastName,
    required String token,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final uri = Uri.parse('$API_BASE_URL/api/kyc/dojah/nin-selfie');
    final req = http.MultipartRequest('POST', uri);
    req.headers['Authorization'] = 'Bearer $token';

    req.fields['nin'] = nin;
    if (firstName != null && firstName.isNotEmpty) {
      req.fields['firstName'] = firstName;
    }
    if (lastName != null && lastName.isNotEmpty) {
      req.fields['lastName'] = lastName;
    }

    try {
      req.files.add(await http.MultipartFile.fromPath('selfie', selfie.path));
    } catch (e, st) {
      developer.log('Failed to attach selfie',
          error: e, stackTrace: st, name: 'KycService.submitDojahNinSelfie');
      throw UserFriendlyException(
          'Failed to attach selfie. Please try again.');
    }

    try {
      final streamed = await req.send().timeout(timeout);
      final resp = await http.Response.fromStream(streamed).timeout(timeout);

      developer.log(
          'Dojah NIN-selfie response: status=${resp.statusCode} body=${resp.body}',
          name: 'KycService.submitDojahNinSelfie');

      Map<String, dynamic>? body;
      try {
        if (resp.body.isNotEmpty) body = jsonDecode(resp.body);
      } catch (_) {}

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return body ?? {};
      }

      // Server returned an error envelope; surface the message if present
      final serverMsg = body?['message']?.toString();
      throw UserFriendlyException(
        serverMsg ?? ErrorMapper.messageForResponse(resp),
        developerMessage:
            'Dojah verification failed: status=${resp.statusCode} body=${resp.body}',
      );
    } on UserFriendlyException {
      rethrow;
    } on SocketException catch (e) {
      throw UserFriendlyException(ErrorMapper.messageForException(e),
          developerMessage: e.toString());
    } on TimeoutException catch (e) {
      throw UserFriendlyException(ErrorMapper.messageForException(e),
          developerMessage: e.toString());
    } catch (e, st) {
      developer.log('Unexpected error in submitDojahNinSelfie',
          error: e, stackTrace: st, name: 'KycService.submitDojahNinSelfie');
      throw UserFriendlyException('Something went wrong. Please try again.');
    }
  }

  /// POST /api/kyc/dojah/start-session — asks the backend to seed a fresh
  /// KYC record (status=`pending`, providerStatus=`started`) and hand us a
  /// canonical `referenceId` to pass into the Dojah SDK. Per
  /// `dojah-pending-resolution-mobile.md`, this is the documented entry
  /// point; the SDK echoes the same reference back on success and
  /// `verify-reference` later uses it to look up the final result.
  ///
  /// Returns the `referenceId` string on success, or null on failure (the
  /// caller can then fall back to a client-generated reference to avoid
  /// blocking the flow on a transient backend error).
  static Future<String?> startDojahSession({
    required String token,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final uri = Uri.parse('$API_BASE_URL/api/kyc/dojah/start-session');
    try {
      final resp = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(timeout);

      developer.log(
          'startDojahSession response: status=${resp.statusCode} body=${resp.body}',
          name: 'KycService.startDojahSession');

      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      if (resp.body.isEmpty) return null;
      try {
        final body = jsonDecode(resp.body);
        if (body is Map) {
          // Standard shape: { success: true, data: { referenceId: "..." } }
          final data = body['data'];
          if (data is Map && data['referenceId'] != null) {
            return data['referenceId'].toString();
          }
          // Fallback: top-level referenceId
          if (body['referenceId'] != null) {
            return body['referenceId'].toString();
          }
        }
      } catch (e, st) {
        developer.log('Failed to parse startDojahSession body',
            error: e, stackTrace: st, name: 'KycService.startDojahSession');
      }
      return null;
    } on SocketException catch (e, st) {
      developer.log('Network error in startDojahSession',
          error: e, stackTrace: st, name: 'KycService.startDojahSession');
      return null;
    } on TimeoutException catch (e, st) {
      developer.log('Timeout in startDojahSession',
          error: e, stackTrace: st, name: 'KycService.startDojahSession');
      return null;
    } catch (e, st) {
      developer.log('Unexpected error in startDojahSession',
          error: e, stackTrace: st, name: 'KycService.startDojahSession');
      return null;
    }
  }

  /// POST /api/kyc/dojah/verify-reference — sends a Dojah reference returned
  /// by the native Flutter SDK so the backend can call Dojah's "Get
  /// Verification Details" API server-side and persist the authoritative
  /// status.
  ///
  /// Returns a map with at least `{ 'status': 'approved' | 'rejected' |
  /// 'pending' | 'pending_review' }` plus optional `failureReason` etc.,
  /// matching the envelope of `submitDojahNinSelfie`. If the backend
  /// endpoint hasn't shipped yet (404), returns
  /// `{ 'status': 'pending_review', 'failureReason': 'endpoint_not_ready' }`
  /// so the client can surface a graceful "verification submitted" message
  /// without breaking; the existing GET /api/kyc/status polling will pick
  /// up the real result once the backend ships.
  static Future<Map<String, dynamic>> verifyDojahReference({
    required String referenceId,
    required String token,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final uri = Uri.parse('$API_BASE_URL/api/kyc/dojah/verify-reference');
    try {
      final resp = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'referenceId': referenceId}),
      ).timeout(timeout);

      developer.log(
          'verifyDojahReference response: status=${resp.statusCode} body=${resp.body}',
          name: 'KycService.verifyDojahReference');

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        if (resp.body.isEmpty) return {'status': 'pending'};
        try {
          final body = jsonDecode(resp.body);
          if (body is Map && body['data'] is Map) {
            return Map<String, dynamic>.from(body['data']);
          }
          if (body is Map) return Map<String, dynamic>.from(body);
        } catch (e, st) {
          developer.log('Failed to parse verifyDojahReference body',
              error: e,
              stackTrace: st,
              name: 'KycService.verifyDojahReference');
        }
        return {'status': 'pending'};
      }

      // Backend hasn't shipped the endpoint yet — degrade gracefully.
      // The artisan dashboard's GET /api/kyc/status polling will catch up
      // once the backend is wired.
      if (resp.statusCode == 404) {
        return {
          'status': 'pending_review',
          'failureReason': 'endpoint_not_ready',
        };
      }

      throw UserFriendlyException(ErrorMapper.messageForResponse(resp),
          developerMessage:
              'verifyDojahReference failed: status=${resp.statusCode} body=${resp.body}');
    } on UserFriendlyException {
      rethrow;
    } on SocketException catch (e, st) {
      developer.log('Network error in verifyDojahReference',
          error: e, stackTrace: st, name: 'KycService.verifyDojahReference');
      throw UserFriendlyException(ErrorMapper.messageForException(e),
          developerMessage: e.toString());
    } on TimeoutException catch (e, st) {
      developer.log('Timeout in verifyDojahReference',
          error: e, stackTrace: st, name: 'KycService.verifyDojahReference');
      throw UserFriendlyException(ErrorMapper.messageForException(e),
          developerMessage: e.toString());
    } catch (e, st) {
      developer.log('Unexpected error in verifyDojahReference',
          error: e, stackTrace: st, name: 'KycService.verifyDojahReference');
      throw UserFriendlyException('Something went wrong. Please try again.',
          developerMessage: e.toString());
    }
  }

  /// GET /api/kyc/artisan/:id/status — returns the latest KYC state for an
  /// arbitrary artisan (by artisan profile `_id` OR linked `userId`). Used
  /// by client-facing screens (artisan profile, search results, booking
  /// detail) to render verified/pending/rejected badges without needing
  /// the artisan to be the authenticated user.
  ///
  /// Optional auth — pass a token if you have one (richer response), but it
  /// also works for unauthenticated browsing.
  ///
  /// Possible statuses: 'approved' | 'pending' | 'pending_review' |
  /// 'rejected' | 'not_submitted'.
  /// Returns the unwrapped `data` object, or null if the artisan / endpoint
  /// returned an error envelope.
  static Future<Map<String, dynamic>?> getArtisanKycStatus({
    required String artisanIdOrUserId,
    String? token,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final uri = Uri.parse(
        '$API_BASE_URL/api/kyc/artisan/$artisanIdOrUserId/status');
    try {
      final headers = <String, String>{};
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
      final resp = await http.get(uri, headers: headers).timeout(timeout);

      developer.log(
          'getArtisanKycStatus($artisanIdOrUserId) response: status=${resp.statusCode} body=${resp.body}',
          name: 'KycService.getArtisanKycStatus');

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        if (resp.body.isEmpty) return null;
        try {
          final body = jsonDecode(resp.body);
          if (body is Map && body['data'] is Map) {
            return Map<String, dynamic>.from(body['data']);
          }
          if (body is Map) return Map<String, dynamic>.from(body);
        } catch (e, st) {
          developer.log('Failed to parse getArtisanKycStatus body',
              error: e, stackTrace: st, name: 'KycService.getArtisanKycStatus');
        }
        return null;
      }

      // 404 means artisan not found or invalid id — surface as null rather
      // than throwing so callers can render a "not verified" badge cleanly.
      if (resp.statusCode == 404) return null;

      throw UserFriendlyException(ErrorMapper.messageForResponse(resp),
          developerMessage:
              'getArtisanKycStatus failed: status=${resp.statusCode} body=${resp.body}');
    } on UserFriendlyException {
      rethrow;
    } on SocketException catch (e, st) {
      developer.log('Network error in getArtisanKycStatus',
          error: e, stackTrace: st, name: 'KycService.getArtisanKycStatus');
      throw UserFriendlyException(ErrorMapper.messageForException(e),
          developerMessage: e.toString());
    } on TimeoutException catch (e, st) {
      developer.log('Timeout in getArtisanKycStatus',
          error: e, stackTrace: st, name: 'KycService.getArtisanKycStatus');
      throw UserFriendlyException(ErrorMapper.messageForException(e),
          developerMessage: e.toString());
    } catch (e, st) {
      developer.log('Unexpected error in getArtisanKycStatus',
          error: e, stackTrace: st, name: 'KycService.getArtisanKycStatus');
      throw UserFriendlyException('Something went wrong. Please try again.',
          developerMessage: e.toString());
    }
  }

  /// GET /api/kyc/status — returns the latest KYC state for the authenticated user.
  /// Possible statuses: 'pending' | 'pending_review' | 'approved' | 'rejected' | 'not_submitted'
  /// Response also includes `failureReason` (string|null) when status is rejected.
  /// Returns the unwrapped `data` object, or an empty map if the body is empty.
  static Future<Map<String, dynamic>> getKycStatus({
    required String token,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final uri = Uri.parse('$API_BASE_URL/api/kyc/status');
    try {
      final resp = await http.get(uri, headers: {
        'Authorization': 'Bearer $token',
      }).timeout(timeout);

      developer.log(
          'getKycStatus response: status=${resp.statusCode} body=${resp.body}',
          name: 'KycService.getKycStatus');

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        if (resp.body.isEmpty) return {};
        try {
          final body = jsonDecode(resp.body);
          if (body is Map && body['data'] is Map) {
            return Map<String, dynamic>.from(body['data']);
          }
          if (body is Map) return Map<String, dynamic>.from(body);
        } catch (e, st) {
          developer.log('Failed to parse getKycStatus body',
              error: e, stackTrace: st, name: 'KycService.getKycStatus');
          throw UserFriendlyException(
              'Could not read verification status. Please try again.',
              developerMessage: 'JSON parse failed: ${resp.body}');
        }
        return {};
      }

      throw UserFriendlyException(ErrorMapper.messageForResponse(resp),
          developerMessage:
              'getKycStatus failed: status=${resp.statusCode} body=${resp.body}');
    } on UserFriendlyException {
      rethrow;
    } on SocketException catch (e, st) {
      developer.log('Network error in getKycStatus',
          error: e, stackTrace: st, name: 'KycService.getKycStatus');
      throw UserFriendlyException(ErrorMapper.messageForException(e),
          developerMessage: e.toString());
    } on TimeoutException catch (e, st) {
      developer.log('Timeout in getKycStatus',
          error: e, stackTrace: st, name: 'KycService.getKycStatus');
      throw UserFriendlyException(ErrorMapper.messageForException(e),
          developerMessage: e.toString());
    } catch (e, st) {
      developer.log('Unexpected error in getKycStatus',
          error: e, stackTrace: st, name: 'KycService.getKycStatus');
      throw UserFriendlyException('Something went wrong. Please try again.',
          developerMessage: e.toString());
    }
  }
}
