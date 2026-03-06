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
}
