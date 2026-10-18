import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../repositories/repositories.dart';
import 'token_store.dart';

/// An error the API answered with: [message] is written to be shown as it
/// is; [code] is for branching ("wrong_code", "request_expired", …).
class ApiException extends AppException {
  const ApiException(super.message, {required this.code, this.status = 0});

  final String code;

  /// The HTTP status; 0 when RijHub couldn't be reached.
  final int status;

  bool get offline => code == 'offline';
}

/// Talks to the RijHub API: JSON both ways, the signed-in person's token on
/// every request, and a quiet refresh when the token runs out. When the
/// server ends the session (signed out on every device, account deleted or
/// suspended), the tokens are dropped and [sessionEnded] fires so the app
/// can sign the person out.
class ApiClient {
  ApiClient({
    required this.baseUrl,
    required this.tokens,
    http.Client? client,
    this.timeout = const Duration(seconds: 25),
  }) : _http = client ?? http.Client();

  /// The API's origin, for example `https://api.rijhub.com`.
  final Uri baseUrl;
  final TokenStore tokens;
  final Duration timeout;
  final http.Client _http;
  final _ended = StreamController<void>.broadcast();
  Completer<bool?>? _refreshing;

  static const _offline = ApiException(
      "You're offline, or RijHub can't be reached. Check your connection and try again.",
      code: 'offline');

  Stream<void> get sessionEnded => _ended.stream;

  Future<bool> get signedIn async => await tokens.access() != null;

  Future<Object?> get(String path, {Map<String, Object?>? query}) =>
      _send('GET', path, query: query);

  Future<Object?> post(String path, [Object? body]) =>
      _send('POST', path, body: body);

  Future<Object?> put(String path, [Object? body]) =>
      _send('PUT', path, body: body);

  Future<Object?> patch(String path, [Object? body]) =>
      _send('PATCH', path, body: body);

  Future<Object?> delete(String path) => _send('DELETE', path);

  /// Keeps a new pair from a sign-in, sign-up, refresh or role switch.
  Future<void> saveTokens(Object? pair) async {
    final p = pair! as Map<String, Object?>;
    await tokens.save(
      access: p['access_token']! as String,
      refresh: p['refresh_token']! as String,
    );
  }

  Uri url(String path, [Map<String, Object?>? query]) {
    final params = <String, String>{
      for (final MapEntry(:key, :value) in (query ?? const {}).entries)
        if (value != null) key: '$value',
    };
    return baseUrl.replace(
      path: '${baseUrl.path.replaceAll(RegExp(r'/$'), '')}$path',
      queryParameters: params.isEmpty ? null : params,
    );
  }

  Future<Object?> _send(
    String method,
    String path, {
    Object? body,
    Map<String, Object?>? query,
    bool retried = false,
  }) async {
    final token = await tokens.access();
    final request = http.Request(method, url(path, query))
      ..headers['Accept'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final http.Response response;
    try {
      response = await http.Response.fromStream(
          await _http.send(request).timeout(timeout));
    } on TimeoutException {
      throw const ApiException(
          "RijHub is taking too long to answer. Try again in a moment.",
          code: 'offline');
    } on SocketException {
      throw _offline;
    } on http.ClientException {
      throw _offline;
    }
    if (response.statusCode == 401 && token != null) {
      if (!retried) {
        final refreshed = await _refresh();
        if (refreshed == true) {
          return _send(method, path, body: body, query: query, retried: true);
        }
        // Couldn't reach RijHub to refresh: still signed in, just offline.
        if (refreshed == null) throw _offline;
      }
      await _endSession();
    }
    if (response.statusCode >= 400) {
      final error = _error(response);
      if (error.code == 'account_suspended') await _endSession();
      throw error;
    }
    if (response.statusCode == 204 || response.bodyBytes.isEmpty) return null;
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  /// A fresh pair from the refresh token: true when it worked, false when
  /// the server said no (the session is over), null when RijHub couldn't
  /// be reached (still signed in). One refresh at a time: requests that
  /// hit the expiry together wait for the same one.
  Future<bool?> refreshTokens() async {
    final running = _refreshing;
    if (running != null) return running.future;
    final done = _refreshing = Completer<bool?>();
    try {
      final refresh = await tokens.refresh();
      if (refresh == null) return _finish(done, false);
      final response = await _http
          .post(url('/v1/auth/refresh'),
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json'
              },
              body: jsonEncode({'refresh_token': refresh}))
          .timeout(timeout);
      if (response.statusCode == 401 || response.statusCode == 403) {
        return _finish(done, false);
      }
      if (response.statusCode != 200) return _finish(done, null);
      await saveTokens(jsonDecode(utf8.decode(response.bodyBytes)));
      return _finish(done, true);
    } on Object catch (e) {
      debugPrint('token refresh failed: $e');
      return _finish(done, null);
    } finally {
      _refreshing = null;
    }
  }

  Future<bool?> _refresh() => refreshTokens();

  bool? _finish(Completer<bool?> done, bool? ok) {
    if (!done.isCompleted) done.complete(ok);
    return ok;
  }

  /// Signs the device out because the server ended the session.
  Future<void> endSession() => _endSession();

  Future<void> _endSession() async {
    if (await tokens.access() == null) return;
    await tokens.clear();
    _ended.add(null);
  }

  ApiException _error(http.Response response) {
    final status = response.statusCode;
    Object? detail;
    try {
      detail = (jsonDecode(utf8.decode(response.bodyBytes)) as Map)['detail'];
    } on Object {
      detail = null;
    }
    if (detail is Map) {
      return ApiException(
        (detail['message'] as String?) ?? _fallback(status),
        code: (detail['code'] as String?) ?? 'error',
        status: status,
      );
    }
    if (detail is String) {
      return ApiException(detail, code: 'error', status: status);
    }
    return ApiException(_fallback(status), code: 'error', status: status);
  }

  static String _fallback(int status) => status >= 500
      ? 'Something went wrong on our side. Try again in a moment.'
      : 'That didn\'t work. Try again.';
}
