import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../services/token_storage.dart';
import '../../services/user_service.dart';
import '../../services/artist_service.dart';
import '../../api_config.dart';
import '../../services/notification_service.dart';
import '../../utils/app_notification.dart';
import '../../state/app_state_notifier.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '../message_client/message_client_widget.dart';
import '../artisan_detail_page/artisan_detail_page_widget.dart';
import '../search_page/search_page_widget.dart';
import '../booking_details/booking_details_widget.dart';
import 'booking_page_model.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '/main.dart';
import '../../utils/navigation_utils.dart';
import 'dart:math' as math;
export 'booking_page_model.dart';

class BookingPageWidget extends StatefulWidget {
  final String? bookingId;
  final String? threadId;
  const BookingPageWidget({super.key, this.bookingId, this.threadId});

  static String routeName = 'BookingPage';
  static String routePath = '/bookingPage';

  @override
  State<BookingPageWidget> createState() => _BookingPageWidgetState();
}

class _BookingPageWidgetState extends State<BookingPageWidget> {
  late BookingPageModel _model;
  final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();

  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _bookings = [];

  bool _loadingBookings = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  final int _limit = 12;
  String _searchQuery = '';
  Timer? _searchDebounce;
  Timer? _autoRefreshTimer;

  String? _participantId;
  bool _isArtisan = false;
  // Optional initial IDs passed when navigating to this page (e.g., from payment flow)
  String? _initialBookingId;
  String? _initialThreadId;

  final Map<String, Map<String, dynamic>> _userCache = {};
  final int _userCacheMax = 300;
  // Track per-booking action loading (accept/reject/complete) to prevent duplicate taps
  final Map<String, bool> _actionLoading = {};

  // Track per-booking thread-fetching state to avoid duplicate fetches when user taps Message
  final Map<String, bool> _fetchingThread = {};

  bool _isActionLoading(String id) => _actionLoading[id] == true;
  void _setActionLoading(String id, bool v) { if (mounted) setState(() { if (v) _actionLoading[id] = true; else _actionLoading.remove(id); }); }
  bool _isFetchingThread(String? id) => id != null && id.isNotEmpty && _fetchingThread[id] == true;
  void _setFetchingThread(String id, bool v) { if (mounted) setState(() { if (v) _fetchingThread[id] = true; else _fetchingThread.remove(id); }); }

  // Fetch the threadId for a booking using the API: GET /api/chat/booking/:bookingId
  Future<String?> _fetchThreadIdForBooking(String bookingId) async {
    try {
      final token = await TokenStorage.getToken();
      if (token == null || token.isEmpty) return null;
      final headers = <String, String>{'Content-Type': 'application/json', 'Authorization': 'Bearer $token'};
      final uri = Uri.parse('$API_BASE_URL/api/chat/booking/$bookingId');
      final resp = await http.get(uri, headers: headers).timeout(const Duration(seconds: 12));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        if (kDebugMode) debugPrint('fetchThreadIdForBooking non-2xx ${resp.statusCode} ${resp.body}');
        return null;
      }
      if (resp.body.isEmpty) return null;
      final body = jsonDecode(resp.body);
      final data = body is Map ? (body['data'] ?? body) : body;
      if (data is Map) {
        return (data['threadId']?.toString() ?? data['_id']?.toString());
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('fetchThreadIdForBooking error: $e');
      return null;
    }
  }

  // Helper: extract the artisan map from a booking regardless of shape
  Map<String, dynamic>? _extractArtisanFromBooking(Map<String, dynamic> booking) {
    try {
      if (booking['artisan'] is Map) return Map<String, dynamic>.from(booking['artisan']);
      if (booking['artisanUser'] is Map) return Map<String, dynamic>.from(booking['artisanUser']);
      if (booking['booking'] is Map) {
        final b = booking['booking'] as Map;
        if (b['artisan'] is Map) return Map<String, dynamic>.from(b['artisan']);
        if (b['artisanUser'] is Map) return Map<String, dynamic>.from(b['artisanUser']);
      }
    } catch (_) {}
    return null;
  }

  // Helper: extract a display name from various user shapes
  String _extractNameFromUser(dynamic user) {
    if (user == null) return 'Unknown';
    try {
      if (user is Map) {
        final keys = ['name', 'fullName', 'businessName', 'displayName', 'username'];
        for (final k in keys) {
          final v = user[k];
          if (v is String && v.trim().isNotEmpty) return v.trim();
        }
      }
      if (user is String && user.isNotEmpty) return user;
    } catch (_) {}
    return 'Unknown';
  }

  // New helper: determine if a booking matches the provided lower-cased query
  bool _matchesSearch(Map<String, dynamic> b, String qLower) {
    if (qLower.isEmpty) return true;
    try {
      // Booking id(s)
      final idCandidates = <String?>[
        b['_id']?.toString(),
        b['id']?.toString(),
        (b['booking'] is Map) ? (b['booking']['_id']?.toString() ?? b['booking']['id']?.toString()) : null,
      ];
      for (final c in idCandidates) {
        if (c != null && c.toLowerCase().contains(qLower)) return true;
      }

      // Use the same name-extraction that the BookingCard uses to match displayed name
      try {
        // Artisan display name
        final artisan = _extractArtisanFromBooking(b) ?? <String, dynamic>{};
        final artisanDisplay = _extractNameFromUser(artisan).toLowerCase();
        if (artisanDisplay.contains(qLower)) return true;

        // Customer display name (various shapes)
        dynamic customer;
        try {
          customer = b['customer'] ?? b['customerUser'] ?? (b['booking'] is Map ? b['booking']['customer'] : null);
        } catch (_) { customer = null; }
        final customerDisplay = _extractNameFromUser(customer).toLowerCase();
        if (customerDisplay.contains(qLower)) return true;
      } catch (_) {}

      // Also check common name-like keys anywhere in the booking payload
      final nameKeys = ['name','fullName','full_name','firstName','first_name','lastName','last_name','businessName','displayName','username','company'];
      for (final k in nameKeys) {
        try {
          final v = b[k] ?? (b['booking'] is Map ? b['booking'][k] : null) ?? (b['artisan'] is Map ? b['artisan'][k] : null) ?? (b['customer'] is Map ? b['customer'][k] : null);
          if (v is String && v.toLowerCase().contains(qLower)) return true;
        } catch (_) {}
      }

      // Service / job title
      final titleCandidates = <dynamic>[b['service'], b['title'], b['jobTitle'], (b['booking'] is Map ? b['booking']['service'] : null)];
      for (final t in titleCandidates) {
        if (t != null && t.toString().toLowerCase().contains(qLower)) return true;
      }

      // Price / amount
      try {
        final price = (b['price'] ?? b['booking']?['price'] ?? b['amount'] ?? b['payment']?['amount'])?.toString();
        if (price != null && price.toLowerCase().contains(qLower)) return true;
      } catch (_) {}

      // Thread/chat id
      final thread = (b['threadId'] ?? b['chat']?['_id'])?.toString();
      if (thread != null && thread.toLowerCase().contains(qLower)) return true;

      // Shallow recursive search: look into string values within the map up to a small depth
      bool scanStrings(dynamic node, int depth) {
        if (node == null || depth <= 0) return false;
        if (node is String) return node.toLowerCase().contains(qLower);
        if (node is Map) {
          for (final v in node.values) {
            try { if (scanStrings(v, depth - 1)) return true; } catch (_) {}
          }
        } else if (node is List) {
          for (final e in node) {
            try { if (scanStrings(e, depth - 1)) return true; } catch (_) {}
          }
        }
        return false;
      }

      if (scanStrings(b, 3)) return true;

      // Fuzzy matching: allow subsequence matches and small edit distances so
      // short/typo queries still match visible names. This helps when users
      // type fragments or slightly-misspelled names.
      try {
        String normalize(String s) => s.replaceAll(RegExp(r'\s+'), '').toLowerCase();
        bool fuzzyCheck(String src) {
          // src is non-nullable String
          if (src.isEmpty) return false;
          final t = normalize(src);
          final q = normalize(qLower);
          if (t.contains(q)) return true;
          if (_isSubsequence(q, t)) return true;
          // allow small Levenshtein distance relative to query length
          final dist = _levenshteinDistance(q, t);
          if (dist <= (q.length <= 3 ? 1 : 2)) return true;
          return false;
        }

        // Collect a few representative strings to test fuzzily: names, titles, ids
        final fuzzyCandidates = <String>[];
        try { fuzzyCandidates.addAll(idCandidates.whereType<String>()); } catch (_) {}
        try { fuzzyCandidates.add(_extractNameFromUser(_extractArtisanFromBooking(b) ?? <String,dynamic>{})); } catch (_) {}
        try { fuzzyCandidates.add(_extractNameFromUser(b['customer'] ?? b['customerUser'] ?? (b['booking'] is Map ? b['booking']['customer'] : null))); } catch (_) {}
        try { fuzzyCandidates.addAll(titleCandidates.where((t) => t != null).map((t) => t.toString())); } catch (_) {}
        try { final p = (b['price'] ?? b['booking']?['price'] ?? b['amount'] ?? b['payment']?['amount']); if (p != null) fuzzyCandidates.add(p.toString()); } catch (_) {}

        for (final c in fuzzyCandidates) {
          try {
            if (fuzzyCheck(c)) return true;
          } catch (_) {}
        }
      } catch (_) {}
    } catch (_) {}
    return false;
  }

  // Helper: checks whether s is a subsequence of t (characters in order, not necessarily contiguous)
  bool _isSubsequence(String s, String t) {
    if (s.isEmpty) return true;
    var si = 0;
    for (var i = 0; i < t.length && si < s.length; i++) {
      if (t[i] == s[si]) si++;
    }
    return si == s.length;
  }

  // Simple Levenshtein distance implementation
  int _levenshteinDistance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final la = a.length;
    final lb = b.length;
    final prev = List<int>.filled(lb + 1, 0);
    final curr = List<int>.filled(lb + 1, 0);
    for (var j = 0; j <= lb; j++) prev[j] = j;
    for (var i = 1; i <= la; i++) {
      curr[0] = i;
      for (var j = 1; j <= lb; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        curr[j] = math.min(math.min(curr[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
      }
      for (var j = 0; j <= lb; j++) prev[j] = curr[j];
    }
    return prev[lb];
  }

  @override
  void initState() {
    super.initState();
    _initialBookingId = widget.bookingId;
    _initialThreadId = widget.threadId;
    _model = createModel(context, () => BookingPageModel());
    _model.textController ??= TextEditingController();
    _model.textFieldFocusNode ??= FocusNode();

    _loadProfileAndBookings();

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200 &&
          !_loadingMore &&
          _hasMore &&
          !_loadingBookings) {
        _fetchMore();
      }
    });

    _model.textController?.addListener(() {
      final q = _model.textController?.text ?? '';
      if (_searchDebounce?.isActive ?? false) _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 450), () {
        if (!mounted) return;
        setState(() {
          _searchQuery = q.trim();
          _page = 1;
          _hasMore = true;
          _bookings.clear();
          _loadingBookings = true;
        });
        _fetchBookings(reset: true);
      });
    });

    // Start an automatic refresh timer to reload bookings every 5 seconds so
    // the UI reflects new bookings or status changes without manual pull-to-refresh.
    // We schedule it after a small delay to avoid hammering the API immediately on page open.
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 5), (t) async {
      try {
        if (!mounted) return;
        // Only run a background refresh when not already loading to avoid concurrent requests
        if (_loadingBookings || _loadingMore) return;
        await _fetchBookingsInBackground();
      } catch (e) {
        if (kDebugMode) debugPrint('Auto-refresh error: $e');
      }
    });
  }

  Future<void> _loadProfileAndBookings() async {
    try {
      final profile = await UserService.getProfile();
      final pid = profile?['_id']?.toString() ?? profile?['id']?.toString();
      final role = (profile?['role'] ?? '').toString().toLowerCase();
      _isArtisan = role.contains('artisan');
      _participantId = pid;
    } catch (_) {
      _participantId = null;
      _isArtisan = false;
    }

    await _fetchBookings(reset: true);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _autoRefreshTimer?.cancel();
    _scrollController.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _fetchBookings({bool reset = false}) async {
    if (!_hasMore && !reset) return;
    if (reset) {
      _page = 1;
      _hasMore = true;
      _bookings.clear();
      if (mounted) setState(() => _loadingBookings = true);
    } else {
      if (mounted) setState(() => _loadingMore = true);
    }

    try {
      final token = await TokenStorage.getToken();
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';

      final pid = _participantId;
      if (pid == null || pid.isEmpty) {
        if (mounted) setState(() { _loadingBookings = false; _loadingMore = false; _hasMore = false; });
        return;
      }

      final qParam = _searchQuery.isNotEmpty ? '&q=${Uri.encodeComponent(_searchQuery)}' : '';
      // If searching by name, request a larger limit so we can filter client-side.
      final effectiveLimit = _searchQuery.isNotEmpty ? 1000 : _limit;
      final url = _isArtisan
          ? '$API_BASE_URL/api/bookings/artisan/$pid?page=$_page&limit=$effectiveLimit$qParam'
          : '$API_BASE_URL/api/bookings/customer/$pid?page=$_page&limit=$effectiveLimit$qParam';

      final response = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 8));
      if (response.statusCode >= 200 && response.statusCode < 300 && response.body.isNotEmpty) {
        final decoded = jsonDecode(response.body);
        dynamic data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
        List items = [];
        if (data is List) items = data;
        else if (data is Map && data['items'] is List) items = data['items'];
        else if (data is Map && data['bookings'] is List) items = data['bookings'];

        final processed = items.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();

        // If there's a search query, filter bookings by various fields locally.
        List<Map<String, dynamic>> filtered = processed;
        if (_searchQuery.isNotEmpty) {
          final qLower = _searchQuery.toLowerCase();
          filtered = processed.where((b) => _matchesSearch(Map<String,dynamic>.from(b), qLower)).toList();
        }

        if (mounted) {
          setState(() {
            if (_page == 1) _bookings.clear();
            _bookings.addAll(filtered);
            // hasMore should be based on the effective limit we requested
            _hasMore = filtered.length == effectiveLimit;
            if (_hasMore) _page++;
            _loadingBookings = false;
            _loadingMore = false;
          });
        }

        // Debugging aid: when a search query returns no client-side matches,
        // log a short report showing what fields were inspected for the first
        // few fetched bookings so developers can see why the visible name
        // didn't match the query.
        try {
          if (kDebugMode && _searchQuery.isNotEmpty && filtered.isEmpty && processed.isNotEmpty) {
            final qLower = _searchQuery.toLowerCase();
            final maxSamples = processed.length < 10 ? processed.length : 10;
            debugPrint('🔎 Booking search debug: query="${_searchQuery}" — no client-side matches found. Showing up to $maxSamples inspected items:');
            for (var i = 0; i < maxSamples; i++) {
              try {
                final item = Map<String, dynamic>.from(processed[i]);
                final id = (_extractBookingId(item) ?? item['_id']?.toString() ?? item['id']?.toString()) ?? '<no-id>';
                final artisan = _extractArtisanFromBooking(item) ?? <String, dynamic>{};
                final artisanName = _extractNameFromUser(artisan);
                final customer = item['customer'] ?? item['customerUser'] ?? (item['booking'] is Map ? item['booking']['customer'] : null);
                final customerName = _extractNameFromUser(customer);
                final matchedPaths = _findMatchingPaths(item, qLower, depth: 3);
                if (matchedPaths.isEmpty) {
                  debugPrint('  - id=$id artisan="$artisanName" customer="$customerName" -> no string field contained the query');
                } else {
                  debugPrint('  - id=$id artisan="$artisanName" customer="$customerName" -> matched at: ${matchedPaths.join(', ')}');
                }
              } catch (e) {
                debugPrint('  - error inspecting processed[$i]: $e');
              }
            }
          }
        } catch (_) {}
      } else {
        if (mounted) setState(() { _loadingBookings = false; _loadingMore = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _loadingBookings = false; _loadingMore = false; });
    }
  }

  // Background fetch that updates the bookings list without toggling
  // the visible loading indicators. Use this for silent periodic refreshes
  // so the UI doesn't show a spinner or skeleton while new data is pulled.
  Future<void> _fetchBookingsInBackground() async {
    try {
      // Prevent overlapping background fetches
      if (!_hasMore && _page > 1 && (_searchQuery.isEmpty)) {
        // still attempt a short fetch if desired, but avoid frequent calls when no more pages
      }

      final token = await TokenStorage.getToken();
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';

      final pid = _participantId;
      if (pid == null || pid.isEmpty) return;

      final qParam = _searchQuery.isNotEmpty ? '&q=${Uri.encodeComponent(_searchQuery)}' : '';
      // Request enough items to cover the currently visible pages to avoid truncation.
      final effectiveLimit = _searchQuery.isNotEmpty ? 1000 : (_page * _limit);
      final url = _isArtisan
          ? '$API_BASE_URL/api/bookings/artisan/$pid?page=1&limit=$effectiveLimit$qParam'
          : '$API_BASE_URL/api/bookings/customer/$pid?page=1&limit=$effectiveLimit$qParam';

      final response = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 8));
      if (response.statusCode >= 200 && response.statusCode < 300 && response.body.isNotEmpty) {
        final decoded = jsonDecode(response.body);
        dynamic data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
        List items = [];
        if (data is List) items = data;
        else if (data is Map && data['items'] is List) items = data['items'];
        else if (data is Map && data['bookings'] is List) items = data['bookings'];

        final processed = items.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();

        // If there's a search query, filter bookings by various fields locally.
        List<Map<String, dynamic>> filtered = processed;
        if (_searchQuery.isNotEmpty) {
          final qLower = _searchQuery.toLowerCase();
          filtered = processed.where((b) => _matchesSearch(Map<String,dynamic>.from(b), qLower)).toList();
        }

        if (!mounted) return;
        // Update the list silently: replace items but don't flip loading flags.
        setState(() {
          // Keep paging state but refresh the data shown to the user.
          _bookings.clear();
          _bookings.addAll(filtered);
          // Update hasMore conservatively based on fetched size
          _hasMore = filtered.length == effectiveLimit;
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Background fetch error: $e');
    }
  }

  Future<void> _fetchMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    await _fetchBookings(reset: false);
  }

  Future<Map<String,dynamic>?> _fetchUserById(String userId) async {
    try {
      final token = await TokenStorage.getToken();
      final headers = <String,String>{'Content-Type':'application/json'};
      if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
      final url = '$API_BASE_URL/api/users/$userId';
      final res = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds:6));
      if (res.statusCode >=200 && res.statusCode <300 && res.body.isNotEmpty) {
        final d = jsonDecode(res.body);
        if (d is Map) {
          if (d['data'] is Map) return Map<String,dynamic>.from(d['data']);
          if (d['user'] is Map) return Map<String,dynamic>.from(d['user']);
          if (d['profile'] is Map) return Map<String,dynamic>.from(d['profile']);
          return Map<String,dynamic>.from(d);
        }
      }
    } catch (_) {}
    return null;
  }

  void _onProfileTap(BuildContext context, Map<String,dynamic> booking) async {
    // Determine counterpart (customer when current user is artisan, else artisan)
    final bool isArtisan = _isArtisan;
    Map<String,dynamic>? inlineUser;
    String? id;

    if (isArtisan) {
      inlineUser = booking['customer'] is Map ? Map<String,dynamic>.from(booking['customer']) : (booking['customerUser'] is Map ? Map<String,dynamic>.from(booking['customerUser']) : null);
      id = booking['customerId']?.toString() ?? booking['customer']?['_id']?.toString() ?? booking['booking']?['customerId']?.toString();
    } else {
      inlineUser = booking['artisan'] is Map ? Map<String,dynamic>.from(booking['artisan']) : (booking['artisanUser'] is Map ? Map<String,dynamic>.from(booking['artisanUser']) : null);
      id = booking['artisanId']?.toString() ?? booking['artisan']?['_id']?.toString() ?? booking['booking']?['artisanId']?.toString();
    }

    Map<String,dynamic>? user;
    if (id != null && id.isNotEmpty) {
      user = _userCache[id] ?? await _fetchUserById(id);
      if (user != null) {
        // maintain cache size
        _userCache[id] = user;
        if (_userCache.length > _userCacheMax) {
          _userCache.remove(_userCache.keys.first);
        }
      }
    }
    user ??= inlineUser;

    // Try to find a richer artisan profile in the booking payload first.
    Map<String, dynamic>? artisanProfile;
    try {
      final candidates = [
        booking['artisanProfile'],
        booking['artisan_profile'],
        booking['artisanProfile'] ?? booking['artisan_profile'],
        booking['booking'] is Map ? (booking['booking']['artisanProfile'] ?? booking['booking']['artisan']) : null,
        booking['artisan'],
        booking['artisanUser'],
      ];
      for (final c in candidates) {
        if (c is Map) { artisanProfile = Map<String,dynamic>.from(c); break; }
      }
    } catch (_) {}

    // If we don't have a full artisan profile yet and we have an id, try ArtistService.getByUserId
    if (artisanProfile == null && id != null && id.isNotEmpty) {
      try {
        final fetched = await ArtistService.getByUserId(id);
        if (fetched != null) artisanProfile = fetched;
      } catch (_) {}
    }

    // If we have both an artisanProfile and a user map, merge missing user fields into artisanProfile
    try {
      if (artisanProfile != null && user != null) {
        final mergeKeys = ['name', 'fullName', 'email', 'phone', 'profileImage', 'avatar', 'photo', 'location', 'city', 'rating', 'avgRating', 'portfolio', 'pricing', 'pricingDetails'];
        for (final k in mergeKeys) {
          try {
            if ((artisanProfile[k] == null || (artisanProfile[k] is String && (artisanProfile[k] as String).trim().isEmpty)) && user[k] != null) {
              artisanProfile[k] = user[k];
            }
          } catch (_) {}
        }
        if (artisanProfile['user'] == null) artisanProfile['user'] = user;
        if ((artisanProfile['userId'] == null || artisanProfile['userId'].toString().isEmpty) && user['_id'] != null) artisanProfile['userId'] = user['_id'].toString();
        if ((artisanProfile['_id'] == null || artisanProfile['_id'].toString().isEmpty) && user['_id'] != null) artisanProfile['_id'] = user['_id'].toString();
      }
    } catch (_) {}

    final payload = artisanProfile ?? user;

    if (payload != null) {
      try {
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ArtisanDetailPageWidget(artisan: Map<String,dynamic>.from(payload))),
        );
      } catch (_) {}
    }
  }

  Future<void> _acceptBooking(Map<String,dynamic> booking) async {
    final id = booking['_id']?.toString() ?? booking['booking']?['_id']?.toString() ?? booking['id']?.toString();
    if (id == null || id.isEmpty) return;
    // Validate booking is in awaiting-acceptance state before calling accept
    final st = (booking['booking']?['status'] ?? booking['status'] ?? '').toString().toLowerCase();
    final paymentStatus = (booking['booking']?['paymentStatus'] ?? booking['paymentStatus'] ?? '').toString().toLowerCase();
    if (!st.contains('awaiting')) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cannot accept booking: status is "$st"')));
      return;
    }
    if (paymentStatus.isNotEmpty && paymentStatus != 'paid') {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cannot accept booking: paymentStatus is "$paymentStatus"')));
      return;
    }
    if (_isActionLoading(id)) return;
    _setActionLoading(id, true);
    final index = _bookings.indexWhere((b) => (b['_id']?.toString() ?? b['booking']?['_id']?.toString() ?? b['id']?.toString()) == id);
    // optimistic UI: set loading on that booking (optional)
    try {
      final token = await TokenStorage.getToken();
      final headers = <String,String>{'Content-Type':'application/json'};
      if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
      debugPrint('Accept booking -> id=$id status=$st paymentStatus=$paymentStatus url=$API_BASE_URL/api/bookings/$id/accept');
      final url = '$API_BASE_URL/api/bookings/$id/accept';
      final res = await http.post(Uri.parse(url), headers: headers, body: jsonEncode({})).timeout(const Duration(seconds:8));
      if (res.statusCode >=200 && res.statusCode <300) {
        dynamic d;
        if (res.body.isNotEmpty) d = jsonDecode(res.body);
        Map<String,dynamic>? updated;
        if (d is Map) {
          updated = (d['data'] is Map) ? Map<String,dynamic>.from(d['data']) : (d['booking'] is Map ? Map<String,dynamic>.from(d['booking']) : Map<String,dynamic>.from(d));
        }
        setState(() {
          if (index != -1) {
            if (updated != null) _bookings[index] = updated;
            else _bookings[index]['booking'] = {...?_bookings[index]['booking'], 'status': 'accepted'};
          }
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Booking accepted')));

        // Notify both artisan and client about the accepted booking
        try {
          final bookingId = booking['_id']?.toString();
          final userId = _isArtisan ? booking['customerId']?.toString() : booking['artisanId']?.toString();
          final title = 'Booking Accepted';
          final body = _isArtisan ? 'Your booking has been accepted.' : 'The artisan has accepted your booking.';
          final payload = {'bookingId': bookingId, 'status': 'accepted'};
          final sent = await NotificationService.sendNotification(userId, title, body, payload: payload);
          if (sent && mounted) {
            try {
              final cnt = await NotificationService.fetchUnreadCount();
              try { AppStateNotifier.instance.setUnreadNotifications(cnt); } catch (_) {}
            } catch (_) {}
          }
          // show a local ephemeral toast to the user
          AppNotification.showSuccess(context, body);
        } catch (e) {
          debugPrint('Error sending notification: $e');
        }
      } else {
        debugPrint('Accept booking failed: status=${res.statusCode} body=${res.body}');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to accept booking (${res.statusCode}) ${res.body.isNotEmpty ? '- ${res.body}' : ''}')));
        await _showApiErrorDetails(url, headers, res, id);
      }
    } catch (e, st) {
      debugPrint('Accept booking error: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Network error while accepting booking')));
    } finally {
      _setActionLoading(id, false);
    }
  }

  Future<void> _rejectBooking(Map<String,dynamic> booking) async {
    final id = booking['_id']?.toString() ?? booking['booking']?['_id']?.toString() ?? booking['id']?.toString();
    if (id == null || id.isEmpty) return;
    final st = (booking['booking']?['status'] ?? booking['status'] ?? '').toString().toLowerCase();
    if (!st.contains('awaiting')) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cannot reject booking: status is "$st"')));
      return;
    }
    if (_isActionLoading(id)) return;
    _setActionLoading(id, true);
    final index = _bookings.indexWhere((b) => (b['_id']?.toString() ?? b['booking']?['_id']?.toString() ?? b['id']?.toString()) == id);
    try {
      final token = await TokenStorage.getToken();
      final headers = <String,String>{'Content-Type':'application/json'};
      if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
      debugPrint('Reject booking -> id=$id status=$st url=$API_BASE_URL/api/bookings/$id/reject');
      final url = '$API_BASE_URL/api/bookings/$id/reject';
      final bodyMap = {'reason': 'Rejected by artisan'};
      final res = await http.post(Uri.parse(url), headers: headers, body: jsonEncode(bodyMap)).timeout(const Duration(seconds:8));
      if (res.statusCode >=200 && res.statusCode <300) {
        dynamic d;
        if (res.body.isNotEmpty) d = jsonDecode(res.body);
        Map<String,dynamic>? updated;
        if (d is Map) {
          updated = (d['data'] is Map) ? Map<String,dynamic>.from(d['data']) : (d['booking'] is Map ? Map<String,dynamic>.from(d['booking']) : Map<String,dynamic>.from(d));
        }
        setState(() {
          if (index != -1) {
            if (updated != null) _bookings[index] = updated;
            else {
              _bookings[index]['booking'] = {...?_bookings[index]['booking'], 'status': 'cancelled', 'refundStatus': 'refunded'};
            }
          }
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Booking rejected. Refund will be processed.')));

        // Notify both artisan and client about the rejected booking
        try {
          final bookingId = booking['_id']?.toString();
          final userId = _isArtisan ? booking['customerId']?.toString() : booking['artisanId']?.toString();
          final title = 'Booking Rejected';
          final body = _isArtisan ? 'Your booking has been rejected.' : 'The artisan has rejected your booking.';
          final payload = {'bookingId': bookingId, 'status': 'rejected'};
          final sent = await NotificationService.sendNotification(userId, title, body, payload: payload);
          if (sent && mounted) {
            try {
              final cnt = await NotificationService.fetchUnreadCount();
              try { AppStateNotifier.instance.setUnreadNotifications(cnt); } catch (_) {}
            } catch (_) {}
          }
          // show a local ephemeral toast to the user
          AppNotification.showSuccess(context, body);
        } catch (e) {
          debugPrint('Error sending notification: $e');
        }

        // If current user is the customer, suggest other artisans
        if (!mounted) return;
        if (!(_isArtisan)) {
          final jobQ = _extractJobTitle(booking);
          showDialog(context: context, builder: (ctx) {
            return AlertDialog(
              title: const Text('Booking rejected'),
              content: Text('The artisan has rejected this booking. We will refund you automatically. Would you like to find other artisans for this job?'),
              actions: [
                TextButton(onPressed: () { Navigator.of(ctx).pop(); }, child: const Text('Close')),
                ElevatedButton(onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => SearchPageWidget(initialQuery: jobQ.isNotEmpty ? jobQ : null)));
                }, child: const Text('Find artisans')),
              ],
            );
          });
        }
      } else {
        debugPrint('Reject booking failed: status=${res.statusCode} body=${res.body}');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to reject booking (${res.statusCode}) ${res.body.isNotEmpty ? '- ${res.body}' : ''}')));
        await _showApiErrorDetails(url, headers, res, id);
      }
    } catch (e, st) {
      debugPrint('Reject booking error: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Network error while rejecting booking')));
    } finally {
      _setActionLoading(id, false);
    }
  }

  Future<void> _cancelBooking(Map<String,dynamic> booking) async {
    final id = booking['_id']?.toString() ?? booking['booking']?['_id']?.toString() ?? booking['id']?.toString();
    if (id == null || id.isEmpty) return;
    final st = (booking['booking']?['status'] ?? booking['status'] ?? '').toString().toLowerCase();
    // Only allow cancel when booking is awaiting artisan acceptance or still pending
    if (!(st.startsWith('await') || st == 'pending' || st.contains('awaiting'))) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cannot cancel booking: status is "$st"')));
      return;
    }
    if (_isActionLoading(id)) return;
    final confirm = await showDialog<bool>(context: context, builder: (ctx) {
      return AlertDialog(
        title: const Text('Cancel booking'),
        content: const Text('Are you sure you want to cancel this booking? You will be refunded if payment was made.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('No')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Yes, cancel')),
        ],
      );
    });
    if (confirm != true) return;
    _setActionLoading(id, true);
    final index = _bookings.indexWhere((b) => (b['_id']?.toString() ?? b['booking']?['_id']?.toString() ?? b['id']?.toString()) == id);
    try {
      final token = await TokenStorage.getToken();
      final headers = <String,String>{'Content-Type':'application/json'};
      if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
      final url = '$API_BASE_URL/api/bookings/$id';
      if (kDebugMode) debugPrint('Cancel booking -> DELETE $url');
      // Try first without Content-Type so server won't attempt to parse an empty JSON body.
      final headersNoContent = Map<String, String>.from(headers);
      headersNoContent.remove('Content-Type');
      http.Response res;
      try {
        res = await http.delete(Uri.parse(url), headers: headersNoContent).timeout(const Duration(seconds:8));
      } catch (e) {
        // network error when trying without content-type: fallback to sending empty JSON too
        if (kDebugMode) debugPrint('DELETE without Content-Type failed: $e; will retry with empty JSON body');
        res = await http.delete(Uri.parse(url), headers: headers, body: jsonEncode({})).timeout(const Duration(seconds:8));
      }
      // If server rejects because content-type was set but body was empty, retry with an empty JSON body.
      if (res.statusCode == 400 && res.body.isNotEmpty && res.body.contains('FST_ERR_CTP_EMPTY_JSON_BODY')) {
        if (kDebugMode) debugPrint('Server rejected empty JSON body; retrying DELETE with {}');
        res = await http.delete(Uri.parse(url), headers: headers, body: jsonEncode({})).timeout(const Duration(seconds:8));
      }
      if (res.statusCode >=200 && res.statusCode <300) {
        dynamic d;
        if (res.body.isNotEmpty) d = jsonDecode(res.body);
        Map<String,dynamic>? updated;
        if (d is Map) {
          updated = (d['data'] is Map) ? Map<String,dynamic>.from(d['data']) : (d['booking'] is Map ? Map<String,dynamic>.from(d['booking']) : Map<String,dynamic>.from(d));
        }
        setState(() {
          if (index != -1) {
            if (updated != null) _bookings[index] = updated;
            else _bookings[index]['booking'] = {...?_bookings[index]['booking'], 'status': 'cancelled', 'refundStatus': 'refunded'};
          }
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Booking cancelled.')));
        try { AppNotification.showSuccess(context, 'Booking cancelled'); } catch (_) {}
      } else {
        // Try to extract a helpful server message from the response body
        String serverMsg = '';
        try {
          if (res.body.isNotEmpty) {
            final parsed = jsonDecode(res.body);
            if (parsed is Map) serverMsg = (parsed['message'] ?? parsed['error'] ?? parsed['detail'] ?? '')?.toString() ?? '';
            else serverMsg = res.body;
          }
        } catch (_) { serverMsg = res.body; }

        // Specific handling: server-side validation attempted to set paymentStatus to 'refunded'
        // which isn't a valid enum. This indicates a backend validation/model issue; surface details.
        if (serverMsg.toLowerCase().contains('paymentstatus') && serverMsg.toLowerCase().contains('is not a valid enum')) {
          // Server attempted to set paymentStatus to 'refunded', which is invalid per schema.
          // Surface a clearer UI state: mark this booking locally as having a cancel request
          // so the user sees their action was attempted and can contact support.
          if (index != -1) {
            try {
              setState(() {
                // keep existing booking shape but add a local flag
                _bookings[index] = {..._bookings[index], 'cancelRequested': true, 'cancelRequestAt': DateTime.now().toUtc().toIso8601String()};
              });
            } catch (_) {}
          }
          if (!mounted) return;
          final display = 'Could not cancel booking automatically — server validation failed. We recorded your cancel request locally.\nReason: ${serverMsg}';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(display), duration: const Duration(seconds:6)));
          // Offer the developer/admin details dialog for debugging
          try { await _showApiErrorDetails(url, headers, res, id); } catch (_) {}
          // Also show an instruction dialog to the user suggesting contacting support
          try {
            showDialog(context: context, builder: (ctx) {
              return AlertDialog(
                title: const Text('Cancel request queued'),
                content: Text('We could not complete the cancellation automatically. The server responded: "${serverMsg}".\n\nWe recorded your cancel request locally — please contact support if you need this processed urgently.'),
                actions: [
                  TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
                ],
              );
            });
          } catch (_) {}
          return;
        }

        // Quick client-side validation: many 400s are due to malformed booking ids
        try {
          final looksLikeObjectId = RegExp(r'^[a-fA-F0-9]{24}\$').hasMatch(id);
          if (!looksLikeObjectId) {
            debugPrint('Cancel booking warning: booking id does not look like a 24-char ObjectId: $id');
          }
        } catch (_) {}

        final display = 'Failed to cancel booking (${res.statusCode})${serverMsg.isNotEmpty ? ' — $serverMsg' : ''}';
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(display)));
        // Show richer API details (response body + booking fetch) to help debug 400 errors
        try { await _showApiErrorDetails(url, headers, res, id); } catch (_) {}
      }
    } catch (e, st) {
      debugPrint('Cancel booking error: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Network error while cancelling booking')));
    } finally {
      _setActionLoading(id, false);
    }
  }

  Future<void> _completeBooking(Map<String,dynamic> booking) async {
    final id = booking['_id']?.toString() ?? booking['booking']?['_id']?.toString() ?? booking['id']?.toString();
    if (id == null || id.isEmpty) return;
    final status = (booking['booking']?['status'] ?? booking['status'] ?? '').toString().toLowerCase();
    final paymentStatus = (booking['booking']?['paymentStatus'] ?? booking['paymentStatus'] ?? '').toString().toLowerCase();
    // Only allow completion for in-progress bookings where payment is already paid
    if (!(status == 'in-progress' || status == 'in_progress' || status == 'inprogress' || status == 'accepted')) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cannot complete booking: status is "$status"')));
      return;
    }
    if (paymentStatus.isNotEmpty && paymentStatus != 'paid') {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cannot complete booking: payment status is "$paymentStatus"')));
      return;
    }
    if (_isActionLoading(id)) return;
    _setActionLoading(id, true);
    final index = _bookings.indexWhere((b) => (b['_id']?.toString() ?? b['booking']?['_id']?.toString() ?? b['id']?.toString()) == id);

    try {
      final token = await TokenStorage.getToken();
      final headers = <String,String>{'Content-Type':'application/json'};
      if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';

      final uri = Uri.parse('$API_BASE_URL/api/bookings/$id/complete');
      final payload = <String, dynamic>{'confirm': true};
      final currStatus = booking['booking']?['status'] ?? booking['status'];
      if (currStatus != null) payload['currentStatus'] = currStatus;

      if (kDebugMode) debugPrint('Complete booking -> POST $uri payload=$payload');
      final resp = await http.post(uri, headers: headers, body: jsonEncode(payload)).timeout(const Duration(seconds: 12));

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        dynamic decoded;
        if (resp.body.isNotEmpty) decoded = jsonDecode(resp.body);
        Map<String,dynamic>? updated;
        if (decoded is Map) {
          updated = (decoded['data'] is Map) ? Map<String,dynamic>.from(decoded['data']) : (decoded['booking'] is Map ? Map<String,dynamic>.from(decoded['booking']) : null);
        }
        setState(() {
          if (index != -1) {
            if (updated != null) _bookings[index] = updated;
            else _bookings[index]['booking'] = {...?_bookings[index]['booking'], 'status': 'completed'};
          }
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Job marked complete.')));

        // Notify other participant
        try {
          final bookingId = id;
          final userId = _isArtisan ? booking['customerId']?.toString() : booking['artisanId']?.toString();
          final title = 'Job completed';
          final body = _isArtisan ? 'The customer marked the job complete.' : 'You marked the job complete. Please rate the artisan.';
          final payloadN = {'bookingId': bookingId, 'status': 'completed'};
          final sent = await NotificationService.sendNotification(userId, title, body, payload: payloadN);
          if (sent && mounted) {
            try {
              final cnt = await NotificationService.fetchUnreadCount();
              try { AppStateNotifier.instance.setUnreadNotifications(cnt); } catch (_) {}
            } catch (_) {}
          }
          AppNotification.showSuccess(context, body);
        } catch (e) {
          debugPrint('Error sending completion notification: $e');
        }

        // Optionally show rating prompt to customer (if they are the customer)
        if (!_isArtisan && mounted) {
          // Simple prompt to navigate to rating flow could be added; we'll show a dialog that offers to rate now or later.
          try {
            final doRate = await showDialog<bool>(context: context, builder: (ctx) {
              return AlertDialog(
                title: const Text('Rate the artisan'),
                content: const Text('Would you like to rate and review the artisan now?'),
                actions: [
                  TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Later')),
                  ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Rate now')),
                ],
              );
            });
            if (doRate == true) {
              // Navigate to booking details or rating UI if available. Attempt BookingDetails if exists.
              try {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookingDetailsWidget(bookingId: id)));
              } catch (_) {}
            }
          } catch (_) {}
        }
      } else {
        String msg = 'Failed to complete booking';
        try {
          final parsed = resp.body.isNotEmpty ? jsonDecode(resp.body) : null;
          if (parsed is Map && (parsed['message'] != null || parsed['error'] != null)) {
            msg = (parsed['message'] ?? parsed['error']).toString();
          } else if (resp.body.isNotEmpty) msg = resp.body;
        } catch (_) {}
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$msg')));
        await _showApiErrorDetails(uri.toString(), headers, resp, id);
      }
    } catch (e, st) {
      debugPrint('Complete booking error: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Network error while completing booking')));
    } finally {
      _setActionLoading(id, false);
    }
  }

  // Debug helper: find paths of string fields that contain the query (case-insensitive)
  List<String> _findMatchingPaths(dynamic node, String qLower, {String path = '', int depth = 3}) {
    final matches = <String>[];
    if (node == null || depth <= 0) return matches;
    try {
      if (node is String) {
        if (node.toLowerCase().contains(qLower)) matches.add(path.isEmpty ? '<value>' : path);
        return matches;
      }
      if (node is Map) {
        for (final entry in node.entries) {
          final key = entry.key?.toString() ?? '<key>';
          final value = entry.value;
          final childPath = path.isEmpty ? key : '$path.$key';
          try {
            if (value is String) {
              if (value.toLowerCase().contains(qLower)) matches.add(childPath);
            } else if (value is num) {
              if (value.toString().toLowerCase().contains(qLower)) matches.add(childPath);
            } else if (value is Map || value is List) {
              matches.addAll(_findMatchingPaths(value, qLower, path: childPath, depth: depth - 1));
            } else {
              // ignore other types
            }
          } catch (_) {}
        }
        return matches;
      }
      if (node is List) {
        for (var i = 0; i < node.length; i++) {
          final v = node[i];
          final childPath = '$path[$i]';
          matches.addAll(_findMatchingPaths(v, qLower, path: childPath, depth: depth - 1));
        }
        return matches;
      }
    } catch (_) {}
    return matches;
  }

  // Helper to display API failure details: response body and latest booking fetch
  Future<void> _showApiErrorDetails(String url, Map<String,String> headers, http.Response res, String bookingId) async {
    try {
      debugPrint('API error for $url: status=${res.statusCode}, body=${res.body}');
      // Try fetching booking details to understand server state
      final detailUrl = '$API_BASE_URL/api/bookings/$bookingId';
      final detailRes = await http.get(Uri.parse(detailUrl), headers: headers).timeout(const Duration(seconds:6));
      final detailBody = detailRes.body.isNotEmpty ? detailRes.body : '<no body>';
      if (!mounted) return;
      showDialog(context: context, builder: (ctx) {
        return AlertDialog(
          title: Text('Server error (${res.statusCode})'),
          content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Request: $url'), const SizedBox(height:8), Text('Response: ${res.body.isNotEmpty ? res.body : '<empty>'}'), const SizedBox(height:12), Text('Booking details fetch: $detailUrl'), const SizedBox(height:8), Text(detailBody)])),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close'))],
        );
      });
    } catch (e, st) {
      debugPrint('Error while fetching API details: $e\n$st');
    }
  }

  // Build a skeleton loader that mimics the bookings list UI
  Widget _buildSkeletonLoader(ThemeData theme, ColorScheme cs) {
    // Show several placeholder cards to indicate loading
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.only(left: 12, right: 12, bottom: MediaQuery.of(context).padding.bottom + kBottomNavigationBarHeight + 24.0),
      itemCount: 5,
      itemBuilder: (c, i) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: _skeletonCard(theme, cs),
        );
      },
    );
  }

  Widget _skeletonCard(ThemeData theme, ColorScheme cs) {
    final base = cs.onSurface.withAlpha(30);
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withAlpha(20), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 50, height: 50, decoration: BoxDecoration(color: base, shape: BoxShape.circle)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(height: 14, width: double.infinity, decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(6))),
                    const SizedBox(height: 8),
                    Container(height: 12, width: 150, decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(6))),
                  ]),
                ),
                const SizedBox(width: 8),
                Container(height: 18, width: 64, decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(8))),
              ],
            ),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(height: 10, width: 80, decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(6))),
                const SizedBox(height: 8),
                Container(height: 12, width: 120, decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(6))),
              ]),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Container(height: 10, width: 60, decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(6))),
                const SizedBox(height: 8),
                Container(height: 12, width: 80, decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(6))),
              ])
            ]),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: Container(height: 40, decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(12)))),
              const SizedBox(width: 12),
              Container(width: 40, height: 40, decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(12))),
            ])
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // If this page isn't hosted inside NavBarPage, redirect to NavBarPage so the
    // bottom navigation is always shown. Schedule after build to avoid side-effects.
    final bool _isNestedNavBar = context.findAncestorWidgetOfExactType<NavBarPage>() != null;
    if (!_isNestedNavBar) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          NavigationUtils.safePushReplacement(context, NavBarPage(initialPage: 'BookingPage'));
        } catch (_) {
          try {
            Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => NavBarPage(initialPage: 'BookingPage')));
          } catch (_) {}
        }
      });
    }

    return Scaffold(
      key: scaffoldKey,
      backgroundColor: isDark ? Colors.black : Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.onSurface.withAlpha(26), width: 1))),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const SizedBox(width:48), Text('Bookings', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, fontSize: 18)), const SizedBox(width:48)]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: TextFormField(
                controller: _model.textController,
                focusNode: _model.textFieldFocusNode,
                textInputAction: TextInputAction.search,
                onFieldSubmitted: (v) {
                  _searchDebounce?.cancel();
                  final q = v.trim();
                  if (!mounted) return;
                  setState(() { _searchQuery = q; _page = 1; _hasMore = true; _bookings.clear(); _loadingBookings = true; });
                  _fetchBookings(reset: true);
                },
                decoration: InputDecoration(hintText: 'Search bookings...', filled: true, fillColor: isDark ? Colors.grey[900] : Colors.grey[50], prefixIcon: Icon(Icons.search_rounded, color: cs.onSurface.withAlpha(102)), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
              ),
            ),
            Expanded(
              child: _loadingBookings && _bookings.isEmpty
                  ? _buildSkeletonLoader(theme, cs)
                  : _bookings.isEmpty
                      ? Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Text(_searchQuery.isEmpty ? 'No bookings yet' : 'No bookings match "$_searchQuery"', style: theme.textTheme.bodyMedium),
                            const SizedBox(height: 12),
                            if (_searchQuery.isNotEmpty) Row(mainAxisSize: MainAxisSize.min, children: [
                              OutlinedButton(onPressed: () {
                                // Clear the search and reload
                                _model.textController?.clear();
                                if (!mounted) return;
                                setState(() { _searchQuery = ''; _page = 1; _hasMore = true; _bookings.clear(); _loadingBookings = true; });
                                _fetchBookings(reset: true);
                              }, child: const Text('Clear search')),
                              const SizedBox(width: 8),
                              ElevatedButton(onPressed: () {
                                // Focus the search field so user can try a different query
                                FocusScope.of(context).requestFocus(_model.textFieldFocusNode);
                              }, child: const Text('Search again')),
                            ])
                          ])
                        )
                      : RefreshIndicator(
                          onRefresh: () async => _fetchBookings(reset: true),
                          color: cs.primary,
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: EdgeInsets.only(left: 12, right: 12, bottom: MediaQuery.of(context).padding.bottom + kBottomNavigationBarHeight + 24.0),
                            itemCount: _bookings.length + (_hasMore ? 1 : 0),
                            itemBuilder: (c, i) {
                              if (i >= _bookings.length) {
                                return _loadingMore
                                    ? Padding(
                                        padding: const EdgeInsets.only(bottom: 16.0),
                                        child: Center(child: CircularProgressIndicator()),
                                      )
                                    : const SizedBox();
                              }
                              final booking = _bookings[i];
                              final id = booking['_id']?.toString() ?? booking['booking']?['_id']?.toString() ?? booking['id']?.toString() ?? '';
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12.0),
                                child: _BookingCard(
                                  booking: booking,
                                  isArtisan: _isArtisan,
                                  onProfileTap: () => _onProfileTap(context, booking),
                                  onAccept: () => _acceptBooking(booking),
                                  onReject: () => _rejectBooking(booking),
                                  onComplete: () => _completeBooking(booking),
                                  onCancel: () => _cancelBooking(booking),
                                  isActionLoading: _isActionLoading(id),
                                  // Provide a handler that will fetch threadId if needed and navigate
                                  onMessage: (ctx, effectiveBookingId, effectiveThreadId, jobTitleParam, priceParam, dateParam) async {
                                    // Delegate to state method which has access to TokenStorage and HTTP
                                    await _handleMessageTap(ctx, booking, effectiveBookingId, effectiveThreadId, jobTitleParam, priceParam, dateParam);
                                  },
                                  isFetchingThread: _isFetchingThread(id),
                                   theme: theme,
                                   colorScheme: cs,
                                   initialBookingId: _initialBookingId,
                                   initialThreadId: _initialThreadId,
                                 ),
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

  Future<void> _handleMessageTap(BuildContext context, Map<String,dynamic> booking, String? effectiveBookingId, String? effectiveThreadId, String jobTitleParam, String priceParam, String dateParam) async {
    if (effectiveBookingId == null || effectiveBookingId.isEmpty) return;
    try {
      // If we already have a threadId, just navigate
      if (effectiveThreadId != null && effectiveThreadId.isNotEmpty) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => MessageClientWidget(bookingId: effectiveBookingId, threadId: effectiveThreadId, jobTitle: jobTitleParam, bookingPrice: priceParam, bookingDateTime: dateParam)));
        return;
      }
      // Avoid duplicate fetches for same booking
      if (_isFetchingThread(effectiveBookingId)) return;
      _setFetchingThread(effectiveBookingId, true);
      final fetched = await _fetchThreadIdForBooking(effectiveBookingId);
      _setFetchingThread(effectiveBookingId, false);
      if (fetched == null || fetched.isEmpty) {
        // Show an informational snackbar but still navigate (MessageClient can poll/create)
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Chat is being prepared — opening messages.')));
      }
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => MessageClientWidget(bookingId: effectiveBookingId, threadId: fetched, jobTitle: jobTitleParam, bookingPrice: priceParam, bookingDateTime: dateParam)));
    } catch (e) {
      if (kDebugMode) debugPrint('handleMessageTap error: $e');
      _setFetchingThread(effectiveBookingId, false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unable to open chat.'))) ;
      // Fallback: navigate without thread id so MessageClient can try its own logic
      try { Navigator.of(context).push(MaterialPageRoute(builder: (_) => MessageClientWidget(bookingId: effectiveBookingId, threadId: null, jobTitle: jobTitleParam, bookingPrice: priceParam, bookingDateTime: dateParam))); } catch (_) {}
    }
  }
}

// Top-level helpers (shared between the page state and _BookingCard)
String _extractJobTitle(Map<String,dynamic> booking) {
  try {
    final data = booking['booking'] ?? booking;
    final keys = ['service','serviceTitle','serviceType','jobTitle','title'];
    for (final k in keys) { final v = data[k]; if (v is String && v.isNotEmpty) return v; }
    final id = booking['_id']?.toString() ?? booking['id']?.toString() ?? data['_id']?.toString() ?? data['id']?.toString();
    if (id != null && id.isNotEmpty) {
      if (id.length > 24) return '${id.substring(0, 12)}...${id.substring(id.length - 6)}';
      return id;
    }
    return '---';
  } catch (_) { return '---'; }
}

String _extractDate(Map<String,dynamic> booking) {
  final data = booking['booking'] ?? booking;
  final keys = ['createdAt','schedule','dateTime'];
  for (final k in keys) {
    final v = data[k]; if (v==null) continue;
    try {
      if (v is num) {
        final ms = v > 1000000000000 ? v.toInt() : (v * 1000).toInt();
        return DateFormat.yMMMd().add_jm().format(DateTime.fromMillisecondsSinceEpoch(ms));
      }
      final s = v.toString();
      final dt = DateTime.tryParse(s);
      if (dt != null) return DateFormat.yMMMd().add_jm().format(dt);
      final digits = int.tryParse(RegExp(r'\d+').stringMatch(s) ?? '');
      if (digits!=null) {
        final ms = digits > 1000000000000 ? digits : digits*1000;
        return DateFormat.yMMMd().add_jm().format(DateTime.fromMillisecondsSinceEpoch(ms));
      }
    } catch (_) { return v.toString(); }
  }
  return '-';
}

String _extractPrice(Map<String,dynamic> booking) {
  final data = booking['booking'] ?? booking;
  final keys=['price','amount','total'];
  for (final k in keys) {
    final v = data[k]; if (v==null) continue;
    try {
      if (v is num) return '₦${NumberFormat('#,##0','en_US').format(v)}';
      if (v is String) {
        final n = num.tryParse(v.replaceAll(RegExp(r'[^0-9.-]'),''));
        if (n!=null) return '₦${NumberFormat('#,##0','en_US').format(n)}';
        return v;
      }
    } catch(_) { return v.toString(); }
  }
  return '-';
}

String? _extractBookingId(dynamic booking) {
  try {
    if (booking == null) return null;
    if (booking is String) return booking.isNotEmpty ? booking : null;
    if (booking is num) return booking.toString();
    if (booking is Map) {
      final candidates = ['_id', 'id', 'bookingId', 'booking_id', 'booking'];
      for (final k in candidates) {
        final v = booking[k];
        if (v == null) continue;
        if (v is String && v.isNotEmpty) return v;
        if (v is num) return v.toString();
        if (v is Map) {
          final nested = _extractBookingId(v);
          if (nested != null && nested.isNotEmpty) return nested;
        }
      }
      if (booking['booking'] is Map) {
        final v = booking['booking'];
        final nested = _extractBookingId(v);
        if (nested != null && nested.isNotEmpty) return nested;
      }
      if (booking['data'] is Map) {
        final nested = _extractBookingId(booking['data']);
        if (nested != null && nested.isNotEmpty) return nested;
      }
      if (booking['bookingId'] is Map) {
        final nested = _extractBookingId(booking['bookingId']);
        if (nested != null && nested.isNotEmpty) return nested;
      }
    }
  } catch (_) {}
  return null;
}

class _BookingCard extends StatelessWidget {
  final Map<String,dynamic> booking;
  final bool isArtisan;
  final VoidCallback onProfileTap;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onComplete;
  final VoidCallback? onCancel;
  final bool isActionLoading;
  final ThemeData theme;
  final ColorScheme colorScheme;
  // Optional initial IDs passed from the parent BookingPageWidget (e.g., after payment)
  final String? initialBookingId;
  final String? initialThreadId;

  // New parameters for message handling
  final void Function(BuildContext, String, String, String, String, String) onMessage;
  final bool isFetchingThread;

  const _BookingCard({required this.booking, required this.isArtisan, required this.onProfileTap, this.onAccept, this.onReject, this.onComplete, this.onCancel, this.isActionLoading=false, required this.theme, required this.colorScheme, this.initialBookingId, this.initialThreadId, required this.onMessage, this.isFetchingThread = false});

  @override
  Widget build(BuildContext context) {
    final counterpart = (isArtisan ? (booking['customer'] ?? booking['customerUser']) : (booking['artisan'] ?? booking['artisanUser']));
    final name = _extractName(counterpart);
    final profileUrl = _extractProfileUrl(counterpart);
    final jobTitle = _extractJobTitle(booking);
    final dateStr = _extractDate(booking);
    final priceStr = _extractPrice(booking);
    final statusRaw = booking['booking']?['status'] ?? booking['status'] ?? 'pending';
    final status = statusRaw?.toString().toLowerCase() ?? 'pending';
    // Determine broader cancel eligibility (many APIs use different status labels)
    final cancelEligible = (status.startsWith('await') || status == 'pending' || status.contains('awaiting') || status.contains('waiting') || status == 'created' || status == 'held');
    // Debug: log booking id and cancel eligibility to help troubleshoot missing Cancel button
    // Detect whether this booking originated from a quote so we can treat quote flows differently
    bool isQuote = false;
    try {
      final qcand = booking['acceptedQuote'] ?? booking['accepted_quote'] ?? booking['quoteId'] ?? booking['quote'] ?? booking['booking']?['acceptedQuote'] ?? booking['booking']?['quoteId'] ?? booking['booking']?['quote'];
      if (qcand != null) isQuote = true;
      final bs = booking['bookingSource'] ?? booking['booking']?['bookingSource'] ?? booking['payment']?['bookingSource'];
      if (!isQuote && bs != null && bs.toString().toLowerCase() == 'quote') isQuote = true;
    } catch (_) {}
    try { debugPrint('BookingCard(build): id=${_extractBookingId(booking) ?? booking['_id'] ?? booking['id']}, status=$status, isArtisan=$isArtisan, cancelEligible=$cancelEligible, isQuote=$isQuote'); } catch (_) {}
    final statusColor = _getStatusColor(status, theme);

    // Payment / refund / review flags
    final paymentStatus = (booking['paymentStatus'] ?? booking['booking']?['paymentStatus'] ?? 'unpaid')?.toString().toLowerCase() ?? 'unpaid';
    final refundStatus = (booking['refundStatus'] ?? booking['booking']?['refundStatus'] ?? 'none')?.toString().toLowerCase() ?? 'none';

    // Define active statuses where messaging should be allowed
    final activeStatuses = <String>{'accepted', 'in-progress', 'in_progress', 'inprogress', 'completed'};
    final bool isActiveStatus = activeStatuses.contains(status);
    final bool messageEnabled = isActiveStatus && refundStatus == 'none';

    String messageDisabledReason() {
      if (messageEnabled) return 'Message artisan';
      if (status == 'pending') {
        if (paymentStatus != 'paid') return 'Payment pending — messaging disabled';
        return 'Waiting for artisan acceptance — messaging disabled';
      }
      if (status == 'cancelled') return 'Booking cancelled — messaging disabled';
      if (status == 'closed') return 'Booking closed — messaging disabled';
      if (refundStatus == 'requested') return 'Refund requested — messaging disabled';
      if (refundStatus == 'refunded') return 'Refund processed — messaging disabled';
      return 'Messaging is disabled for this booking status';
    }

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.onSurface.withAlpha(26), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.surface,
                    border: Border.all(color: colorScheme.onSurface.withAlpha(26), width: 1),
                  ),
                  child: ClipOval(
                    child: profileUrl != null && profileUrl.isNotEmpty
                        ? Image.network(
                            profileUrl.startsWith('/') ? '$API_BASE_URL$profileUrl' : profileUrl,
                            fit: BoxFit.cover,
                            width: 50,
                            height: 50,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    value: loadingProgress.expectedTotalBytes != null
                                        ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                        : null,
                                    strokeWidth: 2,
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) => Center(
                              child: Icon(
                                Icons.person_outline,
                                color: colorScheme.onSurface.withAlpha(77),
                                size: 24,
                              ),
                            ),
                          )
                        : Icon(
                            Icons.person_outline,
                            color: colorScheme.onSurface.withAlpha(77),
                            size: 24,
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        jobTitle,
                        style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurface.withAlpha(153)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha(26),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    status,
                    style: theme.textTheme.labelSmall?.copyWith(color: statusColor, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Date',
                      style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurface.withAlpha(153)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateStr,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Amount',
                      style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurface.withAlpha(153)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      priceStr,
                      style: theme.textTheme.titleMedium?.copyWith(color: colorScheme.primary, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 20),

            Row(
              children: [
                // If artisan needs to accept/reject an incoming paid booking, show action buttons
                if (isArtisan && (status == 'awaiting-acceptance' || status == 'awaiting_acceptance' || status == 'awaiting-accept')) ...[
                  Expanded(
                    child: Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: isActionLoading ? null : onReject,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colorScheme.onSurface,
                            side: BorderSide(color: colorScheme.onSurface.withAlpha(40)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: isActionLoading ? SizedBox(height:16,width:16,child:CircularProgressIndicator(strokeWidth:2)) : Text('Reject', style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: isActionLoading ? null : onAccept,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: isActionLoading ? SizedBox(height:16,width:16,child:CircularProgressIndicator(color: colorScheme.onPrimary, strokeWidth:2)) : Text('Accept', style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ]),
                  ),
                ] else ...[
                  Expanded(
                    child: Tooltip(
                      message: messageEnabled ? 'Message artisan' : messageDisabledReason(),
                      child: OutlinedButton(
                        onPressed: messageEnabled
                            ? () async {
                                // Compose effective IDs from available data
                                final effectiveBookingId = (initialBookingId != null && initialBookingId!.isNotEmpty)
                                    ? initialBookingId
                                    : (_extractBookingId(booking) ?? (booking['_id']?.toString() ?? booking['booking']?['_id']?.toString() ?? booking['id']?.toString()));
                                final extractedThread = _extractThreadId(booking);
                                final effectiveThreadId = (initialThreadId != null && initialThreadId!.isNotEmpty)
                                    ? initialThreadId
                                    : (extractedThread?.toString());

                                // Delegate fetching/navigation to parent state
                                try {
                                  onMessage(context, effectiveBookingId ?? '', effectiveThreadId ?? '', jobTitle, priceStr, dateStr);
                                } catch (e) {
                                  if (kDebugMode) debugPrint('BookingCard: onMessage callback error: $e');
                                }
                              }
                            : null,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: messageEnabled ? colorScheme.primary : colorScheme.onSurface.withAlpha(90),
                          side: BorderSide(color: messageEnabled ? colorScheme.primary : colorScheme.onSurface.withAlpha(40)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: isFetchingThread ? SizedBox(height:16,width:16,child:CircularProgressIndicator(strokeWidth:2)) : Text('Message', style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                  if (!isArtisan) ...[
                    const SizedBox(width: 12),
                    // Show Cancel button for customers when booking is awaiting artisan acceptance or pending
                    // Only show Cancel when the booking is cancel-eligible AND the payment is not in a 'pending-unpaid' state.
                    // If status == 'pending' and paymentStatus != 'paid' then payment hasn't completed and we should NOT show Cancel.
                    // Additionally: for direct-hire flows (not from a quote), DO NOT show Cancel when status == 'pending'.
                    if (cancelEligible && onCancel != null && !(status == 'pending' && paymentStatus != 'paid') && !(status == 'pending' && !isQuote)) ...[
                      OutlinedButton(
                        onPressed: isActionLoading ? null : onCancel,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: BorderSide(color: Colors.redAccent.withAlpha(38)),
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: isActionLoading
                            ? SizedBox(height:16,width:16,child:CircularProgressIndicator(strokeWidth:2,color: Colors.redAccent))
                            : Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.close, size: 16, color: Colors.redAccent), const SizedBox(width: 8), Text('Cancel', style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.redAccent))]),
                      ),
                      const SizedBox(width: 12),
                    ],
                    if ((status == 'in-progress' || status == 'in_progress' || status == 'inprogress') && onComplete != null) ...[
                       ElevatedButton(
                         onPressed: isActionLoading ? null : () async {
                           final confirm = await showDialog<bool>(context: context, builder: (ctx) {
                             return AlertDialog(
                               title: const Text('Complete job'),
                               content: const Text('Are you sure you want to mark this booking as complete? This will release payment to the artisan.'),
                               actions: [
                                 TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                                 ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Confirm')),
                               ],
                             );
                           });
                           if (confirm == true) onComplete?.call();
                         },
                         style: ElevatedButton.styleFrom(
                           backgroundColor: colorScheme.primary,
                           foregroundColor: colorScheme.onPrimary,
                           padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                         ),
                         child: isActionLoading ? SizedBox(height:16,width:16,child:CircularProgressIndicator(color: colorScheme.onPrimary, strokeWidth:2)) : Row(mainAxisSize: MainAxisSize.min, children: [ Icon(Icons.check_circle_outline, size: 16), const SizedBox(width: 8), Text('Complete', style: const TextStyle(fontWeight: FontWeight.w600)) ]),
                       ),
                       const SizedBox(width: 12),
                     ],
                     ElevatedButton(
                       onPressed: onProfileTap,
                       style: ElevatedButton.styleFrom(
                         backgroundColor: colorScheme.primary,
                         foregroundColor: colorScheme.onPrimary,
                         padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                         elevation: 0,
                         shadowColor: Colors.transparent,
                       ),
                       child: Row(
                         mainAxisSize: MainAxisSize.min,
                         children: [
                           Icon(Icons.person_outline, size: 16),
                           const SizedBox(width: 8),
                           Text('Profile', style: const TextStyle(fontWeight: FontWeight.w600)),
                         ],
                       ),
                     ),
                   ],
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _extractName(dynamic user) {
    if (user == null) return 'Unknown';
    final keys = ['name','fullName','businessName','displayName','username'];
    for (final k in keys) {
      final v = user[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return 'Unknown';
  }

  String? _extractProfileUrl(dynamic user) {
    if (user == null) return null;
    try {
      if (user is Map) {
        final keys = ['profileImage','photo','avatar','image','picture','photoUrl','profile_pic'];
        for (final k in keys) {
          final v = user[k];
          if (v is String && v.isNotEmpty) return v;
          if (v is Map) {
            final url = v['url'] ?? v['path'] ?? v['secure_url'];
            if (url is String && url.isNotEmpty) return url;
          }
        }
        if (user['profile'] is Map) {
          final p = user['profile'] as Map;
          final url = p['photo'] ?? p['avatar'] ?? p['image'] ?? p['profileImage'];
          if (url is String && url.isNotEmpty) return url;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  String? _extractThreadId(dynamic booking) {
    try {
      if (booking == null) return null;
      dynamic t;
      if (booking is Map) {
        if (booking['threadId'] != null) t = booking['threadId'];
        else if (booking['booking'] is Map && booking['booking']['threadId'] != null) t = booking['booking']['threadId'];
        else if (booking['chat'] is Map) t = booking['chat']['_id'] ?? booking['chat']['id'] ?? booking['chat']['threadId'];
        else if (booking['thread'] is Map) t = booking['thread']['_id'] ?? booking['thread']['id'];
        else if (booking['booking'] is Map && booking['booking']['chat'] is Map) t = booking['booking']['chat']['_id'] ?? booking['booking']['chat']['id'];
      }
      if (t == null) return null;
      if (t is String) return t.isNotEmpty ? t : null;
      if (t is num) return t.toString();
      if (t is Map) return (t['_id'] ?? t['id'])?.toString();
      return null;
    } catch (_) {
      return null;
    }
  }

  Color _getStatusColor(dynamic status, ThemeData theme) {
    final s = status?.toString().toLowerCase() ?? '';
    if (s == 'pending') return Colors.orange;
    if (s == 'completed' || s == 'closed') return Colors.green;
    if (s == 'accepted') return theme.colorScheme.primary;
    if (s == 'rejected' || s == 'cancelled') return Colors.red;
    return Colors.grey;
  }
}

