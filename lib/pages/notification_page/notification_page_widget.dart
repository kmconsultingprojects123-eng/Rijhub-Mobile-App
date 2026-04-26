import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'notification_page_model.dart';
import 'notification_detail_page.dart';
import '../../models/notification_model.dart';
import '../../services/notification_service.dart' as ServiceNotif;
import '../../state/app_state_notifier.dart';
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
  List<NotificationItem> _notifications = [];
  int _page = 1;
  final int _perPage = 20;
  bool _hasMore = true;
  bool _loadingMore = false;
  final ScrollController _scrollController = ScrollController();
  String _selectedFilter = 'all';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  bool _hasLoadError = false;

  Future<void> _loadNotifications() async {
    setState(() {
      _loadingNotifications = true;
      _hasLoadError = false;
      _page = 1;
    });
    try {
      final resp = await ServiceNotif.NotificationService.fetchNotifications(
          page: 1, perPage: 50);

      final notificationResponse = NotificationResponse.fromJson(resp, 1, 50);

      if (!mounted) return;
      setState(() {
        _notifications = notificationResponse.notifications;
        _loadingNotifications = false;
        _hasLoadError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _notifications = [];
        _loadingNotifications = false;
        _hasLoadError = true;
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
        if (_scrollController.position.pixels >=
                _scrollController.position.maxScrollExtent - 200 &&
            !_loadingMore &&
            _hasMore &&
            !_loadingNotifications) {
          _loadMoreNotifications();
        }
      });
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _loadMoreNotifications() async {
    if (!_hasMore || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final nextPage = _page + 1;
      final resp = await ServiceNotif.NotificationService.fetchNotifications(
          page: nextPage, perPage: _perPage);

      final notificationResponse =
          NotificationResponse.fromJson(resp, nextPage, _perPage);

      if (!mounted) return;
      setState(() {
        _notifications.addAll(notificationResponse.notifications);
        _page = nextPage;
        _hasMore = notificationResponse.hasMore;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  /// Get filtered and searched notifications
  List<NotificationItem> _getFilteredNotifications() {
    List<NotificationItem> filtered = _notifications;

    // Apply filter
    if (_selectedFilter != 'all') {
      filtered = filtered.where((n) => n.type == _selectedFilter).toList();
    }

    // Apply search
    if (_searchQuery.isNotEmpty) {
      filtered = filtered
          .where((n) =>
              n.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              n.message.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }

    return filtered;
  }

  /// Get available filter types from current notifications
  List<String> _getAvailableFilters() {
    final types = <String>{};
    for (final notification in _notifications) {
      types.add(notification.type);
    }
    return ['all', ...types.toList()..sort()];
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

  Color _getNotificationColor(String type, BuildContext context) {
    final theme = Theme.of(context);
    switch (type) {
      case 'special_request':
        return theme.colorScheme.primary;
      case 'commission':
        return theme.colorScheme.primary;
      case 'review':
        return Colors.amber;
      case 'order':
        return Colors.green;
      case 'message':
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

  String _normalizeCurrencyText(String text) {
    if (text.isEmpty) return text;
    return text.replaceAllMapped(
      RegExp(r'([?�])(?=\s*\d)'),
      (_) => '₦',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final filteredNotifications = _getFilteredNotifications();

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
                      fontWeight: FontWeight.w600,
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
                        final success = await ServiceNotif.NotificationService
                            .markAllRead();
                        if (success) {
                          AppStateNotifier.instance.setUnreadNotifications(0);
                          AppNotification.showSuccess(
                              context, 'All notifications marked as read');
                          setState(() {
                            _notifications = _notifications
                                .map((n) => n.copyWith(isRead: true))
                                .toList();
                          });
                        }
                      } catch (_) {}
                    },
                  ),
                ],
              ),
            ),

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: TextField(
                controller: _searchController,
                onChanged: (value) {
                  setState(() => _searchQuery = value);
                },
                decoration: InputDecoration(
                  hintText: 'Search notifications...',
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.5),
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: colorScheme.onSurface.withOpacity(0.5),
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.close_rounded,
                            color: colorScheme.onSurface.withOpacity(0.5),
                          ),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: colorScheme.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: colorScheme.onSurface.withOpacity(0.1),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: colorScheme.onSurface.withOpacity(0.1),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: colorScheme.primary,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),

            // Filter Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: _getAvailableFilters().map((filter) {
                  final isSelected = _selectedFilter == filter;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(
                        filter == 'all' ? 'All' : filter.replaceAll('_', ' '),
                      ),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() => _selectedFilter = filter);
                      },
                      backgroundColor: colorScheme.surface,
                      selectedColor: colorScheme.primary.withOpacity(0.2),
                      side: BorderSide(
                        color: isSelected
                            ? colorScheme.primary
                            : colorScheme.onSurface.withOpacity(0.2),
                      ),
                      labelStyle: theme.textTheme.labelSmall?.copyWith(
                        color: isSelected
                            ? colorScheme.primary
                            : colorScheme.onSurface.withOpacity(0.7),
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),

            // Notifications List
            Expanded(
              child: _loadingNotifications && _notifications.isEmpty
                  ? ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                      itemCount: 6,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: _buildSkeletonCard(),
                        );
                      },
                    )
                  : _hasLoadError
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24.0,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.error_outline_rounded,
                                  size: 64,
                                  color: colorScheme.error.withOpacity(0.5),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Failed to load notifications',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Please check your connection and try again',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color:
                                        colorScheme.onSurface.withOpacity(0.6),
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
                                  child: const Text(
                                    'Retry',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : filteredNotifications.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24.0,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.notifications_none_rounded,
                                      size: 64,
                                      color: colorScheme.onSurface
                                          .withOpacity(0.3),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      _searchQuery.isNotEmpty
                                          ? 'No matching notifications'
                                          : 'No notifications',
                                      style:
                                          theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _searchQuery.isNotEmpty
                                          ? 'Try a different search term'
                                          : 'Your notifications will appear here',
                                      textAlign: TextAlign.center,
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        color: colorScheme.onSurface
                                            .withOpacity(0.6),
                                      ),
                                    ),
                                    if (_searchQuery.isNotEmpty) ...[
                                      const SizedBox(height: 24),
                                      ElevatedButton(
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() => _searchQuery = '');
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: colorScheme.primary,
                                          foregroundColor:
                                              colorScheme.onPrimary,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 32,
                                            vertical: 12,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                        ),
                                        child: const Text(
                                          'Clear Search',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _loadNotifications,
                              color: colorScheme.primary,
                              child: ListView.builder(
                                controller: _scrollController,
                                padding:
                                    const EdgeInsets.fromLTRB(20, 8, 20, 20),
                                itemCount: filteredNotifications.length +
                                    (_hasMore ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index >= filteredNotifications.length) {
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
                                  final notification =
                                      filteredNotifications[index];
                                  return Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 12.0),
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

  Widget _buildNotificationCard(NotificationItem notification) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final icon = _getNotificationIcon(notification.type);
    final iconColor = _getNotificationColor(notification.type, context);

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => NotificationDetailPage(
              notification: notification,
            ),
          ),
        );
      },
      onLongPress: () {
        // Show swipe-to-delete option via context menu
        showModalBottomSheet(
          context: context,
          builder: (context) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(Icons.check_rounded, color: Colors.green),
                  title: Text('Mark as Read'),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      final index = _notifications.indexOf(notification);
                      if (index != -1) {
                        _notifications[index] =
                            notification.copyWith(isRead: true);
                      }
                    });
                  },
                ),
                ListTile(
                  leading:
                      Icon(Icons.delete_outline_rounded, color: Colors.red),
                  title: Text('Delete'),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _notifications
                          .removeWhere((n) => n.id == notification.id);
                    });
                    AppNotification.showSuccess(
                      context,
                      'Notification deleted',
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: notification.isRead
              ? colorScheme.surface
              : colorScheme.primary.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: notification.isRead
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
                            notification.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: notification.isRead
                                  ? colorScheme.onSurface.withOpacity(0.9)
                                  : colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _dateTimeAgo(notification.createdAt),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _normalizeCurrencyText(notification.message),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.7),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!notification.isRead) ...[
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

  String _dateTimeAgo(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
