import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../api_config.dart';

class UnsignedUploadNotConfigured implements Exception {
  final String message;
  UnsignedUploadNotConfigured([this.message = 'Unsigned Cloudinary upload not configured']);
  @override
  String toString() => 'UnsignedUploadNotConfigured: $message';
}

/// Upload helper that requests an upload signature from the backend and
/// uploads a file directly to Cloudinary. The backend must implement
/// POST /api/uploads/sign which returns JSON with at least: { signature, timestamp, api_key, upload_url?, public_id? }
/// The function returns a map { 'url': <secure_url>, 'public_id': <public_id> } on success.
class UploadService {
  /// Request a server-generated signature for a single upload. The server
  /// should validate the authenticated user and return signature/timestamp.
  static Future<Map<String, dynamic>> requestSignature({
    String? folder,
    String? publicId,
    String? token,
  }) async {
    final uri = Uri.parse('$API_BASE_URL/api/uploads/sign');
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    final body = <String, dynamic>{};
    if (folder != null) body['folder'] = folder;
    if (publicId != null) body['public_id'] = publicId;

    final resp = await http.post(uri, headers: headers, body: jsonEncode(body)).timeout(const Duration(seconds: 20));
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }

    // Return a special error shape for 404 so callers can decide to fallback
    // to unsigned uploads. We keep the original error info in the thrown
    // Exception to aid debugging.
    throw Exception('Signature request failed: ${resp.statusCode} ${resp.body}');
  }

  /// Upload a file to Cloudinary using the signed params returned by the server.
  /// If server returns an upload_url use that; otherwise use the default cloudinary endpoint.
  static Future<Map<String, dynamic>> uploadFileDirect({
    required File file,
    required Map<String, dynamic> signData,
  }) async {
    // Basic checks
    if (!file.existsSync()) {
      throw Exception('Upload failed: file not found at ${file.path}');
    }

    final cloudUrl = (signData['upload_url'] as String?) ?? 'https://api.cloudinary.com/v1_1/${signData['cloud_name'] ?? ''}/auto/upload';
    final uri = Uri.parse(cloudUrl);

    // Try upload with a couple retries for transient network/server errors
    const int maxAttempts = 3;
    int attempt = 0;
    late http.Response finalResp;

    while (attempt < maxAttempts) {
      attempt += 1;
      try {
        final req = http.MultipartRequest('POST', uri);

        // Add signature fields from signData (api_key, timestamp, signature, public_id, folder)
        for (final k in ['api_key', 'timestamp', 'signature', 'public_id', 'folder']) {
          if (signData[k] != null) {
            req.fields[k] = signData[k].toString();
          }
        }

        final multipart = await http.MultipartFile.fromPath('file', file.path);
        req.files.add(multipart);

        final streamed = await req.send().timeout(const Duration(seconds: 60));
        finalResp = await http.Response.fromStream(streamed);

        if (finalResp.statusCode >= 200 && finalResp.statusCode < 300) {
          final body = jsonDecode(finalResp.body);
          return {
            'url': body['secure_url'] ?? body['url'],
            'public_id': body['public_id'] ?? signData['public_id'],
            'raw': body,
          };
        }

        // For 5xx errors, retry after backoff; for 4xx fail fast (likely client/signature issue)
        if (finalResp.statusCode >= 500 && attempt < maxAttempts) {
          final wait = Duration(milliseconds: 300 * (1 << (attempt - 1)));
          await Future.delayed(wait);
          continue;
        }

        // Non-retriable error - surface server response
        throw Exception('Cloud upload failed: ${finalResp.statusCode} ${finalResp.body}');
      } catch (e) {
        // Network-level errors (timeout, socket) - retry if attempts left
        if (attempt < maxAttempts) {
          final wait = Duration(milliseconds: 300 * (1 << (attempt - 1)));
          await Future.delayed(wait);
          continue;
        }
        // No attempts left - rethrow with context
        throw Exception('Cloud upload failed after $attempt attempts: $e');
      }
    }

    // Should not reach here, but throw with last response if available
    throw Exception('Cloud upload failed: unexpected error. Last response: ${finalResp.statusCode} ${finalResp.body}');
  }

  /// Upload a file using an unsigned upload preset (no backend signature).
  /// Requires CLOUDINARY_CLOUD_NAME and CLOUDINARY_UPLOAD_PRESET to be set.
  static Future<Map<String, dynamic>> uploadFileUnsigned({
    required File file,
    required String uploadPreset,
    required String cloudName,
  }) async {
    if (cloudName.isEmpty || uploadPreset.isEmpty) {
      throw UnsignedUploadNotConfigured();
    }

    if (!file.existsSync()) {
      throw Exception('Upload failed: file not found at ${file.path}');
    }

    final uri = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/auto/upload');
    final req = http.MultipartRequest('POST', uri);
    req.fields['upload_preset'] = uploadPreset;

    final mf = await http.MultipartFile.fromPath('file', file.path);
    req.files.add(mf);

    final streamed = await req.send().timeout(const Duration(seconds: 60));
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final body = jsonDecode(resp.body);
      return {
        'url': body['secure_url'] ?? body['url'],
        'public_id': body['public_id'],
        'raw': body,
      };
    }
    throw Exception('Unsigned cloud upload failed: ${resp.statusCode} ${resp.body}');
  }
}
