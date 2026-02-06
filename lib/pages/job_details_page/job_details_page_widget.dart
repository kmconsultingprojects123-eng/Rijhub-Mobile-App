import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/user_service.dart';
import '../../services/token_storage.dart';
import '../../api_config.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:rijhub/pages/quote_details/quote_details_page_widget.dart';
import '../../utils/app_notification.dart';
import '../artisan_kyc_page/artisan_kyc_route_wrapper.dart';
import '../applicants_page/applicants_page_widget.dart';
import '../submit_quote_page/submit_quote_page_widget.dart';

class JobDetailsPageWidget extends StatefulWidget {
  final Map<String, dynamic> job;
  final bool openApplications;
  final bool openApply;
  const JobDetailsPageWidget({
    super.key,
    required this.job,
    this.openApplications = false,
    this.openApply = false,
  });

  static String routeName = 'JobDetailsPage';
  static String routePath = '/jobDetailsPage';

  @override
  State<JobDetailsPageWidget> createState() => _JobDetailsPageWidgetState();
}

class _JobDetailsPageWidgetState extends State<JobDetailsPageWidget> {
  // Theme colors that adapt to light/dark mode
  Color get _primaryColor => const Color(0xFFA20025);
  Color get _successColor => const Color(0xFF10B981);
  Color get _warningColor => const Color(0xFFF59E0B);
  Color get _errorColor => const Color(0xFFEF4444);

  // Get colors based on theme
  Color _getTextPrimary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.white
          : const Color(0xFF111827);

  Color _getTextSecondary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF9CA3AF)
          : const Color(0xFF6B7280);

  Color _getSurfaceColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1F2937)
          : const Color(0xFFF9FAFB);

  Color _getBorderColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF374151)
          : const Color(0xFFE5E7EB);

  Color _getBackgroundColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.black
          : Colors.white;

  // State variables
  bool _loadingRole = true;
  bool _isArtisan = false;
  bool _hasApplied = false;
  bool _isOwner = false;

  @override
  void initState() {
    super.initState();
    _initialize();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.openApplications) _openApplicantsPage(context);
      if (widget.openApply) _openSubmitQuotePage(context);
    });
  }

  /// Extract a canonical user id from a possibly nested profile map.
  /// Tries several common keys and also checks nested `user` object.
  String? _extractUserIdFromProfile(Map<String, dynamic>? profile) {
    if (profile == null) return null;
    try {
      final candidates = ['_id', 'id', 'userId', 'user_id', 'uid'];
      for (final k in candidates) {
        final v = profile[k];
        if (v != null) return v.toString();
      }
      // Some endpoints embed the user under 'user'
      if (profile['user'] is Map) {
        for (final k in candidates) {
          final v = (profile['user'] as Map)[k];
          if (v != null) return v.toString();
        }
      }
      // Some APIs return { data: { user: {...} } }
      if (profile['data'] is Map) {
        final data = profile['data'] as Map;
        for (final k in candidates) {
          final v = data[k] ?? (data['user'] is Map ? (data['user'] as Map)[k] : null);
          if (v != null) return v.toString();
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _initialize() async {
    try {
      final profile = await UserService.getProfile();
      final role = (profile?['role'] ?? profile?['type'] ?? '').toString().toLowerCase();
      final id = _extractUserIdFromProfile(profile);

      // Check if user is job owner
      final clientId = _extractClientId(widget.job);
      final isOwner = id != null && clientId != null && id == clientId;

      setState(() {
        _isArtisan = role.contains('artisan');
        _isOwner = isOwner;
      });

      if (_isArtisan) await _checkIfApplied();
    } catch (_) {
      // Silent error
    } finally {
      if (mounted) setState(() => _loadingRole = false);
    }
  }

  String? _extractClientId(Map<String, dynamic> job) {
    try {
      if (job['clientId'] is Map) {
        return (job['clientId']['_id'] ?? job['clientId']['id'])?.toString();
      }
      return (job['clientId'] ?? job['owner'] ?? job['createdBy'])?.toString();
    } catch (_) {
      return null;
    }
  }

  Future<void> _checkIfApplied() async {
    try {
      final jobId =
          widget.job['_id'] ?? widget.job['id'] ?? widget.job['jobId'];
      if (jobId == null) return;

      final quotes = await _fetchJobQuotes(jobId.toString());
      final profile = await UserService.getProfile();
      final myId = _extractUserIdFromProfile(profile);
      if (myId == null) return;

      final hasApplied = quotes.any((quote) {
        final artisan =
            quote['artisanUser'] ?? quote['artisan'] ?? quote['user'] ?? {};
        final artisanId = (artisan is Map)
            ? (artisan['_id'] ?? artisan['id'] ?? artisan['userId'])?.toString()
            : artisan?.toString();
        return artisanId == myId;
      });

      if (mounted) setState(() => _hasApplied = hasApplied);
    } catch (_) {
      // Silent error
    }
  }

  Future<List<Map<String, dynamic>>> _fetchJobQuotes(String jobId) async {
    final token = await TokenStorage.getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('$API_BASE_URL/api/jobs/$jobId/quotes'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final data = body['data'] ?? body['quotes'] ?? body;
      if (data is List) {
        return List<Map<String, dynamic>>.from(
            data.map((e) => Map<String, dynamic>.from(e)));
      }
      return [];
    }
    throw Exception('Failed to load applications');
  }

  String _formatBudget(dynamic budget) {
    if (budget == null) return 'Not specified';
    try {
      if (budget is num) {
        return '₦${NumberFormat('#,##0', 'en_US').format(budget)}';
      }
      final numVal =
          num.tryParse(budget.toString().replaceAll(RegExp(r'[^0-9.-]'), ''));
      if (numVal != null) {
        return '₦${NumberFormat('#,##0', 'en_US').format(numVal)}';
      }
      return budget.toString();
    } catch (_) {
      return budget.toString();
    }
  }

  bool _isJobClosed() {
    final status = (widget.job['status'] ?? '').toString().toLowerCase();
    return status == 'closed' || status == 'done' || status == 'inactive';
  }

  bool _isJobPaid() {
    try {
      final booking = widget.job['booking'] ?? widget.job['bookingData'] ?? widget.job['booking_data'];
      if (booking != null) {
        final paymentStatus = booking['paymentStatus'] ?? (booking['payment'] is Map ? booking['payment']['status'] : booking['payment']);
        if (paymentStatus is String) {
          return paymentStatus.toLowerCase().contains('paid') || paymentStatus.toLowerCase().contains('success');
        }
        return paymentStatus == true;
      }

      final paymentStatus = widget.job['paymentStatus'];
      if (paymentStatus is String) return paymentStatus.toLowerCase().contains('paid');
    } catch (_) {}
    return false;
  }

  List<String> _extractTrades() {
    try {
      final tradeData = widget.job['trade'] ?? widget.job['trades'] ?? widget.job['skill'] ?? widget.job['skills'];
      if (tradeData == null) return [];
      if (tradeData is String) {
        return tradeData.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      }
      if (tradeData is List) {
        return tradeData.map((e) {
          if (e is String) return e;
          if (e is Map) return (e['name'] ?? e['title'] ?? '').toString();
          return e.toString();
        }).where((s) => s.isNotEmpty).toList();
      }
    } catch (_) {}
    return [];
  }

  // Replaced bottom sheet with full screen page. Use Navigator to open ApplicantsPage instead.
  void _openApplicantsPage(BuildContext context) {
    final jobId = widget.job['_id'] ?? widget.job['id'] ?? widget.job['jobId'];
    if (jobId == null) {
      AppNotification.showError(context, 'Job ID not found');
      return;
    }

    try {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ApplicantsPage(jobId: jobId.toString(), primaryColor: _primaryColor),
      ));
    } catch (_) {}
  }

  // For artisans we now navigate to a full page for submitting a quote (placeholder)
  void _openSubmitQuotePage(BuildContext context) {
    final jobId = widget.job['_id'] ?? widget.job['id'] ?? widget.job['jobId'];
    if (jobId == null) {
      AppNotification.showError(context, 'Job ID not found');
      return;
    }

    try {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SubmitQuotePage(jobId: jobId.toString(), primaryColor: _primaryColor),
      ));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final title =
        (job['title'] ?? job['jobTitle'] ?? 'Untitled Job').toString();
    final description = (job['description'] ?? job['details'] ?? '').toString();
    final budget = job['budget'];
    final isClosed = _isJobClosed();
    final trades = _extractTrades();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Format date
    String formattedDate = '';
    try {
      final rawDate = job['createdAt'] ?? job['created'] ?? job['date'];
      if (rawDate != null) {
        final date = DateTime.tryParse(rawDate.toString());
        if (date != null) {
          formattedDate = DateFormat('MMM dd, yyyy').format(date.toLocal());
        }
      }
    } catch (_) {}

    return Scaffold(
      backgroundColor: _getBackgroundColor(context),
      appBar: AppBar(
        backgroundColor: _getBackgroundColor(context),
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_rounded,
            color: _getTextPrimary(context),
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Job Details',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: _getTextPrimary(context),
          ),
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Content
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: _getTextPrimary(context),
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Date and status
                      Row(
                        children: [
                          if (formattedDate.isNotEmpty)
                            Row(
                              children: [
                                Icon(
                                  Icons.calendar_today_outlined,
                                  size: 16,
                                  color: _getTextSecondary(context),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  formattedDate,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: _getTextSecondary(context),
                                  ),
                                ),
                              ],
                            ),
                          if (isClosed) ...[
                            const SizedBox(width: 16),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color:
                                    _getTextSecondary(context).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.lock_outline_rounded,
                                    size: 12,
                                    color: _getTextSecondary(context),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Closed',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: _getTextSecondary(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Budget card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: _getSurfaceColor(context),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _getBorderColor(context).withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.account_balance_wallet_outlined,
                                  size: 20,
                                  color: _primaryColor,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Budget',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: _getTextSecondary(context),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _formatBudget(budget),
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w700,
                                color: _primaryColor,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Skills section
                      if (trades.isNotEmpty) ...[
                        Text(
                          'Required Skills',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: _getTextPrimary(context),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: trades.map((trade) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: _primaryColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                trade,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: _primaryColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 24),
                      ],

                      // Description
                      Text(
                        'Description',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: _getTextPrimary(context),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 16,
                          color: _getTextPrimary(context),
                          height: 1.6,
                        ),
                      ),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),

            // Action button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              decoration: BoxDecoration(
                color: _getBackgroundColor(context),
                border: Border(
                  top: BorderSide(
                    color: _getBorderColor(context),
                    width: 1,
                  ),
                ),
              ),
              child: _loadingRole
                  ? Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(_primaryColor),
                        ),
                      ),
                    )
                  : SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isJobPaid() ||
                                isClosed ||
                                (_isArtisan && _hasApplied)
                            ? null
                            : () async {
                                if (_isArtisan) {
                                  // Ensure KYC verified before allowing quote submission
                                  try {
                                    final kyc =
                                        await TokenStorage.getKycVerified();
                                    if (kyc != true) {
                                      final go = await showDialog<bool>(
                                        context: context,
                                        barrierDismissible: false,
                                        builder: (ctx) {
                                          return AlertDialog(
                                            title: const Text('KYC required'),
                                            content: const Text(
                                                'You must complete KYC verification before you can submit quotes. Go to KYC now?'),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.of(ctx)
                                                        .pop(false),
                                                child: const Text('Not now'),
                                              ),
                                              ElevatedButton(
                                                onPressed: () =>
                                                    Navigator.of(ctx).pop(true),
                                                child: const Text('Go to KYC'),
                                              ),
                                            ],
                                          );
                                        },
                                      );
                                      if (go == true) {
                                        try {
                                          final status = await TokenStorage.getKycStatus();
                                          if (status == 'pending') {
                                            // Inform user that admin review is in progress
                                            await showDialog<void>(
                                              context: context,
                                              builder: (ctx) => AlertDialog(
                                                title: const Text('Awaiting KYC approval'),
                                                content: const Text('Your KYC request is pending admin review. We will notify you when it is approved.'),
                                                actions: [
                                                  TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
                                                ],
                                              ),
                                            );
                                          } else {
                                            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ArtisanKycWidget()));
                                            final after = await TokenStorage.getKycVerified();
                                            if (after == true) {
                                              _openSubmitQuotePage(context);
                                            }
                                          }
                                        } catch (_) {}
                                      }
                                      return;
                                    }
                                  } catch (_) {
                                    final go = await showDialog<bool>(
                                      context: context,
                                      barrierDismissible: false,
                                      builder: (ctx) {
                                        return AlertDialog(
                                          title: const Text('KYC required'),
                                          content: const Text(
                                              'You must complete KYC verification before you can submit quotes. Go to KYC now?'),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.of(ctx).pop(false),
                                              child: const Text('Not now'),
                                            ),
                                            ElevatedButton(
                                              onPressed: () =>
                                                  Navigator.of(ctx).pop(true),
                                              child: const Text('Go to KYC'),
                                            ),
                                          ],
                                        );
                                      },
                                    );
                                    if (go == true) {
                                      try {
                                        final status = await TokenStorage.getKycStatus();
                                        if (status == 'pending') {
                                          await showDialog<void>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: const Text('Awaiting KYC approval'),
                                              content: const Text('Your KYC request is pending admin review. We will notify you when it is approved.'),
                                              actions: [
                                                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
                                              ],
                                            ),
                                          );
                                        } else {
                                          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ArtisanKycWidget()));
                                        }
                                      } catch (_) {}
                                    }
                                    return;
                                  }

                                  // KYC passed; open submit quote page
                                  _openSubmitQuotePage(context);
                                } else if (_isOwner) {
                                  _openApplicantsPage(context);
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          isClosed
                              ? 'Job Closed'
                              : _isJobPaid()
                                  ? 'Job Paid'
                                  : _isArtisan
                                      ? (_hasApplied
                                          ? 'Application Submitted'
                                          : 'Submit Quote')
                                      : (_isOwner
                                          ? 'View Applicants'
                                          : 'Login to Apply'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
            ),
        ]
      ),
      ),
    );
  }
}

