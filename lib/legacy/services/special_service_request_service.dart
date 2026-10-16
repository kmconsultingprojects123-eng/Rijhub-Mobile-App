import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../api_config.dart';
import 'token_storage.dart';
import 'user_service.dart';

class SpecialServiceRequestService {
  static const bool _verboseApiLogging = false;

  static Map<String, dynamic> _specialRequestGatewayMetadata(
    String requestId, {
    String? requestTitle,
    dynamic selectedPrice,
    String? paymentMode,
  }) {
    return <String, dynamic>{
      'specialRequestId': requestId,
      'specialServiceRequestId': requestId,
      'type': 'special_service_request',
      'bookingSource': 'special_request',
      if (requestTitle != null && requestTitle.trim().isNotEmpty)
        'requestTitle': requestTitle.trim(),
      if (selectedPrice != null) 'selectedPrice': selectedPrice,
      if (paymentMode != null && paymentMode.isNotEmpty)
        'paymentMode': paymentMode,
      'custom_fields': [
        {
          'display_name': 'Special Request ID',
          'variable_name': 'special_request_id',
          'value': requestId,
        },
        {
          'display_name': 'Special Service Request ID',
          'variable_name': 'special_service_request_id',
          'value': requestId,
        },
        {
          'display_name': 'Booking Source',
          'variable_name': 'booking_source',
          'value': 'special_request',
        },
      ],
    };
  }

  static Map<String, dynamic>? _extractMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is Map) return Map<String, dynamic>.from(decoded);
        } catch (_) {}
      }
    }
    return null;
  }

  static int? _extractInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  static List<int>? _buildRangeOptions(int? min, int? max) {
    if (min == null || max == null || min >= max) return null;
    final range = max - min;
    final values = <int>{};
    for (int i = 0; i < 5; i++) {
      values.add(min + (range * i ~/ 4));
    }
    values.add(max);
    final sorted = values.toList()..sort();
    return sorted;
  }

  static Map<String, dynamic>? _extractPaymentMap(dynamic value) {
    final map = _extractMap(value);
    if (map == null) return null;

    if ((map['authorization_url'] ?? map['authorizationUrl']) != null) {
      return map;
    }

    return _extractPaymentMap(
          map['data'] ??
              map['payment'] ??
              map['paymentData'] ??
              map['authorization'],
        ) ??
        map;
  }

  static String? _extractErrorMessage(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      try {
        return _extractErrorMessage(jsonDecode(trimmed));
      } catch (_) {
        return trimmed;
      }
    }
    if (value is Map) {
      for (final key in ['message', 'error', 'detail', 'msg']) {
        final candidate = _extractErrorMessage(value[key]);
        if (candidate != null && candidate.isNotEmpty) return candidate;
      }
      if (value['data'] != null) {
        final nested = _extractErrorMessage(value['data']);
        if (nested != null && nested.isNotEmpty) return nested;
      }
    }
    if (value is List) {
      for (final item in value) {
        final candidate = _extractErrorMessage(item);
        if (candidate != null && candidate.isNotEmpty) return candidate;
      }
    }
    return null;
  }

  static Map<String, dynamic>? _extractEnvelopeData(dynamic body) {
    if (body is Map && body['data'] is Map) {
      return Map<String, dynamic>.from(body['data']);
    }
    if (body is Map) {
      return Map<String, dynamic>.from(body);
    }
    return null;
  }

  static Map<String, dynamic> _normalizeLifecycleResponse(
    Map<String, dynamic> input,
  ) {
    final requestData = _extractMap(input['request']) ??
        _extractMap(input['specialRequest']) ??
        _extractMap(input['special_service_request']) ??
        <String, dynamic>{};
    final bookingData = _extractMap(input['booking']);
    final paymentData = _extractPaymentMap(input['payment']) ??
        _extractPaymentMap(input['paymentData']) ??
        _extractPaymentMap(input['authorization']) ??
        _extractPaymentMap(input['data']);

    final normalized = <String, dynamic>{...input};

    if (requestData.isNotEmpty) {
      normalized.addAll(requestData);
      normalized['request'] = requestData;
      normalized['specialRequest'] ??= requestData;
    }

    if (bookingData != null && bookingData.isNotEmpty) {
      normalized['booking'] = bookingData;
      normalized['bookingId'] ??= bookingData['_id'] ?? bookingData['id'];
      normalized['paymentStatus'] ??=
          bookingData['paymentStatus'] ?? bookingData['payment_status'];
    }

    if (paymentData != null && paymentData.isNotEmpty) {
      normalized['payment'] = paymentData;
      normalized['authorization_url'] ??=
          paymentData['authorization_url'] ?? paymentData['authorizationUrl'];
      normalized['authorizationUrl'] ??=
          paymentData['authorizationUrl'] ?? paymentData['authorization_url'];
      normalized['reference'] ??= paymentData['reference'];
      normalized['access_code'] ??=
          paymentData['access_code'] ?? paymentData['accessCode'];
    }

    normalized['bookingId'] ??=
        requestData['bookingId'] ?? requestData['booking_id'];
    normalized['paymentStatus'] ??= normalized['payment_status'] ??
        (paymentData != null ? paymentData['status'] : null);

    return _normalizeRequest(normalized);
  }

  static Map<String, dynamic> _normalizeRequest(Map<String, dynamic> input) {
    final normalized = Map<String, dynamic>.from(input);
    final note = _extractMap(normalized['note']);
    final artisanReply = _extractMap(normalized['artisanReply']);
    final mergedReply = <String, dynamic>{};

    if (note != null) mergedReply.addAll(note);
    if (artisanReply != null) mergedReply.addAll(artisanReply);

    for (final key in [
      'quote',
      'quoteType',
      'min',
      'max',
      'minQuote',
      'maxQuote',
      'options',
      'selectedPrice',
      'budget',
      'minBudget',
      'maxBudget',
      'price',
      'amount',
      'message',
    ]) {
      final value = normalized[key];
      if (value != null && mergedReply[key] == null) {
        mergedReply[key] = value;
      }
    }

    if (mergedReply.isNotEmpty) {
      final min = _extractInt(mergedReply['min'] ?? mergedReply['minQuote']);
      final max = _extractInt(mergedReply['max'] ?? mergedReply['maxQuote']);
      if (min != null && mergedReply['min'] == null) mergedReply['min'] = min;
      if (max != null && mergedReply['max'] == null) mergedReply['max'] = max;
      if (min != null && mergedReply['minQuote'] == null) {
        mergedReply['minQuote'] = min;
      }
      if (max != null && mergedReply['maxQuote'] == null) {
        mergedReply['maxQuote'] = max;
      }
      if (min != null &&
          max != null &&
          (mergedReply['quoteType'] == null ||
              mergedReply['quoteType'].toString().trim().isEmpty)) {
        mergedReply['quoteType'] = 'range';
      }
      if (mergedReply['options'] == null) {
        final generatedOptions = _buildRangeOptions(min, max);
        if (generatedOptions != null && generatedOptions.isNotEmpty) {
          mergedReply['options'] = generatedOptions;
        }
      }
      normalized['artisanReply'] = mergedReply;
      normalized['note'] = note ?? mergedReply;
    }

    final imageUrls = <String>{};

    void collectImage(dynamic source) {
      if (source == null) return;
      if (source is String) {
        final trimmed = source.trim();
        if (trimmed.isNotEmpty &&
            (trimmed.startsWith('http://') || trimmed.startsWith('https://'))) {
          imageUrls.add(trimmed);
        }
        return;
      }
      if (source is Map) {
        for (final key in [
          'url',
          'secure_url',
          'secureUrl',
          'imageUrl',
          'image_url',
          'path'
        ]) {
          final value = source[key];
          if (value is String && value.trim().isNotEmpty) {
            collectImage(value);
            return;
          }
        }
        return;
      }
      if (source is List) {
        for (final item in source) {
          collectImage(item);
        }
      }
    }

    collectImage(normalized['attachments']);
    collectImage(normalized['imageUrls']);

    if (imageUrls.isNotEmpty) {
      normalized['imageUrls'] = imageUrls.toList();
      normalized['attachments'] =
          imageUrls.map((url) => <String, dynamic>{'url': url}).toList();
    }

    return normalized;
  }

  /// Fetch special service requests for a client
  static Future<List<Map<String, dynamic>>> fetchForClient(String clientId,
      {int? page, int? pageSize}) async {
    final token = await TokenStorage.getToken();
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';

    final queryParams = <String, String>{'clientId': clientId};
    if (page != null) queryParams['page'] = page.toString();
    if (pageSize != null) queryParams['limit'] = pageSize.toString();

    final uri = Uri.parse('$API_BASE_URL/api/special-service-requests')
        .replace(queryParameters: queryParams);

    debugLog('GET $uri', headers);

    try {
      final resp = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 15));

      debugLogResponse(resp.statusCode, resp.body, uri);

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : null;
        if (body == null) return [];
        if (body is Map && body['data'] is List) {
          return List<Map<String, dynamic>>.from(
            body['data']
                .map((e) => _normalizeRequest(Map<String, dynamic>.from(e))),
          );
        }
        if (body is List) {
          return List<Map<String, dynamic>>.from(
            body.map((e) => _normalizeRequest(Map<String, dynamic>.from(e))),
          );
        }
        return [];
      }
      throw Exception(
          'Failed to fetch client special requests: ${resp.statusCode}');
    } catch (e) {
      rethrow;
    }
  }

  /// Fetch special service requests for an artisan
  static Future<List<Map<String, dynamic>>> fetchForArtisan(String artisanId,
      {int? page, int? pageSize}) async {
    final token = await TokenStorage.getToken();
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';

    final queryParams = <String, String>{'artisanId': artisanId};
    if (page != null) queryParams['page'] = page.toString();
    if (pageSize != null) queryParams['limit'] = pageSize.toString();

    final uri = Uri.parse('$API_BASE_URL/api/special-service-requests')
        .replace(queryParameters: queryParams);

    debugLog('GET $uri', headers);

    try {
      final resp = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 15));

      debugLogResponse(resp.statusCode, resp.body, uri);

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : null;
        if (body == null) return [];
        if (body is Map && body['data'] is List) {
          return List<Map<String, dynamic>>.from(
            body['data']
                .map((e) => _normalizeRequest(Map<String, dynamic>.from(e))),
          );
        }
        if (body is List) {
          return List<Map<String, dynamic>>.from(
            body.map((e) => _normalizeRequest(Map<String, dynamic>.from(e))),
          );
        }
        return [];
      }
      throw Exception(
          'Failed to fetch artisan special requests: ${resp.statusCode}');
    } catch (e) {
      rethrow;
    }
  }

  /// Fetch a specific special request by ID
  static Future<Map<String, dynamic>?> fetchById(String requestId) async {
    final token = await TokenStorage.getToken();
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';

    final uri =
        Uri.parse('$API_BASE_URL/api/special-service-requests/$requestId');

    debugLog('GET $uri', headers);

    try {
      final resp = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 15));

      debugLogResponse(resp.statusCode, resp.body, uri);

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : null;
        if (body == null) return null;
        final data = _extractEnvelopeData(body);
        if (data != null) return _normalizeLifecycleResponse(data);
        return null;
      }
      return null;
    } catch (e) {
      if (_verboseApiLogging && kDebugMode) {
        debugPrint('Error fetching special request: $e');
      }
      return null;
    }
  }

  /// Fetch artisan response for a special request
  static Future<Map<String, dynamic>?> fetchArtisanResponse(
      String requestId) async {
    final token = await TokenStorage.getToken();
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';

    final uri = Uri.parse(
        '$API_BASE_URL/api/special-service-requests/$requestId/response');

    debugLog('GET $uri', headers);

    try {
      final resp = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 15));

      debugLogResponse(resp.statusCode, resp.body, uri);

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : null;
        if (body == null) return null;
        final data = _extractEnvelopeData(body);
        if (data != null) {
          return _normalizeLifecycleResponse(data);
        }
        return null;
      }
      return null;
    } catch (e) {
      if (_verboseApiLogging && kDebugMode) {
        debugPrint('Error fetching artisan response: $e');
      }
      return null;
    }
  }

  /// Accept artisan response with optional selected price.
  /// The server may return `{ request, booking, payment }`, so flatten that
  /// into a single map the UI can work with consistently.
  static Future<Map<String, dynamic>?> acceptResponse(String requestId,
      {dynamic selectedPrice,
      String? requestTitle,
      String? paymentMode}) async {
    final token = await TokenStorage.getToken();
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';

    // Use PUT endpoint as per API docs to update status to 'accepted'
    final uri =
        Uri.parse('$API_BASE_URL/api/special-service-requests/$requestId');
    final body = <String, dynamic>{'status': 'accepted'};
    if (selectedPrice != null) {
      body['selectedPrice'] = selectedPrice;
    }
    final effectivePaymentMode =
        paymentMode ?? dotenv.env['PAYMENT_MODE'] ?? 'upfront';
    body['paymentMode'] = effectivePaymentMode;

    debugLog('PUT $uri', headers, body);

    try {
      final resp = await http
          .put(uri, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));

      debugLogResponse(resp.statusCode, resp.body, uri);

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final responseBody =
            resp.body.isNotEmpty ? jsonDecode(resp.body) : null;
        if (responseBody == null) return null;
        final data = _extractEnvelopeData(responseBody);
        if (data != null) {
          final normalized = _normalizeLifecycleResponse(data);
          return normalized;
        }
        return null;
      }
      return null;
    } catch (e) {
      if (_verboseApiLogging && kDebugMode) {
        debugPrint('Error accepting response: $e');
      }
      return null;
    }
  }

  /// Update special request status
  static Future<Map<String, dynamic>?> updateStatus(
      String requestId, String status) async {
    return updateRequest(requestId, {'status': status});
  }

  /// Update a special request using the documented generic PUT endpoint.
  static Future<Map<String, dynamic>?> updateRequest(
    String requestId,
    Map<String, dynamic> payload,
  ) async {
    final token = await TokenStorage.getToken();
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';

    final uri =
        Uri.parse('$API_BASE_URL/api/special-service-requests/$requestId');
    final body = Map<String, dynamic>.from(payload);

    debugLog('PUT $uri', headers, body);

    try {
      final resp = await http
          .put(uri, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));

      debugLogResponse(resp.statusCode, resp.body, uri);

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final responseBody =
            resp.body.isNotEmpty ? jsonDecode(resp.body) : null;
        if (responseBody == null) return null;
        final data = _extractEnvelopeData(responseBody);
        if (data != null) return _normalizeLifecycleResponse(data);
        return null;
      }
      return null;
    } catch (e) {
      if (_verboseApiLogging && kDebugMode) {
        debugPrint('Error updating request: $e');
      }
      return null;
    }
  }

  /// Submit artisan response to a special request
  static Future<Map<String, dynamic>?> submitArtisanResponse(
      String requestId, Map<String, dynamic> data) async {
    final token = await TokenStorage.getToken();
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';

    final uri = Uri.parse(
        '$API_BASE_URL/api/special-service-requests/$requestId/response');
    final body = <String, dynamic>{'status': 'responded', ...data};

    // Prefer POST first because the newer convenience endpoint supports
    // range quotes. Some backends still accept PUT, but that older path can
    // flatten or drop min/max quote fields.
    debugLog('POST $uri', headers, body);

    try {
      final resp = await http
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));

      debugLogResponse(resp.statusCode, resp.body, uri);

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final responseBody =
            resp.body.isNotEmpty ? jsonDecode(resp.body) : null;
        if (responseBody == null) return null;
        final data = _extractEnvelopeData(responseBody);
        if (data != null) return _normalizeLifecycleResponse(data);
        return null;
      }

      debugLog('PUT $uri', headers, body);

      final fallbackResp = await http
          .put(uri, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));

      debugLogResponse(fallbackResp.statusCode, fallbackResp.body, uri);

      if (fallbackResp.statusCode >= 200 && fallbackResp.statusCode < 300) {
        final responseBody =
            fallbackResp.body.isNotEmpty ? jsonDecode(fallbackResp.body) : null;
        if (responseBody == null) return null;
        final data = _extractEnvelopeData(responseBody);
        if (data != null) return _normalizeLifecycleResponse(data);
      }
      return null;
    } catch (e) {
      if (_verboseApiLogging && kDebugMode) {
        debugPrint('Error submitting artisan response: $e');
      }
      return null;
    }
  }

  /// Create a new special service request
  static Future<Map<String, dynamic>?> create(
      Map<String, dynamic> payload) async {
    final token = await TokenStorage.getToken();
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';

    final uri = Uri.parse('$API_BASE_URL/api/special-service-requests');

    final body = Map<String, dynamic>.from(payload);

    debugLog('POST $uri', headers, body);

    try {
      final resp = await http
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 30));

      debugLogResponse(resp.statusCode, resp.body, uri);

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final responseBody =
            resp.body.isNotEmpty ? jsonDecode(resp.body) : null;
        if (responseBody == null) return null;
        final data = _extractEnvelopeData(responseBody);
        if (data != null) return _normalizeLifecycleResponse(data);
        return null;
      }
      throw Exception(
          'Failed to create special request: ${resp.statusCode} ${resp.body}');
    } catch (e) {
      if (_verboseApiLogging && kDebugMode) {
        debugPrint('Error creating special request: $e');
      }
      rethrow;
    }
  }

  /// Create a new special service request with optional file uploads
  static Future<Map<String, dynamic>?> createWithFiles(
      Map<String, dynamic> payload, List<XFile> files) async {
    if (files.isEmpty) {
      return create(payload);
    }

    final token = await TokenStorage.getToken();
    final uri = Uri.parse('$API_BASE_URL/api/special-service-requests');

    final request = http.MultipartRequest('POST', uri);
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    // Add form fields from payload
    payload.forEach((key, value) {
      if (value != null) {
        request.fields[key] = value.toString();
      }
    });

    // Add files
    for (final file in files) {
      final fileBytes = await file.readAsBytes();
      final multipartFile = http.MultipartFile.fromBytes(
        'files[]',
        fileBytes,
        filename: file.name,
      );
      request.files.add(multipartFile);
    }

    debugLogMultipart(
        'POST $uri', request.headers, request.fields, request.files.length);

    try {
      final streamedResponse =
          await request.send().timeout(const Duration(seconds: 30));
      final resp = await http.Response.fromStream(streamedResponse);

      debugLogResponse(resp.statusCode, resp.body, uri);

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final responseBody =
            resp.body.isNotEmpty ? jsonDecode(resp.body) : null;
        if (responseBody == null) return null;
        final data = _extractEnvelopeData(responseBody);
        if (data != null) return _normalizeLifecycleResponse(data);
        return null;
      }
      throw Exception(
          'Failed to create special request: ${resp.statusCode} ${resp.body}');
    } catch (e) {
      if (_verboseApiLogging && kDebugMode) {
        debugPrint('Error creating special request with files: $e');
      }
      rethrow;
    }
  }

  /// Initialize payment for a special request's booking
  static Future<Map<String, dynamic>?> initializePayment(String requestId,
      {String? email, String? requestTitle, dynamic selectedPrice}) async {
    final token = await TokenStorage.getToken();
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';

    final uri =
        Uri.parse('$API_BASE_URL/api/special-service-requests/$requestId/pay');
    final body = email != null && email.isNotEmpty
        ? <String, dynamic>{'email': email}
        : <String, dynamic>{};

    debugLog('POST $uri', headers, body);

    try {
      final resp = await http
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));

      debugLogResponse(resp.statusCode, resp.body, uri);

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final responseBody =
            resp.body.isNotEmpty ? jsonDecode(resp.body) : null;
        if (responseBody == null) return null;
        final data = _extractEnvelopeData(responseBody);
        if (data != null) return _normalizeLifecycleResponse(data);
        return null;
      }
      final decoded = resp.body.isNotEmpty ? jsonDecode(resp.body) : null;
      final message = _extractErrorMessage(decoded) ??
          _extractErrorMessage(resp.body) ??
          'Payment initialization failed';
      return {
        '_error': true,
        'statusCode': resp.statusCode,
        'message': message,
        'body': decoded ?? resp.body,
      };
    } catch (e) {
      if (_verboseApiLogging && kDebugMode) {
        debugPrint('Error initializing payment: $e');
      }
      return {
        '_error': true,
        'message': 'Error initializing payment: $e',
      };
    }
  }

  /// Initialize payment for a special request without creating booking
  static Future<Map<String, dynamic>?> initializePaymentGeneric(
      String requestId, int amount,
      {String? email, String? requestTitle, String? paymentMode}) async {
    final token = await TokenStorage.getToken();
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';

    final uri = Uri.parse('$API_BASE_URL/api/payments/initialize');
    final body = <String, dynamic>{
      'amount': amount,
      'currency': 'NGN',
      'specialRequestId': requestId,
      'specialServiceRequestId': requestId,
      'type': 'special_service_request',
      'bookingSource': 'special_request',
      'metadata': _specialRequestGatewayMetadata(
        requestId,
        requestTitle: requestTitle,
        selectedPrice: amount,
        paymentMode: paymentMode ?? dotenv.env['PAYMENT_MODE'] ?? 'upfront',
      ),
    };
    if (email != null && email.isNotEmpty) body['email'] = email;

    debugLog('POST $uri', headers, body);

    try {
      final resp = await http
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));

      debugLogResponse(resp.statusCode, resp.body, uri);

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final responseBody =
            resp.body.isNotEmpty ? jsonDecode(resp.body) : null;
        if (responseBody == null) return null;
        final data = _extractEnvelopeData(responseBody);
        if (data != null) return _normalizeLifecycleResponse(data);
        return null;
      }
      return null;
    } catch (e) {
      if (_verboseApiLogging && kDebugMode) {
        debugPrint('Error initializing generic payment: $e');
      }
      return null;
    }
  }

  /// Create a booking directly for an accepted special request when payment is
  /// deferred until completion.
  static Future<Map<String, dynamic>?> createDeferredBooking({
    required String requestId,
    required String artisanId,
    required int price,
    String? schedule,
    String? email,
    String? requestTitle,
    String? description,
    String? location,
  }) async {
    final token = await TokenStorage.getToken();
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';

    String? resolvedEmail = email?.trim();
    if (resolvedEmail == null || resolvedEmail.isEmpty) {
      try {
        final profile = await UserService.getProfile();
        final candidate = profile?['email']?.toString().trim();
        if (candidate != null && candidate.isNotEmpty) {
          resolvedEmail = candidate;
        }
      } catch (_) {}
    }
    if (resolvedEmail == null || resolvedEmail.isEmpty) {
      try {
        final remembered = await TokenStorage.getRememberedEmail();
        if (remembered != null && remembered.trim().isNotEmpty) {
          resolvedEmail = remembered.trim();
        }
      } catch (_) {}
    }

    final normalizedSchedule = (schedule != null && schedule.trim().isNotEmpty)
        ? schedule.trim()
        : DateTime.now().toUtc().toIso8601String();

    final body = <String, dynamic>{
      'artisanId': artisanId,
      'price': price,
      'schedule': normalizedSchedule,
      'status': 'pending',
      'paymentMode': 'afterCompletion',
      'bookingSource': 'special_request',
      'specialRequestId': requestId,
      'specialServiceRequestId': requestId,
      'metadata': _specialRequestGatewayMetadata(
        requestId,
        requestTitle: requestTitle,
        selectedPrice: price,
        paymentMode: 'afterCompletion',
      ),
    };

    if (resolvedEmail != null && resolvedEmail.isNotEmpty) {
      body['email'] = resolvedEmail;
    }
    if (requestTitle != null && requestTitle.trim().isNotEmpty) {
      body['service'] = requestTitle.trim();
      body['serviceTitle'] = requestTitle.trim();
    }
    if (description != null && description.trim().isNotEmpty) {
      body['notes'] = description.trim();
      body['description'] = description.trim();
      body['serviceDetail'] = description.trim();
    }
    if (location != null && location.trim().isNotEmpty) {
      body['location'] = location.trim();
      body['address'] = location.trim();
    }

    final uri = Uri.parse('$API_BASE_URL/api/bookings/hire');
    debugLog('POST $uri', headers, body);

    try {
      final resp = await http
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));

      debugLogResponse(resp.statusCode, resp.body, uri);

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final responseBody =
            resp.body.isNotEmpty ? jsonDecode(resp.body) : null;
        if (responseBody == null) return null;
        final data = _extractEnvelopeData(responseBody);
        if (data == null) return null;
        final normalized = _normalizeLifecycleResponse(data);
        final bookingId = normalized['bookingId']?.toString();
        if (bookingId != null && bookingId.isNotEmpty) {
          final threadId = await fetchThreadIdForBooking(bookingId);
          if (threadId != null && threadId.isNotEmpty) {
            normalized['threadId'] = threadId;
          }
        }
        return normalized;
      }
      return {
        '_error': true,
        'statusCode': resp.statusCode,
        'message': _extractErrorMessage(resp.body) ??
            'Failed to create deferred booking',
      };
    } catch (e) {
      if (_verboseApiLogging && kDebugMode) {
        debugPrint('Error creating deferred special-request booking: $e');
      }
      return {
        '_error': true,
        'message': 'Error creating deferred booking: $e',
      };
    }
  }

  static Future<String?> fetchThreadIdForBooking(String bookingId) async {
    final token = await TokenStorage.getToken();
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';

    final uri = Uri.parse('$API_BASE_URL/api/chat/booking/$bookingId');
    debugLog('GET $uri', headers);

    try {
      final resp = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 15));

      debugLogResponse(resp.statusCode, resp.body, uri);

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final responseBody =
            resp.body.isNotEmpty ? jsonDecode(resp.body) : null;
        if (responseBody is Map) {
          final data = responseBody['data'] ?? responseBody;
          if (data is Map) {
            return (data['threadId']?.toString() ??
                data['_id']?.toString() ??
                data['id']?.toString());
          }
        }
      }
    } catch (e) {
      if (_verboseApiLogging && kDebugMode) {
        debugPrint('Error fetching thread for booking: $e');
      }
    }

    return null;
  }

  /// Verify payment by reference
  static Future<Map<String, dynamic>?> verifyPayment(
    String reference, {
    String? specialRequestId,
    String? specialServiceRequestId,
  }) async {
    final token = await TokenStorage.getToken();
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';

    final uri = Uri.parse('$API_BASE_URL/api/payments/verify');
    final body = <String, dynamic>{'reference': reference};

    debugLog('POST $uri', headers, body);

    try {
      final resp = await http
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));

      debugLogResponse(resp.statusCode, resp.body, uri);

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final responseBody =
            resp.body.isNotEmpty ? jsonDecode(resp.body) : null;
        if (responseBody == null) return null;
        final data = _extractEnvelopeData(responseBody);
        if (data != null) return _normalizeLifecycleResponse(data);
        return null;
      }
      return null;
    } catch (e) {
      if (_verboseApiLogging && kDebugMode) {
        debugPrint('Error verifying payment: $e');
      }
      return null;
    }
  }

  // Helper logging methods
  static void debugLog(String message, Map<String, String> headers,
      [Map<String, dynamic>? body]) {
    if (!_verboseApiLogging || !kDebugMode) return;
    // ignore: avoid_print
    print(
        '┌──────────────────────────────────────────────────────────────────────────────');
    // ignore: avoid_print
    print('│ [API Request] $message');
    if (headers.isNotEmpty) {
      // ignore: avoid_print
      print('│ Headers:');
      // ignore: avoid_print
      headers.forEach((k, v) => print('│   $k: $v'));
    }
    if (body != null) {
      // ignore: avoid_print
      print('│ Body: ${jsonEncode(body)}');
    }
    // ignore: avoid_print
    print(
        '└──────────────────────────────────────────────────────────────────────────────');
  }

  static void debugLogResponse(int statusCode, String responseBody, Uri uri) {
    if (!_verboseApiLogging || !kDebugMode) return;
    // ignore: avoid_print
    print(
        '┌──────────────────────────────────────────────────────────────────────────────');
    // ignore: avoid_print
    print('│ [API Response] $statusCode $uri');
    // ignore: avoid_print
    print('│ Body: $responseBody');
    // ignore: avoid_print
    print(
        '└──────────────────────────────────────────────────────────────────────────────');
  }

  static void debugLogMultipart(String message, Map<String, String> headers,
      Map<String, String> fields, int fileCount) {
    if (!_verboseApiLogging || !kDebugMode) return;
    // ignore: avoid_print
    print(
        '┌──────────────────────────────────────────────────────────────────────────────');
    // ignore: avoid_print
    print('│ [API Multipart Request] $message');
    if (headers.isNotEmpty) {
      // ignore: avoid_print
      print('│ Headers:');
      // ignore: avoid_print
      headers.forEach((k, v) => print('│   $k: $v'));
    }
    if (fields.isNotEmpty) {
      // ignore: avoid_print
      print('│ Fields:');
      // ignore: avoid_print
      fields.forEach((k, v) => print('│   $k: $v'));
    }
    // ignore: avoid_print
    print('│ Files: $fileCount');
    // ignore: avoid_print
    print(
        '└──────────────────────────────────────────────────────────────────────────────');
  }
}
