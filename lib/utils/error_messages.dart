import 'dart:convert';
import 'dart:async';

class ErrorMessages {
  /// Convert various error forms into a short, user-friendly string.
  static String humanize(dynamic error, {String? context}) {
    try {
      // Timeout
      if (error is TimeoutException) return 'Request timed out. Please check your connection and try again.';

      // If it's already a string, try to decode JSON inside it or return trimmed string
      if (error is String) {
        final s = error.trim();
        // try JSON
        try {
          final decoded = jsonDecode(s);
          return _extractFromBody(decoded) ?? _shortFallback(s);
        } catch (_) {
          return _shortFallback(s);
        }
      }

      // If it's an Exception with message
      if (error is Exception) {
        final s = error.toString();
        // remove the leading "Exception: " if present
        final cleaned = s.replaceFirst(RegExp(r'^Exception:\s*'), '');
        // try parse possible JSON inside
        try {
          final decoded = jsonDecode(cleaned);
          return _extractFromBody(decoded) ?? _shortFallback(cleaned);
        } catch (_) {
          return _shortFallback(cleaned);
        }
      }

      // If it's an http.Response-like Map or decoded JSON object
      if (error is Map || error is List) {
        final extracted = _extractFromBody(error);
        if (extracted != null) return extracted;
      }

      // If it has a `message` property
      try {
        final msg = (error as dynamic).message;
        if (msg != null) return msg.toString();
      } catch (_) {}

      // Fallback to toString
      final s = error.toString();
      return _shortFallback(s);
    } catch (_) {
      return 'Something went wrong. Please try again.';
    }
  }

  static String? _extractFromBody(dynamic decoded) {
    if (decoded == null) return null;
    if (decoded is String) return decoded;
    if (decoded is Map) {
      // Common server shapes
      if (decoded.containsKey('message')) return decoded['message']?.toString();
      if (decoded.containsKey('error')) {
        final e = decoded['error'];
        if (e is String) return e;
        if (e is Map && e.containsKey('message')) return e['message']?.toString();
      }
      if (decoded.containsKey('errors')) {
        final errs = decoded['errors'];
        if (errs is Map) {
          // Join first field errors
          for (final v in errs.values) {
            if (v is String) return v;
            if (v is List && v.isNotEmpty) return v.first.toString();
          }
        }
      }
      // Try nested data.message
      if (decoded.containsKey('data') && decoded['data'] is Map) {
        final d = decoded['data'];
        if (d.containsKey('message')) return d['message']?.toString();
      }
    }
    return null;
  }

  static String _shortFallback(String s) {
    if (s.isEmpty) return 'Something went wrong. Please try again.';

    // Recognize some common server messages and remap to friendlier text
    final lc = s.toLowerCase();

    // Detect HTTP 413 / "Request Entity Too Large" responses which may come back as
    // plain text, JSON, or verbose HTML from nginx. Map to a clear user-facing message.
    if (lc.contains('request entity too large') || lc.contains('413 request') ||
        (RegExp(r'\b413\b').hasMatch(lc) && (lc.contains('request') || lc.contains('entity') || lc.contains('<html')))) {
      return 'The file you tried to upload is too large. Please choose a smaller image or compress it and try again.';
    }

    if (lc.contains('artisan profile not found')) return 'We could not find your artisan profile. Please complete your artisan registration.';
    if (lc.contains('invalid image data') || lc.contains('invalid image')) return 'Failed to load an image. Please try again.';
    if (lc.contains('401') || lc.contains('unauthorized') || lc.contains('not authenticated')) return 'You are not authenticated. Please sign in again.';
    if (lc.contains('404') || lc.contains('not found')) return 'Requested resource not found.';
    if (lc.contains('timeout')) return 'Request timed out. Please try again.';
    if (lc.contains('socket') && lc.contains('disconnected')) return 'Realtime connection lost. Some features may be unavailable.';
    if (lc.length > 200) return s.substring(0, 200) + '...';

    return s;
  }
}

