import 'package:flutter/material.dart';
import 'dart:async';
import '../../services/special_service_request_service.dart';
import '../../services/notification_service.dart';
import '../../services/token_storage.dart';
import '../../services/user_service.dart';
import '../../services/location_service.dart';
import '../../utils/app_notification.dart';
import '../../utils/realtime_notifications.dart';
import 'package:rijhub/pages/profile/special_request_details_widget.dart';
import '/flutter_flow/flutter_flow_theme.dart';

class ProfileSpecialRequestsWidget extends StatefulWidget {
  const ProfileSpecialRequestsWidget({super.key, bool? isClient})
      : isClient = isClient ?? true;
  final bool isClient;

  static String routeName = 'ProfileSpecialRequests';
  static String routePath = '/profile/special-requests';

  @override
  State<ProfileSpecialRequestsWidget> createState() =>
      _ProfileSpecialRequestsWidgetState();
}

class _ProfileSpecialRequestsWidgetState
    extends State<ProfileSpecialRequestsWidget> {
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];
  String _searchQuery = '';
  final List<String> _selectedStatuses = [];
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _loadingMore = false;
  int _currentPage = 1;
  final int _pageSize = 10;
  bool _isClient = true; // Default to client, will be updated in initState
  Timer? _autoRefreshTimer;
  StreamSubscription<Map<String, dynamic>>? _notificationSubscription;
  bool _isRefreshingSilently = false;
  final Map<String, Map<String, dynamic>> _userProfileCache = {};
  final Map<String, String> _locationCache = {};
  // Constants
  static const Color _defaultPrimaryColor = Color(0xFFA20025);

  Color get primaryColor =>
      FlutterFlowTheme.of(context).primary ?? _defaultPrimaryColor;

  List<Map<String, dynamic>> get filteredItems {
    return _items.where((item) {
      final status = item['status']?.toString().toLowerCase() ?? '';
      final matchesSearch = _matchesSearch(item);
      final matchesFilter =
          _selectedStatuses.isEmpty || _selectedStatuses.contains(status);
      return matchesSearch && matchesFilter;
    }).toList();
  }

  bool get _hasActiveFilters =>
      _searchQuery.trim().isNotEmpty || _selectedStatuses.isNotEmpty;

  bool _matchesSearch(Map<String, dynamic> item) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return true;

    final searchFields = <String>[
      item['title']?.toString() ?? '',
      item['categoryName']?.toString() ?? '',
      item['description']?.toString() ?? '',
      item['location']?.toString() ?? '',
      item['urgency']?.toString() ?? '',
      item['status']?.toString() ?? '',
      item['_id']?.toString() ?? '',
      item['id']?.toString() ?? '',
      item['client']?['name']?.toString() ?? '',
      item['artisan']?['name']?.toString() ?? '',
    ];

    return searchFields.any((field) => field.toLowerCase().contains(query));
  }

  void _clearSearchAndFilters() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _selectedStatuses.clear();
    });
  }

  Future<void> _notifyCancellation(Map<String, dynamic> request) async {
    try {
      final toUserId = _isClient
          ? (request['artisanId']?.toString() ??
              request['artisan']?['id']?.toString())
          : (request['clientId']?.toString() ??
              request['client']?['id']?.toString());
      final requestId =
          request['_id']?.toString() ?? request['id']?.toString() ?? '';
      if (toUserId == null || toUserId.isEmpty || requestId.isEmpty) return;
      final actorName = await TokenStorage.getUserName();
      await NotificationService.sendSpecialRequestNotification(
        toUserId: toUserId,
        requestId: requestId,
        eventType: 'cancelled',
        requestTitle: request['title']?.toString(),
        actorName: actorName,
      );
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _initializeUserRole();
  }

  Future<void> _initializeUserRole() async {
    try {
      final role = await TokenStorage.getRole();
      setState(() {
        _isClient = role?.toLowerCase() != 'artisan';
      });
    } catch (_) {
      // Default to client if role can't be determined
      setState(() => _isClient = true);
    }
    await _load();
    _bindRealtimeNotifications();
    _startAutoRefresh();
  }

  void _bindRealtimeNotifications() {
    _notificationSubscription?.cancel();
    RealtimeNotifications.instance.init();
    _notificationSubscription =
        RealtimeNotifications.instance.events.listen((event) async {
      if (event['event']?.toString() != 'notification') return;
      final type =
          event['type']?.toString() ?? event['payload']?['type']?.toString();
      if (type != 'special_request') return;
      await _reloadListSilently();
    });
  }

  /// Start automatic refresh of request list (live updates)
  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (!mounted) {
        _autoRefreshTimer?.cancel();
        return;
      }
      final route = ModalRoute.of(context);
      if (route?.isCurrent == false) {
        return;
      }
      // Reload list silently (without loading spinner)
      await _reloadListSilently();
    });
  }

  /// Reload list in background without showing loader
  Future<void> _reloadListSilently() async {
    if (_isRefreshingSilently || _loadingMore) return;
    _isRefreshingSilently = true;
    try {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route?.isCurrent == false) return;
      final id = await TokenStorage.getUserId();
      if (id == null || id.isEmpty) return;

      final res = _isClient
          ? await SpecialServiceRequestService.fetchForClient(id,
              page: 1, pageSize: _pageSize)
          : await SpecialServiceRequestService.fetchForArtisan(id,
              page: 1, pageSize: _pageSize);

      if (res.isNotEmpty && mounted) {
        await _prepareItems(res);

        // Only update if data changed
        if (!_listsEqual(_items, res)) {
          setState(() {
            _items = res;
            _currentPage = 1;
          });
        }
      }
    } catch (e) {
      // Silently ignore errors in background refresh.
    } finally {
      _isRefreshingSilently = false;
    }
  }

  /// Check if two lists are equal (for change detection)
  bool _listsEqual(
      List<Map<String, dynamic>> list1, List<Map<String, dynamic>> list2) {
    if (list1.length != list2.length) return false;
    for (int i = 0; i < list1.length; i++) {
      if (list1[i]['_id'] != list2[i]['_id'] ||
          list1[i]['status'] != list2[i]['status']) {
        return false;
      }
    }
    return true;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _autoRefreshTimer?.cancel();
    _notificationSubscription?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels ==
            _scrollController.position.maxScrollExtent &&
        !_loadingMore) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    _currentPage++;
    final id = await TokenStorage.getUserId();
    if (id == null || id.isEmpty) {
      setState(() => _loadingMore = false);
      return;
    }
    try {
      final res = _isClient
          ? await SpecialServiceRequestService.fetchForClient(id,
              page: _currentPage, pageSize: _pageSize)
          : await SpecialServiceRequestService.fetchForArtisan(id,
              page: _currentPage, pageSize: _pageSize);
      if (res.isNotEmpty) {
        await _prepareItems(res);
        setState(() {
          _items.addAll(res);
          _loadingMore = false;
        });
      } else {
        // No more data
        setState(() => _loadingMore = false);
      }
    } catch (e) {
      setState(() => _loadingMore = false);
      AppNotification.showError(context, 'Failed to load more requests');
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _currentPage = 1; // Reset to first page
    final id = await TokenStorage.getUserId();
    if (id == null || id.isEmpty) {
      AppNotification.showError(context, 'Not signed in');
      setState(() => _loading = false);
      return;
    }
    try {
      final res = _isClient
          ? await SpecialServiceRequestService.fetchForClient(id,
              page: _currentPage, pageSize: _pageSize)
          : await SpecialServiceRequestService.fetchForArtisan(id,
              page: _currentPage, pageSize: _pageSize);
      await _prepareItems(res);
      setState(() {
        _items = res;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      AppNotification.showError(context, 'Failed to load requests');
    }
  }

  Future<void> _prepareItems(List<Map<String, dynamic>> items) async {
    await Future.wait([
      _populateUserProfiles(items),
      _convertLocationsToHumanReadable(items),
    ]);
  }

  Future<void> _populateUserProfiles(List<Map<String, dynamic>> items) async {
    final Set<String> userIds = {};
    for (final item in items) {
      final clientId =
          item['clientId']?.toString() ?? item['client']?['id']?.toString();
      final artisanId =
          item['artisanId']?.toString() ?? item['artisan']?['id']?.toString();
      if (clientId != null) userIds.add(clientId);
      if (artisanId != null) userIds.add(artisanId);
    }

    final uncachedIds = userIds
        .where((userId) => !_userProfileCache.containsKey(userId))
        .toList();
    await Future.wait(
      uncachedIds.map((userId) async {
        try {
          final profile = await UserService.getUserById(userId);
          if (profile != null) {
            _userProfileCache[userId] = profile;
          }
        } catch (_) {
          // Ignore errors for individual profiles
        }
      }),
    );

    // Helper to extract URL from profile image (which may be {url, public_id, _id} or just a string)
    String? _extractImageUrl(dynamic imageData) {
      if (imageData == null) return null;
      if (imageData is String) return imageData;
      if (imageData is Map) return imageData['url']?.toString();
      return null;
    }

    for (final item in items) {
      final clientId =
          item['clientId']?.toString() ?? item['client']?['id']?.toString();
      final artisanId =
          item['artisanId']?.toString() ?? item['artisan']?['id']?.toString();

      if (clientId != null && _userProfileCache.containsKey(clientId)) {
        final profile = _userProfileCache[clientId]!;
        item['client'] = {
          'id': clientId,
          'name': profile['name']?.toString() ??
              profile['firstName']?.toString() ??
              'Client',
          'profileImage': _extractImageUrl(profile['profileImage']),
        };
      } else if (item['client'] == null) {
        item['client'] = {'name': 'Client', 'profileImage': null};
      }

      if (artisanId != null && _userProfileCache.containsKey(artisanId)) {
        final profile = _userProfileCache[artisanId]!;
        item['artisan'] = {
          'id': artisanId,
          'name': profile['name']?.toString() ??
              profile['firstName']?.toString() ??
              'Artisan',
          'profileImage': _extractImageUrl(profile['profileImage']),
        };
      } else if (item['artisan'] == null) {
        item['artisan'] = {'name': 'Artisan', 'profileImage': null};
      }
    }
  }

  Future<void> _convertLocationsToHumanReadable(
      List<Map<String, dynamic>> items) async {
    final locationsToResolve = <String>{};
    for (final item in items) {
      final locationStr = item['location']?.toString();
      if (locationStr != null &&
          locationStr.isNotEmpty &&
          !_locationCache.containsKey(locationStr)) {
        locationsToResolve.add(locationStr);
      }
    }

    await Future.wait(
      locationsToResolve.map((locationStr) async {
        try {
          final humanReadable =
              await LocationService.getHumanReadableLocation(locationStr);
          _locationCache[locationStr] = humanReadable;
        } catch (_) {
          _locationCache[locationStr] = locationStr;
        }
      }),
    );

    for (final item in items) {
      final locationStr = item['location']?.toString();
      if (locationStr != null && locationStr.isNotEmpty) {
        item['location'] = _locationCache[locationStr] ?? locationStr;
      }
    }
  }

  Color _statusColor(String s) {
    final st = s.toLowerCase();
    if (st == 'pending') {
      return Colors.amber[700] ?? Colors.amber;
    } else if (st == 'responded') {
      return Colors.blue;
    } else if (st == 'accepted') {
      return Colors.orange;
    } else if (st == 'confirmed') {
      return Colors.green;
    } else if (['in_progress', 'ongoing'].contains(st)) {
      return Colors.indigo;
    } else if (st == 'completed') {
      return Colors.teal;
    } else if (['rejected', 'declined'].contains(st)) {
      return Colors.red;
    } else if (st == 'cancelled') {
      return Colors.grey;
    } else {
      return primaryColor;
    }
  }

  String _statusText(String s) {
    final st = s.toLowerCase();
    switch (st) {
      case 'pending':
        return 'Pending';
      case 'responded':
        return 'Responded';
      case 'accepted':
        return 'Accepted';
      case 'confirmed':
        return 'Confirmed';
      case 'in_progress':
        return 'In Progress';
      case 'ongoing':
        return 'Ongoing';
      case 'completed':
        return 'Completed';
      case 'rejected':
        return 'Rejected';
      case 'declined':
        return 'Declined';
      case 'cancelled':
        return 'Cancelled';
      default:
        return st.replaceAll('_', ' ');
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'Unknown date';
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays == 0) {
        return 'Today';
      } else if (difference.inDays == 1) {
        return 'Yesterday';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} days ago';
      } else if (difference.inDays < 30) {
        final weeks = (difference.inDays / 7).floor();
        return '$weeks week${weeks > 1 ? 's' : ''} ago';
      } else {
        return '${date.day}/${date.month}/${date.year}';
      }
    } catch (_) {
      return dateStr;
    }
  }

  IconData _getStatusIcon(String status) {
    final st = status.toLowerCase();
    switch (st) {
      case 'pending':
        return Icons.pending_outlined;
      case 'responded':
        return Icons.mark_email_read_outlined;
      case 'accepted':
        return Icons.payments_outlined;
      case 'confirmed':
        return Icons.verified_outlined;
      case 'in_progress':
      case 'ongoing':
        return Icons.handyman_outlined;
      case 'completed':
        return Icons.done_all_outlined;
      case 'rejected':
        return Icons.cancel_outlined;
      case 'declined':
        return Icons.do_not_disturb_on_outlined;
      case 'cancelled':
        return Icons.remove_circle_outline;
      default:
        return Icons.info_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 375;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final horizontalPadding = isSmallScreen ? 16.0 : 20.0;
    final bodyFontSize = isSmallScreen ? 14.0 : 15.0;
    final smallFontSize = isSmallScreen ? 12.0 : 13.0;

    Color _borderColor() => Theme.of(context).dividerColor;
    final chipBackgroundColor =
        isDark ? const Color(0xFF1F2937) : Colors.grey.shade100;
    final chipBorderColor =
        isDark ? const Color(0xFF374151) : Colors.grey.shade300;
    final chipLabelColor = isDark ? Colors.grey.shade300 : Colors.grey.shade700;
    final selectedChipBackground = isDark
        ? primaryColor.withValues(alpha: 0.24)
        : primaryColor.withValues(alpha: 0.12);
    final selectedChipBorder = isDark
        ? primaryColor.withValues(alpha: 0.52)
        : primaryColor.withValues(alpha: 0.28);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: _borderColor(), width: 1),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_rounded,
                        color: Theme.of(context).colorScheme.onSurface,
                        size: 24),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _isClient ? 'My Requests' : 'Assigned Jobs',
                      style: theme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: isSmallScreen ? 20 : 22,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                color: primaryColor,
                child: Column(
                  children: [
                    // Search bar - Always visible
                    Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: horizontalPadding, vertical: 8),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (value) =>
                            setState(() => _searchQuery = value.trim()),
                        decoration: InputDecoration(
                          hintText: 'Search requests...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded),
                                  onPressed: () {
                                    setState(() {
                                      _searchController.clear();
                                      _searchQuery = '';
                                    });
                                  },
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: _borderColor()),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: _borderColor()),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: primaryColor),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                    // Filter chips - Always visible
                    Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: horizontalPadding),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            'all',
                            'pending',
                            'responded',
                            'confirmed',
                            'accepted',
                            'in_progress',
                            'completed',
                            'rejected',
                            'declined',
                            'cancelled'
                          ].map((status) {
                            final isSelected = status == 'all'
                                ? _selectedStatuses.isEmpty
                                : _selectedStatuses.contains(status);
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(status == 'all'
                                    ? 'All'
                                    : _statusText(status)),
                                selected: isSelected,
                                onSelected: (selected) {
                                  setState(() {
                                    if (status == 'all') {
                                      _selectedStatuses.clear();
                                    } else if (selected) {
                                      _selectedStatuses.remove('all');
                                      _selectedStatuses.add(status);
                                    } else {
                                      _selectedStatuses.remove(status);
                                    }
                                  });
                                },
                                backgroundColor: isSelected
                                    ? selectedChipBackground
                                    : chipBackgroundColor,
                                selectedColor: selectedChipBackground,
                                side: BorderSide(
                                  color: isSelected
                                      ? selectedChipBorder
                                      : chipBorderColor,
                                  width: 1,
                                ),
                                showCheckmark: false,
                                checkmarkColor: primaryColor,
                                labelStyle: TextStyle(
                                  color: isSelected
                                      ? primaryColor
                                      : chipLabelColor,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // List area - Shows skeleton during loading
                    Expanded(
                      child: _loading
                          ? _buildSkeletonLoaders(
                              context, isDark, horizontalPadding)
                          : _items.isEmpty
                              ? _buildEmptyState(
                                  context, theme, primaryColor, bodyFontSize)
                              : filteredItems.isEmpty
                                  ? _buildFilteredEmptyState(
                                      context,
                                      theme,
                                      primaryColor,
                                      bodyFontSize,
                                    )
                                  : ListView.builder(
                                      controller: _scrollController,
                                      physics: const BouncingScrollPhysics(),
                                      padding: EdgeInsets.symmetric(
                                          horizontal: horizontalPadding,
                                          vertical: 8),
                                      itemCount: filteredItems.length +
                                          (_loadingMore ? 1 : 0),
                                      itemBuilder: (context, index) {
                                        if (index == filteredItems.length) {
                                          return const Center(
                                            child: Padding(
                                              padding: EdgeInsets.all(16),
                                              child:
                                                  CircularProgressIndicator(),
                                            ),
                                          );
                                        }
                                        final item = filteredItems[index];
                                        return _buildRequestCard(
                                          context: context,
                                          item: item,
                                          theme: theme,
                                          primaryColor: primaryColor,
                                          isDark: isDark,
                                          bodyFontSize: bodyFontSize,
                                          smallFontSize: smallFontSize,
                                          isClient: _isClient,
                                          onTap: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    SpecialRequestDetailsWidget(
                                                        request: item),
                                              ),
                                            );
                                          },
                                          onCancel: () async {
                                            final confirmed =
                                                await showDialog<bool>(
                                              context: context,
                                              builder: (c) => AlertDialog(
                                                title: const Text(
                                                    'Cancel Request'),
                                                content: const Text(
                                                    'Are you sure you want to cancel this request?'),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.of(c)
                                                            .pop(false),
                                                    child: const Text('No'),
                                                  ),
                                                  ElevatedButton(
                                                    onPressed: () =>
                                                        Navigator.of(c)
                                                            .pop(true),
                                                    style: ElevatedButton
                                                        .styleFrom(
                                                      backgroundColor:
                                                          primaryColor,
                                                    ),
                                                    child: const Text('Yes'),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (confirmed == true) {
                                              final id =
                                                  item['_id']?.toString() ??
                                                      item['id']?.toString() ??
                                                      '';
                                              if (id.isEmpty) {
                                                AppNotification.showError(
                                                    context,
                                                    'Invalid request id');
                                                return;
                                              }
                                              try {
                                                final updated =
                                                    await SpecialServiceRequestService
                                                        .updateStatus(
                                                            id, 'cancelled');
                                                if (updated != null) {
                                                  await _notifyCancellation(
                                                      updated);
                                                  AppNotification.showSuccess(
                                                      context,
                                                      'Request cancelled');
                                                  await _load();
                                                } else {
                                                  AppNotification.showError(
                                                      context,
                                                      'Failed to cancel');
                                                }
                                              } catch (e) {
                                                AppNotification.showError(
                                                    context,
                                                    'Error cancelling request');
                                              }
                                            }
                                          },
                                        );
                                      },
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

  Widget _buildSkeletonLoaders(
      BuildContext context, bool isDark, double horizontalPadding) {
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding:
          EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 16),
      itemCount: 6, // Show 6 skeleton cards
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row with avatar and text
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Profile avatar skeleton
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[700] : Colors.grey[300],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Name skeleton
                          Container(
                            width: 80,
                            height: 12,
                            decoration: BoxDecoration(
                              color:
                                  isDark ? Colors.grey[700] : Colors.grey[300],
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Title skeleton
                          Container(
                            width: double.infinity,
                            height: 16,
                            decoration: BoxDecoration(
                              color:
                                  isDark ? Colors.grey[700] : Colors.grey[300],
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Status chip skeleton
                    Container(
                      width: 70,
                      height: 24,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[700] : Colors.grey[300],
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // Description skeleton
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      height: 14,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[700] : Colors.grey[300],
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 200,
                      height: 14,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[700] : Colors.grey[300],
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Info chips skeleton
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Container(
                      width: 80,
                      height: 20,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[700] : Colors.grey[300],
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 80,
                      height: 20,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[700] : Colors.grey[300],
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 100,
                      height: 20,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[700] : Colors.grey[300],
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Divider
              Container(
                height: 1,
                color: isDark ? Colors.grey[700] : Colors.grey[300],
              ),
              const SizedBox(height: 12),
              // Tap hint skeleton
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  width: 120,
                  height: 12,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[700] : Colors.grey[300],
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context, var theme, Color primaryColor,
      double bodyFontSize) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.request_page_outlined,
              size: 48,
              color: primaryColor.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No Requests Yet',
            style: TextStyle(
              fontSize: bodyFontSize + 2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isClient
                ? 'You haven\'t made any special service requests.'
                : 'No jobs assigned yet.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: bodyFontSize,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 24),
          if (_isClient) ...[
            ElevatedButton.icon(
              onPressed: () {
                // Navigate to discovery page
                Navigator.of(context).pushNamed('/discovery');
              },
              icon: Icon(Icons.search_rounded, size: 20),
              label: Text('Find Artisan'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilteredEmptyState(BuildContext context, var theme,
      Color primaryColor, double bodyFontSize) {
    final selectedLabels = _selectedStatuses.map(_statusText).join(', ');
    final hasSearch = _searchQuery.trim().isNotEmpty;
    final hasStatusFilter = _selectedStatuses.isNotEmpty;

    String subtitle;
    if (hasSearch && hasStatusFilter) {
      subtitle =
          'No requests found for "${_searchQuery.trim()}" in $selectedLabels.';
    } else if (hasSearch) {
      subtitle =
          'No requests found for "${_searchQuery.trim()}". Try a different keyword.';
    } else {
      subtitle =
          'No requests match the selected status filter. Try another tab.';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.search_off_rounded,
                size: 42,
                color: primaryColor.withOpacity(0.55),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No matching requests',
              style: TextStyle(
                fontSize: bodyFontSize + 2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: bodyFontSize,
                color: Colors.grey[600],
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _clearSearchAndFilters,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label:
                  Text(_hasActiveFilters ? 'Clear search & filters' : 'Reset'),
              style: OutlinedButton.styleFrom(
                foregroundColor: primaryColor,
                side: BorderSide(color: primaryColor.withOpacity(0.4)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestCard({
    required BuildContext context,
    required Map<String, dynamic> item,
    required var theme,
    required Color primaryColor,
    required bool isDark,
    required double bodyFontSize,
    required double smallFontSize,
    required bool isClient,
    required VoidCallback onTap,
    required VoidCallback onCancel,
  }) {
    final title = item['title']?.toString() ??
        item['categoryName']?.toString() ??
        'Service Request';
    final status = item['status']?.toString() ?? 'pending';
    final description = item['description']?.toString();
    final createdAt =
        item['createdAt']?.toString() ?? item['created_at']?.toString();
    final urgency = item['urgency']?.toString() ?? 'Normal';
    final location = item['location']?.toString();
    final statusColor = _statusColor(status);
    final statusText = _statusText(status);
    final statusIcon = _getStatusIcon(status);
    final dateText = _formatDate(createdAt);
    final canCancel = status.toLowerCase() != 'cancelled' &&
        status.toLowerCase() != 'completed' &&
        status.toLowerCase() != 'rejected';

    // Extract profile data
    final clientImageUrl = item['client']?['profileImage']?.toString();
    final artisanImageUrl = item['artisan']?['profileImage']?.toString();
    final clientName = item['client']?['name']?.toString() ?? 'Client';
    final artisanName = item['artisan']?['name']?.toString() ?? 'Artisan';

    // Determine which profile to show based on isClient
    final profileImageUrl = isClient ? artisanImageUrl : clientImageUrl;
    final personName = isClient ? artisanName : clientName;
    final profileIcon = isClient ? Icons.build : Icons.person;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row with title and status
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Profile image
                    CircleAvatar(
                      radius: 22,
                      backgroundImage: profileImageUrl != null
                          ? NetworkImage(profileImageUrl)
                          : null,
                      backgroundColor: statusColor.withOpacity(0.12),
                      child: profileImageUrl == null
                          ? Icon(profileIcon, color: statusColor, size: 22)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            personName,
                            style: theme.bodySmall?.copyWith(
                              color: Colors.grey,
                              fontSize: smallFontSize - 1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            title,
                            style: theme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: bodyFontSize + 1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Status chip on the right
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: statusColor.withOpacity(0.3),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            statusIcon,
                            size: 12,
                            color: statusColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            statusText,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: smallFontSize - 1,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Description (if available)
                if (description != null && description.isNotEmpty) ...[
                  Text(
                    description,
                    style: theme.bodyMedium?.copyWith(
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                      fontSize: bodyFontSize - 1,
                      height: 1.4,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                ],

                // Info row - date, urgency, location
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    _buildInfoChip(
                      icon: Icons.access_time_rounded,
                      label: dateText,
                      color:
                          isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                      smallFontSize: smallFontSize,
                    ),
                    _buildInfoChip(
                      icon: urgency.toLowerCase() == 'urgent'
                          ? Icons.warning_amber_rounded
                          : Icons.speed_rounded,
                      label: urgency,
                      color: urgency.toLowerCase() == 'urgent'
                          ? Colors.orange
                          : (isDark
                              ? Colors.grey.shade500
                              : Colors.grey.shade600),
                      smallFontSize: smallFontSize,
                    ),
                    if (location != null && location.isNotEmpty)
                      _buildInfoChip(
                        icon: Icons.location_on_rounded,
                        label: location,
                        color: isDark
                            ? Colors.grey.shade500
                            : Colors.grey.shade600,
                        smallFontSize: smallFontSize,
                      ),
                  ],
                ),

                const SizedBox(height: 12),

                // Divider and action hint
                Divider(
                  height: 20,
                  color: isDark ? Colors.grey[800] : Colors.grey[200],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'Tap to view details →',
                      style: TextStyle(
                        fontSize: smallFontSize - 1,
                        color: primaryColor.withOpacity(0.7),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required Color color,
    required double smallFontSize,
  }) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 278),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: smallFontSize - 1,
                color: color,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
