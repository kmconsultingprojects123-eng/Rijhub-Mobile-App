import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../../services/job_service.dart';
import '../../services/artist_service.dart';
import '../../services/user_service.dart';
import '../../utils/navigation_utils.dart';
import '../../utils/error_messages.dart';
import '/main.dart';

class ArtisanJobsHistoryWidget extends StatefulWidget {
  const ArtisanJobsHistoryWidget({super.key});
  static String routeName = 'ArtisanJobsHistory';
  static String routePath = '/artisanJobsHistory';

  @override
  State<ArtisanJobsHistoryWidget> createState() => _ArtisanJobsHistoryWidgetState();
}

class _ArtisanJobsHistoryWidgetState extends State<ArtisanJobsHistoryWidget> {
  // Design system colors
  final Color _primaryColor = const Color(0xFFA20025);
  final Color _surfaceColorLight = const Color(0xFFF9FAFB);
  final Color _surfaceColorDark = const Color(0xFF1F2937);
  final Color _textPrimaryLight = const Color(0xFF111827);
  final Color _textPrimaryDark = Colors.white;
  final Color _textSecondaryLight = const Color(0xFF6B7280);
  final Color _textSecondaryDark = const Color(0xFF9CA3AF);
  final Color _borderColorLight = const Color(0xFFE5E7EB);
  final Color _borderColorDark = const Color(0xFF374151);
  final Color _successColor = const Color(0xFF10B981);
  final Color _warningColor = const Color(0xFFF59E0B);
  final Color _errorColor = const Color(0xFFEF4444);

  // State variables
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _jobs = [];
  TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadJobs();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _loadJobs(query: _searchController.text.trim());
    });
  }

  Future<void> _loadJobs({String? query}) async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Fetch profile to determine role
      final profile = await UserService.getProfile();
      List<Map<String, dynamic>> jobList = [];

      if (profile != null &&
          profile['role'] != null &&
          profile['role'].toString().toLowerCase().contains('artisan')) {

        final artisanId = (profile['_id'] ?? profile['id'] ?? profile['userId'])?.toString();
        if (artisanId != null && artisanId.isNotEmpty) {
          final bookings = await ArtistService.fetchArtisanBookings(artisanId, page: 1, limit: 100);
          jobList = List<Map<String, dynamic>>.from(bookings);
        }
      } else {
        final jobs = await JobService.getMyJobs();
        try {
          jobList = List<Map<String, dynamic>>.from(jobs);
        } catch (_) {
          jobList = <Map<String, dynamic>>[];
        }
      }

      // Filter completed jobs
      final completedJobs = jobList.where((job) {
        final Map<String, dynamic> jobMap = Map<String, dynamic>.from(job);
        final booking = jobMap['booking'] is Map
            ? Map<String, dynamic>.from(jobMap['booking'])
            : jobMap;

        final status = (booking['status'] ?? jobMap['status'] ?? '')
            .toString()
            .toLowerCase();
        final paymentStatus = (booking['paymentStatus'] ??
            (booking['payment'] is Map ? booking['payment']['status'] : null) ?? '')
            .toString()
            .toLowerCase();

        return status == 'closed' ||
            status == 'completed' ||
            status == 'done' ||
            paymentStatus == 'paid';
      }).toList();

      // Apply search filter
      final filteredJobs = query != null && query.isNotEmpty
          ? completedJobs.where((job) {
        final Map<String, dynamic> jobMap = Map<String, dynamic>.from(job);
        final booking = jobMap['booking'] is Map
            ? Map<String, dynamic>.from(jobMap['booking'])
            : jobMap;

        final title = (booking['service'] ??
            booking['title'] ??
            booking['jobTitle'] ?? '')
            .toString()
            .toLowerCase();
        final description = (booking['description'] ??
            booking['details'] ?? '')
            .toString()
            .toLowerCase();

        return title.contains(query.toLowerCase()) ||
            description.contains(query.toLowerCase());
      }).toList()
          : completedJobs;

      if (mounted) {
        setState(() {
          _jobs = filteredJobs;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = ErrorMessages.humanize(e);
           _loading = false;
         });
       }
     }
  }

  Color _getSurfaceColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? _surfaceColorDark
        : _surfaceColorLight;
  }

  Color _getTextPrimary(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? _textPrimaryDark
        : _textPrimaryLight;
  }

  Color _getTextSecondary(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? _textSecondaryDark
        : _textSecondaryLight;
  }

  Color _getBorderColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? _borderColorDark
        : _borderColorLight;
  }

  Widget _buildJobCard(BuildContext context, Map<String, dynamic> job) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = _getTextPrimary(context);
    final textSecondary = _getTextSecondary(context);
    final borderColor = _getBorderColor(context);
    final surfaceColor = _getSurfaceColor(context);

    // Extract job data
    final booking = (job['booking'] is Map)
        ? Map<String, dynamic>.from(job['booking'])
        : Map<String, dynamic>.from(job);

    final title = (booking['service'] ??
        booking['title'] ??
        booking['jobTitle'] ??
        job['title'] ?? 'Untitled Job')
        .toString();

    final description = (booking['description'] ??
        booking['details'] ??
        job['description'] ?? '')
        .toString();

    // Format date
    String formattedDate = '';
    try {
      final rawDate = (booking['createdAt'] ??
          booking['created_at'] ??
          booking['created'] ??
          job['createdAt'] ??
          job['created'])?.toString() ?? '';
      final date = DateTime.tryParse(rawDate);
      if (date != null) {
        formattedDate = DateFormat('MMM dd, yyyy').format(date.toLocal());
      }
    } catch (_) {}

    // Extract price
    String priceText = '';
    final priceData = (booking['price'] ??
        booking['budget'] ??
        job['budget'] ??
        job['price']);
    if (priceData != null) {
      try {
        final numVal = (priceData is num)
            ? priceData
            : num.tryParse(priceData.toString().replaceAll(RegExp(r'[^0-9.-]'), ''));
        if (numVal != null) {
          priceText = '₦${NumberFormat('#,##0', 'en_US').format(numVal)}';
        }
      } catch (_) {}
    }

    // Extract customer info
    String customerName = '';
    String? customerAvatarUrl;
    try {
      final customer = booking['customerId'] ??
          booking['customerUser'] ??
          job['customerUser'] ??
          job['customer'];

      if (customer is Map) {
        customerName = (customer['name'] ??
            customer['fullName'] ??
            customer['username'] ?? '')
            .toString();

        final avatarData = customer['profileImage'];
        if (avatarData is Map) {
          customerAvatarUrl = (avatarData['url'] ?? '').toString();
        } else if (avatarData is String) {
          customerAvatarUrl = avatarData;
        }
      } else if (customer != null) {
        customerName = customer.toString();
      }
    } catch (_) {}

    // Extract trades
    List<String> trades = [];
    try {
      final tradeData = booking['trade'] ??
          job['trade'] ??
          booking['trades'] ??
          job['trades'];
      if (tradeData is List) {
        trades = tradeData
            .map((e) => e?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
      }
    } catch (_) {}

    // Determine status and color
    final statusRaw = (booking['status'] ?? job['status'] ?? '')
        .toString()
        .toLowerCase();

    Color statusColor = textSecondary;
    String statusText = 'Unknown';

    if (statusRaw.contains('closed') ||
        statusRaw.contains('completed') ||
        statusRaw.contains('done') ||
        (booking['paymentStatus'] ?? '').toString().toLowerCase().contains('paid')) {
      statusColor = _successColor;
      statusText = 'Completed';
    } else if (statusRaw.contains('pending') || statusRaw.contains('accepted')) {
      statusColor = _warningColor;
      statusText = 'Pending';
    } else {
      statusColor = textSecondary;
      statusText = statusRaw.isNotEmpty
          ? statusRaw[0].toUpperCase() + statusRaw.substring(1)
          : 'Unknown';
    }

    // Generate avatar
    Widget buildAvatar() {
      if (customerAvatarUrl != null && customerAvatarUrl!.isNotEmpty) {
        return Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor.withOpacity(0.3)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              customerAvatarUrl!,
              width: 44,
              height: 44,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  decoration: BoxDecoration(
                    color: _primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.person_outline_rounded,
                    size: 20,
                    color: _primaryColor,
                  ),
                );
              },
            ),
          ),
        );
      }

      if (customerName.isNotEmpty) {
        final parts = customerName.split(' ');
        final initials = parts
            .where((part) => part.isNotEmpty)
            .take(2)
            .map((part) => part[0])
            .join()
            .toUpperCase();

        return Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              initials,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _primaryColor,
              ),
            ),
          ),
        );
      }

      return Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Icon(
          Icons.person_outline_rounded,
          size: 20,
          color: textSecondary,
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? surfaceColor.withOpacity(0.7) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor.withOpacity(0.3),
          width: 1,
        ),
        boxShadow: isDark
            ? []
            : [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar
                buildAvatar(),
                const SizedBox(width: 12),

                // Title and info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: textPrimary,
                                letterSpacing: -0.3,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (priceText.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              priceText,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: _primaryColor,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              customerName.isNotEmpty ? customerName : 'Customer',
                              style: TextStyle(
                                fontSize: 14,
                                color: textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              statusText,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Trades and date row
            Row(
              children: [
                if (trades.isNotEmpty) ...[
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: trades.take(2).map((trade) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: surfaceColor,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: borderColor.withOpacity(0.5),
                            ),
                          ),
                          child: Text(
                            trade,
                            style: TextStyle(
                              fontSize: 12,
                              color: textSecondary,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (formattedDate.isNotEmpty)
                  Text(
                    formattedDate,
                    style: TextStyle(
                      fontSize: 12,
                      color: textSecondary,
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 12),

            // Description
            if (description.isNotEmpty)
              Text(
                description,
                style: TextStyle(
                  fontSize: 14,
                  color: textSecondary,
                  height: 1.5,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final placeholder = colorScheme.onSurface.withOpacity(0.06);
    final placeholderAlt = colorScheme.onSurface.withOpacity(0.08);
    final border = colorScheme.onSurface.withOpacity(0.08);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: border,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: placeholder,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 180,
                      height: 16,
                      decoration: BoxDecoration(
                        color: placeholderAlt,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 120,
                      height: 14,
                      decoration: BoxDecoration(
                        color: placeholder,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 60,
                height: 36,
                decoration: BoxDecoration(
                  color: placeholder,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: 150,
            height: 14,
            decoration: BoxDecoration(
              color: placeholderAlt,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = _getTextPrimary(context);
    final textSecondary = _getTextSecondary(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.work_outline_rounded,
              size: 56,
              color: textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              'No Completed Jobs',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your completed jobs will appear here',
              style: TextStyle(
                fontSize: 14,
                color: textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? Colors.black : Colors.white;
    final textPrimary = _getTextPrimary(context);
    final textSecondary = _getTextSecondary(context);
    final borderColor = _getBorderColor(context);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_rounded,
            color: textPrimary,
          ),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              try {
                NavigationUtils.safePushReplacement(
                  context,
                  const NavBarPage(initialPage: 'JobPostPage'),
                );
              } catch (_) {
                Navigator.of(context).maybePop();
              }
            }
          },
        ),
        title: Text(
          'Completed Jobs',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w400,
            color: textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              // Search bar
              Container(
                decoration: BoxDecoration(
                  color: isDark ? _surfaceColorDark : _surfaceColorLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: borderColor.withOpacity(0.5),
                    width: 1,
                  ),
                ),
                child: TextFormField(
                  controller: _searchController,
                  style: TextStyle(
                    fontSize: 15,
                    color: textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search completed jobs...',
                    hintStyle: TextStyle(
                      color: textSecondary,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: textSecondary,
                      size: 20,
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                      icon: Icon(
                        Icons.clear_rounded,
                        size: 18,
                        color: textSecondary,
                      ),
                      onPressed: () {
                        _searchController.clear();
                        _loadJobs();
                      },
                    )
                        : null,
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Content
              Expanded(
                child: _loading
                    ? ListView.builder(
                  itemCount: 3,
                  itemBuilder: (context, index) => _buildSkeletonCard(context),
                )
                    : _error != null
                    ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 48,
                          color: _errorColor,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Failed to load jobs',
                          style: TextStyle(
                            fontSize: 16,
                            color: textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          style: TextStyle(
                            fontSize: 14,
                            color: textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadJobs,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Try Again'),
                        ),
                      ],
                    ),
                  ),
                )
                    : _jobs.isEmpty
                    ? _buildEmptyState(context)
                    : ListView.builder(
                  itemCount: _jobs.length,
                  itemBuilder: (context, index) => _buildJobCard(context, _jobs[index]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

