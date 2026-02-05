import 'dart:convert';
import 'package:http/http.dart' as http;
import '../api_config.dart';

class WalletServiceException implements Exception {
  final String message;
  final int? statusCode;
  WalletServiceException(this.message, [this.statusCode]);
  @override
  String toString() =>
      'WalletServiceException: $message ${statusCode != null ? '(status $statusCode)' : ''}';
}

class WalletService {
  // Try multiple endpoints and return the first successful list of transactions
  static Future<List<Map<String, dynamic>>> fetchTransactions({
    required String token,
    http.Client? client,
    String? apiBaseUrl,
    int page = 1,
    int limit = 50,
  }) async {
    client ??= http.Client();
    final base = apiBaseUrl ?? API_BASE_URL;
    final endpoints = [
      '$base/api/transactions',
      '$base/api/wallet/transactions',
      '$base/api/payments',
    ];

    for (final ep in endpoints) {
      try {
        // Append pagination query params when supported
        final uri = Uri.parse(ep).replace(queryParameters: {
          'page': page.toString(),
          'limit': limit.toString()
        });

        // ┌──────────────────────────────────────────────────────────────────────────────
        // │ API Logger - Request (WalletService)
        // └──────────────────────────────────────────────────────────────────────────────
        // ignore: avoid_print
        print(
            '┌──────────────────────────────────────────────────────────────────────────────');
        // ignore: avoid_print
        print('│ [API Request] GET $uri');
        // ignore: avoid_print
        print(
            '└──────────────────────────────────────────────────────────────────────────────');

        final resp = await client.get(uri, headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        }).timeout(const Duration(seconds: 10));

        // ┌──────────────────────────────────────────────────────────────────────────────
        // │ API Logger - Response (WalletService)
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

        if (resp.statusCode >= 200 &&
            resp.statusCode < 300 &&
            resp.body.isNotEmpty) {
          final decoded = jsonDecode(resp.body);
          final list = decoded is Map
              ? (decoded['data'] ??
                  decoded['transactions'] ??
                  decoded['results'] ??
                  decoded)
              : decoded;
          if (list is List) {
            final allTx = List<Map<String, dynamic>>.from(list.map(
                (e) => e is Map ? Map<String, dynamic>.from(e) : {'raw': e}));
            return allTx;
          }
        }
      } catch (_) {
        // try next endpoint
      }
    }

    // If none returned a list, throw
    throw WalletServiceException('Unable to fetch transactions');
  }

  static Future<Map<String, dynamic>?> fetchPayoutDetails({
    required String token,
    http.Client? client,
    String? apiBaseUrl,
  }) async {
    client ??= http.Client();
    final base = apiBaseUrl ?? API_BASE_URL;
    final uri = Uri.parse('$base/api/wallet/payout-details');

    // ┌──────────────────────────────────────────────────────────────────────────────
    // │ API Logger - Request (WalletService)
    // └──────────────────────────────────────────────────────────────────────────────
    // ignore: avoid_print
    print(
        '┌──────────────────────────────────────────────────────────────────────────────');
    // ignore: avoid_print
    print('│ [API Request] GET $uri');
    // ignore: avoid_print
    print(
        '└──────────────────────────────────────────────────────────────────────────────');

    final resp = await client.get(uri, headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    }).timeout(const Duration(seconds: 10));

    // ┌──────────────────────────────────────────────────────────────────────────────
    // │ API Logger - Response (WalletService)
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

    if (resp.statusCode >= 200 &&
        resp.statusCode < 300 &&
        resp.body.isNotEmpty) {
      final decoded = jsonDecode(resp.body);
      // API docs show response shape may be { payoutDetails: {...}, hasRecipient: true }
      if (decoded is Map && decoded.containsKey('payoutDetails')) {
        final pd = decoded['payoutDetails'];
        if (pd is Map) return Map<String, dynamic>.from(pd);
      }
      final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
      if (data is Map) return Map<String, dynamic>.from(data);
    }

    return null;
  }

  static Future<Map<String, dynamic>> savePayoutDetails({
    required String token,
    required Map<String, dynamic> body,
    http.Client? client,
    String? apiBaseUrl,
  }) async {
    client ??= http.Client();
    final base = apiBaseUrl ?? API_BASE_URL;
    final uri = Uri.parse('$base/api/wallet/payout-details');

    http.Response resp;
    try {
      // ┌──────────────────────────────────────────────────────────────────────────────
      // │ API Logger - Request (WalletService PUT)
      // └──────────────────────────────────────────────────────────────────────────────
      // ignore: avoid_print
      print(
          '┌──────────────────────────────────────────────────────────────────────────────');
      // ignore: avoid_print
      print('│ [API Request] PUT $uri');
      // ignore: avoid_print
      print('│ Body: ${jsonEncode(body)}');
      // ignore: avoid_print
      print(
          '└──────────────────────────────────────────────────────────────────────────────');

      resp = await client.put(uri, body: jsonEncode(body), headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      }).timeout(const Duration(seconds: 12));

      // ┌──────────────────────────────────────────────────────────────────────────────
      // │ API Logger - Response (WalletService PUT)
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
    } catch (e) {
      throw WalletServiceException('Network error saving payout details');
    }

    if (resp.statusCode == 404) {
      // try POST
      try {
        // ┌──────────────────────────────────────────────────────────────────────────────
        // │ API Logger - Request (WalletService POST)
        // └──────────────────────────────────────────────────────────────────────────────
        // ignore: avoid_print
        print(
            '┌──────────────────────────────────────────────────────────────────────────────');
        // ignore: avoid_print
        print('│ [API Request] POST $uri');
        // ignore: avoid_print
        print('│ Body: ${jsonEncode(body)}');
        // ignore: avoid_print
        print(
            '└──────────────────────────────────────────────────────────────────────────────');

        resp = await client.post(uri, body: jsonEncode(body), headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        }).timeout(const Duration(seconds: 12));

        // ┌──────────────────────────────────────────────────────────────────────────────
        // │ API Logger - Response (WalletService POST)
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
      } catch (e) {
        throw WalletServiceException('Network error saving payout details');
      }
    }

    // If still not ok, try multipart fallback
    if (!(resp.statusCode >= 200 &&
        resp.statusCode < 300 &&
        resp.body.isNotEmpty)) {
      try {
        final mpReq = http.MultipartRequest('POST', uri);
        mpReq.headers.addAll({'Authorization': 'Bearer $token'});
        body.forEach((k, v) {
          mpReq.fields[k] = v?.toString() ?? '';
        });

        // ┌──────────────────────────────────────────────────────────────────────────────
        // │ API Logger - Request (WalletService Multipart)
        // └──────────────────────────────────────────────────────────────────────────────
        // ignore: avoid_print
        print(
            '┌──────────────────────────────────────────────────────────────────────────────');
        // ignore: avoid_print
        print('│ [API Request] POST (Multipart) $uri');
        // ignore: avoid_print
        print('│ Fields: ${mpReq.fields}');
        // ignore: avoid_print
        print(
            '└──────────────────────────────────────────────────────────────────────────────');

        final streamed =
            await client.send(mpReq).timeout(const Duration(seconds: 15));
        resp = await http.Response.fromStream(streamed);

        // ┌──────────────────────────────────────────────────────────────────────────────
        // │ API Logger - Response (WalletService Multipart)
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
      } catch (_) {
        // fall through
      }
    }

    if (resp.statusCode >= 200 &&
        resp.statusCode < 300 &&
        resp.body.isNotEmpty) {
      final decoded = jsonDecode(resp.body);
      // API returns { success: true, data: <wallet> } or { payoutDetails: {...} }
      if (decoded is Map && decoded.containsKey('data')) {
        final data = decoded['data'];
        if (data is Map) return Map<String, dynamic>.from(data);
      }
      if (decoded is Map && decoded.containsKey('payoutDetails')) {
        final pd = decoded['payoutDetails'];
        if (pd is Map) return Map<String, dynamic>.from(pd);
      }
      final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
      if (data is Map) return Map<String, dynamic>.from(data);
      return {};
    }

    // Try to extract message
    String msg = 'Failed to save payout details';
    try {
      if (resp.body.isNotEmpty) {
        final parsed = jsonDecode(resp.body);
        if (parsed is Map && (parsed['message'] ?? parsed['error']) != null) {
          msg = (parsed['message'] ?? parsed['error']).toString();
        }
      }
    } catch (_) {}

    throw WalletServiceException(msg, resp.statusCode);
  }
}
