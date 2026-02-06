import '/flutter_flow/flutter_flow_util.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/job_service.dart';
import '../create_job_page1/create_job_page1_widget.dart';
import '../edit_job_page/edit_job_page_widget.dart';
import '../job_details_page/job_details_page_widget.dart';
import '../message_client/message_client_widget.dart';
import '../../utils/navigation_utils.dart';
import '../../services/user_service.dart';
import '../../utils/app_notification.dart';
import '../../utils/error_messages.dart';

class JobHistoryPageWidget extends StatefulWidget {
  const JobHistoryPageWidget({super.key});
  static String routeName = 'JobHistoryPage';
  static String routePath = '/jobHistoryPage';

  @override
  State<JobHistoryPageWidget> createState() => _JobHistoryPageWidgetState();
}

class _JobHistoryPageWidgetState extends State<JobHistoryPageWidget> {
  // State variables
  bool _loading = true;
  bool _roleLoaded = false;
  bool _isArtisan = false;
  List<Map<String, dynamic>> _jobs = [];
  String? _error;
  bool _sheetSubmitting = false;
  String _selectedTab = 'Posted';
  final List<String> _tabs = ['Posted', 'Completed'];
  TextEditingController? _searchController;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _loadUserRole();
    _loadJobs();

    _searchController!.addListener(() {
      if (_debounce?.isActive ?? false) _debounce!.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), () {
        _loadJobs(query: _searchController!.text.trim());
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController?.dispose();
    super.dispose();
  }

  Future<void> _loadUserRole() async {
    try {
      await AppStateNotifier.instance.refreshAuth();
      if (!AppStateNotifier.instance.loggedIn) {
        if (mounted) setState(() => _roleLoaded = true);
        return;
      }

      final profile = await UserService.getProfile();
      final role = (profile?['role'] ?? profile?['type'] ?? '').toString().toLowerCase();
      if (mounted) {
        setState(() {
          _isArtisan = role.contains('artisan');
          _roleLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _roleLoaded = true);
    }
  }

  Future<void> _loadJobs({String? query}) async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final jobs = await JobService.getMyJobs();
      List<Map<String, dynamic>> jobList = [];

      try {
        jobList = List<Map<String, dynamic>>.from(jobs);
      } catch (_) {
        // Handle conversion error
      }

      // Filter by search query
      if (query != null && query.isNotEmpty) {
        jobList = jobList.where((job) {
          final title = (job['title'] ?? job['jobTitle'] ?? '').toString().toLowerCase();
          final description = (job['description'] ?? job['details'] ?? '').toString().toLowerCase();
          return title.contains(query.toLowerCase()) || description.contains(query.toLowerCase());
        }).toList();
      }

      if (mounted) {
        setState(() {
          _jobs = jobList;
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

  Future<void> _deleteJob(String id) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Delete Job',
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Are you sure you want to delete this job? This action cannot be undone.',
          style: TextStyle(
            color: colorScheme.onSurface.withAlpha((0.7 * 255).toInt()),
          ),
        ),
        backgroundColor: colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        elevation: isDark ? 0 : 2,
        shadowColor: isDark ? Colors.transparent : Colors.black.withAlpha((0.1 * 255).toInt()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: colorScheme.onSurface.withAlpha((0.7 * 255).toInt()),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              backgroundColor: colorScheme.errorContainer,
              foregroundColor: colorScheme.onErrorContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Delete',
              style: TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final success = await JobService.deleteJob(id);
        if (success) {
          AppNotification.showSuccess(context, 'Job deleted successfully');
          _loadJobs(query: _searchController!.text.trim());
        }
      } catch (e) {
        AppNotification.showError(context, 'Failed to delete job');
      }
    }
  }

  void _showEditDialog(Map<String, dynamic> job) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // Create a normalized copy of the job to ensure EditJobForm gets the fields it expects.
    final Map<String, dynamic> prefilledJob = Map<String, dynamic>.from(job);

    // Title/company/description
    prefilledJob['title'] = (job['title'] ?? job['jobTitle'] ?? job['name'] ?? '').toString();
    prefilledJob['company'] = (job['company'] ?? job['employer'] ?? '').toString();
    prefilledJob['description'] = (job['description'] ?? job['details'] ?? job['desc'] ?? '').toString();

    // Location/address
    prefilledJob['location'] = (job['location'] ?? job['address'] ?? job['venue'] ?? '').toString();

    // Budget: prefer budget, fall back to price/amount; keep numeric or string form
    prefilledJob['budget'] = job['budget'] ?? job['price'] ?? job['amount'] ?? job['salary'] ?? '';

    // Trade/skills: ensure a List when possible
    try {
      if (job['trade'] is List) {
        prefilledJob['trade'] = List.from(job['trade']);
      } else if (job['skills'] is List) {
        prefilledJob['trade'] = List.from(job['skills']);
      } else if (job['skills'] is String && (job['skills'] as String).trim().isNotEmpty) {
        prefilledJob['trade'] = (job['skills'] as String).split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      } else if (job['trade'] is String && (job['trade'] as String).trim().isNotEmpty) {
        prefilledJob['trade'] = (job['trade'] as String).split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      }
    } catch (_) {}

    // Coordinates: unify to [lon, lat] if possible
    try {
      if (job['coordinates'] is List && (job['coordinates'] as List).length >= 2) {
        prefilledJob['coordinates'] = List<double>.from((job['coordinates'] as List).map((e) => (e is num) ? e.toDouble() : double.tryParse(e.toString()) ?? 0.0));
      } else if (job['coords'] is Map) {
        final c = job['coords'];
        final lat = (c['lat'] ?? c['latitude'])?.toString();
        final lon = (c['lon'] ?? c['longitude'])?.toString();
        if (lat != null && lon != null) {
          final latN = double.tryParse(lat);
          final lonN = double.tryParse(lon);
          if (latN != null && lonN != null) prefilledJob['coordinates'] = [lonN, latN];
        }
      } else if (job['location'] is Map) {
        final loc = job['location'];
        final lat = (loc['lat'] ?? loc['latitude'])?.toString();
        final lon = (loc['lon'] ?? loc['longitude'])?.toString();
        if (lat != null && lon != null) {
          final latN = double.tryParse(lat);
          final lonN = double.tryParse(lon);
          if (latN != null && lonN != null) prefilledJob['coordinates'] = [lonN, latN];
        }
      }
    } catch (_) {}

    // Schedule/deadline
    prefilledJob['schedule'] = job['schedule'] ?? job['deadline'] ?? job['dueDate'] ?? job['date'];

    // Category id normalization
    try {
      if (job['category'] is Map) {
        prefilledJob['categoryId'] = (job['category']['_id'] ?? job['category']['id'] ?? job['category']['categoryId'])?.toString();
      } else {
        prefilledJob['categoryId'] = (job['categoryId'] ?? job['category'] ?? job['category_id'])?.toString();
      }
    } catch (_) {}

    // Experience/type
    prefilledJob['type'] = job['type'] ?? job['experience'] ?? job['experienceLevel'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAliasWithSaveLayer,
      builder: (context) {
        final formKey = GlobalKey<EditJobFormState>();

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.88,
          minChildSize: 0.4,
          maxChildSize: 0.98,
          snap: true,
          snapSizes: const [0.4, 0.88],
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Top handle
                  Container(
                    margin: const EdgeInsets.only(top: 8, bottom: 4),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.outline.withAlpha((0.4 * 255).toInt()),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Edit Job',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Update job details',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurface.withAlpha((0.7 * 255).toInt()),
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isDark
                                  ? colorScheme.surfaceContainerHighest.withAlpha((0.5 * 255).toInt())
                                  : colorScheme.surfaceContainerHighest.withAlpha((0.3 * 255).toInt()),
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              size: 20,
                              color: colorScheme.onSurface.withAlpha((0.8 * 255).toInt()),
                            ),
                          ),
                          splashRadius: 20,
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),

                  // Divider
                  Container(
                    height: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          colorScheme.outline.withAlpha(isDark ? (0.6 * 255).toInt() : (0.4 * 255).toInt()),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Content
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      physics: const ClampingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      child: EditJobForm(
                        key: formKey,
                        // Pass the normalized job so the form fields are prefilled consistently
                        job: prefilledJob,
                        embedded: true,
                        onUpdated: () {
                          // Close the sheet and refresh jobs
                          try {
                            Navigator.pop(context);
                          } catch (_) {}
                          _loadJobs(query: _searchController!.text.trim());
                        },
                      ),
                    ),
                  ),

                  // Bottom action bar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? colorScheme.surface.withAlpha((0.95 * 255).toInt())
                          : colorScheme.surface.withAlpha((0.98 * 255).toInt()),
                      border: Border(
                        top: BorderSide(
                          color: colorScheme.outline.withAlpha(isDark ? (0.15 * 255).toInt() : (0.1 * 255).toInt()),
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              side: BorderSide(
                                color: colorScheme.outline.withAlpha(isDark ? (0.15 * 255).toInt() : (0.1 * 255).toInt()),
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                color: colorScheme.onSurface.withAlpha((0.7 * 255).toInt()),
                                fontWeight: FontWeight.w500,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _sheetSubmitting
                                ? null
                                : () async {
                              try {
                                setState(() => _sheetSubmitting = true);
                                await formKey.currentState?.submit();
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ErrorMessages.humanize(e))));
                              } finally {
                                if (mounted) setState(() => _sheetSubmitting = false);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: const StadiumBorder(),
                              backgroundColor: colorScheme.primary,
                              foregroundColor: colorScheme.onPrimary,
                              elevation: 0,
                            ),
                            child: _sheetSubmitting
                                ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(colorScheme.onPrimary),
                              ),
                            )
                                : Text('Save Changes', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Bottom safe area
                  SizedBox(height: MediaQuery.of(context).padding.bottom),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildJobCard(Map<String, dynamic> job) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 360;

    // Adaptive colors
    final primaryColor = cs.primary;
    final surface = cs.surface;
    final textPrimary = cs.onSurface;
    final textSecondary = cs.onSurface.withAlpha((0.7 * 255).toInt());
    final borderColor = cs.outline.withAlpha(isDark ? (0.15 * 255).toInt() : (0.1 * 255).toInt());
    final successColor = Color.lerp(cs.secondary, Colors.green, 0.5) ?? Colors.green;
    final warningColor = cs.primaryContainer;

    // Extract job data
    final title = (job['title'] ?? job['jobTitle'] ?? 'Untitled Job').toString();
    final description = (job['description'] ?? job['details'] ?? '').toString();

    // Parse date
    final rawDate = (job['createdAt'] ?? job['created_at'] ?? job['created'])?.toString() ?? '';
    DateTime? date = DateTime.tryParse(rawDate);
    final formattedDate = date != null
        ? DateFormat('MMM dd, yyyy').format(date.toLocal())
        : rawDate;

    // Parse budget
    final budget = job['budget'];
    String budgetText = '';
    if (budget != null) {
      final numVal = (budget is num) ? budget : num.tryParse(budget.toString().replaceAll(RegExp(r'[^0-9.-]'), ''));
      if (numVal != null) {
        budgetText = '₦${NumberFormat('#,##0', 'en_US').format(numVal)}';
      }
    }

    // Parse status
    final rawStatus = (job['status'] ?? '').toString();
    final statusLower = rawStatus.toLowerCase().trim();
    final isCompleted = statusLower == 'closed' || statusLower == 'done';
    final statusText = rawStatus.isEmpty ? 'Unknown' : rawStatus[0].toUpperCase() + rawStatus.substring(1).toLowerCase();
    Color statusColor = textSecondary;

    if (statusLower == 'open' || statusLower == 'active') {
      statusColor = successColor;
    } else if (statusLower == 'pending') {
      statusColor = warningColor;
    } else if (statusLower == 'closed' || statusLower == 'done') {
      statusColor = primaryColor;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Padding(
        padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row with responsive layout
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: isSmallScreen ? 16 : 17,
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        formattedDate,
                        style: TextStyle(
                          fontSize: isSmallScreen ? 12 : 13,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isSmallScreen ? 8 : 12,
                    vertical: isSmallScreen ? 4 : 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha((isDark ? 0.2 : 0.1 * 255).toInt()),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: statusColor.withAlpha((0.3 * 255).toInt()),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: isSmallScreen ? 11 : 12,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Budget
            if (budgetText.isNotEmpty) ...[
              Row(
                children: [
                  Text(
                    'Budget: ',
                    style: TextStyle(
                      fontSize: isSmallScreen ? 13 : 14,
                      color: textSecondary,
                    ),
                  ),
                  Text(
                    budgetText,
                    style: TextStyle(
                      fontSize: isSmallScreen ? 15 : 16,
                      fontWeight: FontWeight.w700,
                      color: primaryColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],

            // Description with responsive sizing
            Text(
              description,
              style: TextStyle(
                fontSize: isSmallScreen ? 13 : 14,
                color: textSecondary,
                height: 1.5,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),

            const SizedBox(height: 24),

            // Action buttons - responsive layout
            LayoutBuilder(
              builder: (context, constraints) {
                final availableWidth = constraints.maxWidth;
                final useCompactLayout = availableWidth < 380;

                return Column(
                  children: [
                    if (useCompactLayout)
                    // Compact layout for small screens
                      Column(
                        children: [
                          if (!isCompleted)
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => _showEditDialog(job),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      side: BorderSide(color: primaryColor, width: 1.5),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.edit_outlined, size: 16, color: primaryColor),
                                        const SizedBox(width: 6),
                                        Text('Edit', style: TextStyle(fontSize: 13, color: primaryColor)),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () {
                                      final id = job['_id'] ?? job['id'] ?? job['jobId'] ?? '';
                                      if (id.toString().isNotEmpty) {
                                        _deleteJob(id.toString());
                                      }
                                    },
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      side: BorderSide(color: primaryColor, width: 1.5),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.delete_outline, size: 16, color: primaryColor),
                                        const SizedBox(width: 6),
                                        Text('Delete', style: TextStyle(fontSize: 13, color: primaryColor)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () {
                                    try {
                                      Navigator.of(context).push(MaterialPageRoute(
                                        builder: (_) => JobDetailsPageWidget(job: job),
                                      ));
                                    } catch (_) {}
                                  },
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    side: BorderSide(color: borderColor, width: 1.5),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.visibility_outlined, size: 16, color: textPrimary.withAlpha((0.8 * 255).toInt())),
                                      const SizedBox(width: 6),
                                      Text('Details', style: TextStyle(fontSize: 13, color: textPrimary.withAlpha((0.8 * 255).toInt()))),
                                    ],
                                  ),
                                ),
                              ),
                              if (job['booking'] != null) ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () {
                                      try {
                                        String? threadId;
                                        try { threadId = job['booking']?['threadId']?.toString(); } catch (_) {}
                                        try { threadId ??= job['booking']?['chat']?['_id']?.toString(); } catch (_) {}
                                        try { threadId ??= job['booking']?['chat']?['id']?.toString(); } catch (_) {}
                                        try { threadId ??= job['booking']?['thread']?['_id']?.toString(); } catch (_) {}
                                        NavigationUtils.safePush(
                                          context,
                                          MessageClientWidget(
                                            bookingId: job['booking']?['_id']?.toString() ?? job['bookingId']?.toString(),
                                            threadId: threadId?.toString(),
                                            jobTitle: job['title']?.toString(),
                                            bookingPrice: job['price']?.toString(),
                                            bookingDateTime: job['createdAt']?.toString(),
                                          ),
                                        );
                                      } catch (_) {}
                                    },
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      side: BorderSide(color: successColor, width: 1.5),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.chat_outlined, size: 16, color: successColor),
                                        const SizedBox(width: 6),
                                        Text('Chat', style: TextStyle(fontSize: 13, color: successColor)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      )
                    else
                    // Regular layout for larger screens
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Left actions
                          Flexible(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (!isCompleted)
                                  OutlinedButton(
                                    onPressed: () => _showEditDialog(job),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      side: BorderSide(color: primaryColor, width: 1.5),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.edit_outlined, size: 16, color: primaryColor),
                                        const SizedBox(width: 6),
                                        Text('Edit', style: TextStyle(fontSize: 14, color: primaryColor)),
                                      ],
                                    ),
                                  ),
                                if (!isCompleted)
                                  OutlinedButton(
                                    onPressed: () {
                                      final id = job['_id'] ?? job['id'] ?? job['jobId'] ?? '';
                                      if (id.toString().isNotEmpty) {
                                        _deleteJob(id.toString());
                                      }
                                    },
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      side: BorderSide(color: primaryColor, width: 1.5),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.delete_outline, size: 16, color: primaryColor),
                                        const SizedBox(width: 6),
                                        Text('Delete', style: TextStyle(fontSize: 14, color: primaryColor)),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),

                          // Right actions
                          Flexible(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.end,
                              children: [
                                OutlinedButton(
                                  onPressed: () {
                                    try {
                                      Navigator.of(context).push(MaterialPageRoute(
                                        builder: (_) => JobDetailsPageWidget(job: job),
                                      ));
                                    } catch (_) {}
                                  },
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    side: BorderSide(color: borderColor, width: 1.5),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.visibility_outlined, size: 16, color: textPrimary.withAlpha((0.8 * 255).toInt())),
                                      const SizedBox(width: 6),
                                      Text('Details', style: TextStyle(fontSize: 14, color: textPrimary.withAlpha((0.8 * 255).toInt()))),
                                    ],
                                  ),
                                ),
                                if (job['booking'] != null)
                                  OutlinedButton(
                                    onPressed: () {
                                      try {
                                        String? threadId;
                                        try { threadId = job['booking']?['threadId']?.toString(); } catch (_) {}
                                        try { threadId ??= job['booking']?['chat']?['_id']?.toString(); } catch (_) {}
                                        try { threadId ??= job['booking']?['chat']?['id']?.toString(); } catch (_) {}
                                        try { threadId ??= job['booking']?['thread']?['_id']?.toString(); } catch (_) {}
                                        NavigationUtils.safePush(
                                          context,
                                          MessageClientWidget(
                                            bookingId: job['booking']?['_id']?.toString() ?? job['bookingId']?.toString(),
                                            threadId: threadId?.toString(),
                                            jobTitle: job['title']?.toString(),
                                            bookingPrice: job['price']?.toString(),
                                            bookingDateTime: job['createdAt']?.toString(),
                                          ),
                                        );
                                      } catch (_) {}
                                    },
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      side: BorderSide(color: successColor, width: 1.5),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.chat_outlined, size: 16, color: successColor),
                                        const SizedBox(width: 6),
                                        Text('Chat', style: TextStyle(fontSize: 14, color: successColor)),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonCard() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final baseColor = isDark
        ? colorScheme.surfaceContainerHighest.withAlpha((0.3 * 255).toInt())
        : colorScheme.surfaceContainerHighest.withAlpha((0.1 * 255).toInt());

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outline.withAlpha(isDark ? (0.1 * 255).toInt() : (0.08 * 255).toInt()),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 180,
                      height: 20,
                      decoration: BoxDecoration(
                        color: baseColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 120,
                      height: 14,
                      decoration: BoxDecoration(
                        color: baseColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 70,
                height: 28,
                decoration: BoxDecoration(
                  color: baseColor,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            width: 140,
            height: 18,
            decoration: BoxDecoration(
              color: baseColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                height: 14,
                decoration: BoxDecoration(
                  color: baseColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                height: 14,
                decoration: BoxDecoration(
                  color: baseColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: 200,
                height: 14,
                decoration: BoxDecoration(
                  color: baseColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 70,
                    height: 36,
                    decoration: BoxDecoration(
                      color: baseColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 80,
                    height: 36,
                    decoration: BoxDecoration(
                      color: baseColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ],
              ),
              Container(
                width: 100,
                height: 36,
                decoration: BoxDecoration(
                  color: baseColor,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final screenH = MediaQuery.of(context).size.height;
    final screenW = MediaQuery.of(context).size.width;
    final isSmallScreen = screenW < 360;

    final iconColor = cs.onSurface.withAlpha(((isDark ? 0.5 : 0.4) * 255).toInt());
    final titleColor = cs.onSurface;
    final subtitleColor = cs.onSurface.withAlpha(((isDark ? 0.7 : 0.6) * 255).toInt());

    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 16 : 24, vertical: math.min(48.0, screenH * 0.06)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: isSmallScreen ? 100 : 120,
                height: isSmallScreen ? 100 : 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (isDark ? cs.surfaceContainerHighest : cs.surfaceContainerHighest).withAlpha(((isDark ? 0.3 : 0.1) * 255).toInt()),
                ),
                child: Icon(
                  _selectedTab == 'Posted' ? Icons.work_outline_rounded : Icons.check_circle_outline_rounded,
                  size: isSmallScreen ? 40 : 48,
                  color: iconColor,
                ),
              ),
              SizedBox(height: isSmallScreen ? 20 : 24),
              Text(
                _selectedTab == 'Posted' ? 'No Active Jobs' : 'No Completed Jobs',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: titleColor,
                  fontSize: isSmallScreen ? 20 : 24,
                ),
              ),
              SizedBox(height: isSmallScreen ? 8 : 12),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 8 : 0),
                child: Text(
                  _selectedTab == 'Posted'
                      ? 'Start by creating your first job posting'
                      : 'Jobs you\'ve completed will appear here',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: subtitleColor,
                    height: 1.5,
                    fontSize: isSmallScreen ? 14 : 16,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                ),
              ),
              if (_selectedTab == 'Posted' && !_isArtisan) ...[
                SizedBox(height: isSmallScreen ? 24 : 32),
                ElevatedButton(
                  onPressed: () {
                    try {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const CreateJobPage1Widget(),
                      ));
                    } catch (_) {}
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    padding: EdgeInsets.symmetric(
                      horizontal: isSmallScreen ? 20 : 28,
                      vertical: isSmallScreen ? 14 : 16,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: isDark ? 0 : 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, size: isSmallScreen ? 18 : 20),
                      SizedBox(width: isSmallScreen ? 6 : 8),
                      Text('Create New Job', style: TextStyle(
                          fontSize: isSmallScreen ? 14 : 15,
                          fontWeight: FontWeight.w600
                      )),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 360;
    final isTablet = screenWidth > 600;

    // Filter jobs based on selected tab
    final filteredJobs = _jobs.where((job) {
      final status = (job['status'] ?? '').toString().toLowerCase();
      final booking = job['booking'] ?? job['bookingData'] ?? job['booking_data'];
      final bookingStatus = booking != null
          ? (booking['status'] ?? '').toString().toLowerCase()
          : '';

      if (_selectedTab == 'Completed') {
        return status == 'closed' ||
            status == 'done' ||
            bookingStatus == 'done';
      } else {
        return !(status == 'closed' ||
            status == 'done' ||
            bookingStatus == 'done');
      }
    }).toList();

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: theme.scaffoldBackgroundColor,
          elevation: 0,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_rounded,
              color: cs.onSurface,
              size: isSmallScreen ? 22 : 24,
            ),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: Text(
            'My Jobs',
            style: TextStyle(
              fontSize: isSmallScreen ? 18 : 20,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          centerTitle: false,
        ),
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isSmallScreen ? 16 : 24,
              vertical: isSmallScreen ? 12 : 16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Search bar
                Container(
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: cs.outline.withAlpha(isDark ? (0.2 * 255).toInt() : (0.1 * 255).toInt()),
                      width: 1.5,
                    ),
                  ),
                  child: TextFormField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search jobs...',
                      hintStyle: TextStyle(
                        color: cs.onSurface.withAlpha((0.5 * 255).toInt()),
                        fontSize: isSmallScreen ? 14 : 15,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: isSmallScreen ? 16 : 20,
                        vertical: isSmallScreen ? 14 : 16,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: cs.onSurface.withAlpha((0.5 * 255).toInt()),
                        size: isSmallScreen ? 20 : 22,
                      ),
                      suffixIcon: _searchController!.text.isNotEmpty
                          ? IconButton(
                        icon: Icon(
                          Icons.clear_rounded,
                          size: 18,
                          color: cs.onSurface.withAlpha((0.5 * 255).toInt()),
                        ),
                        onPressed: () {
                          _searchController!.clear();
                          _loadJobs();
                        },
                      )
                          : null,
                    ),
                    style: TextStyle(
                      fontSize: isSmallScreen ? 14 : 15,
                      color: cs.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

                SizedBox(height: isSmallScreen ? 12 : 16),

                // Create job button (for non-artisans)
                if (_roleLoaded && !_isArtisan)
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      onPressed: () {
                        try {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const CreateJobPage1Widget(),
                          ));
                        } catch (_) {}
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cs.primary,
                        foregroundColor: cs.onPrimary,
                        padding: EdgeInsets.symmetric(
                          horizontal: isSmallScreen ? 16 : 20,
                          vertical: isSmallScreen ? 12 : 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: isDark ? 0 : 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_rounded, size: isSmallScreen ? 16 : 18),
                          SizedBox(width: isSmallScreen ? 6 : 8),
                          Text(
                            'Create Job',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: isSmallScreen ? 13 : 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                SizedBox(height: isSmallScreen ? 20 : 24),

                // Tab selector
                Container(
                  height: isSmallScreen ? 44 : 48,
                  decoration: BoxDecoration(
                    color: isDark
                        ? cs.surfaceContainerHighest.withAlpha((0.2 * 255).toInt())
                        : cs.surfaceContainerHighest.withAlpha((0.1 * 255).toInt()),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: cs.outline.withAlpha(isDark ? (0.2 * 255).toInt() : (0.1 * 255).toInt()),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: _tabs.map((tab) {
                      final isSelected = _selectedTab == tab;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                          child: GestureDetector(
                            onTap: () {
                              setState(() => _selectedTab = tab);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOut,
                              decoration: BoxDecoration(
                                color: isSelected ? cs.primary : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(
                                  tab,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: isSmallScreen ? 13 : 14,
                                    color: isSelected
                                        ? cs.onPrimary
                                        : cs.onSurface.withAlpha((0.7 * 255).toInt()),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                SizedBox(height: isSmallScreen ? 20 : 24),

                // Content
                Expanded(
                  child: _loading
                      ? ListView.builder(
                    itemCount: 3,
                    itemBuilder: (context, index) => _buildSkeletonCard(),
                  )
                      : _error != null
                      ? Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 16 : 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            size: isSmallScreen ? 48 : 56,
                            color: cs.error.withAlpha((0.8 * 255).toInt()),
                          ),
                          SizedBox(height: isSmallScreen ? 16 : 20),
                          Text(
                            'Unable to Load Jobs',
                            style: TextStyle(
                              fontSize: isSmallScreen ? 18 : 20,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                          SizedBox(height: isSmallScreen ? 6 : 8),
                          Text(
                            _error!,
                            style: TextStyle(
                              fontSize: isSmallScreen ? 13 : 14,
                              color: cs.onSurface.withAlpha((0.7 * 255).toInt()),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: isSmallScreen ? 20 : 24),
                          ElevatedButton.icon(
                            onPressed: _loadJobs,
                            icon: Icon(Icons.refresh_rounded, size: isSmallScreen ? 16 : 18),
                            label: Text(
                              'Try Again',
                              style: TextStyle(fontWeight: FontWeight.w500),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: cs.primary,
                              foregroundColor: cs.onPrimary,
                              padding: EdgeInsets.symmetric(
                                horizontal: isSmallScreen ? 20 : 24,
                                vertical: isSmallScreen ? 12 : 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                      : filteredJobs.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                    itemCount: filteredJobs.length,
                    itemBuilder: (context, index) => _buildJobCard(filteredJobs[index]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

