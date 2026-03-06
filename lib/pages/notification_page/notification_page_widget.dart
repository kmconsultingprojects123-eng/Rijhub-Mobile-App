import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'notification_page_model.dart';
import '../../services/notification_service.dart' as ServiceNotif;
import '../../state/app_state_notifier.dart';
import '../job_details_page/job_details_page_widget.dart';
import '../message_client/message_client_widget.dart';
import '../../utils/navigation_utils.dart';
import '../../utils/app_notification.dart';
export 'notification_page_model.dart';

/// Create a page a notification page for the artisan app
class NotificationPageWidget extends StatefulWidget {
  const NotificationPageWidget({super.key});

  static String routeName = 'notificationPage';
  static String routePath = '/notificationPage';

  @override
  State<NotificationPageWidget> createState() => _NotificationPageWidgetState();
}

class _NotificationPageWidgetState extends State<NotificationPageWidget> {
  late NotificationPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();
  bool _loadingNotifications = true;
  List<dynamic> _notifications = [];
  int _page = 1;
  final int _perPage = 20;
  bool _hasMore = true;
  bool _loadingMore = false;
  final ScrollController _scrollController = ScrollController();

  Future<void> _loadNotifications() async {
    setState(() => _loadingNotifications = true);
    try {
      final resp = await ServiceNotif.NotificationService.fetchNotifications(page: 1, perPage: 50);
      List<dynamic> items = [];
      if (resp == null) {
        items = [];
      } else if (resp is Map) {
        if (resp.containsKey('data') && resp['data'] is List) items = resp['data'];
        else if (resp.containsKey('notifications') && resp['notifications'] is List) items = resp['notifications'];
        else if (resp.containsKey('items') && resp['items'] is List) items = resp['items'];
        else {
          final listVal = resp.values.firstWhere((v) => v is List, orElse: () => null);
          if (listVal is List) items = listVal;
        }
      } else if (resp is List) {
        items = resp;
      }

      if (!mounted) return;
      setState(() {
        _notifications = items;
        _loadingNotifications = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _notifications = [];
        _loadingNotifications = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => NotificationPageModel());

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final success = await ServiceNotif.NotificationService.markAllRead();
        if (success) {
          AppStateNotifier.instance.setUnreadNotifications(0);
        }
      } catch (_) {}

      _loadNotifications();
      _scrollController.addListener(() {
        if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 && !_loadingMore && _hasMore && !_loadingNotifications) {
          _loadMoreNotifications();
        }
      });
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _loadMoreNotifications() async {
    if (!_hasMore || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final nextPage = _page + 1;
      final resp = await ServiceNotif.NotificationService.fetchNotifications(page: nextPage, perPage: _perPage);
      List<dynamic> items = [];
      if (resp == null) items = [];
      else if (resp is Map) {
        if (resp.containsKey('data') && resp['data'] is List) items = resp['data'];
        else if (resp.containsKey('notifications') && resp['notifications'] is List) items = resp['notifications'];
        else if (resp.containsKey('items') && resp['items'] is List) items = resp['items'];
        else {
          final listVal = resp.values.firstWhere((v) => v is List, orElse: () => null);
          if (listVal is List) items = listVal;
        }
      } else if (resp is List) items = resp;

      if (!mounted) return;
      setState(() {
        _notifications.addAll(items);
        _page = nextPage;
        _hasMore = items.length >= _perPage;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _handleNotificationTap(dynamic n) async {
    try {
      final jobId = n['jobId'] ?? n['job'] ?? n['data']?['jobId'];
      final bookingId = n['bookingId'] ?? n['data']?['bookingId'];
      // Extract possible thread/chat id from the notification payload
      String? threadId = n['threadId'] ?? n['data']?['threadId'];
      try {
        threadId ??= n['data']?['thread']?.toString();
      } catch (_) {}
      try {
        threadId ??= n['data']?['chat']?['_id']?.toString() ?? n['data']?['chat']?['id']?.toString();
      } catch (_) {}
      final url = n['url'] ?? n['link'] ?? n['data']?['url'];

      if (jobId != null) {
        final job = await ServiceNotif.NotificationService.fetchJobById(jobId.toString());
        if (job != null) {
          try {
            await NavigationUtils.safePush(context, JobDetailsPageWidget(job: job));
            return;
          } catch (_) {
            try {
              await NavigationUtils.safePush(context, JobDetailsPageWidget(job: job));
              return;
            } catch (_) {}
          }
        }
      }

      if (bookingId != null || threadId != null) {
        final bId = bookingId?.toString() ?? n['data']?['booking']?.toString();
        try {
          await NavigationUtils.safePush(context, MessageClientWidget(
            bookingId: bId,
            threadId: threadId?.toString(),
            jobTitle: n['title']?.toString(),
            bookingPrice: n['amount']?.toString(),
            bookingDateTime: n['createdAt']?.toString(),
          ));
          return;
        } catch (_) {}
      }

      if (url != null && url.toString().isNotEmpty) {
        await launchURL(url.toString());
        return;
      }

      AppNotification.showInfo(context, n['message']?.toString() ?? 'Opened notification');
    } catch (e) {}
  }

  String dateTimeAgo(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  IconData _getNotificationIcon(String type) {
    switch (type) {
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

  Color _getNotificationColor(String type, BuildContext context) {
    final theme = Theme.of(context);
    switch (type) {
      case 'commission':
        return theme.colorScheme.primary;
      case 'review':
        return Colors.amber;
      case 'order':
        return Colors.green;
      case 'message':
        // Use app primary instead of default blue
        return theme.colorScheme.primary;
      case 'booking':
        return Colors.purple;
      case 'favorite':
        return Colors.pink;
      case 'sales':
        return theme.colorScheme.primary;
      case 'payment':
        return Colors.green;
      default:
        return theme.colorScheme.onSurface.withAlpha((0.6 * 255).round());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      key: scaffoldKey,
      backgroundColor: isDark ? Colors.black : Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: colorScheme.onSurface.withOpacity(0.1),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.chevron_left_rounded,
                      color: colorScheme.onSurface.withOpacity(0.8),
                      size: 28,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Text(
                    'Notifications',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                      fontSize: 18,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.check_rounded,
                      color: colorScheme.primary,
                      size: 24,
                    ),
                    onPressed: () async {
                      try {
                        final success = await ServiceNotif.NotificationService.markAllRead();
                        if (success) {
                          AppStateNotifier.instance.setUnreadNotifications(0);
                          AppNotification.showSuccess(context, 'All notifications marked as read');
                        }
                      } catch (_) {}
                    },
                  ),
                ],
              ),
            ),

            // Notifications List
            Expanded(
              child: _loadingNotifications && _notifications.isEmpty
                  ? ListView.builder(
                // Add top padding so first card sits below the header
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                itemCount: 6,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: _buildSkeletonCard(),
                  );
                },
              )
                  : _notifications.isEmpty
                  ? Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.notifications_none_rounded,
                        size: 64,
                        color: colorScheme.onSurface.withOpacity(0.3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No notifications',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your notifications will appear here',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _loadNotifications,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Refresh',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
                  : RefreshIndicator(
                onRefresh: _loadNotifications,
                color: colorScheme.primary,
                child: ListView.builder(
                  controller: _scrollController,
                  // Add top padding so first card sits below the header
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                  itemCount: _notifications.length + (_hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= _notifications.length) {
                      return _loadingMore
                          ? Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: colorScheme.primary,
                          ),
                        ),
                      )
                          : const SizedBox();
                    }
                    final notification = _notifications[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: _buildNotificationCard(notification),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonCard() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.onSurface.withOpacity(0.1),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorScheme.onSurface.withOpacity(0.08),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 14,
                  width: 120,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurface.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 12,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurface.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 12,
                  width: 160,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurface.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 10,
                  width: 80,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurface.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationCard(dynamic notification) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final title = notification['title'] ?? 'Notification';
    final message = notification['message'] ?? '';
    final type = notification['type'] ?? 'default';
    final createdAt = notification['createdAt'] != null
        ? DateTime.tryParse(notification['createdAt']) ?? DateTime.now()
        : DateTime.now();
    final isRead = notification['read'] ?? false;

    final icon = _getNotificationIcon(type);
    final iconColor = _getNotificationColor(type, context);

    return InkWell(
      onTap: () => _handleNotificationTap(notification),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: isRead ? colorScheme.surface : colorScheme.primary.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isRead
                ? colorScheme.onSurface.withOpacity(0.1)
                : colorScheme.primary.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: iconColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isRead
                                  ? colorScheme.onSurface.withOpacity(0.9)
                                  : colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          dateTimeAgo(createdAt),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      message,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.7),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!isRead) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

