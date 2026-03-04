import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/user_service.dart';
import '../../services/token_storage.dart';
import '../../api_config.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../utils/app_notification.dart';
import '../../utils/auth_guard.dart';
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
  bool _isLoggedIn = false;
  String? _myId;
  String _role = '';
  // Human-readable location from reverse geocoding (if available)
  String? _humanLocation;
  bool _loadingHumanLocation = false;
  // Posted-by user name lookup
  String? _postedByName;
  bool _loadingPostedBy = false;

  @override
  void initState() {
    super.initState();
    _initialize();
    _loadHumanLocation();
    _loadPostedBy();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.openApplications) _openApplicantsPage(context);
      if (widget.openApply) _openSubmitQuotePage(context);
    });
  }

  Future<void> _loadHumanLocation() async {
    try {
      final coordsRaw = widget.job['coordinates'] ?? widget.job['coords'] ?? widget.job['locationCoords'];
      double? lat, lon;
      if (coordsRaw is List && coordsRaw.length >= 2) {
        lat = coordsRaw[1] is num ? coordsRaw[1].toDouble() : double.tryParse(coordsRaw[1].toString());
        lon = coordsRaw[0] is num ? coordsRaw[0].toDouble() : double.tryParse(coordsRaw[0].toString());
      } else if (coordsRaw is Map) {
        lat = (coordsRaw['lat'] ?? coordsRaw['latitude']) is num
            ? (coordsRaw['lat'] ?? coordsRaw['latitude']).toDouble()
            : double.tryParse((coordsRaw['lat'] ?? coordsRaw['latitude']).toString());
        lon = (coordsRaw['lon'] ?? coordsRaw['lng'] ?? coordsRaw['longitude']) is num
            ? (coordsRaw['lon'] ?? coordsRaw['lng'] ?? coordsRaw['longitude']).toDouble()
            : double.tryParse((coordsRaw['lon'] ?? coordsRaw['lng'] ?? coordsRaw['longitude']).toString());
      }

      if (lat == null || lon == null) return;

      _loadingHumanLocation = true;
      if (mounted) setState(() {});

      // Use OpenStreetMap Nominatim reverse geocoding (follow usage policy, add User-Agent)
      final url = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=$lat&lon=$lon&addressdetails=1');
      try {
        final resp = await http.get(url, headers: {'User-Agent': 'rijhub-app/1.0 (+https://example.com)'}).timeout(const Duration(seconds: 8));
        if (resp.statusCode >= 200 && resp.statusCode < 300 && resp.body.isNotEmpty) {
          final json = jsonDecode(resp.body);
          if (json is Map) {
            final display = json['display_name']?.toString();
            if (display != null && display.isNotEmpty) {
              _humanLocation = display;
            } else if (json['address'] is Map) {
              final addr = json['address'] as Map;
              // Build a readable address from common components
              final parts = <String>[];
              for (final k in ['house_number','road','neighbourhood','suburb','city','town','village','state_district','state','postcode','country']) {
                final v = addr[k];
                if (v != null && v.toString().trim().isNotEmpty) parts.add(v.toString().trim());
              }
              if (parts.isNotEmpty) _humanLocation = parts.join(', ');
            }
          }
        }
      } catch (e) {
        debugPrint('reverse geocode failed: $e');
      }
    } catch (e) {
      debugPrint('loadHumanLocation error: $e');
    } finally {
      _loadingHumanLocation = false;
      if (mounted) setState(() {});
    }
  }

  /// Normalize an id-like value into a trimmed string, or null if none.
  String? _normalizeId(dynamic v) {
    if (v == null) return null;
    try {
      if (v is String) return v.trim();
      if (v is num) return v.toString();
      if (v is Map) {
        final candidates = ['_id', 'id', 'userId', 'user_id', 'uid', 'clientId'];
        for (final k in candidates) {
          final val = v[k];
          if (val != null) return val.toString().trim();
        }
        // fallback: try toString()
        return v.toString();
      }
      return v.toString().trim();
    } catch (_) {
      return null;
    }
  }

  /// Extract a canonical user id from a possibly nested profile map.
  /// Tries several common keys and also checks nested `user` object.
  String? _extractUserIdFromProfile(Map<String, dynamic>? profile) {
    if (profile == null) return null;
    try {
      final candidates = ['_id', 'id', 'userId', 'user_id', 'uid'];
      for (final k in candidates) {
        final v = profile[k];
        final id = _normalizeId(v);
        if (id != null && id.isNotEmpty) return id;
      }
      // Some endpoints embed the user under 'user'
      if (profile['user'] is Map) {
        final userMap = profile['user'] as Map;
        for (final k in candidates) {
          final v = userMap[k];
          final id = _normalizeId(v);
          if (id != null && id.isNotEmpty) return id;
        }
      }
      // Some APIs return { data: { user: {...} } }
      if (profile['data'] is Map) {
        final data = profile['data'] as Map;
        for (final k in candidates) {
          final v = data[k] ?? (data['user'] is Map ? (data['user'] as Map)[k] : null);
          final id = _normalizeId(v);
          if (id != null && id.isNotEmpty) return id;
        }
      }
    } catch (e) {
      debugPrint('extractUserIdFromProfile error: $e');
    }
    return null;
  }

  String? _extractClientId(Map<String, dynamic> job) {
    try {
      // Try several common keys and nested shapes
      final possible = ['clientId', 'client', 'owner', 'createdBy', 'created_by', 'ownerId', 'client_id', 'postedBy'];
      for (final p in possible) {
        if (job[p] != null) {
          final id = _normalizeId(job[p]);
          if (id != null && id.isNotEmpty) return id;
        }
      }

      // If clientId is a nested object under 'clientDetails' or similar
      if (job['clientDetails'] is Map) {
        final cd = job['clientDetails'] as Map;
        final id = _normalizeId(cd['_id'] ?? cd['id'] ?? cd['userId']);
        if (id != null && id.isNotEmpty) return id;
      }

      // fallback: check job['clientId'] if Map
      if (job['clientId'] is Map) {
        return _normalizeId((job['clientId'] as Map)['_id'] ?? (job['clientId'] as Map)['id']);
      }

      return null;
    } catch (e) {
      debugPrint('extractClientId error: $e');
      return null;
    }
  }

  Future<void> _initialize() async {
    try {
      final profile = await UserService.getProfile();
      _isLoggedIn = profile != null;
      _role = (profile?['role'] ?? profile?['type'] ?? '').toString().toLowerCase();
      final id = _extractUserIdFromProfile(profile);
      _myId = id;

      // Check if user is job owner
      final clientId = _extractClientId(widget.job);
      final isOwner = id != null && clientId != null && id == clientId;

      setState(() {
        _isArtisan = _role.contains('artisan');
        _isOwner = isOwner;
      });

      if (_isArtisan) await _checkIfApplied();
    } catch (e) {
      debugPrint('JobDetails.initialize error: $e');
      // keep silent for users but log in debug
    } finally {
      if (mounted) setState(() => _loadingRole = false);
    }
  }

  String? _extractJobId() {
    return widget.job['_id'] ?? widget.job['id'] ?? widget.job['jobId'];
  }

  Future<void> _checkIfApplied() async {
    try {
      final jobId = _extractJobId();
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
    } catch (e) {
      debugPrint('checkIfApplied error: $e');
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

  // Convert coordinates to human-readable location using reverse geocoding
  String? _formatCoordinatesToLocation(dynamic coordsRaw) {
    if (coordsRaw == null) return null;

    try {
      double? lat, lon;

      if (coordsRaw is List && coordsRaw.length >= 2) {
        lat = coordsRaw[1] is num ? coordsRaw[1].toDouble() : double.tryParse(coordsRaw[1].toString());
        lon = coordsRaw[0] is num ? coordsRaw[0].toDouble() : double.tryParse(coordsRaw[0].toString());
      } else if (coordsRaw is Map) {
        lat = (coordsRaw['lat'] ?? coordsRaw['latitude']) is num
            ? (coordsRaw['lat'] ?? coordsRaw['latitude']).toDouble()
            : double.tryParse((coordsRaw['lat'] ?? coordsRaw['latitude']).toString());
        lon = (coordsRaw['lon'] ?? coordsRaw['lng'] ?? coordsRaw['longitude']) is num
            ? (coordsRaw['lon'] ?? coordsRaw['lng'] ?? coordsRaw['longitude']).toDouble()
            : double.tryParse((coordsRaw['lon'] ?? coordsRaw['lng'] ?? coordsRaw['longitude']).toString());
      }

      if (lat != null && lon != null) {
        // Convert to DMS (Degrees, Minutes, Seconds) format for better readability
        String latDir = lat >= 0 ? 'N' : 'S';
        String lonDir = lon >= 0 ? 'E' : 'W';
        double absLat = lat.abs();
        double absLon = lon.abs();

        int latDeg = absLat.floor();
        int latMin = ((absLat - latDeg) * 60).floor();
        double latSec = ((absLat - latDeg - latMin/60) * 3600);

        int lonDeg = absLon.floor();
        int lonMin = ((absLon - lonDeg) * 60).floor();
        double lonSec = ((absLon - lonDeg - lonMin/60) * 3600);

        return '${latDeg}°${latMin}\'${latSec.toStringAsFixed(2)}"$latDir, ${lonDeg}°${lonMin}\'${lonSec.toStringAsFixed(2)}"$lonDir';
      }

      // Fallback to simple coordinate format
      return '$lat, $lon';
    } catch (_) {
      return null;
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
    } catch (e) {
      debugPrint('openApplicantsPage error: $e');
    }
  }

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
    } catch (e) {
      debugPrint('openSubmitQuotePage error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final title = (job['title'] ?? job['jobTitle'] ?? 'Untitled Job').toString();
    final description = (job['description'] ?? job['details'] ?? '').toString();
    final budget = job['budget'];
    final isClosed = _isJobClosed();
    final trades = _extractTrades();

    // Additional job meta
    final experienceLevel = (job['experienceLevel'] ?? job['experience'] ?? job['yearsExperience'])?.toString();
    final categoryName = (job['categoryDetails'] is Map)
        ? (job['categoryDetails']['name'] ?? job['categoryDetails']['title'])?.toString()
        : (job['category'] ?? job['categoryId'])?.toString();
    final location = (job['location'] ?? job['address'] ?? job['place'])?.toString();
    final coordsRaw = job['coordinates'] ?? job['coords'] ?? job['locationCoords'];
    final formattedLocation = _formatCoordinatesToLocation(coordsRaw) ?? location;
    final locationLabel = _humanLocation ?? formattedLocation ?? '';

    final scheduleRaw = job['schedule'] ?? job['date'] ?? job['scheduledAt'];
    String scheduleStr = '';
    try {
      if (scheduleRaw != null) {
        final d = DateTime.tryParse(scheduleRaw.toString());
        if (d != null) scheduleStr = DateFormat('MMM dd, yyyy HH:mm').format(d.toLocal());
      }
    } catch (_) {}

    final paymentStatus = job['paymentStatus'] ?? (job['booking'] is Map ? job['booking']['paymentStatus'] : null);
    final clientName = (job['clientDetails'] is Map)
        ? (job['clientDetails']['name'] ?? job['clientDetails']['fullName'] ?? job['clientDetails']['username'])
        : job['clientName'] ?? job['client'] ?? job['clientId'];

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

    // Helper widget for info cards
    Widget _buildInfoCard(String title, String value, IconData icon, {bool isPrimary = false}) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isPrimary ? _primaryColor.withOpacity(0.05) : _getSurfaceColor(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isPrimary ? _primaryColor.withOpacity(0.2) : _getBorderColor(context),
            width: 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 20,
              color: isPrimary ? _primaryColor : _getTextSecondary(context),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isPrimary ? _primaryColor : _getTextSecondary(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Increase the font size slightly for primary cards (e.g., Budget)
                  Builder(builder: (_) {
                    final valueFontSize = isPrimary ? 18.0 : 14.0;
                    return Text(
                      value,
                      style: TextStyle(
                        fontSize: valueFontSize,
                        fontWeight: FontWeight.w600,
                        color: _getTextPrimary(context),
                        height: 1.3,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Helper widget for detail sections
    Widget _buildDetailSection(String title, List<Widget> children) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: _getTextPrimary(context),
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      );
    }

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
      body: Column(
        children: [
          // Status banner
          if (isClosed)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              color: _warningColor.withOpacity(0.1),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_outline, size: 18, color: _warningColor),
                  const SizedBox(width: 8),
                  Text(
                    'Job Closed',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _warningColor,
                    ),
                  ),
                ],
              ),
            ),

          // Main content
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title and date
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: _getTextPrimary(context),
                          height: 1.3,
                        ),
                      ),
                      if (formattedDate.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_today_outlined,
                              size: 16,
                              color: _getTextSecondary(context),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Posted on $formattedDate',
                              style: TextStyle(
                                fontSize: 14,
                                color: _getTextSecondary(context),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Budget Card
                  _buildInfoCard(
                    'BUDGET',
                    _formatBudget(budget),
                    Icons.account_balance_wallet_outlined,
                    isPrimary: true,
                  ),

                  const SizedBox(height: 16),

                  // Quick Info (reflowed): two-column header row, full-width LOCATION,
                  // then Posted By & Schedule side-by-side under the location. Payment shown below.
                  Builder(builder: (_) {
                    Widget? catCard = (categoryName != null && categoryName.isNotEmpty)
                        ? _buildInfoCard('CATEGORY', categoryName, Icons.category_outlined)
                        : null;
                    Widget? expCard = (experienceLevel != null && experienceLevel.isNotEmpty)
                        ? _buildInfoCard('EXPERIENCE', experienceLevel, Icons.timeline_outlined)
                        : null;
                    final clientId = _extractClientId(widget.job);
                    Widget? postedCard;
                    if (clientId != null || clientName != null) {
                      final display = _loadingPostedBy
                          ? 'Loading...'
                          : (_postedByName ?? (clientName != null ? clientName.toString() : clientId.toString()));
                      postedCard = _buildInfoCard('POSTED BY', display, Icons.person_outline);
                    } else {
                      postedCard = null;
                    }
                    Widget? scheduleCard = (scheduleStr.isNotEmpty)
                        ? _buildInfoCard('Application deadline', scheduleStr, Icons.schedule_outlined)
                        : null;
                    Widget? paymentCard = (paymentStatus != null)
                        ? _buildInfoCard('PAYMENT', paymentStatus.toString(), Icons.payment_outlined)
                        : null;

                    Widget locationCard;
                    if (_loadingHumanLocation && (locationLabel.isEmpty)) {
                      locationCard = _buildInfoCard('LOCATION', 'Looking up address...', Icons.location_on_outlined);
                    } else {
                      locationCard = _buildInfoCard('LOCATION', locationLabel.isNotEmpty ? locationLabel : 'Not specified', Icons.location_on_outlined);
                    }

                    Widget twoColRow(Widget? a, Widget? b) {
                      if (a == null && b == null) return const SizedBox.shrink();
                      if (a == null) return b!;
                      if (b == null) return a;
                      return Row(
                        children: [
                          Expanded(child: a),
                          const SizedBox(width: 12),
                          Expanded(child: b),
                        ],
                      );
                    }

                    final List<Widget> children = [];

                    // Top two-column row (category, experience)
                    final topRow = twoColRow(catCard, expCard);
                    if (topRow is! SizedBox) children.add(topRow);

                    // Spacing
                    if (children.isNotEmpty) children.add(const SizedBox(height: 12));

                    // Full-width location
                    children.add(locationCard);
                    children.add(const SizedBox(height: 12));

                    // Posted By & Schedule under the location
                    final bottomRow = twoColRow(postedCard, scheduleCard);
                    if (bottomRow is! SizedBox) children.add(bottomRow);

                    // Payment card below (full width) if present
                    if (paymentCard != null) {
                      children.add(const SizedBox(height: 12));
                      children.add(paymentCard);
                    }

                    return Column(children: children);
                  }),

                  const SizedBox(height: 24),

                  // Skills Section
                  if (trades.isNotEmpty)
                    _buildDetailSection(
                      'Required Skills',
                      [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: trades.map((trade) {
                            return Chip(
                              label: Text(
                                trade,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: _primaryColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              backgroundColor: _primaryColor.withOpacity(0.1),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              side: BorderSide(color: _primaryColor.withOpacity(0.3)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            );
                          }).toList(),
                        ),
                      ],
                    ),

                  const SizedBox(height: 24),

                  // Description Section
                  _buildDetailSection(
                    'Job Description',
                    [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _getSurfaceColor(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _getBorderColor(context)),
                        ),
                        child: Text(
                          description,
                          style: TextStyle(
                            fontSize: 15,
                            color: _getTextPrimary(context),
                            height: 1.6,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Additional Details Section
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Additional Information',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: _getTextPrimary(context),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _getSurfaceColor(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _getBorderColor(context)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Job Status as badge
                            if ((job['status'] ?? '').toString().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 100,
                                      child: Text(
                                        'Status:',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: _getTextSecondary(context),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Builder(builder: (ctx) {
                                        final statusStr = (job['status'] ?? job['state'] ?? '').toString();
                                        final isClosedLocal = statusStr.toLowerCase() == 'closed' || statusStr.toLowerCase() == 'done' || statusStr.toLowerCase() == 'inactive';
                                        final badgeColor = isClosedLocal ? _warningColor : _successColor;
                                        return Align(
                                          alignment: Alignment.centerLeft,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: badgeColor.withOpacity(0.12),
                                              borderRadius: BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              statusStr.toString(),
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: badgeColor,
                                              ),
                                            ),
                                          ),
                                        );
                                      }),
                                    ),
                                  ],
                                ),
                              ),

                            // Job ID
                            if (_extractJobId() != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 100,
                                      child: Text(
                                        'Job ID:',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: _getTextSecondary(context),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        _extractJobId().toString(),
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: _getTextPrimary(context),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ].whereType<Widget>().toList(),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
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
            : ((_isLoggedIn && !_isOwner && !_isArtisan)
            ? const SizedBox.shrink()
            : SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isJobPaid() ||
                isClosed ||
                (_isArtisan && _hasApplied)
                ? null
                : () async {
              // Owner should take precedence: open applicants
              if (_isOwner) {
                _openApplicantsPage(context);
                return;
              }

              // Guest or unauthenticated: prompt to sign in
              if (!_isArtisan) {
                await showGuestAuthRequiredDialog(context, message: 'Sign in or create an account to apply for this job.');
                return;
              }

              if (_isArtisan) {
                // Ensure KYC verified before allowing quote submission
                try {
                  final kyc = await TokenStorage.getKycVerified();
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
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: const Text('Not now'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.of(ctx).pop(true),
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
                      } catch (e) {
                        debugPrint('KYC flow error: $e');
                      }
                    }
                    return;
                  }
                } catch (e) {
                  debugPrint('KYC check error: $e');
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
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('Not now'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
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
                    } catch (e) {
                      debugPrint('KYC flow error: $e');
                    }
                  }
                  return;
                }

                // KYC passed; open submit quote page
                _openSubmitQuotePage(context);
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
                  : _isOwner
                  ? 'View Applicants'
                  : _isArtisan
                  ? (_hasApplied
                  ? 'Application Submitted'
                  : 'Submit Quote')
                  : 'Login to Apply',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        )),
      ),
    );
  }

  Future<void> _loadPostedBy() async {
    try {
      final clientId = _extractClientId(widget.job);
      if (clientId == null || clientId.isEmpty) return;
      _loadingPostedBy = true;
      if (mounted) setState(() {});

      final name = await _fetchUserById(clientId);
      if (name != null && name.isNotEmpty) _postedByName = name;
    } catch (e) {
      debugPrint('loadPostedBy error: $e');
    } finally {
      _loadingPostedBy = false;
      if (mounted) setState(() {});
    }
  }

  Future<String?> _fetchUserById(String id) async {
    try {
      final token = await TokenStorage.getToken();
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';

      final candidates = [
        '$API_BASE_URL/api/users/$id',
        '$API_BASE_URL/api/users/user/$id',
        '$API_BASE_URL/api/users?id=$id',
        '$API_BASE_URL/api/users?userId=$id',
      ];

      for (final url in candidates) {
        try {
          final resp = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 10));
          if (resp.statusCode >= 200 && resp.statusCode < 300 && resp.body.isNotEmpty) {
            dynamic body;
            try { body = jsonDecode(resp.body); } catch (_) { body = null; }
            Map<String, dynamic>? userMap;
            if (body is Map) {
              if (body['data'] is Map) userMap = Map<String, dynamic>.from(body['data']);
              else if (body['user'] is Map) userMap = Map<String, dynamic>.from(body['user']);
              else userMap = Map<String, dynamic>.from(body);
            }
            if (userMap != null) {
              final candidatesName = ['name', 'fullName', 'full_name', 'username', 'firstName', 'displayName'];
              for (final k in candidatesName) {
                if (userMap[k] != null && userMap[k].toString().trim().isNotEmpty) return userMap[k].toString().trim();
              }
              if (userMap['user'] is Map) {
                final u = Map<String, dynamic>.from(userMap['user']);
                for (final k in candidatesName) {
                  if (u[k] != null && u[k].toString().trim().isNotEmpty) return u[k].toString().trim();
                }
              }
            }
          }
        } catch (_) {
          // try next endpoint
          continue;
        }
      }
    } catch (e) {
      debugPrint('fetchUserById error: $e');
    }
    return null;
  }
}

