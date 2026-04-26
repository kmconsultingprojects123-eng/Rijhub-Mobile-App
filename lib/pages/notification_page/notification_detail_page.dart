import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/notification_model.dart';
import '../../services/notification_service.dart' as ServiceNotif;
import '../job_details_page/job_details_page_widget.dart';
import '../message_client/message_client_widget.dart';
import '../profile/special_request_details_widget.dart';
import '../../services/special_service_request_service.dart';
import '../../utils/navigation_utils.dart';
import '../../utils/app_notification.dart';

class NotificationDetailPage extends StatefulWidget {
  final NotificationItem notification;

  const NotificationDetailPage({
    Key? key,
    required this.notification,
  }) : super(key: key);

  static const String routeName = 'notificationDetail';
  static const String routePath = '/notificationDetail';

  @override
  State<NotificationDetailPage> createState() => _NotificationDetailPageState();
}

class _NotificationDetailPageState extends State<NotificationDetailPage> {
  bool _isLoading = false;

  /// Navigate to the relevant detail page based on notification type
  Future<void> _navigateToDetail() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      final notification = widget.notification;

      // Handle special requests
      if (notification.type == 'special_request' &&
          notification.requestId != null &&
          notification.requestId!.isNotEmpty) {
        final request = await SpecialServiceRequestService.fetchById(
            notification.requestId!);
        if (request != null && mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SpecialRequestDetailsWidget(request: request),
            ),
          );
          return;
        }
      }

      // Handle jobs
      if (notification.jobId != null) {
        final job = await ServiceNotif.NotificationService.fetchJobById(
            notification.jobId.toString());
        if (job != null && mounted) {
          try {
            await NavigationUtils.safePushRoute(
                context, JobDetailsPageWidget.routePath,
                extra: {'job': job});
            return;
          } catch (_) {}
        }
      }

      // Handle bookings/messages
      if (notification.bookingId != null || notification.threadId != null) {
        try {
          await NavigationUtils.safePush(
              context,
              MessageClientWidget(
                bookingId: notification.bookingId,
                threadId: notification.threadId,
                jobTitle: notification.title,
                bookingPrice: _displayAmount(notification.bookingPrice),
                bookingDateTime: notification.createdAt.toIso8601String(),
              ));
          return;
        } catch (_) {}
      }

      // Handle URLs
      if (notification.url != null && notification.url!.isNotEmpty) {
        await launchURL(notification.url!);
        return;
      }

      // Default: show info
      AppNotification.showInfo(
          context,
          notification.message.isNotEmpty
              ? notification.message
              : 'No additional details available');
    } catch (e) {
      if (mounted) {
        AppNotification.showError(
            context, 'Failed to navigate: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _displayAmount(dynamic value) {
    try {
      if (value == null) return '-';
      if (value is num) {
        return '₦${NumberFormat('#,##0', 'en_US').format(value)}';
      }

      final text = value.toString().trim();
      if (text.isEmpty) return '-';

      final normalized = text.replaceAll(RegExp(r'[^0-9.-]'), '');
      final parsed = num.tryParse(normalized);
      if (parsed != null) {
        return '₦${NumberFormat('#,##0', 'en_US').format(parsed)}';
      }

      if (text.contains('?') || text.contains('�')) {
        return text.replaceAll('?', '₦').replaceAll('�', '₦');
      }

      return text;
    } catch (_) {
      return value.toString();
    }
  }

  String _normalizeCurrencyText(String text) {
    if (text.isEmpty) return text;
    return text.replaceAllMapped(
      RegExp(r'([?�])(?=\s*\d)'),
      (_) => '₦',
    );
  }

  String _getDetailMessage(NotificationItem notification) {
    switch (notification.type) {
      case 'special_request':
        return 'View the special service request details and accept or reject it.';
      case 'booking':
        return 'View booking details and communicate with the client.';
      case 'payment':
        return 'Payment details and transaction history.';
      case 'message':
        return 'Continue your conversation with the customer.';
      case 'review':
        return 'View the review left by your customer.';
      case 'order':
        return 'View order details and status.';
      case 'commission':
        return 'View your earned commission details.';
      case 'sales':
        return 'View sales information and statistics.';
      case 'workshop':
        return 'Workshop event details and information.';
      case 'favorite':
        return 'You have been added to a customer\'s favorites.';
      default:
        return notification.message;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final notification = widget.notification;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Notification Details'),
        actions: [
          IconButton(
            icon: Icon(
              Icons.check_rounded,
              color: colorScheme.primary,
            ),
            onPressed: () {},
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon and Type
                    Center(
                      child: Column(
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: _getNotificationColor(notification.type)
                                  .withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _getNotificationIcon(notification.type),
                              size: 40,
                              color: _getNotificationColor(notification.type),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _getNotificationColor(notification.type)
                                  .withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _getNotificationColor(notification.type)
                                    .withOpacity(0.3),
                              ),
                            ),
                            child: Text(
                              notification.type
                                  .replaceAll('_', ' ')
                                  .toUpperCase(),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: _getNotificationColor(notification.type),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Title
                    Text(
                      notification.title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Timestamp
                    Row(
                      children: [
                        Icon(
                          Icons.access_time_rounded,
                          size: 16,
                          color: colorScheme.onSurface.withOpacity(0.5),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatDateTime(notification.createdAt),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Message/Content
                    if (notification.message.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Message',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: colorScheme.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: colorScheme.onSurface.withOpacity(0.1),
                              ),
                            ),
                            child: Text(
                              _normalizeCurrencyText(notification.message),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurface.withOpacity(0.8),
                                height: 1.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),

                    // Details Section
                    if (_hasDetailsToShow(notification))
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Details',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildDetailsSection(
                              notification, colorScheme, theme),
                          const SizedBox(height: 24),
                        ],
                      ),

                    // Info Message
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: colorScheme.primary.withOpacity(0.2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.info_rounded,
                                size: 20,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'About This Notification',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _getDetailMessage(notification),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurface.withOpacity(0.7),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build details section based on notification type
  Widget _buildDetailsSection(
      NotificationItem notification, ColorScheme colorScheme, ThemeData theme) {
    final details = <MapEntry<String, String>>[];

    if (notification.requestId != null) {
      details.add(MapEntry('Request ID', notification.requestId!));
    }
    if (notification.jobId != null) {
      details.add(MapEntry('Job ID', notification.jobId!));
    }
    if (notification.bookingId != null) {
      details.add(MapEntry('Booking ID', notification.bookingId!));
    }
    if (notification.amount != null) {
      details.add(MapEntry('Amount', _displayAmount(notification.amount)));
    }
    if (notification.bookingPrice != null) {
      details.add(MapEntry('Price', _displayAmount(notification.bookingPrice)));
    }

    return Column(
      children: details.asMap().entries.map((entry) {
        final isLast = entry.key == details.length - 1;
        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  entry.value.key,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                Text(
                  entry.value.value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            if (!isLast) ...[
              const SizedBox(height: 12),
              Divider(
                color: colorScheme.onSurface.withOpacity(0.08),
                height: 1,
              ),
              const SizedBox(height: 12),
            ],
          ],
        );
      }).toList(),
    );
  }

  bool _hasDetailsToShow(NotificationItem notification) {
    return notification.requestId != null ||
        notification.jobId != null ||
        notification.bookingId != null ||
        notification.amount != null ||
        notification.bookingPrice != null;
  }

  String _getActionButtonText(String type) {
    switch (type) {
      case 'special_request':
        return 'View Request';
      case 'booking':
        return 'View Booking';
      case 'message':
        return 'Open Chat';
      case 'review':
        return 'View Review';
      case 'order':
        return 'View Order';
      case 'payment':
        return 'View Payment';
      default:
        return 'Open';
    }
  }

  IconData _getNotificationIcon(String type) {
    switch (type) {
      case 'special_request':
        return Icons.handyman_rounded;
      case 'commission':
        return Icons.palette_rounded;
      case 'review':
        return Icons.star_rounded;
      case 'order':
        return Icons.shopping_bag_rounded;
      case 'message':
        return Icons.message_rounded;
      case 'workshop':
        return Icons.event_rounded;
      case 'favorite':
        return Icons.favorite_rounded;
      case 'sales':
        return Icons.trending_up_rounded;
      case 'booking':
        return Icons.book_online_rounded;
      case 'payment':
        return Icons.payment_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _getNotificationColor(String type) {
    final colorScheme = Theme.of(context).colorScheme;
    switch (type) {
      case 'special_request':
      case 'commission':
      case 'message':
      case 'sales':
        return colorScheme.primary;
      case 'review':
        return Colors.amber;
      case 'order':
      case 'payment':
        return Colors.green;
      case 'booking':
        return Colors.purple;
      case 'favorite':
        return Colors.pink;
      default:
        return colorScheme.onSurface.withAlpha((0.6 * 255).round());
    }
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final notificationDate = DateTime(dt.year, dt.month, dt.day);

    String dayString;
    if (notificationDate == today) {
      dayString = 'Today';
    } else if (notificationDate == yesterday) {
      dayString = 'Yesterday';
    } else {
      dayString = '${dt.day}/${dt.month}/${dt.year}';
    }

    final timeString =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    return '$dayString at $timeString';
  }
}
