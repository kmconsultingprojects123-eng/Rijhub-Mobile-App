import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import '../../utils/app_notification.dart';
import '../../services/special_service_request_service.dart';
import '../../services/token_storage.dart';
import '../../services/location_service.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '../payment_webview/payment_webview_page_widget.dart';
import '../../services/user_service.dart';

class SpecialRequestDetailsWidget extends StatefulWidget {
  final Map<String, dynamic> request;

  const SpecialRequestDetailsWidget({super.key, required this.request});

  @override
  State<SpecialRequestDetailsWidget> createState() => _SpecialRequestDetailsWidgetState();
}

class _SpecialRequestDetailsWidgetState extends State<SpecialRequestDetailsWidget> {
  Map<String, dynamic>? _currentRequest;
  bool _isClient = false;
  bool _isLoading = true;
  Timer? _refreshTimer;
  bool _isRefreshingRequest = false;
  bool _isActivityDialogVisible = false;
  String? _currentUserId;
  final Map<String, Map<String, dynamic>> _userProfileCache = {};
  final Map<String, String> _locationCache = {};

  Color get primaryColor => FlutterFlowTheme.of(context).primary;

  String _normalizedStatus([Map<String, dynamic>? request]) {
    final rawStatus = (request ?? _currentRequest)?['status'];
    if (rawStatus is String) {
      return rawStatus.toLowerCase();
    }
    return rawStatus?.toString().toLowerCase() ?? '';
  }

  bool get _isPending => _normalizedStatus() == 'pending';
  bool get _isResponded => _normalizedStatus() == 'responded';
  bool get _canViewArtisanResponse {
    final status = _normalizedStatus();
    if ([
      'responded',
      'accepted',
      'declined',
      'cancelled',
      'confirmed',
      'in_progress',
      'completed',
    ].contains(status)) {
      return true;
    }

    final artisanReply = _currentRequest?['artisanReply'];
    if (artisanReply is Map && artisanReply.isNotEmpty) {
      return true;
    }

    final note = _currentRequest?['note'];
    if (note is Map && note.isNotEmpty) {
      return true;
    }

    return false;
  }
  bool get _hasSuccessfulPayment {
    String? normalize(dynamic value) {
      final text = value?.toString().trim().toLowerCase();
      return (text == null || text.isEmpty) ? null : text;
    }

    for (final candidate in [
      _currentRequest?['paymentStatus'],
      _currentRequest?['payment_status'],
      _currentRequest?['booking']?['paymentStatus'],
      _currentRequest?['booking']?['payment_status'],
      _currentRequest?['payment']?['status'],
      _currentRequest?['payment']?['gateway_response'],
    ]) {
      final status = normalize(candidate);
      if (status == null) continue;
      if ([
        'paid',
        'success',
        'successful',
        'completed',
        'confirmed',
        'holding',
      ].contains(status)) {
        return true;
      }
    }

    for (final candidate in [
      _currentRequest?['paid'],
      _currentRequest?['isPaid'],
      _currentRequest?['booking']?['paid'],
      _currentRequest?['booking']?['isPaid'],
    ]) {
      if (candidate == true) return true;
      final status = normalize(candidate);
      if (status == 'true') return true;
    }

    return false;
  }

  @override
  void initState() {
    super.initState();
    _currentRequest = Map.from(widget.request);
    _isLoading = false;
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializePage());
  }

  @override
  void dispose() {
    _isActivityDialogVisible = false;
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _showActivityDialog({
    required String title,
    required String message,
    IconData icon = Icons.sync_rounded,
  }) {
    if (!mounted) return;
    if (_isActivityDialogVisible) {
      Navigator.of(context, rootNavigator: true).pop();
      _isActivityDialogVisible = false;
    }

    _isActivityDialogVisible = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: Dialog(
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: primaryColor, size: 24),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: FlutterFlowTheme.of(context).titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: FlutterFlowTheme.of(context).bodyMedium?.copyWith(
                        color: Theme.of(context).hintColor,
                        height: 1.4,
                      ),
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                    backgroundColor: primaryColor.withOpacity(0.14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).then((_) {
      _isActivityDialogVisible = false;
    });
  }

  void _hideActivityDialog() {
    if (!mounted || !_isActivityDialogVisible) return;
    Navigator.of(context, rootNavigator: true).pop();
    _isActivityDialogVisible = false;
  }

  Future<void> _initializePage() async {
    final initialRequest = Map<String, dynamic>.from(widget.request);
    final currentUserId = await _getCurrentUserId();
    final initialIsClient = _resolveIsClientSync(initialRequest, currentUserId);
    if (mounted) {
      setState(() {
        _currentRequest = initialRequest;
        _isClient = initialIsClient;
      });
    }
    final hydratedRequest = await _buildHydratedRequest(
      initialRequest,
      fetchLatest: true,
    );
    final hydratedIsClient = _resolveIsClientSync(hydratedRequest, currentUserId);

    if (!mounted) return;
    setState(() {
      _currentRequest = hydratedRequest;
      _isClient = hydratedIsClient;
    });
    _startAutoRefresh();
  }

  /// Start automatic refresh of request status (live updates)
  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      if (!mounted) {
        _refreshTimer?.cancel();
        return;
      }
      final route = ModalRoute.of(context);
      if (route?.isCurrent == false || _isRefreshingRequest) {
        return;
      }
      // Only refresh if not in a final state
      final status = _normalizedStatus();
      if (!['completed', 'cancelled', 'rejected', 'declined'].contains(status)) {
        await _refreshRequestData();
      } else {
        // Cancel refresh if request is in final state
        _refreshTimer?.cancel();
      }
    });
  }

  Future<Map<String, dynamic>> _withHumanReadableLocation(
      Map<String, dynamic> request) async {
    final updated = Map<String, dynamic>.from(request);
    try {
      final locationStr = updated['location']?.toString();
      if (locationStr != null && locationStr.isNotEmpty) {
        final cached = _locationCache[locationStr];
        final humanReadable = cached ??
            await LocationService.getHumanReadableLocation(locationStr);
        _locationCache[locationStr] = humanReadable;
        updated['location'] = humanReadable;
      }
    } catch (_) {}
    return updated;
  }

  String? _extractProfileImageUrl(dynamic imageData) {
    if (imageData == null) return null;
    if (imageData is String) return imageData;
    if (imageData is Map) return imageData['url']?.toString();
    return null;
  }

  Future<Map<String, dynamic>> _withUserProfiles(
      Map<String, dynamic> request) async {
    final updated = Map<String, dynamic>.from(request);
    final clientId = updated['clientId']?.toString() ?? updated['client']?['id']?.toString();
    final artisanId = updated['artisanId']?.toString() ?? updated['artisan']?['id']?.toString();

    Future<Map<String, dynamic>?> fetchProfile(String id) async {
      final cached = _userProfileCache[id];
      if (cached != null) return cached;
      try {
        final profile = await UserService.getUserById(id);
        if (profile != null) {
          final normalized = Map<String, dynamic>.from(profile);
          _userProfileCache[id] = normalized;
          return normalized;
        }
      } catch (_) {}
      return null;
    }

    final futures = await Future.wait([
      if (clientId != null && clientId.isNotEmpty) fetchProfile(clientId),
      if (artisanId != null && artisanId.isNotEmpty) fetchProfile(artisanId),
    ]);

    int futureIndex = 0;
    Map<String, dynamic>? clientProfile;
    Map<String, dynamic>? artisanProfile;
    if (clientId != null && clientId.isNotEmpty) {
      clientProfile = futures[futureIndex++];
    }
    if (artisanId != null && artisanId.isNotEmpty) {
      artisanProfile = futures[futureIndex];
    }

    if (clientProfile != null) {
      updated['client'] = {
        'id': clientId,
        'name': clientProfile['name']?.toString() ?? clientProfile['firstName']?.toString() ?? 'Client',
        'profileImage': _extractProfileImageUrl(clientProfile['profileImage']),
      };
    } else if (updated['client'] == null) {
      updated['client'] = {'name': 'Client', 'profileImage': null};
    }

    if (artisanProfile != null) {
      updated['artisan'] = {
        'id': artisanId,
        'name': artisanProfile['name']?.toString() ?? artisanProfile['firstName']?.toString() ?? 'Artisan',
        'profileImage': _extractProfileImageUrl(artisanProfile['profileImage']),
        'rating': artisanProfile['rating'],
        'artisanRating': artisanProfile['artisanRating'],
        'avgRating': artisanProfile['avgRating'],
      };
    } else if (updated['artisan'] == null) {
      updated['artisan'] = {'name': 'Artisan', 'profileImage': null};
    }

    return updated;
  }

  List<String> _extractImages() {
    final images = <String>{};

    void collect(dynamic source) {
      if (source == null) return;

      if (source is String) {
        final trimmed = source.trim();
        if (trimmed.isEmpty) return;

        if (trimmed.startsWith('[')) {
          try {
            collect(jsonDecode(trimmed));
            return;
          } catch (_) {}
        }

        if (trimmed.startsWith('http://') || trimmed.startsWith('https://') || trimmed.startsWith('data:')) {
          images.add(trimmed);
        }
        return;
      }

      if (source is List) {
        for (final item in source) {
          collect(item);
        }
        return;
      }

      if (source is Map) {
        for (final key in ['url', 'path', 'imageUrl', 'image_url', 'secure_url', 'secureUrl']) {
          final value = source[key];
          if (value != null) {
            collect(value);
            return;
          }
        }
      }
    }

    collect(_currentRequest?['attachments']);
    collect(_currentRequest?['imageUrls']);

    return images.toList();
  }

  Map<String, dynamic>? _extractMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
  }

  String? _extractNameFromMap(Map<String, dynamic>? data) {
    if (data == null) return null;
    for (final field in ['name', 'fullName', 'full_name', 'firstName', 'first_name', 'displayName', 'display_name']) {
      final value = data[field]?.toString();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  String? _extractImageFromMap(Map<String, dynamic>? data) {
    if (data == null) return null;
    const profileImageFields = [
      'profileImage',
      'profile_image',
      'profileUrl',
      'profile_url',
      'profileImageUrl',
      'profile_image_url',
      'avatar',
      'avatarUrl',
      'photo',
      'image',
      'picture',
      'profilePicture',
    ];

    for (final field in profileImageFields) {
      final imageData = data[field];
      if (imageData is Map) {
        final url = imageData['url']?.toString();
        if (url != null && url.isNotEmpty && (url.startsWith('http') || url.startsWith('https') || url.startsWith('data:'))) {
          return url;
        }
      }
      if (imageData is String && imageData.isNotEmpty && (imageData.startsWith('http') || imageData.startsWith('https') || imageData.startsWith('data:'))) {
        return imageData;
      }
    }

    final nestedUser = _extractMap(data['user']);
    if (nestedUser != null) {
      return _extractImageFromMap(nestedUser);
    }

    return null;
  }

  double _extractRatingFromMap(Map<String, dynamic>? data) {
    if (data == null) return 0.0;
    const ratingFields = [
      'rating',
      'artisanRating',
      'artisan_rating',
      'stars',
      'score',
      'review_rating',
      'reviewRating',
      'avgRating',
      'avg_rating',
      'ratingAverage',
      'rating_average',
    ];

    for (final field in ratingFields) {
      final rating = data[field];
      if (rating is num) {
        return rating.toDouble();
      }
      if (rating != null) {
        final parsed = double.tryParse(rating.toString());
        if (parsed != null) {
          return parsed;
        }
      }
    }

    final nestedUser = _extractMap(data['user']);
    if (nestedUser != null) {
      return _extractRatingFromMap(nestedUser);
    }

    return 0.0;
  }

  Map<String, dynamic>? _artisanData() {
    final artisan = _extractMap(_currentRequest?['artisan']);
    if (artisan != null) return artisan;

    final userInArtisan = _extractMap(_currentRequest?['artisanUser']);
    if (userInArtisan != null) return userInArtisan;

    return null;
  }

  Map<String, dynamic>? _clientData() {
    final client = _extractMap(_currentRequest?['client']);
    if (client != null) return client;

    final user = _extractMap(_currentRequest?['user']);
    if (user != null) return user;

    final customer = _extractMap(_currentRequest?['customer']);
    if (customer != null) return customer;

    return null;
  }

  String _extractKYCStatus() {
    final kycFields = ['kycStatus', 'kyc_status', 'kycVerification', 'kyc_verification', 'verificationStatus', 'verification_status'];
    for (final field in kycFields) {
      final status = _currentRequest?[field]?.toString();
      if (status != null && status.isNotEmpty) {
        return status;
      }
    }
    return 'Not Verified';
  }

  double _extractArtisanRating() {
    final artisan = _artisanData();
    final artisanRating = _extractRatingFromMap(artisan);
    if (artisanRating > 0) return artisanRating;
    return _extractRatingFromMap(_extractMap(_currentRequest));
  }

  String _extractDisplayName() {
    if (_isClient) {
      // Client sees artisan's name
      final artisanNameFields = ['artisanName', 'artisan_name', 'serviceProviderName', 'service_provider_name'];
      for (final field in artisanNameFields) {
        final name = _currentRequest?[field]?.toString();
        if (name != null && name.isNotEmpty) {
          return name;
        }
      }

      final artisanName = _extractNameFromMap(_artisanData());
      if (artisanName != null && artisanName.isNotEmpty) {
        return artisanName;
      }

      return 'Artisan';
    } else {
      // Artisan sees client's name
      final clientNameFields = ['clientName', 'client_name', 'customerName', 'customer_name', 'userName', 'user_name'];
      for (final field in clientNameFields) {
        final name = _currentRequest?[field]?.toString();
        if (name != null && name.isNotEmpty) {
          return name;
        }
      }

      final clientName = _extractNameFromMap(_clientData());
      if (clientName != null && clientName.isNotEmpty) {
        return clientName;
      }

      return 'Client';
    }
  }

  String? _extractDisplayProfileImage() {
    if (_isClient) {
      return _extractImageFromMap(_artisanData());
    } else {
      return _extractImageFromMap(_clientData());
    }
  }

  double _extractDisplayRating() {
    if (_isClient) {
      return _extractArtisanRating();
    } else {
      return 0.0;
    }
  }

  Future<String?> _getCurrentUserId() async {
    if (_currentUserId != null && _currentUserId!.isNotEmpty) {
      return _currentUserId;
    }
    try {
      _currentUserId = await TokenStorage.getUserId();
    } catch (_) {
      _currentUserId = null;
    }
    return _currentUserId;
  }

  bool _resolveIsClientSync(
    Map<String, dynamic>? request,
    String? uid,
  ) {
    try {
      if (uid == null || uid.isEmpty || request == null) return false;

      String? clientId;
      final cands = ['clientId', 'client_id', 'client', 'userId', 'user_id', 'user', 'createdBy'];
      for (final k in cands) {
        final v = request[k];
        if (v == null) continue;
        if (v is Map) {
          final nestedId = v['_id'] ?? v['id'];
          if (nestedId != null) clientId = nestedId.toString();
        } else {
          final s = v.toString();
          if (s.isNotEmpty) clientId = s;
        }
        if (clientId != null) break;
      }
      return clientId == uid;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> _buildHydratedRequest(
    Map<String, dynamic> request, {
    bool fetchLatest = false,
  }) async {
    var updated = Map<String, dynamic>.from(request);

    if (fetchLatest) {
      final id = _safe(updated['_id'] ?? updated['id']);
      if (id != '-') {
        try {
          final freshData = await SpecialServiceRequestService.fetchById(id);
          if (freshData != null) {
            updated = {
              ...updated,
              ...freshData,
            };
          }
        } catch (_) {}
      }
    }

    final hydrated = await Future.wait([
      _withUserProfiles(updated),
      _withHumanReadableLocation(updated),
    ]);
    updated = Map<String, dynamic>.from(updated)
      ..addAll(hydrated[0])
      ..addAll(hydrated[1]);
    return updated;
  }

  bool _requestChanged(Map<String, dynamic> next) {
    final current = _currentRequest;
    if (current == null) return true;
    for (final key in [
      '_id',
      'id',
      'status',
      'updatedAt',
      'bookingId',
      'paymentStatus',
      'payment_status',
      'location',
      'note',
      'artisanReply',
      'title',
      'serviceTitle',
    ]) {
      if (jsonEncode(current[key]) != jsonEncode(next[key])) {
        return true;
      }
    }
    return false;
  }

  void _showImageViewer(String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(0),
        child: _ImageViewerModal(imageUrl: imageUrl),
      ),
    );
  }

  Future<void> _refreshRequestData() async {
    if (_isRefreshingRequest) return;
    _isRefreshingRequest = true;
    try {
      final currentRequest = _currentRequest;
      if (currentRequest == null) return;
      final id = _safe(currentRequest['_id'] ?? currentRequest['id']);
      if (id != '-') {
        final refreshed = await _buildHydratedRequest(
          currentRequest,
          fetchLatest: true,
        );
        final isClient = _resolveIsClientSync(
          refreshed,
          await _getCurrentUserId(),
        );
        if (!mounted) {
          _currentRequest = refreshed;
          _isClient = isClient;
          return;
        }
        if (_requestChanged(refreshed) || _isClient != isClient) {
          setState(() {
            _currentRequest = refreshed;
            _isClient = isClient;
          });
        }
      }
    } catch (_) {}
    finally {
      _isRefreshingRequest = false;
    }
  }

  Future<bool> _waitForBookingCreation({
    int attempts = 5,
    Duration delay = const Duration(seconds: 2),
  }) async {
    for (var i = 0; i < attempts; i++) {
      await _refreshRequestData();
      final status = _normalizedStatus();
      final bookingId = _currentRequest?['bookingId']?.toString() ??
          _currentRequest?['booking']?['_id']?.toString() ??
          _currentRequest?['booking']?['id']?.toString();
      if (status == 'confirmed' ||
          (bookingId != null && bookingId.isNotEmpty && bookingId != '-')) {
        return true;
      }
      if (i < attempts - 1) {
        await Future.delayed(delay);
      }
    }
    return false;
  }

  String _safe(dynamic s) => s?.toString() ?? '-';

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '-';
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inDays == 0) return 'Today at ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      if (diff.inDays == 1) return 'Yesterday at ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      if (diff.inDays < 7) return '${diff.inDays} days ago';
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return dateStr;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending': return Colors.amber;
      case 'responded': return Colors.blue;
      case 'accepted': return Colors.orange;
      case 'confirmed': return Colors.green;
      case 'in_progress': return Colors.indigo;
      case 'completed': return Colors.teal;
      case 'rejected': return Colors.red;
      case 'declined': return Colors.red;
      case 'cancelled': return Colors.grey;
      default: return primaryColor;
    }
  }

  String _getStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'pending': return 'Pending';
      case 'responded': return 'Responded';
      case 'accepted': return 'Accepted';
      case 'confirmed': return 'Confirmed';
      case 'in_progress': return 'In Progress';
      case 'completed': return 'Completed';
      case 'rejected': return 'Rejected';
      case 'declined': return 'Declined';
      case 'cancelled': return 'Cancelled';
      default: return status.replaceAll('_', ' ');
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'pending': return Icons.pending_outlined;
      case 'responded': return Icons.mark_email_read_outlined;
      case 'accepted': return Icons.payments_outlined;
      case 'confirmed': return Icons.verified_outlined;
      case 'in_progress': return Icons.handyman_outlined;
      case 'completed': return Icons.done_all_outlined;
      case 'rejected': return Icons.cancel_outlined;
      case 'declined': return Icons.do_not_disturb_on_outlined;
      case 'cancelled': return Icons.remove_circle_outline;
      default: return Icons.info_outline;
    }
  }

  Future<void> _showArtisanResponseSheet() async {
    try {
      final requestId = _safe(_currentRequest?['_id'] ?? _currentRequest?['id']);
      if (requestId == '-') {
        AppNotification.showError(context, 'Invalid request ID');
        return;
      }

      final fetchedResponse = await SpecialServiceRequestService.fetchArtisanResponse(requestId);
      if (!mounted) return;

      if (fetchedResponse == null) {
        AppNotification.showError(context, 'Failed to fetch artisan response');
        return;
      }

      Map<String, dynamic>? asMap(dynamic value) {
        if (value is Map) {
          return Map<String, dynamic>.from(value);
        }
        if (value is String) {
          final trimmed = value.trim();
          if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
            try {
              final decoded = jsonDecode(trimmed);
              if (decoded is Map) {
                return Map<String, dynamic>.from(decoded);
              }
            } catch (_) {}
          }
        }
        return null;
      }

      // Log the fetched response for debugging
      print('Fetched artisan response: $fetchedResponse');

      // Merge nested reply fields with top-level quote fields so we don't lose
      // pricing when the backend returns `message` in `note` but quote metadata
      // (`quote`, `quoteType`, `minQuote`, `maxQuote`, `options`) at root level.
      Map<String, dynamic> artisanReply = {};
      final responseArtisanReply = asMap(fetchedResponse['artisanReply']);
      final responseNote = asMap(fetchedResponse['note']);
      final currentArtisanReply = asMap(_currentRequest?['artisanReply']);
      final currentNote = asMap(_currentRequest?['note']);

      if (currentArtisanReply != null) artisanReply.addAll(currentArtisanReply);
      if (currentNote != null) artisanReply.addAll(currentNote);
      if (responseArtisanReply != null) artisanReply.addAll(responseArtisanReply);
      if (responseNote != null) artisanReply.addAll(responseNote);

      if (artisanReply.isEmpty) {
        artisanReply = Map<String, dynamic>.from(fetchedResponse);
      } else {
        for (final key in [
          'quote',
          'quoteType',
          'min',
          'max',
          'minQuote',
          'maxQuote',
          'options',
          'selectedPrice',
          'budget',
          'minBudget',
          'maxBudget',
          'price',
          'amount',
        ]) {
          final topLevelValue = fetchedResponse[key] ?? _currentRequest?[key];
          if (topLevelValue != null &&
              topLevelValue.toString().trim().isNotEmpty &&
              artisanReply[key] == null) {
            artisanReply[key] = topLevelValue;
          }
        }
      }

      // Log the extracted artisanReply
      print('Extracted artisanReply: $artisanReply');

      if (artisanReply.isEmpty) {
        AppNotification.showError(context, 'No artisan response found');
        return;
      }

      final artisanName = _currentRequest?['artisanName']?.toString() ?? 'Artisan';
      final message = (artisanReply['message']?.toString() ?? '').isNotEmpty
          ? artisanReply['message'].toString()
          : 'No additional message provided';

      // Determine quote type based on available fields
      final fixedValue =
          artisanReply['quote'] ??
          artisanReply['selectedPrice'] ??
          artisanReply['price'] ??
          artisanReply['amount'] ??
          (((num.tryParse((artisanReply['budget'] ?? '').toString()) ?? 0) > 0)
              ? artisanReply['budget']
              : null);
      final minQuote = artisanReply['min'] ??
          artisanReply['minQuote'] ??
          artisanReply['minBudget'];
      final maxQuote = artisanReply['max'] ??
          artisanReply['maxQuote'] ??
          artisanReply['maxBudget'];
      final normalizedOptions = artisanReply['options'] is List
          ? (artisanReply['options'] as List)
          : artisanReply['priceOptions'] is List
              ? (artisanReply['priceOptions'] as List)
              : artisanReply['priceRange'] is List
                  ? (artisanReply['priceRange'] as List)
                  : null;
      final hasFixed = fixedValue != null &&
          (num.tryParse(fixedValue.toString()) == null ||
              (num.tryParse(fixedValue.toString()) ?? 0) > 0);
      final hasRange =
          (minQuote != null && maxQuote != null) ||
          normalizedOptions != null;
      final quoteType = artisanReply['quoteType']?.toString();

      final isFixed = quoteType == 'fixed' || (hasFixed && !hasRange);
      final isRange = quoteType == 'range' || (!isFixed && hasRange);

      String? fixedQuote;
      List<String>? priceRanges;
      int? min;
      int? max;

      if (isFixed && fixedValue != null) {
        fixedQuote = fixedValue.toString();
      } else if (isRange) {
        final options = normalizedOptions;
        if (options != null && options.isNotEmpty) {
          priceRanges = List<String>.from(options.map((o) => o.toString()));
        } else {
          if (minQuote != null && maxQuote != null) {
            min = int.tryParse(minQuote.toString());
            max = int.tryParse(maxQuote.toString());
            if (min != null && max != null && min < max) {
              final range = max - min;
              priceRanges = [];
              for (int i = 0; i < 5; i++) {
                final start = min + (range * i ~/ 5);
                final end = min + (range * (i + 1) ~/ 5);
                priceRanges!.add('$start - $end');
              }
            }
          }
        }
      }

      // Log the parsed quote information
      print('isFixed: $isFixed, isRange: $isRange, fixedQuote: $fixedQuote, priceRanges: $priceRanges, min: $min, max: $max');

      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) => _ArtisanResponseSheet(
          artisanName: artisanName,
          message: message,
          isFixed: isFixed,
          isRange: isRange,
          fixedQuote: fixedQuote,
          priceRanges: priceRanges,
          min: min,
          max: max,
          onAgreeAndPay: (int? selectedPrice) async {
            final agree = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Confirm Payment'),
                content: Text('Proceed to payment for ₦${selectedPrice ?? 'this service'}?'),
                actions: [
                  TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('No')),
                  ElevatedButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Yes')),
                ],
              ),
            );
            if (agree == true) {
              _showActivityDialog(
                title: 'Preparing Payment',
                message: 'Saving your selection and preparing secure checkout.',
                icon: Icons.payments_outlined,
              );

              try {
                final id = _safe(_currentRequest?['_id'] ?? _currentRequest?['id']);
                if (id == '-') {
                  _hideActivityDialog();
                  AppNotification.showError(context, 'Invalid request ID');
                  return;
                }

                // Call acceptResponse which will initialize payment on the backend
                final updated = await SpecialServiceRequestService.acceptResponse(
                  id,
                  selectedPrice: selectedPrice,
                  requestTitle: _currentRequest?['serviceTitle']?.toString() ??
                      _currentRequest?['title']?.toString(),
                );

                if (!mounted) return;
                _hideActivityDialog();

                if (updated != null) {
                  // Check for nested data structure
                  if (updated['data'] is Map) {
                    // Nested data found
                  }

                  // Merge the updated response with existing request data to preserve all fields
                  final mergedRequest = _currentRequest != null
                      ? {..._currentRequest!, ...updated}
                      : updated;
                  setState(() => _currentRequest = mergedRequest);

                  final bookingData = updated['booking'];
                  final bookingId = updated['bookingId']?.toString() ??
                      (bookingData is Map
                          ? (bookingData['_id'] ?? bookingData['id'])
                              ?.toString()
                          : null);

                  // Check if payment was initialized (payment data or authorization URL present)
                  final paymentData = updated['payment'] ?? updated['paymentData'] ?? updated['authorization'] ?? updated['data']?['payment'];

                  final authUrl = paymentData is Map ? paymentData['authorization_url'] ?? paymentData['authorizationUrl'] : null;

                  Map<String, dynamic>? paymentResponse;
                  if (paymentData != null && authUrl != null && authUrl.toString().isNotEmpty) {
                    paymentResponse = Map<String, dynamic>.from(paymentData);
                  } else {
                    // Try the documented /:id/pay endpoint when accept returns booking without payment.
                    String? email;
                    try {
                      final profile = await UserService.getProfile();
                      email = profile?['email']?.toString();
                      if (email == null || email.trim().isEmpty) {
                        final recent = await TokenStorage.getRecentRegistration();
                        email = recent?['email']?.toString();
                      }
                      if (email == null || email.trim().isEmpty) {
                        email = await TokenStorage.getRememberedEmail();
                      }
                    } catch (_) {
                      email = null;
                    }
                    final payResult =
                        await SpecialServiceRequestService.initializePayment(
                      id,
                      email: email,
                      requestTitle: _currentRequest?['serviceTitle']
                              ?.toString() ??
                          _currentRequest?['title']?.toString(),
                      selectedPrice: selectedPrice,
                    );
                    final payData =
                        payResult?['payment'] is Map ? payResult!['payment'] : payResult;
                    if (payData != null && (payData['authorization_url'] != null || payData['authorizationUrl'] != null)) {
                      final payAuthUrl = payData['authorization_url'] ?? payData['authorizationUrl'];
                      if (payAuthUrl != null && payAuthUrl.toString().isNotEmpty) {
                        paymentResponse = Map<String, dynamic>.from(payData);
                      }
                    }
                  }

                  if (paymentResponse != null && (paymentResponse['authorization_url'] != null || paymentResponse['authorizationUrl'] != null)) {
                    final finalAuthUrl = paymentResponse['authorization_url'] ?? paymentResponse['authorizationUrl'];
                    if (finalAuthUrl != null && finalAuthUrl.toString().isNotEmpty) {
                      // For special service requests, payment is already initialized by the server
                      // Use in-app webview for payment instead of external browser
                      if (mounted) {
                        _showActivityDialog(
                          title: 'Opening Checkout',
                          message: 'Taking you to Paystack to complete payment securely.',
                          icon: Icons.open_in_new_rounded,
                        );
                        await Future.delayed(const Duration(milliseconds: 350));
                        _hideActivityDialog();
                        final result = await Navigator.of(context).push<Map<String, dynamic>>(
                          MaterialPageRoute(
                            builder: (context) => PaymentWebviewPageWidget(
                              url: finalAuthUrl.toString(),
                              successUrlContains: null, // Rely on automatic detection
                            ),
                          ),
                        );

                        if (result != null) {
                          final success = result['success'] as bool?;
                          final resultUrl = result['url'] as String?;
                          final reference = result['reference'] as String?;

                          if (success == true && reference != null && reference.isNotEmpty) {
                            _showActivityDialog(
                              title: 'Verifying Payment',
                              message: 'Confirming your payment with the server.',
                              icon: Icons.verified_outlined,
                            );

                            // Verify the payment with the backend
                            try {
                              final verifyResult =
                                  await SpecialServiceRequestService.verifyPayment(
                                reference,
                              );
                              _hideActivityDialog();

                              if (verifyResult != null && verifyResult['status'] != null) {
                                final statusValue = verifyResult['status'];
                                final paymentStatus = statusValue.toString().toLowerCase();
                                // Handle both string and boolean status values
                                final isSuccess = paymentStatus == 'success' ||
                                    paymentStatus == 'completed' ||
                                    paymentStatus == 'true' ||
                                    statusValue == true;
                                if (isSuccess) {
                                  _showActivityDialog(
                                    title: 'Finalizing Request',
                                    message: 'Updating this request and checking for confirmation.',
                                    icon: Icons.assignment_turned_in_outlined,
                                  );
                                  final bookingCreated =
                                      await _waitForBookingCreation();
                                  await _refreshRequestData();
                                  _hideActivityDialog();
                                  if (mounted) {
                                    if (bookingCreated) {
                                      AppNotification.showSuccess(context,
                                          'Payment verified and request confirmed successfully!');
                                    } else {
                                      AppNotification.showSuccess(context,
                                          'Payment verified successfully. We are waiting for booking confirmation.');
                                    }
                                    Navigator.of(context).pop();
                                  }
                                } else {
                                  AppNotification.showError(context, 'Payment verification failed. Status: $paymentStatus');
                                }
                              } else {
                                AppNotification.showError(context, 'Payment verification failed');
                              }
                            } catch (e) {
                              _hideActivityDialog();
                              AppNotification.showError(context, 'Error verifying payment: $e');
                            }
                          } else if (success == true) {
                            _showActivityDialog(
                              title: 'Refreshing Request',
                              message: 'Payment completed. Updating this request now.',
                              icon: Icons.refresh_rounded,
                            );
                            AppNotification.showSuccess(context, 'Payment completed successfully!');
                            await _refreshRequestData();
                            _hideActivityDialog();
                          } else {
                            AppNotification.showError(context, 'Payment was cancelled or failed');
                          }
                        }
                      }
                    } else {
                      AppNotification.showError(context, 'Payment could not be initialized. Please try again.');
                    }
                  } else {
                    if (bookingId != null && bookingId.isNotEmpty) {
                      AppNotification.showInfo(
                        context,
                        'Payment initialization is still pending. Please try again shortly.',
                      );
                    } else {
                      AppNotification.showError(context, 'Payment could not be initialized. Please try again.');
                    }
                  }
                } else {
                  AppNotification.showError(context, 'Failed to process payment');
                }
              } catch (e) {
                if (mounted) {
                  _hideActivityDialog();
                  AppNotification.showError(context, 'Error processing payment: $e');
                }
              }
            }
          },
          onCancel: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Cancel Request'),
                content: const Text('Are you sure you want to cancel this request?'),
                actions: [
                  TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('No')),
                  ElevatedButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Yes')),
                ],
              ),
            );
            if (confirm == true) {
              try {
                final id = _safe(_currentRequest?['_id'] ?? _currentRequest?['id']);
                if (id != '-') {
                  final updated = await SpecialServiceRequestService.updateStatus(id, 'cancelled');
                  if (updated != null) {
                    setState(() => _currentRequest = updated);
                    AppNotification.showSuccess(context, 'Request cancelled');
                  }
                }
              } catch (e) {
                AppNotification.showError(context, 'Error cancelling request');
              }
            }
          },
        ),
      );
    } catch (e) {
      if (mounted) {
        AppNotification.showError(context, 'Error fetching artisan response');
      }
    }
  }

  Future<void> _showArtisanResponseForm() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _ArtisanResponseForm(
          requestId: _safe(_currentRequest?['_id'] ?? _currentRequest?['id']),
          primaryColor: primaryColor,
          onSuccess: (updatedRequest) {
            setState(() => _currentRequest = updatedRequest);
          },
        ),
      );
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

    Color _surfaceColor() => Theme.of(context).colorScheme.surface;
    Color _borderColor() => Theme.of(context).dividerColor;

    if (_currentRequest == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text('Failed to load request details', style: theme.bodyLarge),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    final images = _extractImages();
    final status = _normalizedStatus();
    final statusColor = _getStatusColor(status);
    final statusText = _getStatusText(status);
    final title = _safe(_currentRequest?['serviceTitle'] ?? _currentRequest?['title']);
    final description = _safe(_currentRequest?['description']);
    final location = _safe(_currentRequest?['location']);
    final createdAt = _formatDate(_currentRequest?['createdAt']?.toString());
    final updatedAt = _currentRequest?['updatedAt'] != null ? _formatDate(_currentRequest?['updatedAt']?.toString()) : null;
    final urgency = _safe(_currentRequest?['urgency']);
    final profileImage = _extractDisplayProfileImage();
    final displayName = _extractDisplayName();
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: _borderColor(), width: 1)),
              ),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(
                        Icons.arrow_back_rounded,
                        color: Theme.of(context).iconTheme.color ?? (isDark ? Colors.white : Colors.black),
                        size: isSmallScreen ? 22 : 24,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Request Details',
                      style: theme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: isSmallScreen ? 20.0 : 22.0,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: (_isLoading || _isRefreshingRequest) ? 2 : 0,
              child: (_isLoading || _isRefreshingRequest)
                  ? LinearProgressIndicator(
                      valueColor:
                          AlwaysStoppedAnimation<Color>(primaryColor),
                      backgroundColor: Colors.transparent,
                    )
                  : null,
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _surfaceColor(),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          // Profile Image and Name
                          Expanded(
                            child: Row(
                              children: [
                                Stack(
                                  children: [
                                    Container(
                                      width: 64,
                                      height: 64,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: _surfaceColor(),
                                        border: Border.all(
                                          color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
                                          width: 2,
                                        ),
                                      ),
                                      child: ClipOval(
                                        child: profileImage != null && profileImage!.isNotEmpty
                                            ? Image.network(
                                          profileImage!,
                                          fit: BoxFit.cover,
                                          loadingBuilder: (context, child, loadingProgress) {
                                            if (loadingProgress == null) return child;
                                            return Center(
                                              child: CircularProgressIndicator(
                                                value: loadingProgress.expectedTotalBytes != null
                                                    ? loadingProgress.cumulativeBytesLoaded /
                                                    loadingProgress.expectedTotalBytes!
                                                    : null,
                                                strokeWidth: 2,
                                                color: primaryColor,
                                              ),
                                            );
                                          },
                                          errorBuilder: (context, error, stackTrace) {
                                            return Icon(
                                              Icons.person_outline,
                                              size: 32,
                                              color: isDark ? Colors.grey[600] : Colors.grey[400],
                                            );
                                          },
                                          cacheWidth: 200,
                                          cacheHeight: 200,
                                        )
                                            : Icon(
                                          Icons.person_outline,
                                          size: 32,
                                          color: isDark ? Colors.grey[600] : Colors.grey[400],
                                        ),
                                      ),
                                    ),
                                    // Verified Badge
                                    Positioned(
                                      bottom: 0,
                                      right: 0,
                                      child: Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          color: Colors.green,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: _surfaceColor(),
                                            width: 2,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.check,
                                          color: Colors.white,
                                          size: 14,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        displayName,
                                        style: theme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          fontSize: bodyFontSize + 1,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Status Badge Pill (Right side, smaller)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: statusColor.withOpacity(0.3), width: 1),
                            ),
                            child: Text(
                              statusText,
                              style: theme.bodySmall?.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.w600,
                                fontSize: smallFontSize - 1,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Service Title Card
                    if (title != '-')
                      _buildDetailCard(
                        context: context,
                        icon: Icons.title_outlined,
                        title: 'Service Title',
                        value: title,
                        theme: theme,
                        primaryColor: primaryColor,
                        isDark: isDark,
                        bodyFontSize: bodyFontSize,
                        smallFontSize: smallFontSize,
                      ),

                    const SizedBox(height: 16),

                    // Description Card
                    if (description != '-')
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _surfaceColor(),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[200]!, width: 1),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: primaryColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(Icons.description_outlined, color: primaryColor, size: isSmallScreen ? 18 : 20),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Description',
                                  style: theme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: bodyFontSize,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              description,
                              style: theme.bodyMedium?.copyWith(
                                color: isDark ? Colors.grey[400] : Colors.grey[700],
                                fontSize: bodyFontSize - 1,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 16),

                    // Info Grid
                    _buildInfoItem(context: context, icon: Icons.location_on_outlined, label: 'Location', value: location, theme: theme, primaryColor: primaryColor, isDark: isDark, bodyFontSize: bodyFontSize, smallFontSize: smallFontSize),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(child: _buildInfoItem(context: context, icon: Icons.calendar_today_outlined, label: 'Created', value: createdAt, theme: theme, primaryColor: primaryColor, isDark: isDark, bodyFontSize: bodyFontSize, smallFontSize: smallFontSize)),
                        const SizedBox(width: 12),
                        Expanded(child: _buildInfoItem(context: context, icon: Icons.speed_outlined, label: 'Urgency', value: urgency, theme: theme, primaryColor: primaryColor, isDark: isDark, bodyFontSize: bodyFontSize, smallFontSize: smallFontSize)),
                      ],
                    ),

                    if (updatedAt != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[900] : Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.update_rounded, size: 14, color: isDark ? Colors.grey[500] : Colors.grey[600]),
                            const SizedBox(width: 8),
                            Text(
                              'Last updated: $updatedAt',
                              style: theme.bodySmall?.copyWith(
                                color: isDark ? Colors.grey[500] : Colors.grey[600],
                                fontSize: smallFontSize - 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Image Gallery
                    if (images.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _buildImageGallery(images: images, theme: theme, primaryColor: primaryColor, isSmallScreen: isSmallScreen),
                    ],

                    const SizedBox(height: 24),

                    // Action Buttons
                    if (_isClient)
                      Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _hasSuccessfulPayment ? null : (_canViewArtisanResponse ? _showArtisanResponseSheet : null),
                              icon: const Icon(Icons.visibility_outlined),
                              label: const Text('View Artisan Response'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _hasSuccessfulPayment ? Colors.grey[400] : (_canViewArtisanResponse ? primaryColor : Colors.grey[400]),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          if (_hasSuccessfulPayment)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                'Client has made payment for the service',
                                style: theme.bodySmall?.copyWith(
                                  color: Colors.grey[600],
                                  fontStyle: FontStyle.italic,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            )
                          else if (!_canViewArtisanResponse)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                'No artisan response yet',
                                style: theme.bodySmall?.copyWith(
                                  color: Colors.grey[600],
                                  fontStyle: FontStyle.italic,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                        ],
                      )
                    else
                      Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _hasSuccessfulPayment ? null : (_isPending ? _showArtisanResponseForm : null),
                              icon: const Icon(Icons.rate_review_outlined),
                              label: const Text('Submit Response'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _hasSuccessfulPayment ? Colors.grey[400] : (_isPending ? primaryColor : Colors.grey[400]),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          if (_hasSuccessfulPayment)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                'Client has made payment for the service',
                                style: theme.bodySmall?.copyWith(
                                  color: Colors.grey[600],
                                  fontStyle: FontStyle.italic,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            )
                          else if (!_isPending)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                'Already submitted a response, wait for client to review',
                                style: theme.bodySmall?.copyWith(
                                  color: Colors.grey[600],
                                  fontStyle: FontStyle.italic,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                        ],
                      ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String value,
    required var theme,
    required Color primaryColor,
    required bool isDark,
    required double bodyFontSize,
    required double smallFontSize,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: bodyFontSize,
              color: primaryColor,
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 0),
            child: Text(
              value,
              style: theme.bodyMedium?.copyWith(
                fontSize: bodyFontSize + 4,
                color: isDark ? Colors.grey[300] : Colors.grey[800],
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
    required var theme,
    required Color primaryColor,
    required bool isDark,
    required double bodyFontSize,
    required double smallFontSize,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[200]!, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: primaryColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.bodySmall?.copyWith(
                  color: isDark ? Colors.grey[500] : Colors.grey[600],
                  fontSize: smallFontSize - 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: bodyFontSize - 1,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildImageGallery({
    required List<String> images,
    required var theme,
    required Color primaryColor,
    required bool isSmallScreen,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Attached Images',
          style: theme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: isSmallScreen ? 14.0 : 16.0,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: images.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: EdgeInsets.only(right: index == images.length - 1 ? 0 : 12),
                child: GestureDetector(
                  onTap: () => _showImageViewer(images[index]),
                  child: Container(
                    width: 120,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: primaryColor.withOpacity(0.1),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            images[index],
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.broken_image, color: Colors.grey, size: 32),
                                    const SizedBox(height: 4),
                                    Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Text(
                                        'Image failed\nto load',
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) {
                                return child;
                              }
                              return Center(
                                child: CircularProgressIndicator(
                                  value: progress.expectedTotalBytes != null
                                      ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                                      : null,
                                  strokeWidth: 2,
                                  color: primaryColor,
                                ),
                              );
                            },
                          ),
                          Positioned(
                            bottom: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.zoom_in, color: Colors.white, size: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// Artisan Response Sheet Component
class _ArtisanResponseSheet extends StatefulWidget {
  final String artisanName;
  final String message;
  final bool isFixed;
  final bool isRange;
  final String? fixedQuote;
  final List<String>? priceRanges;
  final int? min;
  final int? max;
  final Function(int?) onAgreeAndPay;
  final VoidCallback onCancel;

  const _ArtisanResponseSheet({
    required this.artisanName,
    required this.message,
    required this.isFixed,
    required this.isRange,
    this.fixedQuote,
    this.priceRanges,
    this.min,
    this.max,
    required this.onAgreeAndPay,
    required this.onCancel,
  });

  @override
  State<_ArtisanResponseSheet> createState() => _ArtisanResponseSheetState();
}

class _ArtisanResponseSheetState extends State<_ArtisanResponseSheet> {
  Color _borderColor() => Theme.of(context).dividerColor;

  int? _selectedRangePrice;

  List<int> _rangeOptions() {
    final parsed = <int>{};
    for (final option in widget.priceRanges ?? const <String>[]) {
      final cleaned = option.replaceAll(RegExp(r'[^0-9]'), ' ');
      final parts = cleaned.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
      for (final part in parts) {
        final value = int.tryParse(part);
        if (value != null) {
          parsed.add(value);
        }
      }
    }
    return parsed.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 375;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = theme.primary ?? const Color(0xFFA20025);
    final rangeOptions = _rangeOptions();
    final hasPricing = widget.isFixed || widget.isRange;
    final effectiveMin =
        widget.min ?? (rangeOptions.isNotEmpty ? rangeOptions.reduce((a, b) => a < b ? a : b) : null);
    final effectiveMax =
        widget.max ?? (rangeOptions.isNotEmpty ? rangeOptions.reduce((a, b) => a > b ? a : b) : null);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 50,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 20),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[700] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.handshake_outlined, color: primaryColor, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Artisan Response',
                          style: theme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: isSmallScreen ? 16.0 : 18.0,
                          ),
                        ),
                        Text(
                          widget.artisanName,
                          style: theme.bodySmall?.copyWith(
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Quotation Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[900] : Colors.grey[50],
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.price_check, color: primaryColor, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Quotation',
                                style: theme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontSize: isSmallScreen ? 14.0 : 16.0,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (widget.isFixed)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _borderColor()),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.currency_rupee, color: primaryColor, size: 20),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      widget.fixedQuote != null && widget.fixedQuote!.isNotEmpty
                                          ? '₦${widget.fixedQuote}'
                                          : 'Amount not specified',
                                      style: theme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: widget.fixedQuote != null && widget.fixedQuote!.isNotEmpty ? primaryColor : Colors.grey,
                                        fontSize: isSmallScreen ? 18.0 : 20.0,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else if (widget.isRange)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.surface,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: _borderColor()),
                                    ),
                                    child: Row(
                                      children: [
                                        Text(
                                          '₦',
                                          style: theme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: primaryColor,
                                            fontSize: isSmallScreen ? 18.0 : 20.0,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            effectiveMin != null && effectiveMax != null
                                                ? '$effectiveMin - $effectiveMax'
                                                : 'Price range available',
                                            style: theme.titleMedium?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: effectiveMin != null && effectiveMax != null
                                                  ? primaryColor
                                                  : Colors.grey,
                                              fontSize: isSmallScreen ? 18.0 : 20.0,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (rangeOptions.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    'Available prices',
                                    style: theme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? Colors.grey[400] : Colors.grey[700],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: rangeOptions.map((option) {
                                      final isSelected = _selectedRangePrice == option;
                                      return ChoiceChip(
                                        label: Text('₦$option'),
                                        selected: isSelected,
                                        onSelected: (_) {
                                          setState(() => _selectedRangePrice = option);
                                        },
                                        selectedColor: primaryColor.withOpacity(0.15),
                                        labelStyle: TextStyle(
                                          color: isSelected ? primaryColor : null,
                                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                        ),
                                        side: BorderSide(
                                          color: isSelected ? primaryColor : _borderColor(),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ],
                            ),
                          if (!hasPricing) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _borderColor()),
                              ),
                              child: Text(
                                'No price was included in this response.',
                                style: theme.bodyMedium?.copyWith(
                                  color: isDark ? Colors.grey[400] : Colors.grey[700],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Message Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[900] : Colors.grey[50],
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.message_outlined, color: primaryColor, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Message',
                                style: theme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontSize: isSmallScreen ? 14.0 : 16.0,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _borderColor()),
                            ),
                            child: Text(
                              widget.message,
                              style: theme.bodyMedium?.copyWith(height: 1.5),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // Action Buttons
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                border: Border(top: BorderSide(color: _borderColor(), width: 1)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.onCancel,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Cancel Request'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: hasPricing ? () {
                        int? selectedPrice;
                        bool isValid = false;

                        if (widget.isFixed && widget.fixedQuote != null && widget.fixedQuote!.isNotEmpty) {
                          selectedPrice = int.tryParse(widget.fixedQuote!);
                          isValid = selectedPrice != null;
                        } else if (widget.isRange) {
                          selectedPrice = _selectedRangePrice ?? effectiveMax;
                          isValid = selectedPrice != null;
                        }

                        if (!isValid) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                hasPricing
                                    ? 'Please select a valid price'
                                    : 'This response has no quote to pay for yet',
                              ),
                            ),
                          );
                          return;
                        }

                        widget.onAgreeAndPay(selectedPrice);
                      } : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Agree & Pay'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Artisan Response Form Component
class _ArtisanResponseForm extends StatefulWidget {
  final String requestId;
  final Color primaryColor;
  final Function(Map<String, dynamic>) onSuccess;

  const _ArtisanResponseForm({
    required this.requestId,
    required this.primaryColor,
    required this.onSuccess,
  });

  @override
  State<_ArtisanResponseForm> createState() => _ArtisanResponseFormState();
}

class _ArtisanResponseFormState extends State<_ArtisanResponseForm> {
  final TextEditingController _fixedPriceController = TextEditingController();
  final TextEditingController _minPriceController = TextEditingController();
  final TextEditingController _maxPriceController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  String? _selectedBudgetModel;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _fixedPriceController.dispose();
    _minPriceController.dispose();
    _maxPriceController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submitResponse() async {
    if (_selectedBudgetModel == null) {
      AppNotification.showError(context, 'Please select a budget model');
      return;
    }

    if (_selectedBudgetModel == 'fixed') {
      final price = _fixedPriceController.text.trim();
      if (price.isEmpty || int.tryParse(price) == null) {
        AppNotification.showError(context, 'Please enter a valid price');
        return;
      }
    }

    if (_selectedBudgetModel == 'range') {
      final min = int.tryParse(_minPriceController.text.trim());
      final max = int.tryParse(_maxPriceController.text.trim());
      if (min == null || max == null || min >= max) {
        AppNotification.showError(context, 'Please enter a valid price range');
        return;
      }
    }

    final message = _messageController.text.trim();
    if (message.isEmpty) {
      AppNotification.showError(context, 'Please enter a message');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final Map<String, dynamic> noteData = {'message': message};
      final Map<String, dynamic> artisanReply = {'message': message};

      if (_selectedBudgetModel == 'fixed') {
        final quote = int.parse(_fixedPriceController.text.trim());
        noteData['quote'] = quote;
        noteData['quoteType'] = 'fixed';
        artisanReply['quote'] = quote;
        artisanReply['quoteType'] = 'fixed';
      } else if (_selectedBudgetModel == 'range') {
        final min = int.parse(_minPriceController.text.trim());
        final max = int.parse(_maxPriceController.text.trim());
        noteData['min'] = min;
        noteData['max'] = max;
        noteData['quoteType'] = 'range';
        artisanReply['min'] = min;
        artisanReply['max'] = max;
        artisanReply['minQuote'] = min;
        artisanReply['maxQuote'] = max;
        artisanReply['quoteType'] = 'range';
      }

      final Map<String, dynamic> data = {
        'status': 'responded',
        'note': noteData,
        'artisanReply': artisanReply,
      };

      final response = await SpecialServiceRequestService.submitArtisanResponse(widget.requestId, data);
      if (response != null && mounted) {
        widget.onSuccess(response);
        Navigator.of(context).pop();
        AppNotification.showSuccess(context, 'Response submitted successfully');
      } else {
        AppNotification.showError(context, 'Failed to submit response');
      }
    } catch (e) {
      AppNotification.showError(context, 'Error submitting response');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 375;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 50,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[700] : Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: widget.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.rate_review_outlined, color: widget.primaryColor, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Submit Response',
                          style: theme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: isSmallScreen ? 20.0 : 24.0,
                          ),
                        ),
                        Text(
                          'Provide quotation and details',
                          style: theme.bodySmall?.copyWith(
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Budget Model Dropdown
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[900] : Colors.grey[50],
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.attach_money, color: widget.primaryColor, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Budget Model',
                          style: theme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: isSmallScreen ? 14.0 : 16.0,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _selectedBudgetModel,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        filled: true,
                        fillColor: Theme.of(context).scaffoldBackgroundColor,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'fixed', child: Text('Fixed Price')),
                        DropdownMenuItem(value: 'range', child: Text('Price Range')),
                      ],
                      onChanged: (value) => setState(() => _selectedBudgetModel = value),
                      hint: const Text('Select budget model'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Price Input
              if (_selectedBudgetModel == 'fixed')
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[900] : Colors.grey[50],
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.price_check, color: widget.primaryColor, size: 20),
                          const SizedBox(width: 8),
                          Text('Fixed Price', style: theme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _fixedPriceController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: 'e.g., 50000',
                          prefixText: '₦ ',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          filled: true,
                          fillColor: Theme.of(context).scaffoldBackgroundColor,
                        ),
                      ),
                    ],
                  ),
                )
              else if (_selectedBudgetModel == 'range')
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[900] : Colors.grey[50],
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.price_check, color: widget.primaryColor, size: 20),
                          const SizedBox(width: 8),
                          Text('Price Range', style: theme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _minPriceController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                hintText: 'Min',
                                prefixText: '₦ ',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                filled: true,
                                fillColor: Theme.of(context).scaffoldBackgroundColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _maxPriceController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                hintText: 'Max',
                                prefixText: '₦ ',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                filled: true,
                                fillColor: Theme.of(context).scaffoldBackgroundColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: widget.primaryColor.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: widget.primaryColor.withOpacity(0.2)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: widget.primaryColor, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Client will select a price within this range',
                                style: theme.bodySmall?.copyWith(color: widget.primaryColor, fontSize: 12.0),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 16),

              // Message
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[900] : Colors.grey[50],
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.message_outlined, color: widget.primaryColor, size: 20),
                        const SizedBox(width: 8),
                        Text('Message / Notes', style: theme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text('Required', style: theme.bodySmall?.copyWith(color: Colors.red, fontWeight: FontWeight.w600, fontSize: 11.0)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _messageController,
                      maxLines: 4,
                      minLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Describe your approach, timeline, and any additional information...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        filled: true,
                        fillColor: Theme.of(context).scaffoldBackgroundColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 12 : 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: widget.primaryColor, width: 1.5),
                      ),
                      child: Text('Cancel', style: TextStyle(color: widget.primaryColor, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submitResponse,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.primaryColor,
                        padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 12 : 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isSubmitting
                          ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Submit Response'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// Image Viewer Modal
class _ImageViewerModal extends StatelessWidget {
  final String imageUrl;

  const _ImageViewerModal({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 800, maxHeight: 600),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Center(
                child: Icon(Icons.broken_image, color: Colors.grey[800], size: 48),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
