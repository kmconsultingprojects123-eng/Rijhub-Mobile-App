import 'dart:convert';
import 'api_client.dart';
import '../api_config.dart';

class AdminService {
  static Future<Map<String, dynamic>?> getCentral() async {
    final uri = '$API_BASE_URL/api/admin/central';
    final resp = await ApiClient.get(uri, headers: {'Content-Type': 'application/json'});
    try {
      if (resp['status'] is int && resp['status'] >= 200 && resp['status'] < 300) {
        final body = jsonDecode(resp['body']);
        if (body is Map) return Map<String, dynamic>.from(body['data'] ?? body);
      }
    } catch (e) {
      // ignore
    }
    return null;
  }

  // New: return raw response for debugging (status + decoded body if possible)
  static Future<Map<String, dynamic>> fetchCentralRaw() async {
    final uri = '$API_BASE_URL/api/admin/central';
    final resp = await ApiClient.get(uri, headers: {'Content-Type': 'application/json'});
    final result = {'status': resp['status'], 'body': resp['body']};
    try {
      final decoded = jsonDecode(resp['body']);
      result['decoded'] = decoded;
    } catch (_) {}
    return result;
  }

  static Future<Map<String, dynamic>?> updateCentral(Map<String, dynamic> payload) async {
    final uri = '$API_BASE_URL/api/admin/central';
    final resp = await ApiClient.post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload));
    try {
      final body = jsonDecode(resp['body']);
      if (body is Map) return Map<String, dynamic>.from(body);
    } catch (e) {
      // ignore
    }
    return null;
  }
}
