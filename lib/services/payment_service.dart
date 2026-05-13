import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:http/http.dart' as http;

import '../api_config.dart';
import 'token_storage.dart';

/// Thin wrapper for payment-related endpoints documented in
/// `booking-payment-mode-flow-recheck.md` /
/// `UPDATED_ENDPOINTS_DOCS-recheck.md`.
///
/// Currently only exposes the commission preview endpoint
/// (`GET /api/payments/commission`) — used by the artisan booking list to
/// show the platform-fee breakdown next to each booking's amount.
class PaymentService {
  /// GET `/api/payments/commission[?amount=N]`
  ///
  /// Returns the resolved commission preview, or null on any failure
  /// (caller decides whether to hide the breakdown or fall back to a
  /// cached percentage).
  ///
  /// Per the doc:
  ///   - No `amount` -> `{ key, percentage }` (just the percentage so the
  ///     caller can compute fees locally for many bookings without
  ///     hammering the endpoint).
  ///   - With `amount` -> `{ key, percentage, amount, companyFee,
  ///     transferAmount }` for a single preview.
  ///
  /// The doc also notes: "The app should treat this as display data only.
  /// The backend still recalculates the commission during verified
  /// payment, so the client cannot control the actual deducted amount."
  static Future<Map<String, dynamic>?> getCommission({
    double? amount,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      final token = await TokenStorage.getToken();
      if (token == null || token.isEmpty) return null;

      final query = <String, String>{};
      if (amount != null && amount > 0) {
        query['amount'] = amount.toString();
      }
      final uri = Uri.parse('$API_BASE_URL/api/payments/commission')
          .replace(queryParameters: query.isEmpty ? null : query);

      final resp = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(timeout);

      developer.log(
          'getCommission response: status=${resp.statusCode} body=${resp.body}',
          name: 'PaymentService.getCommission');

      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      if (resp.body.isEmpty) return null;
      final body = jsonDecode(resp.body);
      if (body is Map && body['data'] is Map) {
        return Map<String, dynamic>.from(body['data']);
      }
      if (body is Map) return Map<String, dynamic>.from(body);
      return null;
    } on SocketException catch (e, st) {
      developer.log('Network error in getCommission',
          error: e, stackTrace: st, name: 'PaymentService.getCommission');
      return null;
    } on TimeoutException catch (e, st) {
      developer.log('Timeout in getCommission',
          error: e, stackTrace: st, name: 'PaymentService.getCommission');
      return null;
    } catch (e, st) {
      developer.log('Unexpected error in getCommission',
          error: e, stackTrace: st, name: 'PaymentService.getCommission');
      return null;
    }
  }
}
