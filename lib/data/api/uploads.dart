import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mime_type/mime_type.dart';

import 'api_client.dart';
import 'api_codec.dart';

/// What the API calls each kind of upload, which sets where it's stored.
enum UploadKind { avatar, work, problem, chat, voice }

/// Photos and voice notes, sent straight to Cloud Storage with a signed
/// link from the API: the file never passes through the API itself.
class Uploader {
  Uploader(this._api, {http.Client? client}) : _http = client ?? http.Client();

  final ApiClient _api;
  final http.Client _http;

  /// [ref] as the app holds it, made into something the API can store: a
  /// local file is uploaded and its URL returned; a URL or a bundled asset
  /// is already shareable and returned as it is. Null when the file is
  /// gone, or uploads aren't switched on yet (local development), so the
  /// attachment is left out rather than the whole action failing.
  Future<String?> upload(String ref, UploadKind kind) async {
    if (ref.startsWith('http') || ref.startsWith('assets/')) return ref;
    final file = File(ref.replaceFirst('file://', ''));
    if (!await file.exists()) return null;
    final contentType = mime(file.path) ??
        (kind == UploadKind.voice ? 'audio/aac' : 'image/jpeg');
    final Json slot;
    try {
      slot = asMap(await _api.post('/v1/me/uploads', {
        'kind': kind.name,
        'content_type': contentType,
      }));
    } on ApiException catch (e) {
      if (e.code == 'uploads_unavailable') {
        debugPrint('uploads are off: leaving out ${file.path}');
        return null;
      }
      rethrow;
    }
    final headers = {
      for (final MapEntry(:key, :value) in asMap(slot['headers']).entries)
        key: value! as String,
    };
    final http.Response response;
    try {
      response = await _http.put(Uri.parse(slot['upload_url']! as String),
          headers: headers, body: await file.readAsBytes());
    } on Object {
      throw const ApiException(
          "We couldn't send that file. Check your connection and try again.",
          code: 'offline');
    }
    if (response.statusCode >= 300) {
      debugPrint('upload failed ${response.statusCode}: ${response.body}');
      throw ApiException("We couldn't send that file. Try a smaller one.",
          code: 'upload_failed', status: response.statusCode);
    }
    return slot['public_url']! as String;
  }

  /// Several at once, keeping their order and leaving out any that
  /// couldn't be sent.
  Future<List<String>> uploadAll(Iterable<String> refs, UploadKind kind) async {
    final urls = await Future.wait([for (final r in refs) upload(r, kind)]);
    return [
      for (final u in urls)
        if (u != null) u
    ];
  }
}
