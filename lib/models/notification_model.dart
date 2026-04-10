/// Notification model with proper type safety and data extraction
class NotificationItem {
  final String id;
  final String title;
  final String message;
  final String type;
  final bool isRead;
  final DateTime createdAt;
  final Map<String, dynamic> payload;
  final String? requestId;
  final String? jobId;
  final String? bookingId;
  final String? threadId;
  final String? url;
  final String? amount;
  final String? bookingPrice;

  NotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.isRead,
    required this.createdAt,
    required this.payload,
    this.requestId,
    this.jobId,
    this.bookingId,
    this.threadId,
    this.url,
    this.amount,
    this.bookingPrice,
  });

  /// Factory constructor to parse notification from API response
  factory NotificationItem.fromJson(dynamic json) {
    if (json == null) {
      throw Exception('Notification data is null');
    }

    // Handle if it's not a map
    if (json is! Map) {
      throw Exception('Notification must be a Map');
    }

    final data = Map<String, dynamic>.from(json);

    // Extract payload/data field
    final payload = _extractPayload(data);

    // Extract ID with fallbacks
    final id = data['id']?.toString() ??
        data['_id']?.toString() ??
        data['notificationId']?.toString() ??
        '${DateTime.now().millisecondsSinceEpoch}';

    // Extract type
    final type = (data['type'] ?? payload['type'] ?? 'default').toString();

    // Extract request ID with multiple fallbacks
    final requestId = data['requestId']?.toString() ??
        payload['requestId']?.toString() ??
        payload['specialServiceRequestId']?.toString();

    // Extract job ID
    final jobId = (data['jobId'] ?? data['job'] ?? payload['jobId'])?.toString();

    // Extract booking ID
    final bookingId =
        (data['bookingId'] ?? payload['bookingId'])?.toString();

    // Extract thread ID with multiple fallbacks
    String? threadId = data['threadId']?.toString() ??
        payload['threadId']?.toString() ??
        payload['thread']?.toString();
    threadId ??= payload['chat']?['_id']?.toString() ??
        payload['chat']?['id']?.toString();

    // Extract created at
    DateTime createdAt;
    try {
      if (data['createdAt'] != null) {
        createdAt = DateTime.tryParse(data['createdAt'].toString()) ??
            DateTime.now();
      } else {
        createdAt = DateTime.now();
      }
    } catch (e) {
      createdAt = DateTime.now();
    }

    return NotificationItem(
      id: id,
      title: (data['title'] ?? 'Notification').toString(),
      message: (data['message'] ?? data['body'] ?? '').toString(),
      type: type,
      isRead: data['read'] ?? false,
      createdAt: createdAt,
      payload: payload,
      requestId: requestId,
      jobId: jobId,
      bookingId: bookingId,
      threadId: threadId,
      url: (data['url'] ?? data['link'] ?? payload['url'])?.toString(),
      amount: (data['amount'] ?? payload['amount'])?.toString(),
      bookingPrice: (data['bookingPrice'] ?? payload['bookingPrice'])?.toString(),
    );
  }

  /// Extract payload/data field from notification
  static Map<String, dynamic> _extractPayload(Map<String, dynamic> data) {
    if (data['payload'] is Map) {
      return Map<String, dynamic>.from(data['payload'] as Map);
    } else if (data['data'] is Map) {
      return Map<String, dynamic>.from(data['data'] as Map);
    }
    return {};
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'message': message,
        'type': type,
        'read': isRead,
        'createdAt': createdAt.toIso8601String(),
        'payload': payload,
        'requestId': requestId,
        'jobId': jobId,
        'bookingId': bookingId,
        'threadId': threadId,
        'url': url,
        'amount': amount,
        'bookingPrice': bookingPrice,
      };

  /// Create a copy with updated fields
  NotificationItem copyWith({
    String? id,
    String? title,
    String? message,
    String? type,
    bool? isRead,
    DateTime? createdAt,
    Map<String, dynamic>? payload,
    String? requestId,
    String? jobId,
    String? bookingId,
    String? threadId,
    String? url,
    String? amount,
    String? bookingPrice,
  }) =>
      NotificationItem(
        id: id ?? this.id,
        title: title ?? this.title,
        message: message ?? this.message,
        type: type ?? this.type,
        isRead: isRead ?? this.isRead,
        createdAt: createdAt ?? this.createdAt,
        payload: payload ?? this.payload,
        requestId: requestId ?? this.requestId,
        jobId: jobId ?? this.jobId,
        bookingId: bookingId ?? this.bookingId,
        threadId: threadId ?? this.threadId,
        url: url ?? this.url,
        amount: amount ?? this.amount,
        bookingPrice: bookingPrice ?? this.bookingPrice,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotificationItem &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Enum for notification types
enum NotificationType {
  specialRequest('special_request'),
  commission('commission'),
  review('review'),
  order('order'),
  message('message'),
  workshop('workshop'),
  favorite('favorite'),
  sales('sales'),
  booking('booking'),
  payment('payment'),
  unknown('default');

  final String value;

  const NotificationType(this.value);

  factory NotificationType.fromString(String? type) {
    return NotificationType.values
            .firstWhere((e) => e.value == type?.toLowerCase(), orElse: () {
      return NotificationType.unknown;
    });
  }

  bool get isUnread => false; // Will be managed at model level
}

/// Response wrapper for paginated notifications
class NotificationResponse {
  final List<NotificationItem> notifications;
  final int page;
  final int perPage;
  final int total;
  final bool hasMore;

  NotificationResponse({
    required this.notifications,
    required this.page,
    required this.perPage,
    required this.total,
    required this.hasMore,
  });

  factory NotificationResponse.fromJson(dynamic json, int page, int perPage) {
    List<NotificationItem> notifications = [];

    if (json == null) {
      return NotificationResponse(
        notifications: [],
        page: page,
        perPage: perPage,
        total: 0,
        hasMore: false,
      );
    }

    if (json is List) {
      notifications = (json as List)
          .map((item) {
            try {
              return NotificationItem.fromJson(item);
            } catch (e) {
              return null;
            }
          })
          .whereType<NotificationItem>()
          .toList();
    } else if (json is Map) {
      List<dynamic> items = [];

      if (json['data'] is List) {
        items = json['data'] as List;
      } else if (json['notifications'] is List) {
        items = json['notifications'] as List;
      } else if (json['items'] is List) {
        items = json['items'] as List;
      } else {
        final listVal = json.values
            .firstWhere((v) => v is List, orElse: () => null);
        if (listVal is List) items = listVal;
      }

      notifications = items
          .map((item) {
            try {
              return NotificationItem.fromJson(item);
            } catch (e) {
              return null;
            }
          })
          .whereType<NotificationItem>()
          .toList();
    }

    int total = json is Map ? (json['total'] ?? notifications.length) : notifications.length;

    return NotificationResponse(
      notifications: notifications,
      page: page,
      perPage: perPage,
      total: total,
      hasMore: notifications.length >= perPage,
    );
  }
}

