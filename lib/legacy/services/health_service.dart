// ...new file...
// Lightweight HealthService to probe the API host and provide user-friendly messages.
import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../api_config.dart';

class HealthCheckResult {
  final bool healthy;
  final String message;
  final int? statusCode;
  final String? details;

  HealthCheckResult({
    required this.healthy,
    required this.message,
    this.statusCode,
    this.details,
  });

  @override
  String toString() => 'HealthCheckResult(healthy: $healthy, message: $message, statusCode: $statusCode, details: $details)';
}

class HealthService {
  final String baseUrl;
  final Duration timeout;

  HealthService({String? baseUrl, this.timeout = const Duration(seconds: 5)}) : baseUrl = baseUrl ?? API_BASE_URL;

  Uri _jobsProbeUri() => Uri.parse('$baseUrl/api/jobs?limit=1');
  Uri _authVerifyUri() => Uri.parse('$baseUrl/api/auth/verify');

  Future<HealthCheckResult> check({String? token, bool verifyAuthWhenTokenPresent = true}) async {
    try {
      final res = await http.get(_jobsProbeUri()).timeout(timeout);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (token != null && verifyAuthWhenTokenPresent) {
          return await _verifyToken(token);
        }
        return HealthCheckResult(healthy: true, message: 'Server reachable', statusCode: res.statusCode);
      }

      final friendly = _friendlyMessageForStatus(res.statusCode);
      return HealthCheckResult(
        healthy: false,
        message: 'Server responded: $friendly',
        statusCode: res.statusCode,
        details: 'GET ${_jobsProbeUri()} returned ${res.statusCode}: ${res.body}',
      );
    } on SocketException catch (e) {
      return HealthCheckResult(healthy: false, message: 'No internet connection or server unreachable.', details: e.toString());
    } on TimeoutException catch (e) {
      return HealthCheckResult(healthy: false, message: 'Request timed out. Check your network and try again.', details: e.toString());
    } on HandshakeException catch (e) {
      return HealthCheckResult(healthy: false, message: 'Secure connection failed. Check server certificate or HTTPS.', details: e.toString());
    } catch (e, st) {
      return HealthCheckResult(healthy: false, message: 'Unexpected error while checking server.', details: '$e\n$st');
    }
  }

  Future<HealthCheckResult> _verifyToken(String token) async {
    try {
      final res = await http.get(
        _authVerifyUri(),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(timeout);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        return HealthCheckResult(healthy: true, message: 'Server reachable and session is valid', statusCode: res.statusCode);
      }

      if (res.statusCode == 401 || res.statusCode == 403) {
        return HealthCheckResult(healthy: false, message: 'Session invalid or expired. Please sign in again.', statusCode: res.statusCode, details: res.body);
      }

      final friendly = _friendlyMessageForStatus(res.statusCode);
      return HealthCheckResult(healthy: false, message: 'Server responded: $friendly', statusCode: res.statusCode, details: res.body);
    } on TimeoutException catch (e) {
      return HealthCheckResult(healthy: false, message: 'Token validation timed out. Network may be slow.', details: e.toString());
    } on SocketException catch (e) {
      return HealthCheckResult(healthy: false, message: 'Network error while validating session.', details: e.toString());
    } catch (e, st) {
      return HealthCheckResult(healthy: false, message: 'Unexpected error while validating session.', details: '$e\n$st');
    }
  }

  String _friendlyMessageForStatus(int status) {
    if (status >= 500) return 'Server error ($status) — try again later';
    if (status == 404) return 'Resource not found (404)';
    if (status == 401) return 'Unauthorized (session expired)';
    if (status == 403) return 'Forbidden (insufficient access)';
    if (status >= 400) return 'Bad request or unavailable ($status)';
    return 'HTTP $status';
  }
}

