import 'package:http/http.dart' as http;
import 'token_storage.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:async';

class ApiClient {
  // Internal helper: perform HTTP request with retries and timeout.
  // method: 'GET', 'POST', 'PUT'
  static Future<http.Response> _requestWithRetries(String method, Uri uri,
      {Map<String, String>? headers,
      Object? body,
      int timeoutSeconds = 15,
      int maxAttempts = 2,
      Duration retryDelay = const Duration(milliseconds: 700)}) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      // ┌──────────────────────────────────────────────────────────────────────────────
      // │ API Logger - Request
      // └──────────────────────────────────────────────────────────────────────────────
      print(
          '┌──────────────────────────────────────────────────────────────────────────────');
      print('│ [API Request] $method $uri');
      if (headers != null && headers.isNotEmpty) {
        print('│ Headers:');
        headers.forEach((k, v) => print('│   $k: $v'));
      }
      if (body != null) {
        print('│ Body: $body');
      }
      print(
          '└──────────────────────────────────────────────────────────────────────────────');

      try {
        late http.Response resp;
        if (method == 'GET') {
          resp = await http
              .get(uri, headers: headers)
              .timeout(Duration(seconds: timeoutSeconds));
        } else if (method == 'POST') {
          resp = await http
              .post(uri, headers: headers, body: body)
              .timeout(Duration(seconds: timeoutSeconds));
        } else if (method == 'PUT') {
          resp = await http
              .put(uri, headers: headers, body: body)
              .timeout(Duration(seconds: timeoutSeconds));
        } else {
          throw UnsupportedError('Unsupported method $method');
        }

        // ┌──────────────────────────────────────────────────────────────────────────────
        // │ API Logger - Response
        // └──────────────────────────────────────────────────────────────────────────────
        print(
            '┌──────────────────────────────────────────────────────────────────────────────');
        print('│ [API Response] ${resp.statusCode} $uri');
        print('│ Body: ${resp.body}');
        print(
            '└──────────────────────────────────────────────────────────────────────────────');

        return resp;
      } on TimeoutException catch (_) {
        if (attempt == maxAttempts) {
          print('│ [API Error] Request timed out for $uri');
          print(
              '└──────────────────────────────────────────────────────────────────────────────');
          return http.Response(
              jsonEncode({'message': 'Request timed out'}), 408);
        }
        await Future.delayed(retryDelay * attempt);
        continue;
      } on SocketException catch (_) {
        if (attempt == maxAttempts) {
          print('│ [API Error] Network error for $uri');
          print(
              '└──────────────────────────────────────────────────────────────────────────────');
          return http.Response(jsonEncode({'message': 'Network error'}), 599);
        }
        await Future.delayed(retryDelay * attempt);
        continue;
      } catch (e) {
        print('│ [API Error] Exception for $uri: $e');
        print(
            '└──────────────────────────────────────────────────────────────────────────────');
        return http.Response(jsonEncode({'message': e.toString()}), 500);
      }
    }
    return http.Response(jsonEncode({'message': 'Unknown network error'}), 500);
  }

  static Map<String, dynamic> _buildSuccessfulResult(http.Response resp) {
    Object? jsonBody;
    try {
      if (resp.body.isNotEmpty) jsonBody = jsonDecode(resp.body);
    } catch (_) {
      jsonBody = null;
    }
    return {
      'status': resp.statusCode,
      'body': resp.body,
      'json': jsonBody,
      'userMessage': null,
    };
  }

  static Map<String, dynamic> _buildErrorResult(http.Response resp) {
    Object? jsonBody;
    String raw = resp.body;
    try {
      if (raw.isNotEmpty) jsonBody = jsonDecode(raw);
    } catch (_) {
      jsonBody = null;
    }

    final userMessage = _humanizeErrorResponse(resp.statusCode, jsonBody, raw);

    return {
      'status': resp.statusCode,
      'body': raw,
      'json': jsonBody,
      'userMessage': userMessage,
    };
  }

  static String _humanizeErrorResponse(
      int status, Object? jsonBody, String rawBody) {
    // Prefer server-provided message fields
    try {
      if (jsonBody is Map) {
        // Common fields
        final candidates = ['message', 'error', 'errors', 'detail', 'msg'];
        for (final k in candidates) {
          if (jsonBody.containsKey(k) && jsonBody[k] != null) {
            final v = jsonBody[k];
            if (v is String && v.trim().isNotEmpty) {
              final lc = v.toLowerCase();
              // Map experience-level validation to a friendly message
              if (lc.contains('experiencelevel') ||
                  lc.contains('experience level') ||
                  lc.contains('body/experiencelevel') ||
                  lc.contains('body/experience level')) {
                return 'Please choose a valid experience level.';
              }
              if (lc.contains('must be equal to one of the allowed values') ||
                  lc.contains('allowed values')) {
                return 'One of the provided fields contains an invalid value. Please check and try again.';
              }
              return _friendlyFromRaw(v);
            }
            if (v is Map || v is List) return _friendlyFromStructured(v);
          }
        }
        // Some APIs return a top-level 'code' + 'error' message
        if (jsonBody.containsKey('code') && jsonBody.containsKey('message')) {
          final msg = jsonBody['message'];
          if (msg is String && msg.isNotEmpty) return _friendlyFromRaw(msg);
        }
      }
    } catch (_) {}

    // Fall back to raw string analysis
    if (rawBody.isNotEmpty) {
      // Specific mapping for experienceLevel validation
      final lc = rawBody.toLowerCase();
      if (lc.contains('experiencelevel') || lc.contains('experience level')) {
        return 'Please choose a valid experience level.';
      }
      if (lc.contains('must be equal to one of the allowed values') ||
          lc.contains('allowed values')) {
        return 'One of the provided fields has an invalid value. Please check your input and try again.';
      }
      if (lc.contains('unauthorized') || status == 401 || status == 403) {
        return 'You are not authorized to perform this action. Please sign in and try again.';
      }
      if (lc.contains('not found') || status == 404) {
        return 'The requested resource was not found.';
      }
      if (status >= 500) {
        return 'Server error. Please try again later.';
      }
      // Default to returning the raw message in a user-friendly wrapper
      return _friendlyFromRaw(rawBody);
    }

    // Generic fallback
    if (status >= 500) return 'Server error. Please try again later.';
    if (status == 404) return 'Not found.';
    if (status == 401 || status == 403) return 'Unauthorized. Please sign in.';
    return 'An error occurred. Please try again.';
  }

  static String _friendlyFromRaw(Object raw) {
    try {
      final s = raw.toString();
      // Trim common JSON wrappers
      return s.replaceAll(RegExp(r'''["\[\]"]'''), '').trim();
    } catch (_) {
      return 'An error occurred. Please try again.';
    }
  }

  static String _friendlyFromStructured(Object structured) {
    try {
      if (structured is Map) {
        // If map of field -> messages
        final parts = <String>[];
        structured.forEach((k, v) {
          if (v == null) return;
          if (v is String)
            parts.add('$k: ${v}');
          else if (v is List)
            parts.add('$k: ${v.join(", ")}');
          else
            parts.add('$k: ${v.toString()}');
        });
        if (parts.isNotEmpty) return parts.join(' — ');
      }
      if (structured is List) {
        final parts = structured.map((e) => e.toString()).toList();
        return parts.join('; ');
      }
    } catch (_) {}
    return 'Invalid input data. Please check and try again.';
  }

  static Future<Map<String, dynamic>> get(String url,
      {Map<String, String>? headers}) async {
    final token = await TokenStorage.getToken();
    final merged = {
      if (headers != null) ...headers,
      if (token != null) 'Authorization': 'Bearer $token',
    };

    final resp = await _requestWithRetries('GET', Uri.parse(url),
        headers: merged, timeoutSeconds: 15, maxAttempts: 2);
    if (resp.statusCode >= 200 && resp.statusCode < 300)
      return _buildSuccessfulResult(resp);
    return _buildErrorResult(resp);
  }

  static Future<Map<String, dynamic>> post(String url,
      {Map<String, String>? headers, Object? body}) async {
    final token = await TokenStorage.getToken();
    final merged = {
      if (headers != null) ...headers,
      if (token != null) 'Authorization': 'Bearer $token',
    };

    dynamic sendBody = body;
    final contentType = merged['Content-Type'] ?? merged['content-type'];
    if ((contentType == 'application/json' ||
            contentType == 'application/json; charset=utf-8') &&
        (sendBody == null)) {
      sendBody = jsonEncode({});
    }

    final resp = await _requestWithRetries('POST', Uri.parse(url),
        headers: merged, body: sendBody, timeoutSeconds: 20, maxAttempts: 2);
    if (resp.statusCode >= 200 && resp.statusCode < 300)
      return _buildSuccessfulResult(resp);
    return _buildErrorResult(resp);
  }

  static Future<Map<String, dynamic>> put(String url,
      {Map<String, String>? headers, Object? body}) async {
    final token = await TokenStorage.getToken();
    final merged = {
      if (headers != null) ...headers,
      if (token != null) 'Authorization': 'Bearer $token',
    };

    dynamic sendBody = body;
    final contentType = merged['Content-Type'] ?? merged['content-type'];
    if ((contentType == 'application/json' ||
            contentType == 'application/json; charset=utf-8') &&
        (sendBody == null)) {
      sendBody = jsonEncode({});
    }

    final resp = await _requestWithRetries('PUT', Uri.parse(url),
        headers: merged, body: sendBody, timeoutSeconds: 20, maxAttempts: 2);
    if (resp.statusCode >= 200 && resp.statusCode < 300)
      return _buildSuccessfulResult(resp);
    return _buildErrorResult(resp);
  }

  /// Sends a multipart/form-data request (POST/PUT) and returns the same result
  /// shape used by ApiClient (status/body/json/userMessage).
  /// Fields are simple string fields; fileMap is a map from field name -> list of
  /// local file paths.
  static Future<Map<String, dynamic>> postMultipart(String url,
      {Map<String, String>? headers,
      Map<String, String>? fields,
      Map<String, List<String>>? fileMap,
      String method = 'POST'}) async {
    final token = await TokenStorage.getToken();
    final merged = {
      if (headers != null) ...headers,
      if (token != null) 'Authorization': 'Bearer $token',
    };

    final req = http.MultipartRequest(method, Uri.parse(url));
    req.headers.addAll(merged);

    if (fields != null) {
      fields.forEach((k, v) {
        req.fields[k] = v;
      });
    }

    if (fileMap != null) {
      for (final entry in fileMap.entries) {
        final fieldName = entry.key;
        for (final path in entry.value) {
          try {
            if (path.isEmpty) continue;
            final file = File(path);
            if (!await file.exists()) continue;
            final filename = file.path.split(Platform.pathSeparator).last;
            final multipart = await http.MultipartFile.fromPath(
                fieldName, file.path,
                filename: filename);
            req.files.add(multipart);
          } catch (e) {
            // ignore per-file attach errors; let the server respond accordingly
          }
        }
      }
    }

    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode >= 200 && resp.statusCode < 300)
      return _buildSuccessfulResult(resp);
    return _buildErrorResult(resp);
  }
}
