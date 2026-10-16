import 'dart:convert';
import 'api_client.dart';
import '../api_config.dart';

class NotificationService {
  static String? _readString(dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  static String _utf8SafeString(String value) {
    try {
      return utf8.decode(utf8.encode(value));
    } catch (_) {
      return value;
    }
  }

  static dynamic _utf8SafeValue(dynamic value) {
    if (value == null) return null;
    if (value is String) return _utf8SafeString(value);
    if (value is Map) {
      return value.map(
        (key, val) => MapEntry(key, _utf8SafeValue(val)),
      );
    }
    if (value is List) {
      return value.map(_utf8SafeValue).toList();
    }
    return value;
  }

  // Try to fetch unread count; returns -1 on failure
  static Future<int> fetchUnreadCount() async {
    final candidates = [
      '$API_BASE_URL/api/notifications/unread-count',
      '$API_BASE_URL/api/notifications/count',
      '$API_BASE_URL/api/notifications?unread=true',
      '$API_BASE_URL/api/notifications',
    ];
    int found = -1;
    for (final url in candidates) {
      try {
        final resp = await ApiClient.get(url,
            headers: {'Content-Type': 'application/json'});
        final status = resp['status'] as int? ?? 0;
        final body = resp['body']?.toString() ?? '';
        if (status >= 200 && status < 300 && body.isNotEmpty) {
          try {
            final decoded = jsonDecode(body);
            if (decoded is int) {
              found = decoded;
            } else if (decoded is Map) {
              if (decoded.containsKey('unreadCount'))
                found = int.tryParse(decoded['unreadCount'].toString()) ?? -1;
              else if (decoded.containsKey('count'))
                found = int.tryParse(decoded['count'].toString()) ?? -1;
              else if (decoded.containsKey('total'))
                found = int.tryParse(decoded['total'].toString()) ?? -1;
              else if (decoded['data'] is List)
                found = (decoded['data'] as List).length;
              else {
                for (final k in ['items', 'notifications', 'results', 'data']) {
                  if (decoded[k] is List) {
                    found = (decoded[k] as List).length;
                    break;
                  }
                }
              }
            } else if (decoded is List) {
              found = decoded.length;
            } else if (body.trim().isNotEmpty) {
              final n = int.tryParse(body.trim());
              if (n != null) found = n;
            }
          } catch (_) {}
        }
      } catch (_) {}
      if (found >= 0) break;
    }
    return found;
  }

  // Fetch full notifications list (best-effort) - can be extended later
  static Future<dynamic> fetchNotifications(
      {int page = 1, int perPage = 20}) async {
    final url = '$API_BASE_URL/api/notifications?page=$page&limit=$perPage';
    final resp =
        await ApiClient.get(url, headers: {'Content-Type': 'application/json'});
    final status = resp['status'] as int? ?? 0;
    final body = resp['body']?.toString() ?? '';
    if (status >= 200 && status < 300 && body.isNotEmpty) {
      try {
        return jsonDecode(body);
      } catch (_) {
        return body;
      }
    }
    return null;
  }

  // Mark all notifications as read (best-effort). Returns true on success.
  static Future<bool> markAllRead() async {
    final endpoints = [
      '$API_BASE_URL/api/notifications/mark-all-read',
      '$API_BASE_URL/api/notifications/read',
      '$API_BASE_URL/api/notifications/mark-read',
      '$API_BASE_URL/api/notifications',
    ];
    for (final url in endpoints) {
      try {
        final resp = await ApiClient.post(url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({}));
        final status = resp['status'] as int? ?? 0;
        if (status >= 200 && status < 300) return true;
      } catch (_) {}
    }
    return false;
  }

  /// Send a notification to a specific user (best-effort).
  /// The server must accept POST /api/notifications with a payload like
  /// { toUserId, title, body, payload } or similar. We try a few common endpoints.
  static Future<bool> sendNotification(
      String? toUserId, String title, String body,
      {Map<String, dynamic>? payload}) async {
    if (toUserId == null || toUserId.isEmpty) return false;
    final safeTitle = _utf8SafeString(title);
    final safeBody = _utf8SafeString(body);
    final safePayload = payload == null
        ? null
        : Map<String, dynamic>.from(_utf8SafeValue(payload) as Map);
    final endpoints = [
      '$API_BASE_URL/api/notifications',
      '$API_BASE_URL/api/notifications/send',
      '$API_BASE_URL/api/notifications/create',
    ];
    final bodyMap = <String, dynamic>{
      'toUserId': toUserId,
      'title': safeTitle,
      'body': safeBody,
      'message': safeBody,
      if (safePayload?['type'] != null) 'type': safePayload!['type'],
      if (safePayload != null) 'payload': safePayload,
    };

    for (final url in endpoints) {
      try {
        final resp = await ApiClient.post(url,
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'Accept-Charset': 'utf-8',
            },
            body: jsonEncode(bodyMap));
        final status = resp['status'] as int? ?? 0;
        if (status >= 200 && status < 300) return true;
      } catch (_) {}
    }
    return false;
  }

  static Future<bool> sendSpecialRequestNotification({
    required String? toUserId,
    required String requestId,
    required String eventType,
    String? requestTitle,
    String? actorName,
    String? quoteLabel,
  }) async {
    if (toUserId == null || toUserId.isEmpty || requestId.isEmpty) return false;

    final safeTitle = _readString(requestTitle) ?? 'Special service request';
    final safeActor = _readString(actorName);
    final safeQuote = _readString(quoteLabel);

    late final String title;
    late final String message;
    switch (eventType) {
      case 'created':
        title = 'New special request';
        message = safeActor != null
            ? '$safeActor sent a new request for $safeTitle'
            : 'You received a new request for $safeTitle';
        break;
      case 'responded':
        title = 'Special request updated';
        message = safeQuote != null
            ? '${safeActor ?? 'Your artisan'} responded with $safeQuote'
            : '${safeActor ?? 'Your artisan'} responded to $safeTitle';
        break;
      case 'accepted':
        title = 'Request accepted';
        message = safeQuote != null
            ? '${safeActor ?? 'Client'} accepted $safeTitle at $safeQuote'
            : '${safeActor ?? 'Client'} accepted $safeTitle';
        break;
      case 'payment_pending':
        title = 'Payment in progress';
        message = safeQuote != null
            ? 'Payment is being processed for $safeTitle at $safeQuote'
            : 'Payment is being processed for $safeTitle';
        break;
      case 'payment_confirmed':
        title = 'Payment confirmed';
        message = safeQuote != null
            ? 'Payment confirmed for $safeTitle at $safeQuote'
            : 'Payment confirmed for $safeTitle';
        break;
      case 'cancelled':
        title = 'Request cancelled';
        message = safeActor != null
            ? '$safeActor cancelled $safeTitle'
            : '$safeTitle was cancelled';
        break;
      default:
        title = 'Special request update';
        message = safeTitle;
    }

    return sendNotification(
      toUserId,
      title,
      message,
      payload: {
        'type': 'special_request',
        'eventType': eventType,
        'requestId': requestId,
        if (requestTitle != null && requestTitle.isNotEmpty)
          'requestTitle': requestTitle,
        if (quoteLabel != null && quoteLabel.isNotEmpty)
          'quoteLabel': quoteLabel,
      },
    );
  }

  // Fetch a single job by id. Returns a Map or null if not found.
  static Future<Map<String, dynamic>?> fetchJobById(String id) async {
    if (id.isEmpty) return null;
    final url = '$API_BASE_URL/api/jobs/$id';
    try {
      final resp = await ApiClient.get(url,
          headers: {'Content-Type': 'application/json'});
      final status = resp['status'] as int? ?? 0;
      final body = resp['body']?.toString() ?? '';
      if (status >= 200 && status < 300 && body.isNotEmpty) {
        try {
          final decoded = jsonDecode(body);
          final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
          if (data is Map) return Map<String, dynamic>.from(data);
        } catch (_) {}
      }
    } catch (_) {}
    return null;
  }
}
