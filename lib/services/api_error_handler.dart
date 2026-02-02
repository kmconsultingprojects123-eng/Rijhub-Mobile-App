import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Minimal, reusable API error handling and safe http wrappers for the project.
///
/// Features:
/// - Wraps http.get/post/put/delete and multipart upload with centralized error handling
/// - Maps HTTP status codes and HTML error pages to friendly messages
/// - Logs full technical details (only to console) but shows only friendly messages to users
/// - Returns an [ApiResponse] object for callers to inspect and conditionally show UI

class ApiResponse {
  final bool ok;
  final int? statusCode;
  final dynamic data; // decoded JSON or raw string
  final String message; // friendly message
  final String? raw; // raw body for debugging

  ApiResponse({
    required this.ok,
    this.statusCode,
    this.data,
    required this.message,
    this.raw,
  });
}

class ApiErrorHandler {
  // Map of HTTP status codes to friendly messages
  static const Map<int, String> _statusMessages = {
    400: 'Some of the information you entered is incorrect.',
    401: 'Your session has expired. Please log in again.',
    403: 'You don\'t have permission to do this.',
    404: 'We couldn\'t find what you were looking for.',
    413: 'This file is too large. Please upload a file smaller than 5MB.',
    422: 'Some of your input is invalid.',
    429: 'You are sending too many requests. Please wait a moment.',
    500: 'Something went wrong on our side.',
    502: 'Our service is temporarily unavailable. Please try again.',
    503: 'Our service is temporarily unavailable. Please try again.',
    504: 'Our service is temporarily unavailable. Please try again.',
  };

  /// Convert a raw exception or http.Response into a friendly message and an ApiResponse
  static ApiResponse fromException(Object error, {String? url}) {
    final String technical = _technicalForException(error, url: url);
    _logTechnical(technical);

    String friendly;
    if (error is SocketException) {
      friendly = 'Network error. Please check your internet connection.';
    } else if (error is TimeoutException) {
      friendly = 'Request timed out. Please try again.';
    } else if (error is http.ClientException) {
      friendly = 'Network error. Please check your connection.';
    } else {
      friendly = 'Something went wrong. Please try again.';
    }

    return ApiResponse(ok: false, message: friendly, raw: technical);
  }

  /// Handle a successful HTTP response (may still be error status code)
  static ApiResponse fromHttpResponse(http.Response resp, {String? url, bool isFileUpload = false}) {
    final int status = resp.statusCode;
    final String body = resp.body;

    final String technical = 'HTTP ${resp.statusCode} ${url ?? ''}\nheaders=${resp.headers}\nbody=${body}';
    _logTechnical(technical);

    // Detect HTML error pages
    if (_isHtml(body) || (resp.headers['content-type']?.contains('text/html') ?? false)) {
      // Map common server HTML pages to friendly messages (especially file upload 413)
      if (status == 413 || body.toLowerCase().contains('request entity too large')) {
        return ApiResponse(ok: false, statusCode: status, message: _statusMessages[413]!, raw: technical);
      }

      // Generic server unavailable
      if (status == 502 || status == 503 || status == 504) {
        return ApiResponse(ok: false, statusCode: status, message: _statusMessages[status]!, raw: technical);
      }

      return ApiResponse(ok: false, statusCode: status, message: _friendlyForStatus(status), raw: technical);
    }

    // Try decode JSON
    dynamic decoded;
    try {
      decoded = body.isNotEmpty ? json.decode(body) : null;
    } catch (e) {
      // Not JSON - if success code return raw, otherwise map to friendly
      if (status >= 200 && status < 300) {
        return ApiResponse(ok: true, statusCode: status, data: body, message: 'OK', raw: technical);
      }
      return ApiResponse(ok: false, statusCode: status, message: _friendlyForStatus(status), raw: technical);
    }

    // If status is success, return decoded
    if (status >= 200 && status < 300) {
      return ApiResponse(ok: true, statusCode: status, data: decoded, message: 'OK', raw: technical);
    }

    // Non-success JSON response: map known status codes and try to extract server message safely
    String friendly = _friendlyForStatus(status);

    // Try to extract meaningful message from JSON without exposing raw traces
    if (decoded is Map) {
      // Common keys: message, error, errors
      if (decoded['message'] is String) {
        // Optionally include short server message but don't reveal raw stack traces
        final String s = decoded['message'];
        if (!_looksTechnical(s)) {
          friendly = s;
        }
      } else if (decoded['error'] is String) {
        final String s = decoded['error'];
        if (!_looksTechnical(s)) friendly = s;
      }
    }

    // File upload specific handling
    if (isFileUpload && (status == 413 || (body.toLowerCase().contains('request entity too large')))) {
      friendly = _statusMessages[413]!;
    }

    return ApiResponse(ok: false, statusCode: status, data: decoded, message: friendly, raw: technical);
  }

  static String _friendlyForStatus(int status) {
    return _statusMessages[status] ?? 'Something went wrong. Please try again.';
  }

  static bool _isHtml(String body) {
    final String s = body.trimLeft().toLowerCase();
    if (s.startsWith('<!doctype html') || s.startsWith('<html') || s.contains('<html') || s.contains('<!doctype')) return true;
    if (s.contains('<head>') && s.contains('<body')) return true;
    return false;
  }

  static bool _looksTechnical(String s) {
    final low = s.toLowerCase();
    // crude heuristics: stacktrace keywords, html tags, exception names
    final techKeywords = ['stack', 'exception', 'at ', '<html', '<!doctype', 'trace'];
    return techKeywords.any((k) => low.contains(k));
  }

  static String _technicalForException(Object e, {String? url}) {
    return 'Exception for ${url ?? ''}: ${e.runtimeType} - ${e.toString()}';
  }

  static void _logTechnical(String text) {
    // Always print to console for developers, but avoid showing to users
    if (kDebugMode) {
      debugPrint('API_TECHNICAL: $text');
    } else {
      // In release we still log but use debugPrint (it will be available to OS logs)
      debugPrint('API_TECHNICAL: $text');
    }
  }

  /// Helper to show a friendly message in the UI. Prefer SnackBar but caller can override.
  static void showUserMessage(BuildContext context, String message, {Duration duration = const Duration(seconds: 4)}) {
    try {
      ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), duration: duration));
    } catch (e) {
      // Fallback, in case there is no Scaffold
      debugPrint('Could not show SnackBar: $e');
    }
  }
}

/// Lightweight ApiClient with safe wrappers that route all errors through ApiErrorHandler.
class ApiClient {
  final Map<String, String> defaultHeaders;
  final Duration timeout;

  ApiClient({Map<String, String>? defaultHeaders, Duration? timeout})
      : defaultHeaders = defaultHeaders ?? {'Accept': 'application/json'},
        timeout = timeout ?? const Duration(seconds: 30);

  Future<ApiResponse> safeGet(String url, {Map<String, String>? headers, BuildContext? context}) async {
    try {
      final resp = await http.get(Uri.parse(url), headers: {...defaultHeaders, ...?headers}).timeout(timeout);
      final result = ApiErrorHandler.fromHttpResponse(resp, url: url);
      if (!result.ok && context != null) ApiErrorHandler.showUserMessage(context, result.message);
      return result;
    } on Object catch (e) {
      final res = ApiErrorHandler.fromException(e, url: url);
      if (context != null) ApiErrorHandler.showUserMessage(context, res.message);
      return res;
    }
  }

  Future<ApiResponse> safePost(String url, {Map<String, String>? headers, dynamic body, BuildContext? context}) async {
    try {
      final Map<String, String> h = {...defaultHeaders, ...?headers};
      if (body != null && body is! String && !h.containsKey('Content-Type')) {
        h['Content-Type'] = 'application/json';
      }
      final resp = await http
          .post(Uri.parse(url), headers: h, body: body is String ? body : (body != null ? json.encode(body) : null))
          .timeout(timeout);
      final result = ApiErrorHandler.fromHttpResponse(resp, url: url);
      if (!result.ok && context != null) ApiErrorHandler.showUserMessage(context, result.message);
      return result;
    } on Object catch (e) {
      final res = ApiErrorHandler.fromException(e, url: url);
      if (context != null) ApiErrorHandler.showUserMessage(context, res.message);
      return res;
    }
  }

  Future<ApiResponse> safePut(String url, {Map<String, String>? headers, dynamic body, BuildContext? context}) async {
    try {
      final Map<String, String> h = {...defaultHeaders, ...?headers};
      if (body != null && body is! String && !h.containsKey('Content-Type')) {
        h['Content-Type'] = 'application/json';
      }
      final resp = await http
          .put(Uri.parse(url), headers: h, body: body is String ? body : (body != null ? json.encode(body) : null))
          .timeout(timeout);
      final result = ApiErrorHandler.fromHttpResponse(resp, url: url);
      if (!result.ok && context != null) ApiErrorHandler.showUserMessage(context, result.message);
      return result;
    } on Object catch (e) {
      final res = ApiErrorHandler.fromException(e, url: url);
      if (context != null) ApiErrorHandler.showUserMessage(context, res.message);
      return res;
    }
  }

  Future<ApiResponse> safeDelete(String url, {Map<String, String>? headers, BuildContext? context}) async {
    try {
      final resp = await http.delete(Uri.parse(url), headers: {...defaultHeaders, ...?headers}).timeout(timeout);
      final result = ApiErrorHandler.fromHttpResponse(resp, url: url);
      if (!result.ok && context != null) ApiErrorHandler.showUserMessage(context, result.message);
      return result;
    } on Object catch (e) {
      final res = ApiErrorHandler.fromException(e, url: url);
      if (context != null) ApiErrorHandler.showUserMessage(context, res.message);
      return res;
    }
  }

  /// Multipart upload helper for files (images). Returns ApiResponse and shows friendly errors when context provided.
  Future<ApiResponse> safeMultipartUpload(
    String url, {
    Map<String, String>? fields,
    Map<String, String>? headers,
    List<File>? files,
    String fileField = 'files',
    BuildContext? context,
  }) async {
    try {
      final uri = Uri.parse(url);
      final req = http.MultipartRequest('POST', uri);
      req.headers.addAll({...defaultHeaders, ...?headers});
      if (fields != null) req.fields.addAll(fields);

      if (files != null) {
        for (int i = 0; i < files.length; i++) {
          final file = files[i];
          final len = await file.length();
          // Simple client-side size check: warn if > 8MB (tunable)
          if (len > 8 * 1024 * 1024) {
            final ApiResponse res = ApiResponse(ok: false, message: 'This file is too large. Please upload a file smaller than 5MB.');
            if (context != null) ApiErrorHandler.showUserMessage(context, res.message);
            return res;
          }

          final stream = http.ByteStream(Stream.castFrom(file.openRead()));
          final multipartFile = http.MultipartFile(fileField, stream, len, filename: file.path.split(Platform.pathSeparator).last);
          req.files.add(multipartFile);
        }
      }

      final streamed = await req.send().timeout(timeout);
      final response = await http.Response.fromStream(streamed);
      final res = ApiErrorHandler.fromHttpResponse(response, url: url, isFileUpload: true);
      if (!res.ok && context != null) ApiErrorHandler.showUserMessage(context, res.message);
      return res;
    } on Object catch (e) {
      final res = ApiErrorHandler.fromException(e);
      if (context != null) ApiErrorHandler.showUserMessage(context, res.message);
      return res;
    }
  }
}

/*
Example usage:

final client = ApiClient();

// GET
final resp = await client.safeGet('https://example.com/api/me', context: context);
if (resp.ok) {
  // use resp.data
} else {
  // resp.message is already user-friendly; optionally show again or rely on safeGet to show
}

// POST JSON
final createResp = await client.safePost('https://example.com/api/artisans', body: {
  'name': 'John',
  'trade': ['Plumber'],
}, context: context);

// Multipart upload (images)
final files = [File('/path/to/img1.jpg'), File('/path/to/img2.jpg')];
final uploadResp = await client.safeMultipartUpload('https://example.com/api/uploads', files: files, fileField: 'portfolioImages', context: context);

*/
