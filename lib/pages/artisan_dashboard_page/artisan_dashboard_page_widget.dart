import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/main.dart';
import '../../utils/navigation_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:badges/badges.dart' as badges; // added for notification badge
import 'dart:async'; // <-- added for Timer
import '../../services/notification_service.dart'; // <-- added for NotificationService
import '../../mapbox_config.dart';
import '../../utils/location_permission.dart';
import 'dart:convert';
import 'artisan_dashboard_page_model.dart';
import '../../pages/artisan_kyc_page/artisan_kyc_route_wrapper.dart';
import '../../services/user_service.dart';
import '../../services/artist_service.dart';
import '../../services/token_storage.dart';
import '../../services/api_client.dart';
import '../../api_config.dart';
export 'artisan_dashboard_page_model.dart';

class ArtisanDashboardPageWidget extends StatefulWidget {
  const ArtisanDashboardPageWidget({super.key});

  static String routeName = 'ArtisanDashboardPage';
  static String routePath = '/artisanDashboardPage';

  @override
  State<ArtisanDashboardPageWidget> createState() => _ArtisanDashboardPageWidgetState();
}

class _ArtisanDashboardPageWidgetState extends State<ArtisanDashboardPageWidget> with TickerProviderStateMixin {
  late ArtisanDashboardPageModel _model;
  final scaffoldKey = GlobalKey<ScaffoldState>();
  bool _loadingProfile = true;

  // New local state: artisan-specific profile and kyc status and computed completion
  Map<String, dynamic>? _artisanProfile;
  bool _hasArtisanProfile = false; // NEW: whether the artisan profile document exists
  bool _kycVerifiedLocal = false;
  String? _kycStatus;
  double _profileCompletion = 0.0;

  // Notification badge state (kept in dashboard to mirror Home behavior)
  int _unreadNotifications = 0;
  AnimationController? _notifAnimController;
  Animation<double>? _notifPulse;
  Timer? _notifTimer;

  // Auto-scroll controller and timer for the Recent Reviews horizontal carousel
  PageController? _reviewsPageController;
  Timer? _reviewsAutoScrollTimer;

  // Cache for reviewer user records fetched by id (id -> user map with name/profileImage)
  final Map<String, Map<String, dynamic>> _reviewUserCache = {};

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => ArtisanDashboardPageModel());
    _model.switchValue = true;
    // Initialize cached flags quickly so UI can reflect verification state immediately.
    _initCachedFlags();
    _initKycStatus();

    // Apply any available dashboard/profile cache immediately (don't await) so
    // the page shows content fast while network refreshes happen in the
    // background.
    Future.microtask(() {
      try { _applyCachedDashboardImmediate(); } catch (_) {}
      try { _fetchUnreadNotifications(); } catch (_) {}
    });

    // Defer heavy network and polling work until after the first frame to allow
    // the page to render quickly (reduce initial jank and perceived load time).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Run in a microtask to avoid blocking the frame callback itself.
      Future.microtask(() async {
        try {
          await _loadInitialData();
        } catch (_) {}

        // Start notification animation and polling after initial data load
        try {
          _notifAnimController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
          _notifPulse = Tween<double>(begin: 1.0, end: 1.06).animate(CurvedAnimation(parent: _notifAnimController!, curve: Curves.easeInOut));
          // initial fetch and periodic refresh every 30s (don't block UI)
          try { _fetchUnreadNotifications(); } catch (_) {}
          _notifTimer = Timer.periodic(const Duration(seconds: 30), (_) { if (mounted) _fetchUnreadNotifications(); });
        } catch (_) {}
      });
    });
  }

  Future<void> _fetchUnreadNotifications() async {
    try {
      final count = await NotificationService.fetchUnreadCount();
      if (!mounted) return;
      setState(() {
        _unreadNotifications = (count >= 0) ? count : 0;
        if (_unreadNotifications > 0) {
          try { _notifAnimController?.repeat(reverse: true); } catch (_) {}
        } else {
          try { _notifAnimController?.stop(); } catch (_) {}
        }
      });
    } catch (_) {}
  }

  Future<void> _loadCachedDashboard() async {
    try {
      // Attempt to read cached dashboard data (now namespaced per user). To be
      // extra safe, also compare cached profile user id with the currently
      // authenticated user id and clear cache if they don't match.
      final cachedProfile = await TokenStorage.getDashboardProfile();
      final cached = await TokenStorage.getDashboardData();
      try {
        final currentUser = await UserService.getProfile();
        final currentId = (currentUser?['id'] ?? currentUser?['_id'] ?? currentUser?['userId'])?.toString();
        if (cachedProfile != null && currentId != null && currentId.isNotEmpty) {
          // try several candidate paths for user id inside cached profile
          String? cachedId;
          try {
            cachedId = (cachedProfile['user']?['id'] ?? cachedProfile['user']?['_id'] ?? cachedProfile['user']?['userId'] ?? cachedProfile['_id'] ?? cachedProfile['id'])?.toString();
          } catch (_) { cachedId = null; }
          if (cachedId == null || cachedId != currentId) {
            // mismatch: clear any dashboard cache for safety
            await TokenStorage.deleteDashboardCache();
            if (kDebugMode) debugPrint('ArtisanDashboard: cleared stale dashboard cache (cachedId=$cachedId currentId=$currentId)');
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('ArtisanDashboard: user id check for cached profile failed: $e');
      }

      // Only apply cached profile if it matches the currently-loaded profile
      // (by _id). This prevents applying a different user's cached profile
      // when a new account is created on the device.
      if (cachedProfile != null && mounted) {
        try {
          final cachedId = cachedProfile['_id']?.toString();
          final currentId = _model.profileData?['_id']?.toString();
          // If we haven't yet loaded a profile, it's safe to apply cached
          // profile. If we have, only apply when ids match.
          if (currentId == null || cachedId == null || cachedId == currentId) {
            setState(() {
              _model.displayName = (cachedProfile['name'] ?? cachedProfile['fullName'] ?? cachedProfile['username'])?.toString() ?? _model.displayName;
              _model.profileImageUrl = (cachedProfile['profileImage'] is Map) ? cachedProfile['profileImage']['url'] : (cachedProfile['profileImage'] ?? cachedProfile['photo'] ?? _model.profileImageUrl ?? '');
              _model.profileData = Map<String, dynamic>.from(cachedProfile);
            });
          } else {
            if (kDebugMode) debugPrint('Cached dashboard profile belongs to different user (cachedId=$cachedId currentId=$currentId) - skipping cache apply');
          }
        } catch (e) {
          if (kDebugMode) debugPrint('Error verifying cached profile ownership: $e');
        }
      }

      if (cached != null && mounted) {
        try {
          // If a cached profile was found and we decided not to apply it
          // because it belongs to another user, skip applying dashboard data
          // as well. Otherwise it's safe to apply.
          final cachedProfileId = cachedProfile?['_id']?.toString();
          final currentId = _model.profileData?['_id']?.toString();
          if (cachedProfile != null && cachedProfileId != null && currentId != null && cachedProfileId != currentId) {
            if (kDebugMode) debugPrint('Cached dashboard data belongs to a different user (cachedId=$cachedProfileId currentId=$currentId) - skipping dashboard cache');
          } else {
            setState(() {
              // expected payload keys: analytics, recentBookings, recentReviews, pendingJobs, averageRating
              _model.analytics = Map<String, dynamic>.from(cached['analytics'] ?? cached);
              _model.recentBookings = (cached['recentBookings'] is List) ? List<Map<String,dynamic>>.from(cached['recentBookings']) : (cached['recentBookings'] ?? _model.recentBookings ?? []);
              _model.recentReviews = (cached['recentReviews'] is List) ? List<Map<String,dynamic>>.from(cached['recentReviews']) : (cached['recentReviews'] ?? _model.recentReviews ?? []);
              _model.pendingJobs = (cached['pendingJobs'] is int)
                  ? cached['pendingJobs']
                  : int.tryParse((cached['pendingJobs'] ?? '').toString()) ?? _model.pendingJobs;
              _model.averageRating = (cached['averageRating'] is num) ? (cached['averageRating'] as num).toDouble() : double.tryParse((cached['averageRating'] ?? '').toString()) ?? _model.averageRating;
            });
          }
        } catch (e) {
          if (kDebugMode) debugPrint('Failed to apply dashboard cache: $e');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to load cached dashboard: $e');
    }
  }

  Future<void> _initCachedFlags() async {
    try {
      final cached = await TokenStorage.getKycVerified();
      if (cached != null && mounted) {
        setState(() {
          _model.isVerified = cached;
          _kycVerifiedLocal = cached;
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to read cached kyc flag: $e');
    }
  }

  Future<void> _initKycStatus() async {
    try {
      final s = await TokenStorage.getKycStatus();
      if (!mounted) return;
      setState(() { _kycStatus = s; });
    } catch (e) { if (kDebugMode) debugPrint('Failed to read saved kyc status: $e'); }
  }

  Future<void> _loadKycStatus() async {
    try {
      final s = await TokenStorage.getKycStatus();
      if (mounted) setState(() => _kycStatus = s);
    } catch (_) {}
  }

  Future<void> _loadInitialData() async {
    // Ensure we fetch the authoritative profile first, then apply any cached
    // dashboard/profile data scoped to that profile, then fetch live dashboard
    // data. This prevents cached data from a different user being applied to
    // a newly-created account.
    await _loadProfile();
    // Apply cached dashboard/profile only after we have the current profile
    // (so we can verify the cached payload belongs to the same user).
    await _loadCachedDashboard();
    await _loadDashboardData();

    // Schedule a gentle reminder a short while after the page has initialised
    // so new artisans who've not completed key setup steps get prompted.
    Future.delayed(const Duration(seconds: 10), () {
      try {
        _maybeShowOnboardReminder();
      } catch (_) {}
    });
  }

  // Show a one-time (or until dismissed) reminder to new artisans who
  // haven't set location, completed profile, or done KYC. The dialog offers
  // direct actions to open the location bottom sheet, profile page, or KYC flow.
  Future<void> _maybeShowOnboardReminder() async {
    if (!mounted) return;
    try {
      final already = await TokenStorage.getOnboardReminderShown();
      if (already == true) return; // user opted out or already handled

      // Verify this user is an artisan (best-effort): check stored role or profile data.
      final role = await TokenStorage.getRole();
      final bool isArtisanRole = (role != null && role.toLowerCase() == 'artisan') || (_model.profileData != null && (_model.profileData!['role']?.toString().toLowerCase() == 'artisan' || (_model.profileData!['roles'] is List && (_model.profileData!['roles'] as List).contains('artisan'))));
      if (!isArtisanRole) return;

      // Check missing items
      final hasLocation = (_model.userLocation != null && _model.userLocation!.trim().isNotEmpty);
      final needsProfile = _profileCompletion < 0.8; // encourage >80% completion
      final kycVerified = (_kycVerifiedLocal || _model.isVerified == true);

      if (hasLocation && !needsProfile && kycVerified) {
        // nothing to prompt
        await TokenStorage.saveOnboardReminderShown(true);
        return;
      }

      // Build a message listing the missing items
      final missing = <String>[];
      if (!hasLocation) missing.add('set your service location');
      if (needsProfile) missing.add('complete your profile');
      if (!kycVerified) missing.add('complete KYC verification');

      final message = 'To be more visible to customers and get more jobs, please ${missing.join(', ')}.';

      // Show a dialog with direct actions. Do not auto-dismiss unless user acts.
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) {
          final theme = Theme.of(ctx);
          final colorScheme = theme.colorScheme;
          return Dialog(
            backgroundColor: theme.cardColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.info_outline, color: colorScheme.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Complete your setup',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface.withOpacity(0.85)),
                  ),
                  const SizedBox(height: 16),

                  // Action buttons stacked vertically for clarity and accessibility
                  if (!hasLocation) ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.my_location_rounded),
                        label: const Text('Set location'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          Navigator.of(ctx).pop();
                          try {
                            await _openLocationBottomSheet();
                            await TokenStorage.saveOnboardReminderShown(true);
                          } catch (_) {}
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  if (needsProfile) ...[
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.edit),
                        label: const Text('Complete profile'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colorScheme.primary,
                          side: BorderSide(color: colorScheme.onSurface.withOpacity(0.12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          Navigator.of(ctx).pop();
                          try {
                            await context.pushNamed(ArtisanProfileupdateWidget.routeName);
                            await TokenStorage.saveOnboardReminderShown(true);
                          } catch (_) {}
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  if (!kycVerified) ...[
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.verified_user_outlined),
                        label: Text(_kycStatus == 'pending' ? 'KYC request pending' : 'Complete KYC'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colorScheme.primary,
                          side: BorderSide(color: colorScheme.onSurface.withOpacity(0.12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: (_kycStatus == 'pending') ? null : () async {
                          Navigator.of(ctx).pop();
                          try {
                            final status = await TokenStorage.getKycStatus();
                            if (status == 'pending') {
                              await showDialog<void>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Awaiting KYC approval'),
                                  content: const Text('Your KYC request is pending admin review. We will notify you when it is approved.'),
                                  actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
                                ),
                              );
                            } else {
                              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ArtisanKycWidget()));
                              await TokenStorage.saveOnboardReminderShown(true);
                            }
                          } catch (_) {}
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                        },
                        child: Text('Remind me later', style: theme.textTheme.labelLarge?.copyWith(color: colorScheme.onSurface.withOpacity(0.8))),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () async {
                          await TokenStorage.saveOnboardReminderShown(true);
                          Navigator.of(ctx).pop();
                        },
                        child: Text('Don\'t show again', style: theme.textTheme.labelLarge?.copyWith(color: colorScheme.onSurface.withOpacity(0.8))),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Onboard reminder failed: $e');
    }
  }

  Future<void> _refreshData() async {
    await Future.wait([
      _loadProfile(),
      _loadDashboardData(),
    ]);
    // refresh complete
  }

  Future<void> _loadProfile() async {
    if (!mounted) return;

    try {
      final profile = await UserService.getProfile();
      if (profile == null) return;

      // Primary user fields
      if (mounted) {
        setState(() {
          _model.displayName = (profile['name'] ?? profile['fullName'] ?? profile['username'])?.toString() ?? 'Artisan';
          _model.profileImageUrl = (profile['profileImage'] is Map)
              ? profile['profileImage']['url']
              : (profile['profileImage'] ?? profile['photo'] ?? '');
          _model.profileData = Map<String, dynamic>.from(profile);
        });
      }

      // Prefer canonical cached location for display (non-blocking)
      try {
        final loc = await UserService.getCanonicalLocation();
        if (loc != null && mounted) {
          final addr = (loc['address'] ?? loc['name'] ?? loc['label'])?.toString();
          if (addr != null && addr.isNotEmpty) {
            setState(() => _model.userLocation = addr);
          }
        } else {
          // fallback to profile fields
          if (profile['location'] != null && mounted) setState(() => _model.userLocation = profile['location'].toString());
          else if (profile['address'] is Map && profile['address']['city'] != null && mounted) setState(() => _model.userLocation = profile['address']['city'].toString());
          else if (profile['city'] != null && mounted) setState(() => _model.userLocation = profile['city'].toString());
        }
      } catch (_) {
        if (profile['location'] != null && mounted) setState(() => _model.userLocation = profile['location'].toString());
        else if (profile['address'] is Map && profile['address']['city'] != null && mounted) setState(() => _model.userLocation = profile['address']['city'].toString());
        else if (profile['city'] != null && mounted) setState(() => _model.userLocation = profile['city'].toString());
      }

      // Extract verification status and save locally
      bool normalizedKyc = false;
      try {
        final v = profile['isVerified'] ?? profile['verified'] ?? profile['kycVerified'];
        if (v is bool) normalizedKyc = v;
        else if (v != null) {
          final s = v.toString().toLowerCase();
          normalizedKyc = (s == 'true' || s == '1');
        }
      } catch (_) {}

      if (mounted) setState(() => _model.isVerified = normalizedKyc);
      try { TokenStorage.saveKycVerified(normalizedKyc); } catch (_) {}

      // Fetch artisan profile (if any) for artisan-specific fields
      try {
        bool _isArtisanDocument(Map<String, dynamic>? doc) {
          if (doc == null) return false;
          try {
            final markers = ['trade', 'portfolio', 'pricing', 'serviceArea', 'availability', 'experience', 'bio'];
            for (final m in markers) {
              if (doc.containsKey(m) && doc[m] != null) return true;
            }
            if (doc['user'] is Map) {
              final u = Map<String, dynamic>.from(doc['user']);
              final role = (u['role'] ?? u['type'] ?? '').toString().toLowerCase();
              if (role.contains('artisan')) return true;
            }
            final r = (doc['role'] ?? doc['type'] ?? doc['accountType'] ?? '').toString().toLowerCase();
            if (r.contains('artisan')) return true;
          } catch (_) {}
          return false;
        }

        final artisan = await ArtistService.getMyProfile();
        // print(artisan);
        if (artisan != null && _isArtisanDocument(artisan)) {
          if (mounted) setState(() {
            _artisanProfile = artisan;
            _hasArtisanProfile = true;
          });
        } else {
          // If getMyProfile returned null or looked like a user object, attempt to resolve via user id
          try {
            String? userId;
            try {
              userId = _model.profileData?['_id']?.toString() ?? _model.profileData?['id']?.toString();
            } catch (_) { userId = null; }
            if (userId == null || userId.isEmpty) {
              try { userId = await TokenStorage.getUserId(); } catch (_) { userId = null; }
            }
            if (userId != null && userId.isNotEmpty) {
              debugPrint('ssf');
              final byUser = await ArtistService.getByUserId(userId);
              debugPrint('Artisan profile existence check: $byUser');
              if (byUser != null && _isArtisanDocument(byUser)) {
                if (mounted) setState(() {
                  _artisanProfile = byUser;
                  _hasArtisanProfile = true;
                });
              } else {
                if (mounted) setState(() => _hasArtisanProfile = false);
              }
            } else {
              print(111);
              if (mounted) setState(() => _hasArtisanProfile = false);
            }
          } catch (e) {
            if (kDebugMode) debugPrint('Artisan profile existence check failed: $e');
            if (mounted) setState(() => _hasArtisanProfile = false);
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Failed to fetch artisan profile: $e');
      }

      // Fetch authoritative KYC status
      try {
        final kycUri = Uri.parse('$API_BASE_URL/api/kyc/status');
        final resp = await ApiClient.get(kycUri.toString(), headers: {'Content-Type': 'application/json'});
        final status = resp['status'] as int? ?? 0;
        final body = resp['body']?.toString() ?? '';
        if (status >= 200 && status < 300 && body.isNotEmpty) {
          try {
            final decoded = jsonDecode(body);
            bool verified = false;
            if (decoded is Map) {
              final data = decoded['data'] ?? decoded;
              if (data is Map && data['verified'] != null) {
                final v = data['verified'];
                if (v is bool) verified = v;
                else verified = v.toString().toLowerCase() == 'true' || v.toString() == '1';
              } else if (decoded['verified'] != null) {
                final v = decoded['verified'];
                if (v is bool) verified = v;
                else verified = v.toString().toLowerCase() == 'true' || v.toString() == '1';
              }
            }
            if (mounted) setState(() => _kycVerifiedLocal = verified);
            if (verified && !_model.isVerified) setState(() => _model.isVerified = true);
          } catch (e) {
            if (kDebugMode) debugPrint('Failed parse kyc/status: $e');
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('KYC status fetch failed: $e');
      }

      // Compute completion percentage using both user profile and artisan-specific profile
      _computeProfileCompletion();
      // Save profile cache for fast subsequent loads
      try {
        final toSave = _model.profileData != null ? Map<String, dynamic>.from(_model.profileData!) : <String,dynamic>{};
        await TokenStorage.saveDashboardProfile(toSave);
      } catch (e) {
        if (kDebugMode) debugPrint('Failed to save dashboard profile cache: $e');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error loading profile: $e');
    } finally {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  void _computeProfileCompletion() {
    // If the authenticated user hasn't created an artisan profile document,
    // treat profile completion as 0% (this prevents identity-only prefills from
    // inflating the artisan profile completion shown on the dashboard).
    if (!_hasArtisanProfile) {
      if (mounted) setState(() => _profileCompletion = 0.0);
      return;
    }

    // Define a set of key checks representing important profile fields
    final checks = <bool>[];

    // user-level fields
    final pd = _model.profileData ?? {};
    checks.add((pd['name'] ?? pd['fullName'] ?? pd['username']) != null && pd['name']?.toString().trim().isNotEmpty == true);
    checks.add((pd['email'] ?? '').toString().trim().isNotEmpty);
    checks.add((pd['phone'] ?? '').toString().trim().isNotEmpty);
    final profileImagePresent = (_model.profileImageUrl != null && _model.profileImageUrl.toString().trim().isNotEmpty);
    checks.add(profileImagePresent);

    // artisan-level fields
    final ap = _artisanProfile ?? {};
    checks.add((ap['trade'] != null && ((ap['trade'] is List && (ap['trade'] as List).isNotEmpty) || (ap['trade'] is String && ap['trade'].toString().isNotEmpty))));
    checks.add((ap['experience'] ?? ap['experienceYears'] ?? ap['yearsExperience']) != null);
    checks.add((ap['bio'] ?? '').toString().trim().isNotEmpty);
    // pricing
    final pricing = ap['pricing'] ?? ap['pricingStructure'] ?? ap['rates'];
    checks.add(pricing != null && ((pricing is Map && pricing.isNotEmpty) || pricing.toString().isNotEmpty));
    // availability
    checks.add((ap['availability'] is List && (ap['availability'] as List).isNotEmpty) || (ap['availability'] is String && ap['availability'].toString().isNotEmpty));
    // serviceArea
    final sa = ap['serviceArea'] ?? ap['service_area'] ?? {};
    checks.add(sa != null && ((sa is Map && (sa['address'] != null || (sa['coordinates'] != null))) || (sa.toString().isNotEmpty)));
    // portfolio
    checks.add((ap['portfolio'] is List && (ap['portfolio'] as List).isNotEmpty) || (ap['portfolioImages'] is List && (ap['portfolioImages'] as List).isNotEmpty));

    // KYC flag counts as completing verification but not required for profile completeness; include as bonus
    if (_kycVerifiedLocal || _model.isVerified) {
      checks.add(true); // bonus
    }

    final total = checks.length;
    final passed = checks.where((c) => c).length;
    final percent = total == 0 ? 0.0 : (passed / total);

    if (mounted) setState(() => _profileCompletion = percent.clamp(0.0, 1.0));
  }

  Future<void> _loadDashboardData() async {
    try {
      // Try role-aware central dashboard endpoint first (returns artisan-specific 'mine' data)
      try {
        final centralUrl = '$API_BASE_URL/api/admin/central?limit=10';
        final resp = await ApiClient.get(centralUrl, headers: {'Content-Type': 'application/json'});
        final status = resp['status'] as int? ?? 0;
        final body = resp['body']?.toString() ?? '';
        if (status >= 200 && status < 300 && body.isNotEmpty) {
          final decoded = jsonDecode(body);
          final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
          if (data is Map && data['mine'] is Map) {
            final mine = Map<String, dynamic>.from(data['mine']);
            // extract wallet metrics if present
            final wallet = mine['wallet'] is Map ? Map<String, dynamic>.from(mine['wallet']) : <String, dynamic>{};
            final bookings = (mine['bookings'] is List) ? List<Map<String, dynamic>>.from(mine['bookings']) : <Map<String,dynamic>>[];
            final reviews = (mine['reviews'] is List) ? List<Map<String, dynamic>>.from(mine['reviews']) : <Map<String,dynamic>>[];
            final transactions = (mine['transactions'] is List) ? List<Map<String, dynamic>>.from(mine['transactions']) : <Map<String,dynamic>>[];

            int computedCompleted = 0;
            int computedPending = 0;
            int computedEarnings = 0;
            for (final b in bookings) {
              try {
                final bk = b is Map ? (b['booking'] is Map ? Map<String,dynamic>.from(b['booking']) : Map<String,dynamic>.from(b)) : <String,dynamic>{};
                final status = (bk['status'] ?? '').toString().toLowerCase();
                final priceVal = bk['price'] ?? bk['amount'] ?? bk['priceAmount'] ?? 0;
                final price = priceVal is num ? priceVal.toInt() : int.tryParse(priceVal.toString()) ?? 0;
                if (status == 'pending') computedPending++;
                if (status == 'closed' || status == 'completed' || status == 'done' || status == 'paid') computedCompleted++;
                computedEarnings += price;
              } catch (_) {}
            }

            double avgRating = _model.averageRating;
            try {
              double sum = 0; int cnt = 0;
              for (final r in reviews) {
                final rv = r['rating'] ?? r['stars'] ?? r['score'];
                final val = rv == null ? null : double.tryParse(rv.toString());
                if (val != null) { sum += val; cnt++; }
              }
              if (cnt > 0) avgRating = (sum / cnt).clamp(0.0, 5.0);
            } catch (_) {}

             if (!mounted) return;
             setState(() {
               _model.recentBookings = bookings;
               _model.recentReviews = reviews;
               _model.pendingJobs = computedPending;
               _model.analytics = {
                 'jobsCompleted': wallet['totalJobs'] ?? computedCompleted,
                 'reviews': reviews.length,
                 'earnings': wallet['totalEarned'] ?? computedEarnings,
                 'balance': wallet['balance'] ?? 0,
               };
               _model.averageRating = avgRating;
             });
            // Start auto-scroll for reviews when live data is applied
            try { _startReviewsAutoScroll(); } catch (_) {}
            // persist dashboard data for quick startup
            try {
              final dashboardPayload = {
                'analytics': _model.analytics ?? {},
                'recentBookings': _model.recentBookings ?? [],
                'recentReviews': _model.recentReviews ?? [],
                'pendingJobs': _model.pendingJobs ?? 0,
                'averageRating': _model.averageRating ?? 0.0,
              };
              await TokenStorage.saveDashboardData(dashboardPayload);
            } catch (e) {
              if (kDebugMode) debugPrint('Failed to save dashboard data cache (central): $e');
            }
            return; // done using central endpoint
          }
        }
      } catch (e) {
        // not fatal — fall back to older per-service aggregation below
        if (kDebugMode) debugPrint('Central dashboard fetch failed: $e');
      }

      // Resolve the artisan profile id robustly. Prefer artisan profile _id (artisan document id)
      final artisanId = await _resolveArtisanId();
      if (artisanId == null) return;

      if (_model.profileData == null || _model.profileData!['_id'] == null) {
        final profile = await UserService.getProfile();
        if (profile != null && mounted) {
          setState(() => _model.profileData = Map<String, dynamic>.from(profile));
        }
      }

      final bookings = await ArtistService.fetchArtisanBookings(artisanId, page: 1, limit: 5);
      final reviews = await ArtistService.fetchReviewsForArtisan(artisanId, page: 1, limit: 5);

      // Calculate analytics
      int computedPending = 0;
      int computedCompleted = 0;
      int computedEarnings = 0;
      for (final b in bookings) {
        Map<String, dynamic> bk = {};
        try {
          final bmap = Map<String, dynamic>.from(b as Map);
          bk = bmap['booking'] is Map ? Map<String, dynamic>.from(bmap['booking'] as Map) : bmap;
        } catch (_) {}

        final status = (bk['status'] ?? '').toString().toLowerCase();
        final priceVal = bk['price'] ?? bk['amount'] ?? bk['priceAmount'] ?? 0;
        int price = 0;
        if (priceVal is int) price = priceVal;
        else price = int.tryParse(priceVal.toString()) ?? 0;

        if (status == 'pending') computedPending++;
        if (status == 'closed' || status == 'completed' || status == 'done' || status == 'paid') computedCompleted++;
        computedEarnings += price;
      }

      double computedAvgRating = _model.averageRating;
      try {
        double sum = 0;
        int cnt = 0;
        for (final r in reviews) {
          final rv = r['rating'] ?? r['stars'] ?? r['score'];
          if (rv != null) {
            final val = double.tryParse(rv.toString());
            if (val != null) { sum += val; cnt++; }
          }
        }
        if (cnt > 0) computedAvgRating = (sum / cnt).clamp(0.0, 5.0);
      } catch (_) {}

       if (!mounted) return;

       setState(() {
         _model.recentBookings = bookings;
         _model.recentReviews = reviews;
         _model.pendingJobs = computedPending;
         _model.analytics = {
           'jobsCompleted': computedCompleted,
           'reviews': reviews.length,
           'earnings': computedEarnings,
         };
         _model.averageRating = computedAvgRating;
       });

      // Start auto-scroll for reviews when live data is applied (fallback path)
      try { _startReviewsAutoScroll(); } catch (_) {}

      // persist dashboard data for quick startup
      try {
        final dashboardPayload = {
          'analytics': _model.analytics ?? {},
          'recentBookings': _model.recentBookings ?? [],
          'recentReviews': _model.recentReviews ?? [],
          'pendingJobs': _model.pendingJobs ?? 0,
          'averageRating': _model.averageRating ?? 0.0,
        };
        await TokenStorage.saveDashboardData(dashboardPayload);
      } catch (e) {
        if (kDebugMode) debugPrint('Failed to save dashboard data cache: $e');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error loading dashboard data: $e');
    }
  }

  // New helper: resolve the artisan profile id (artisan document _id) to use with bookings/reviews endpoints.
  Future<String?> _resolveArtisanId() async {
    try {
      // 1) If we already fetched an artisan profile earlier, prefer its _id
      if (_artisanProfile != null) {
        try {
          final id = _artisanProfile!['_id'] ?? _artisanProfile!['id'] ?? _artisanProfile!['userId'];
          if (id != null) {
            if (mounted) {
              setState(() {
                _hasArtisanProfile = true;
              });
              _computeProfileCompletion();
            }
            return id.toString();
          }
        } catch (_) {}
      }

      // 2) Try ArtistService.getMyProfile() which prefers /api/artisans/me or getByUserId internally
      try {
        final ap = await ArtistService.getMyProfile();
        if (ap != null) {
          if (mounted) setState(() => _artisanProfile = ap);
          final aid = ap['_id'] ?? ap['id'] ?? ap['userId'];
          if (aid != null) {
            if (mounted) {
              setState(() => _hasArtisanProfile = true);
              _computeProfileCompletion();
            }
            return aid.toString();
          }
        }
      } catch (_) {}

      // 3) Try to derive user id from _model.profileData or TokenStorage and lookup artisan via getByUserId
      String? userId;
      try {
        userId = _model.profileData?['_id']?.toString() ?? _model.profileData?['id']?.toString();
      } catch (_) {}
      if (userId == null || userId.isEmpty) {
        try { userId = await TokenStorage.getUserId(); } catch (_) { userId = null; }
      }
      if (userId != null && userId.isNotEmpty) {
        try {
          final byUser = await ArtistService.getByUserId(userId);
          if (byUser != null) {
            if (mounted) setState(() => _artisanProfile = byUser);
            final aid = byUser['_id'] ?? byUser['id'] ?? byUser['userId'];
            if (aid != null) {
              if (mounted) {
                setState(() => _hasArtisanProfile = true);
                _computeProfileCompletion();
              }
              return aid.toString();
            }
          }
        } catch (_) {}
      }
    } catch (_) {}
    return null;
  }

    @override
    void dispose() {
    _notifAnimController?.dispose();
    _notifTimer?.cancel();
    _stopReviewsAutoScroll();
    _model.dispose();
    super.dispose();
    }

  Widget _buildAnalyticsCard({
    required BuildContext context,
    required String title,
    required String value,
    required String change,
    required IconData icon,
    required Color color,
    bool isPositive = true,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.surface : theme.colorScheme.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.onSurface.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: color,
                ),
              ),
              if (change.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isPositive ? const Color(0xFFE8F5E8) : const Color(0xFFFFF0F0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isPositive ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                        size: 12,
                        color: isPositive ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        change,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isPositive ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconColor,
    bool enabled = true,
  }) {
    final theme = Theme.of(context);

    // If not enabled, do not call onTap and dim visuals
    final effectiveOnTap = enabled ? onTap : null;
    final titleColor = enabled ? null : theme.colorScheme.onSurface.withOpacity(0.4);
    final subtitleColor = enabled ? theme.colorScheme.onSurface.withOpacity(0.6) : theme.colorScheme.onSurface.withOpacity(0.35);

    return ListTile(
      onTap: effectiveOnTap,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: (iconColor ?? theme.colorScheme.primary).withOpacity(enabled ? 0.1 : 0.04),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          size: 20,
          color: iconColor ?? theme.colorScheme.primary,
        ),
      ),
      title: Text(
        title,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w500,
          color: titleColor,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: subtitleColor,
        ),
      ),
      trailing: enabled
          ? Icon(
        Icons.chevron_right_rounded,
        color: theme.colorScheme.onSurface.withOpacity(0.3),
        size: 20,
      )
          : const SizedBox.shrink(),
      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
    );
  }

    // Quickly apply any cached dashboard/profile data so the UI has something
    // to render while we defer heavier network calls. This improves perceived
    // startup speed.
    Future<void> _applyCachedDashboardImmediate() async {
    try {
      final cachedProfile = await TokenStorage.getDashboardProfile();
      if (cachedProfile != null && mounted) {
        setState(() {
          _model.displayName = (cachedProfile['name'] ?? cachedProfile['fullName'] ?? cachedProfile['username'])?.toString() ?? _model.displayName;
          _model.profileImageUrl = (cachedProfile['profileImage'] is Map) ? cachedProfile['profileImage']['url'] : (cachedProfile['profileImage'] ?? cachedProfile['photo'] ?? _model.profileImageUrl ?? '');
          _model.profileData = Map<String, dynamic>.from(cachedProfile);
          _loadingProfile = false; // we have something to display
        });
      }

      final cached = await TokenStorage.getDashboardData();
      if (cached != null && mounted) {
        setState(() {
          _model.analytics = Map<String, dynamic>.from(cached['analytics'] ?? cached);
          _model.recentBookings = (cached['recentBookings'] is List) ? List<Map<String,dynamic>>.from(cached['recentBookings']) : (cached['recentBookings'] ?? _model.recentBookings ?? []);
          _model.recentReviews = (cached['recentReviews'] is List) ? List<Map<String,dynamic>>.from(cached['recentReviews']) : (cached['recentReviews'] ?? _model.recentReviews ?? []);
          _model.pendingJobs = (cached['pendingJobs'] is int) ? cached['pendingJobs'] : int.tryParse((cached['pendingJobs'] ?? '').toString()) ?? _model.pendingJobs;
          _model.averageRating = (cached['averageRating'] is num) ? (cached['averageRating'] as num).toDouble() : double.tryParse((cached['averageRating'] ?? '').toString()) ?? _model.averageRating;
        });
        // Start the reviews carousel if we have cached reviews
        try { _startReviewsAutoScroll(); } catch (_) {}
      }
    } catch (_) {}
    }

    // Starts the auto-scroll for the reviews PageView. Uses a large initial page
    // index so we can use modulo arithmetic in the builder to simulate an
    // infinite carousel while still allowing user swipes.
    void _startReviewsAutoScroll() {
    try {
      final reviews = _model.recentReviews;
      if (reviews == null || reviews.isEmpty) return;

      // Cancel any existing timer (we'll create a fresh one)
      _reviewsAutoScrollTimer?.cancel();

      // Initialize controller only if it's not already present so we preserve
      // current page during pause/resume.
      if (_reviewsPageController == null) {
        final int base = reviews.length;
        final int initialPage = base * 1000; // large offset to allow back/forward
        _reviewsPageController = PageController(initialPage: initialPage, viewportFraction: 0.92);
      }

      _reviewsAutoScrollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (!mounted || _reviewsPageController == null) return;
        try {
          _reviewsPageController!.nextPage(duration: const Duration(milliseconds: 600), curve: Curves.easeInOut);
        } catch (_) {
          try {
            final next = (_reviewsPageController!.page?.toInt() ?? (_reviewsPageController!.initialPage)) + 1;
            _reviewsPageController!.jumpToPage(next);
          } catch (_) {}
        }
      });
      // don't call setState unnecessarily
    } catch (_) {}
    }

    // Pause autoplay but keep controller so user can resume where they left off
    void _pauseReviewsAutoScroll() {
    try {
      _reviewsAutoScrollTimer?.cancel();
      _reviewsAutoScrollTimer = null;
    } catch (_) {}
    }

    void _stopReviewsAutoScroll() {
    try {
      _reviewsAutoScrollTimer?.cancel();
      _reviewsAutoScrollTimer = null;
      try { _reviewsPageController?.dispose(); } catch (_) {}
      _reviewsPageController = null;
    } catch (_) {}
    }

    // Fetch a user record by id for reviewer display (cached)
    Future<Map<String, dynamic>?> _fetchReviewUserById(String id) async {
      if (id.isEmpty) return null;
      try {
        if (_reviewUserCache.containsKey(id)) return _reviewUserCache[id];
        final token = await TokenStorage.getToken();
        final headers = <String,String>{'Content-Type':'application/json'};
        if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
        final url = '$API_BASE_URL/api/users/$id';
        final res = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 12));
        if (res.statusCode >= 200 && res.statusCode < 300 && res.body.isNotEmpty) {
          final d = jsonDecode(res.body);
          Map<String, dynamic>? data;
          if (d is Map && d['data'] is Map) data = Map<String,dynamic>.from(d['data']);
          else if (d is Map) data = Map<String,dynamic>.from(d);
          if (data != null) {
            final user = <String,dynamic>{};
            user['name'] = (data['name'] ?? data['fullName'] ?? data['displayName'] ?? data['username'])?.toString() ?? '';
            var img = data['profileImage'] ?? data['avatar'] ?? data['photo'] ?? data['image'] ?? data['picture'];
            if (img is Map) img = img['url'] ?? img['src'] ?? img['path'];
            user['profileImage'] = img?.toString() ?? '';
            _reviewUserCache[id] = user;
            return user;
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('fetchReviewUserById error: $e');
      }
      return null;
    }

  @override
    Widget build(BuildContext context) {
    // If this page isn't hosted inside NavBarPage, redirect to NavBarPage so the
    // bottom navigation is shown. We schedule the navigation after build to
    // avoid build-time side-effects.
    final bool _isNestedNavBar = context.findAncestorWidgetOfExactType<NavBarPage>() != null;
    if (!_isNestedNavBar) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          NavigationUtils.safePushReplacement(context, NavBarPage(initialPage: 'homePage'));
        } catch (_) {
          try {
            Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => NavBarPage(initialPage: 'homePage')));
          } catch (_) {}
        }
      });
      // show a small loader while we navigate
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(child: SizedBox(width: 36, height: 36, child: CircularProgressIndicator())),
      );
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final ff = FlutterFlowTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final analytics = _model.analytics ?? {};
    // Defensive numeric extraction to avoid NaN/Infinity when converting or dividing
    final int jobsCompleted = (() {
      try {
        final v = analytics['jobsCompleted'];
        if (v is num) return v.toInt();
        return int.tryParse(v?.toString() ?? '') ?? 0;
      } catch (_) {
        return 0;
      }
    })();

    final int earnings = (() {
      try {
        final v = analytics['earnings'];
        if (v is num) return v.toInt();
        return int.tryParse(v?.toString() ?? '') ?? 0;
      } catch (_) {
        return 0;
      }
    })();

    final int avgPerJob = (jobsCompleted > 0) ? (earnings / jobsCompleted).round() : 0;

    return Scaffold(
      key: scaffoldKey,
      backgroundColor: isDark ? Colors.black : Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Header (match HomePage style but without search)
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
                  // Profile Info (avatar + name + location)
                  Expanded(
                    child: Row(
                      children: [
                        // Avatar
                        if (_loadingProfile)
                          Container(width: 40, height: 40, decoration: BoxDecoration(color: colorScheme.surface, shape: BoxShape.circle))
                        else
                          InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () {},
                            child: Container(
                              width: 40,
                              height: 40,
                              clipBehavior: Clip.antiAlias,
                              decoration: const BoxDecoration(shape: BoxShape.circle),
                              child: Builder(builder: (ctx) {
                                final url = _model.profileImageUrl;
                                if (url != null && url.toString().startsWith('http')) {
                                  return CachedNetworkImage(imageUrl: url.toString(), fit: BoxFit.cover, placeholder: (c,u)=>Container(color: colorScheme.surface));
                                }
                                final name = (_model.displayName ?? '');
                                final initials = name.split(' ').where((s)=>s.isNotEmpty).map((s)=>s[0]).take(2).join().toUpperCase();
                                if (initials.isNotEmpty) {
                                  return Container(
                                    decoration: BoxDecoration(color: colorScheme.primary.withOpacity(0.1), shape: BoxShape.circle),
                                    child: Center(child: Text(initials, style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.w600))),
                                  );
                                }
                                return Container(decoration: BoxDecoration(color: colorScheme.surface, shape: BoxShape.circle), child: Icon(Icons.person_outline, color: colorScheme.onSurface.withOpacity(0.5), size: 20));
                              }),
                            ),
                          ),
                        const SizedBox(width: 12),

                        // Name + location column (take remaining space)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Hello ${_model.displayName ?? "Artisan"}',
                                      style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (_model.isVerified == true)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(color: Colors.green.withAlpha(30), borderRadius: BorderRadius.circular(12)),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.verified, size: 14, color: Colors.green),
                                          const SizedBox(width: 6),
                                          Text('KYC verified', style: theme.textTheme.labelSmall?.copyWith(color: Colors.green, fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              InkWell(
                                onTap: () async {
                                  try { await _openLocationBottomSheet(); } catch (_) {}
                                },
                                borderRadius: BorderRadius.circular(6),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.location_on_outlined, size: 14, color: colorScheme.onSurface.withOpacity(0.6)),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        _model.userLocation ?? _model.profileData?['city']?.toString() ?? 'Location not set',
                                        style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurface.withOpacity(0.6)),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Notification icon with badge and animation
                  badges.Badge(
                    position: badges.BadgePosition.topEnd(top: -4, end: -4),
                    showBadge: _unreadNotifications > 0,
                    badgeContent: AnimatedBuilder(
                      animation: _notifAnimController ?? AlwaysStoppedAnimation(1.0),
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _notifPulse?.value ?? 1.0,
                          child: Text(
                            _unreadNotifications > 99 ? '99+' : '$_unreadNotifications',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      },
                    ),
                    badgeStyle: badges.BadgeStyle(
                      badgeColor: colorScheme.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      elevation: 0,
                    ),
                    child: FlutterFlowIconButton(
                      borderRadius: 20,
                      buttonSize: 44,
                      fillColor: colorScheme.surface,
                      icon: Icon(Icons.notifications_outlined, color: colorScheme.onSurface, size: 22),
                      onPressed: () async {
                        try {
                          await context.pushNamed(NotificationPageWidget.routeName);
                          _fetchUnreadNotifications();
                        } catch (_) {}
                      },
                    ),
                  ),
                ],
              ),
            ),

            // Dashboard Content
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refreshData,
                color: colorScheme.primary,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      24.0,
                      0.0,
                      24.0,
                      MediaQuery.of(context).padding.bottom + 80.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 24),

                        // Main Performance Card
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: colorScheme.onSurface.withOpacity(0.1),
                              width: 1,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Performance Overview',
                                          style: theme.textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'This month',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: colorScheme.onSurface.withOpacity(0.6),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: colorScheme.primary.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.trending_up_rounded,
                                            size: 16,
                                            color: colorScheme.primary,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '+12%',
                                            style: theme.textTheme.labelSmall?.copyWith(
                                              color: colorScheme.primary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),

                                // Performance Metrics
                                Row(
                                  children: [
                                    // Rating Circle
                                    Expanded(
                                      child: Column(
                                        children: [
                                          SizedBox(
                                            width: 72,
                                            height: 72,
                                            child: Stack(
                                              alignment: Alignment.center,
                                              children: [
                                                CircularProgressIndicator(
                                                  value: (_model.averageRating / 5).clamp(0.0, 1.0),
                                                  strokeWidth: 6,
                                                  valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                                                  backgroundColor: colorScheme.primary.withOpacity(0.12),
                                                ),
                                                Column(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      _model.averageRating.toStringAsFixed(1),
                                                      style: theme.textTheme.headlineSmall?.copyWith(
                                                        fontWeight: FontWeight.w700,
                                                      ),
                                                    ),
                                                    Text(
                                                      '/5',
                                                      style: theme.textTheme.bodySmall?.copyWith(
                                                        color: colorScheme.onSurface.withOpacity(0.6),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Rating',
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: colorScheme.onSurface.withOpacity(0.6),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Stats
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          _buildStatRow(
                                            context: context,
                                            icon: Icons.work_outline,
                                            label: 'Jobs Completed',
                                            value: '${analytics['jobsCompleted'] ?? 0}',
                                            color: colorScheme.primary,
                                          ),
                                          const SizedBox(height: 12),
                                          _buildStatRow(
                                            context: context,
                                            icon: Icons.rate_review_outlined,
                                            label: 'Total Reviews',
                                            value: '${analytics['reviews'] ?? 0}',
                                            color: colorScheme.primary,
                                          ),
                                          const SizedBox(height: 12),
                                          _buildStatRow(
                                            context: context,
                                            icon: Icons.pending_outlined,
                                            label: 'Pending Jobs',
                                            value: '${_model.pendingJobs}',
                                            color: ff.warning,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Earnings Summary Card
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: colorScheme.onSurface.withOpacity(0.1),
                              width: 1,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Earnings Summary',
                                          style: theme.textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Total revenue generated',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: colorScheme.onSurface.withOpacity(0.6),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            colorScheme.primary,
                                            colorScheme.primary.withOpacity(0.8),
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        Icons.account_balance_wallet_rounded,
                                        color: colorScheme.onPrimary,
                                        size: 22,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Total Earnings',
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: colorScheme.onSurface.withOpacity(0.6),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            '₦${analytics['earnings'] ?? 0}',
                                            style: theme.textTheme.headlineMedium?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Avg. per Job',
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: colorScheme.onSurface.withOpacity(0.6),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            '₦${avgPerJob}',
                                            style: theme.textTheme.titleLarge?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: () {
                                      try {
                                        context.pushNamed(UserWalletpageWidget.routeName);
                                      } catch (_) {}
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: colorScheme.primary,
                                      foregroundColor: colorScheme.onPrimary,
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: Text(
                                      'View Wallet',
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        color: colorScheme.onPrimary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Profile Completion Section
                        Padding(
                          padding: const EdgeInsets.only(left: 4.0, bottom: 12),
                          child: Text(
                            'PROFILE SETUP',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface.withOpacity(0.6),
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: colorScheme.onSurface.withOpacity(0.1),
                              width: 1,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Profile Completion',
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      '${(_profileCompletion * 100).toInt()}%',
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                LinearProgressIndicator(
                                  value: _profileCompletion,
                                  minHeight: 6,
                                  backgroundColor: colorScheme.onSurface.withOpacity(0.1),
                                  valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                const SizedBox(height: 16),
                                _buildMenuItem(
                                  context: context,
                                  icon: Icons.person_outline,
                                  // If the artisan does not yet have an artisan profile document,
                                  // route the user to the complete-profile flow. Otherwise go to edit.
                                  title: !_hasArtisanProfile
                                      ? 'Create Artisan Profile'
                                      : (_profileCompletion >= 1.0 ? 'Edit Profile' : 'Complete Profile'),
                                  subtitle: !_hasArtisanProfile
                                      ? 'Set up your artisan profile to start getting jobs'
                                      : (_profileCompletion >= 1.0 ? 'Completed' : '${(_profileCompletion * 100).toInt()}% complete'),
                                  onTap: () async {
                                    try {
                                      if (!_hasArtisanProfile) {
                                        // Previously routed to the complete-profile flow; now send user to the
                                        // artisan profile update/create widget per requested change.
                                        await context.pushNamed(ArtisanProfileupdateWidget.routeName);
                                      } else {
                                        // Edit existing profile
                                        await context.pushNamed(ArtisanProfileupdateWidget.routeName);
                                      }
                                      await _refreshData();
                                    } catch (_) {}
                                  },
                                  iconColor: !_hasArtisanProfile
                                      ? colorScheme.primary
                                      : (_profileCompletion >= 1.0 ? ff.success : colorScheme.onSurface.withOpacity(0.5)),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Divider(
                                    height: 1,
                                    color: colorScheme.onSurface.withOpacity(0.1),
                                  ),
                                ),
                                _buildMenuItem(
                                  context: context,
                                  icon: _model.isVerified == true
                                      ? Icons.verified_outlined
                                      : Icons.verified_outlined,
                                  title: 'KYC Verification',
                                  subtitle: _model.isVerified == true
                                      ? 'Verified'
                                      : (_kycStatus == 'pending' ? 'Request pending — awaiting admin approval' : 'Get verified to attract more clients'),
                                  onTap: () async {
                                    try {
                                      final status = _kycStatus ?? await TokenStorage.getKycStatus();
                                      if (status == 'pending') {
                                        // Show awaiting dialog and do not navigate
                                        await showDialog<void>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text('Awaiting KYC approval'),
                                            content: const Text('Your KYC request has been submitted and is awaiting approval from an administrator.'),
                                            actions: [
                                              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
                                            ],
                                          ),
                                        );
                                        return;
                                      }

                                      if (!_model.isVerified) {
                                        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ArtisanKycWidget()));
                                        await _refreshData();
                                        final s = await TokenStorage.getKycStatus();
                                        if (s != _kycStatus && mounted) setState(() => _kycStatus = s);
                                      }
                                    } catch (_) {}
                                  },
                                  iconColor: _model.isVerified == true
                                      ? ff.success
                                      : ff.warning,
                                  enabled: !_model.isVerified && _kycStatus != 'pending',
                                ),

                                // Simple placeholder for TODOs to keep layout stable (original detailed TODO removed to fix syntax)
                                const SizedBox(height: 12),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                  child: Text(
                                    'To-dos coming soon',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurface.withOpacity(0.6),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 12),
                              ], // end Column children for Profile Completion Card
                            ), // end Column
                          ), // end Padding
                        ), // end Card

                        // Recent Bookings Section
                        if (_model.recentBookings != null && _model.recentBookings!.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          Padding(
                            padding: const EdgeInsets.only(left: 4.0, bottom: 12),
                            child: Text(
                              'RECENT BOOKINGS',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface.withOpacity(0.6),
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                          Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: colorScheme.onSurface.withOpacity(0.1),
                                width: 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Recent Bookings',
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      GestureDetector(
                                        onTap: () {
                                          try {
                                            context.pushNamed(BookingPageWidget.routeName);
                                          } catch (_) {}
                                        },
                                        child: Text(
                                          'View All',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: colorScheme.primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                ..._model.recentBookings!.take(3).map((item) {
                                  final service = (item['booking']?['service'] ?? item['service'] ?? 'Job').toString();
                                  final status = (item['booking']?['status'] ?? item['status'] ?? '').toString();

                                  Color statusColor;
                                  switch (status.toLowerCase()) {
                                    case 'pending':
                                      statusColor = colorScheme.primary;
                                      break;
                                    case 'completed':
                                      statusColor = ff.success;
                                      break;
                                    case 'cancelled':
                                      statusColor = colorScheme.error;
                                      break;
                                    default:
                                      statusColor = colorScheme.onSurface.withOpacity(0.6);
                                  }

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 20),
                                    child: Column(
                                      children: [
                                        ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          leading: Container(
                                            width: 40,
                                            height: 40,
                                            decoration: BoxDecoration(
                                              color: colorScheme.primary.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Icon(
                                              Icons.work_outline,
                                              size: 20,
                                              color: colorScheme.primary,
                                            ),
                                          ),
                                          title: Text(
                                            service,
                                            style: theme.textTheme.bodyMedium,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          subtitle: Text(
                                            'Status: ${status}',
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: colorScheme.onSurface.withOpacity(0.6),
                                            ),
                                          ),
                                          trailing: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: statusColor.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              status,
                                              style: theme.textTheme.labelSmall?.copyWith(
                                                color: statusColor,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (_model.recentBookings!.indexOf(item) < _model.recentBookings!.take(3).length -  1)
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 60),
                                            child: Divider(
                                              height: 1,
                                              color: colorScheme.onSurface.withOpacity(0.1),
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                                const SizedBox(height: 12),
                              ],
                            ),
                          ),
                        ],

                        // Recent Reviews Section (horizontal infinite carousel)
                        if (_model.recentReviews != null && _model.recentReviews!.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          Padding(
                            padding: const EdgeInsets.only(left: 4.0, bottom: 12),
                            child: Text(
                              'RECENT REVIEWS',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface.withOpacity(0.6),
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                          SizedBox(
                            height: 150,
                            child: NotificationListener<ScrollNotification>(
                              onNotification: (notification) {
                                if (notification is ScrollStartNotification && notification.dragDetails != null) {
                                  // user started a drag -> pause autoplay
                                  try { _pauseReviewsAutoScroll(); } catch (_) {}
                                } else if (notification is ScrollEndNotification) {
                                  // user stopped scrolling -> resume autoplay
                                  try { _startReviewsAutoScroll(); } catch (_) {}
                                }
                                return false;
                              },
                              child: PageView.builder(
                                controller: _reviewsPageController ?? PageController(viewportFraction: 0.92),
                                physics: const BouncingScrollPhysics(),
                                itemBuilder: (context, index) {
                                  final reviews = _model.recentReviews!;
                                  final r = reviews[index % reviews.length];
                                  final comment = (r['comment'] ?? r['text'] ?? r['message'] ?? '').toString();
                                  final rating = double.tryParse((r['rating'] ?? r['stars'] ?? '0').toString()) ?? 0.0;

                                  // Derive a reviewer id if available (many API shapes)
                                  String? reviewerId;
                                  try {
                                    final candidates = [r['customerId'], r['customer_id'], r['userId'], r['user_id'], r['authorId'], r['author']];
                                    for (final c in candidates) {
                                      if (c == null) continue;
                                      if (c is String && c.isNotEmpty) { reviewerId = c; break; }
                                      if (c is Map && c['_id'] != null) { reviewerId = c['_id'].toString(); break; }
                                    }
                                    if ((reviewerId == null || reviewerId.isEmpty) && r['customer'] is Map) {
                                      final cc = Map<String, dynamic>.from(r['customer']);
                                      if (cc['_id'] != null) reviewerId = cc['_id'].toString();
                                    }
                                    if ((reviewerId == null || reviewerId.isEmpty) && r['user'] is Map) {
                                      final uu = Map<String, dynamic>.from(r['user']);
                                      if (uu['_id'] != null) reviewerId = uu['_id'].toString();
                                    }
                                  } catch (_) { reviewerId = null; }

                                  // Try inline image/name first (existing fallbacks)
                                  String? inlineImageUrl;
                                  String inlineName = (r['customerName'] ?? r['customer']?['name'] ?? r['customerUser']?['name'] ?? r['user']?['name'] ?? r['reviewer']?['name'] ?? 'Customer').toString();

                                  try {
                                    final candidate = r['customer'] ?? r['customerUser'] ?? r['user'] ?? r['reviewer'] ?? {};
                                    if (candidate is Map) {
                                      final img = candidate['profileImage'] ?? candidate['avatar'] ?? candidate['photo'] ?? candidate['image'] ?? candidate['picture'];
                                      if (img is Map) inlineImageUrl = img['url']?.toString();
                                      else if (img != null) inlineImageUrl = img.toString();
                                    }
                                  } catch (_) { inlineImageUrl = null; }

                                  // Use cached fetched user record when available; otherwise trigger background fetch
                                  Map<String,dynamic>? fetchedUser;
                                  if (reviewerId != null && reviewerId.isNotEmpty) {
                                    fetchedUser = _reviewUserCache[reviewerId];
                                    if (fetchedUser == null) {
                                      // Fetch in background; don't await to avoid delaying build
                                      _fetchReviewUserById(reviewerId).then((u) {
                                        if (u != null && mounted) setState(() {});
                                      });
                                    }
                                  }

                                  final displayName = (fetchedUser != null && (fetchedUser['name'] as String).trim().isNotEmpty) ? fetchedUser['name'] as String : inlineName;
                                  final reviewerImageUrl = (fetchedUser != null && (fetchedUser['profileImage'] as String).isNotEmpty) ? fetchedUser['profileImage'] as String : inlineImageUrl;

                                  final initials = displayName.split(' ').where((s) => s.isNotEmpty).map((s) => s[0]).take(2).join().toUpperCase();

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                                    child: Card(
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      child: Padding(
                                        padding: const EdgeInsets.all(12.0),
                                        child: Row(
                                          children: [
                                            if (reviewerImageUrl != null && reviewerImageUrl.startsWith('http'))
                                              Container(
                                                width: 44,
                                                height: 44,
                                                clipBehavior: Clip.antiAlias,
                                                decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
                                                child: CachedNetworkImage(
                                                  imageUrl: reviewerImageUrl,
                                                  fit: BoxFit.cover,
                                                  placeholder: (c, u) => Container(color: ff.warning.withOpacity(0.08)),
                                                  errorWidget: (c, u, e) => Container(
                                                    color: ff.warning.withOpacity(0.08),
                                                    child: Center(child: Text(initials, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
                                                  ),
                                                ),
                                              )
                                            else
                                              Container(
                                                width: 44,
                                                height: 44,
                                                decoration: BoxDecoration(
                                                  color: ff.warning.withOpacity(0.12),
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    initials.isNotEmpty ? initials : 'C',
                                                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                                                  ),
                                                ),
                                              ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          displayName,
                                                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Row(
                                                        children: [
                                                          Icon(Icons.star_rate_rounded, size: 14, color: ff.warning),
                                                          const SizedBox(width: 4),
                                                          Text(rating.toStringAsFixed(1), style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Text(
                                                    comment,
                                                    style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurface.withOpacity(0.7)),
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 18,
            color: color,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Open the same location bottom sheet used on HomePage so behaviour is identical.
  Future<void> _openLocationBottomSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        bool loading = false;
        String statusText = '';
        return StatefulBuilder(builder: (ctx2, setModalState) {
          final theme = Theme.of(ctx2);
          final colorScheme = theme.colorScheme;
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx2).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurface.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  title: Text('Set location', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  subtitle: Text('Choose how to set your service address', style: theme.textTheme.bodySmall),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                          minimumSize: Size(double.infinity, 48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: loading ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: colorScheme.onPrimary, strokeWidth: 2)) : Icon(Icons.my_location_rounded),
                        label: Text(loading ? 'Detecting location...' : 'Use device location', style: theme.textTheme.titleMedium?.copyWith(color: colorScheme.onPrimary)),
                        onPressed: loading ? null : () async {
                          setModalState(() { loading = true; statusText = ''; });
                          final ok = await LocationPermissionService.ensureLocationPermissions(context);
                          if (!ok) {
                            setModalState(() => loading = false);
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permission denied')));
                            return;
                          }

                          try {
                            final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.best));
                            // Reverse geocode using Mapbox to get human-readable address
                            String? address;
                            try {
                              final url = Uri.parse('https://api.mapbox.com/geocoding/v5/mapbox.places/${pos.longitude},${pos.latitude}.json?access_token=$MAPBOX_ACCESS_TOKEN&limit=1');
                              final resp = await http.get(url).timeout(const Duration(seconds: 10));
                              if (resp.statusCode == 200 && resp.body.isNotEmpty) {
                                final body = jsonDecode(resp.body);
                                if (body is Map && body['features'] is List && (body['features'] as List).isNotEmpty) {
                                  final feat = (body['features'] as List).first;
                                  if (feat is Map && feat['place_name'] != null) {
                                    address = feat['place_name'].toString();
                                  }
                                }
                              }
                            } catch (e) {
                              // ignore reverse-geocode failure; we'll still save coords
                            }

                            await TokenStorage.saveLocation(address: address, latitude: pos.latitude, longitude: pos.longitude);
                            if (!mounted) return;
                            setState(() {
                              // Update displayed location on the dashboard header
                              _model.userLocation = address ?? '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
                            });
                            Navigator.of(ctx2).pop();
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(address != null ? 'Location set: $address' : 'Location coordinates saved')));
                          } catch (e) {
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to obtain device location')));
                          } finally {
                            setModalState(() { loading = false; });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colorScheme.onSurface,
                          minimumSize: Size(double.infinity, 48),
                          side: BorderSide(color: colorScheme.onSurface.withOpacity(0.12)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: Icon(Icons.edit_location_outlined),
                        label: Text('Edit profile address', style: theme.textTheme.bodyLarge),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          try { NavigationUtils.safePush(context, EditProfileUserWidget()); } catch (_) {}
                        },
                      ),
                      const SizedBox(height: 8),
                      if (statusText.isNotEmpty) Align(alignment: Alignment.centerLeft, child: Text(statusText, style: theme.textTheme.bodySmall)),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }
}
