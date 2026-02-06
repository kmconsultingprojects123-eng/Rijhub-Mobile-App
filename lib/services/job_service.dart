import 'dart:convert';
import 'package:http/http.dart' as http;
import '../api_config.dart';
import 'token_storage.dart';
import 'user_service.dart';
import 'api_client.dart';

class JobService {
  static Future<Map<String, dynamic>> createJob(
      Map<String, dynamic> payload) async {
    final url = '$API_BASE_URL/api/jobs';

    // Use ApiClient to get structured response and user-friendly errors
    final res = await ApiClient.post(url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload));
    final status = res['status'] as int? ?? 0;
    if (status >= 200 && status < 300) {
      final jsonBody = res['json'];
      if (jsonBody is Map && jsonBody['data'] is Map)
        return Map<String, dynamic>.from(jsonBody['data']);
      if (jsonBody is Map) return Map<String, dynamic>.from(jsonBody);
      return {};
    }

    final userMessage =
        res['userMessage'] as String? ?? 'Failed to create job.';
    throw Exception(userMessage);
  }

  /// Fetch public job categories from the API (/api/job-categories).
  /// Returns a list of maps like { '_id': '...', 'name': 'Plumbing', 'slug': 'plumbing' }.
  static Future<List<Map<String, dynamic>>> getJobCategories(
      {int page = 1, int limit = 100}) async {
    final token = await TokenStorage.getToken();
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    var uri = Uri.parse('$API_BASE_URL/api/job-categories');
    final q = <String, String>{
      'page': page.toString(),
      'limit': limit.toString()
    };
    uri = uri.replace(queryParameters: q);

    // ┌──────────────────────────────────────────────────────────────────────────────
    // │ API Logger - Request (JobService)
    // └──────────────────────────────────────────────────────────────────────────────
    // ignore: avoid_print
    print(
        '┌──────────────────────────────────────────────────────────────────────────────');
    // ignore: avoid_print
    print('│ [API Request] GET $uri');
    if (headers.isNotEmpty) {
      // ignore: avoid_print
      print('│ Headers:');
      // ignore: avoid_print
      headers.forEach((k, v) => print('│   $k: $v'));
    }
    // ignore: avoid_print
    print(
        '└──────────────────────────────────────────────────────────────────────────────');

    final resp =
        await http.get(uri, headers: headers).timeout(Duration(seconds: 15));

    // ┌──────────────────────────────────────────────────────────────────────────────
    // │ API Logger - Response (JobService)
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
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : null;
      if (body == null) return [];
      // body may be { success: true, data: [...] }
      if (body is Map && body['data'] is List)
        return List<Map<String, dynamic>>.from(
            body['data'].map((e) => Map<String, dynamic>.from(e)));
      if (body is List)
        return List<Map<String, dynamic>>.from(
            body.map((e) => Map<String, dynamic>.from(e)));
      return [];
    }
    throw Exception(
        'Failed to fetch job categories: ${resp.statusCode} ${resp.body}');
  }

  /// as query parameters. This returns decoded JSON as a List if possible.
  static Future<List<Map<String, dynamic>>> getAllJobs() async {
    final token = await TokenStorage.getToken();
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    var uri = Uri.parse('$API_BASE_URL/api/jobs');
    // if (params != null && params.isNotEmpty) uri = uri.replace(queryeryParameters: params);

    // ┌──────────────────────────────────────────────────────────────────────────────
    // │ API Logger - Request (JobService)
    // └──────────────────────────────────────────────────────────────────────────────
    // ignore: avoid_print
    print(
        '┌──────────────────────────────────────────────────────────────────────────────');
    // ignore: avoid_print
    print('│ [API Request] GET $uri');
    if (headers.isNotEmpty) {
      // ignore: avoid_print
      print('│ Headers:');
      // ignore: avoid_print
      headers.forEach((k, v) => print('│   $k: $v'));
    }
    // ignore: avoid_print
    print(
        '└──────────────────────────────────────────────────────────────────────────────');

    final resp =
        await http.get(uri, headers: headers).timeout(Duration(seconds: 15));

    // ┌──────────────────────────────────────────────────────────────────────────────
    // │ API Logger - Response (JobService)
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
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : null;
      if (body == null) return [];
      if (body is List)
        return List<Map<String, dynamic>>.from(
            body.map((e) => Map<String, dynamic>.from(e)));
      if (body is Map && body['data'] is List)
        return List<Map<String, dynamic>>.from(
            body['data'].map((e) => Map<String, dynamic>.from(e)));
      // Some APIs return { items: [...] }
      if (body is Map && body['items'] is List)
        return List<Map<String, dynamic>>.from(
            body['items'].map((e) => Map<String, dynamic>.from(e)));
      return [];
    }
    throw Exception('Failed to fetch jobs: ${resp.statusCode} ${resp.body}');
  }

  /// New: Fetch jobs using server-side pagination. Attempts to use `page`, `limit` and an optional `q` query parameter.
  /// Falls back to the same parsing logic as other methods.
  static Future<List<Map<String, dynamic>>> getJobs(
      {int page = 1, int limit = 12, String? query}) async {
    final token = await TokenStorage.getToken();
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    var uri = Uri.parse('$API_BASE_URL/api/jobs');
    final q = <String, String>{
      'page': page.toString(),
      'limit': limit.toString()
    };
    if (query != null && query.trim().isNotEmpty) {
      // Common param names: q, search, query. Try 'q' first.
      q['q'] = query.trim();
    }
    uri = uri.replace(queryParameters: q);

    // ┌──────────────────────────────────────────────────────────────────────────────
    // │ API Logger - Request (JobService)
    // └──────────────────────────────────────────────────────────────────────────────
    // ignore: avoid_print
    print(
        '┌──────────────────────────────────────────────────────────────────────────────');
    // ignore: avoid_print
    print('│ [API Request] GET $uri');
    if (headers.isNotEmpty) {
      // ignore: avoid_print
      print('│ Headers:');
      // ignore: avoid_print
      headers.forEach((k, v) => print('│   $k: $v'));
    }
    // ignore: avoid_print
    print(
        '└──────────────────────────────────────────────────────────────────────────────');

    final resp =
        await http.get(uri, headers: headers).timeout(Duration(seconds: 15));

    // ┌──────────────────────────────────────────────────────────────────────────────
    // │ API Logger - Response (JobService)
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
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : null;
      if (body == null) return [];
      if (body is List)
        return List<Map<String, dynamic>>.from(
            body.map((e) => Map<String, dynamic>.from(e)));
      if (body is Map && body['data'] is List)
        return List<Map<String, dynamic>>.from(
            body['data'].map((e) => Map<String, dynamic>.from(e)));
      if (body is Map && body['items'] is List)
        return List<Map<String, dynamic>>.from(
            body['items'].map((e) => Map<String, dynamic>.from(e)));
      // Some servers respond with { success: true, results: [...], total: 123 }
      if (body is Map) {
        final possibleLists = <String>['results', 'data', 'items'];
        for (final k in possibleLists) {
          if (body[k] is List)
            return List<Map<String, dynamic>>.from(
                body[k].map((e) => Map<String, dynamic>.from(e)));
        }
      }
      return [];
    }
    throw Exception(
        'Failed to fetch paginated jobs: ${resp.statusCode} ${resp.body}');
  }

  /// Fetch open jobs from the server. If `params` is provided it's appended
  /// as query parameters. This returns decoded JSON as a List if possible.
  static Future<List<Map<String, dynamic>>> getUserJobs(
      {Map<String, String>? params}) async {
    final token = await TokenStorage.getToken();
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    var uri = Uri.parse('$API_BASE_URL/api/jobs/mine');
    if (params != null && params.isNotEmpty)
      uri = uri.replace(queryParameters: params);

    // ┌──────────────────────────────────────────────────────────────────────────────
    // │ API Logger - Request (JobService)
    // └──────────────────────────────────────────────────────────────────────────────
    // ignore: avoid_print
    print(
        '┌──────────────────────────────────────────────────────────────────────────────');
    // ignore: avoid_print
    print('│ [API Request] GET $uri');
    if (headers.isNotEmpty) {
      // ignore: avoid_print
      print('│ Headers:');
      // ignore: avoid_print
      headers.forEach((k, v) => print('│   $k: $v'));
    }
    // ignore: avoid_print
    print(
        '└──────────────────────────────────────────────────────────────────────────────');

    final resp =
        await http.get(uri, headers: headers).timeout(Duration(seconds: 15));

    // ┌──────────────────────────────────────────────────────────────────────────────
    // │ API Logger - Response (JobService)
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
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : null;
      if (body == null) return [];
      if (body is List)
        return List<Map<String, dynamic>>.from(
            body.map((e) => Map<String, dynamic>.from(e)));
      if (body is Map && body['data'] is List)
        return List<Map<String, dynamic>>.from(
            body['data'].map((e) => Map<String, dynamic>.from(e)));
      // Some APIs return { items: [...] }
      if (body is Map && body['items'] is List)
        return List<Map<String, dynamic>>.from(
            body['items'].map((e) => Map<String, dynamic>.from(e)));
      return [];
    }
    throw Exception('Failed to fetch jobs: ${resp.statusCode} ${resp.body}');
  }

  /// Try to fetch jobs owned by the currently authenticated user. We first
  /// check the API for a server-side filter (clientId), otherwise we fetch
  /// the jobs list and filter locally.
  static Future<List<Map<String, dynamic>>> getMyJobs() async {
    final profile = await UserService.getProfile();
    if (profile == null) return [];
    final myId =
        (profile['id'] ?? profile['_id'] ?? profile['userId'])?.toString();
    // print(myId);
    // print(await getJobs());
    try {
      // Try server-side filtered query first if we have a valid id
      if (myId != null && myId.isNotEmpty) {
        final serverFiltered = await getUserJobs(params: {'clientId': myId});
        // debug printing removed to reduce console noise in production builds
        if (serverFiltered.isNotEmpty) return serverFiltered;
      }
    } catch (_) {
      // ignore and fallback to fetching all then filtering
    }
    final all = await getUserJobs();
    try {
      return all.where((j) {
        final cid = j['clientId'];
        if (cid == null) return false;
        if (cid is Map)
          return (cid['_id']?.toString() ?? cid['id']?.toString() ?? '') ==
              myId;
        return cid.toString() == myId;
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Delete a job by id (owner only). Returns true on success.
  static Future<bool> deleteJob(String id) async {
    if (id.isEmpty) throw Exception('Job id required');
    final token = await TokenStorage.getToken();
    // Do not send a 'Content-Type' for DELETE when there is no body — some servers
    // reject DELETE requests that include 'application/json' with an empty body.
    final headers = <String, String>{};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    final uri = Uri.parse('$API_BASE_URL/api/jobs/$id');

    // ┌──────────────────────────────────────────────────────────────────────────────
    // │ API Logger - Request (JobService)
    // └──────────────────────────────────────────────────────────────────────────────
    // ignore: avoid_print
    print(
        '┌──────────────────────────────────────────────────────────────────────────────');
    // ignore: avoid_print
    print('│ [API Request] DELETE $uri');
    if (headers.isNotEmpty) {
      // ignore: avoid_print
      print('│ Headers:');
      // ignore: avoid_print
      headers.forEach((k, v) => print('│   $k: $v'));
    }
    // ignore: avoid_print
    print(
        '└──────────────────────────────────────────────────────────────────────────────');

    final resp =
        await http.delete(uri, headers: headers).timeout(Duration(seconds: 15));

    // ┌──────────────────────────────────────────────────────────────────────────────
    // │ API Logger - Response (JobService)
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
    if (resp.statusCode >= 200 && resp.statusCode < 300) return true;
    throw Exception('Failed to delete job: ${resp.statusCode} ${resp.body}');
  }

  /// Update a job by id with provided fields. Returns updated job map.
  static Future<Map<String, dynamic>> updateJob(
      String id, Map<String, dynamic> payload) async {
    if (id.isEmpty) throw Exception('Job id required');
    final token = await TokenStorage.getToken();
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    final uri = Uri.parse('$API_BASE_URL/api/jobs/$id');

    // ┌──────────────────────────────────────────────────────────────────────────────
    // │ API Logger - Request (JobService)
    // └──────────────────────────────────────────────────────────────────────────────
    // ignore: avoid_print
    print(
        '┌──────────────────────────────────────────────────────────────────────────────');
    // ignore: avoid_print
    print('│ [API Request] PATCH $uri');
    if (headers.isNotEmpty) {
      // ignore: avoid_print
      print('│ Headers:');
      // ignore: avoid_print
      headers.forEach((k, v) => print('│   $k: $v'));
    }
    // ignore: avoid_print
    print('│ Body: ${jsonEncode(payload)}');
    // ignore: avoid_print
    print(
        '└──────────────────────────────────────────────────────────────────────────────');

    final resp = await http
        .patch(uri, headers: headers, body: jsonEncode(payload))
        .timeout(Duration(seconds: 15));

    // ┌──────────────────────────────────────────────────────────────────────────────
    // │ API Logger - Response (JobService)
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
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : {};
      if (body is Map && body['data'] is Map)
        return Map<String, dynamic>.from(body['data']);
      if (body is Map) return Map<String, dynamic>.from(body);
      return {};
    }
    throw Exception('Failed to update job: ${resp.statusCode} ${resp.body}');
  }
}
