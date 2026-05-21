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
import '../../google_maps_config.dart';
import '../../utils/location_permission.dart';
import 'dart:convert';
import 'artisan_dashboard_page_model.dart';
// import '../../pages/artisan_kyc_page/artisan_kyc_route_wrapper.dart'; // legacy KYC entry — superseded by ArtisanOnboardingWidget; restore this import + revert the reminder-dialog push in this file to roll back
import '../../services/user_service.dart';
import '../../services/artist_service.dart';
import '../../services/token_storage.dart';
import '../../services/api_client.dart';
import '../../services/kyc_service.dart';
import '../../api_config.dart';
export 'artisan_dashboard_page_model.dart';

class ArtisanDashboardPageWidget extends StatefulWidget {
  const ArtisanDashboardPageWidget({super.key});

  static String routeName = 'ArtisanDashboardPage';
  static String routePath = '/artisanDashboardPage';

  @override
  State<ArtisanDashboardPageWidget> createState() =>
      _ArtisanDashboardPageWidgetState();
}

class _ArtisanDashboardPageWidgetState extends State<ArtisanDashboardPageWidget>
    with TickerProviderStateMixin {
  late ArtisanDashboardPageModel _model;
  final scaffoldKey = GlobalKey<ScaffoldState>();
  bool _loadingProfile = true;

  // New local state: artisan-specific profile and kyc status and computed completion
  Map<String, dynamic>? _artisanProfile;
  // ignore: unused_field
  bool _hasArtisanProfile =
      false; // Set in load logic; previously read by the removed PROFILE SETUP card.
  bool _kycVerifiedLocal = false;
  String? _kycStatus;
  // Backend-supplied reason set on the latest rejected KYC submission (e.g.
  // "Selfie confidence below threshold (41.2/90)"). Read from TokenStorage on
  // mount and refreshed from `/api/kyc/status`. Surfaced verbatim on the
  // rejected card so the artisan knows what to fix on retry.
  String? _kycFailureReason;
  double _profileCompletion = 0.0;

  // Set true once `_initKycStatus()` (which reads the persisted status from
  // TokenStorage) has run for the first time. While false we suppress the
  // KYC-status card so the dashboard doesn't briefly render the "Continue
  // setup" variant on a freshly-mounted instance whose `_kycStatus` hasn't
  // been read yet — the cause of the previously-reported "card flashes
  // with 0%" issue right after the artisan finishes onboarding.
  bool _kycChecked = false;

  // Pending-retry state for the documented Dojah pending-resolution loop.
  // When an artisan lands on the dashboard with `_kycStatus == 'pending'`
  // we replay `verify-reference` up to `_kycMaxRetryAttempts` times in the
  // background, respecting any `retryAfterSeconds` hint from the backend.
  // This catches the case where the artisan finished onboarding but
  // Dojah's final result hadn't propagated server-side yet, so the
  // dashboard would otherwise stay on the "Verification pending" card
  // even after Dojah actually approved/rejected the record.
  static const int _kycMaxRetryAttempts = 5;
  static const Duration _kycRetryDefaultDelay = Duration(seconds: 5);
  Timer? _kycRetryTimer;
  int _kycRetryAttempts = 0;
  // Guards against re-entrancy if `_initKycStatus` runs again (e.g. after
  // `_fetchAuthoritativeKycStatus` updates state) while a retry chain is
  // already in flight.
  bool _kycRetryScheduled = false;

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
  Map<String, dynamic>? _currentUserProfile;
  String? _currentUserId;

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
      try {
        _applyCachedDashboardImmediate();
      } catch (_) {}
      try {
        _fetchUnreadNotifications();
      } catch (_) {}
    });

    // Defer heavy network and polling work until after the first frame to allow
    // the page to render quickly (reduce initial jank and perceived load time).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Run in a microtask to avoid blocking the frame callback itself.
      Future.microtask(() async {
        _startNotificationPolling();
        try {
          await _loadInitialData();
        } catch (_) {}
      });
    });

    // The dashboard is hosted inside NavBarPage (lib/main.dart), so its
    // State PERSISTS across in-app navigations like onboarding -> back.
    // That means `initState` only runs once — when the artisan finishes
    // KYC, returns here, the stale `_kycStatus` (read from TokenStorage on
    // the original mount) sticks until something else triggers a refresh.
    // Listening to AppStateNotifier closes that loop: whenever the global
    // profile changes (the onboarding flow calls `refreshProfile()` on
    // KYC success), we re-apply `kycDetails` against the cached profile
    // and the card / badge update without the artisan needing to
    // pull-to-refresh.
    try {
      AppStateNotifier.instance.addListener(_onGlobalAppStateChanged);
    } catch (_) {}
  }

  void _onGlobalAppStateChanged() {
    if (!mounted) return;
    final profile = AppStateNotifier.instance.profile;
    if (profile == null) return;
    // _applyKycFromProfile is idempotent and already deduplicates state
    // updates via setState — calling it on every notify is cheap.
    try {
      unawaited(_applyKycFromProfile(Map<String, dynamic>.from(profile)));
    } catch (_) {}
  }

  void _startNotificationPolling() {
    if (_notifAnimController != null) return;
    try {
      _notifAnimController = AnimationController(
          vsync: this, duration: const Duration(milliseconds: 800));
      _notifPulse = Tween<double>(begin: 1.0, end: 1.06).animate(
          CurvedAnimation(
              parent: _notifAnimController!, curve: Curves.easeInOut));
      _notifTimer?.cancel();
      _notifTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) _fetchUnreadNotifications();
      });
    } catch (_) {}
  }

  String? _extractUserId(Map<String, dynamic>? profile) {
    if (profile == null) return null;
    try {
      const candidates = ['_id', 'id', 'userId', 'user_id', 'uid'];
      for (final key in candidates) {
        final value = profile[key];
        if (value != null && value.toString().trim().isNotEmpty) {
          return value.toString().trim();
        }
      }
      if (profile['user'] is Map) {
        final nested = Map<String, dynamic>.from(profile['user']);
        for (final key in candidates) {
          final value = nested[key];
          if (value != null && value.toString().trim().isNotEmpty) {
            return value.toString().trim();
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _fetchUnreadNotifications() async {
    try {
      final count = await NotificationService.fetchUnreadCount();
      if (!mounted) return;
      setState(() {
        _unreadNotifications = (count >= 0) ? count : 0;
        if (_unreadNotifications > 0) {
          try {
            _notifAnimController?.repeat(reverse: true);
          } catch (_) {}
        } else {
          try {
            _notifAnimController?.stop();
          } catch (_) {}
        }
      });
    } catch (_) {}
  }

  Future<void> _loadCachedDashboard(
      {Map<String, dynamic>? currentProfile}) async {
    try {
      // Attempt to read cached dashboard data (now namespaced per user). To be
      // extra safe, also compare cached profile user id with the currently
      // authenticated user id and clear cache if they don't match.
      final cachedProfile = await TokenStorage.getDashboardProfile();
      final cached = await TokenStorage.getDashboardData();
      try {
        final currentId = _extractUserId(currentProfile ?? _currentUserProfile);
        if (cachedProfile != null &&
            currentId != null &&
            currentId.isNotEmpty) {
          // try several candidate paths for user id inside cached profile
          String? cachedId;
          try {
            cachedId = (cachedProfile['user']?['id'] ??
                    cachedProfile['user']?['_id'] ??
                    cachedProfile['user']?['userId'] ??
                    cachedProfile['_id'] ??
                    cachedProfile['id'])
                ?.toString();
          } catch (_) {
            cachedId = null;
          }
          if (cachedId == null || cachedId != currentId) {
            // mismatch: clear any dashboard cache for safety
            await TokenStorage.deleteDashboardCache();
            if (kDebugMode)
              debugPrint(
                  'ArtisanDashboard: cleared stale dashboard cache (cachedId=$cachedId currentId=$currentId)');
          }
        }
      } catch (e) {
        if (kDebugMode)
          debugPrint(
              'ArtisanDashboard: user id check for cached profile failed: $e');
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
              _model.displayName = (cachedProfile['name'] ??
                          cachedProfile['fullName'] ??
                          cachedProfile['username'])
                      ?.toString() ??
                  _model.displayName;
              _model.profileImageUrl = (cachedProfile['profileImage'] is Map)
                  ? cachedProfile['profileImage']['url']
                  : (cachedProfile['profileImage'] ??
                      cachedProfile['photo'] ??
                      _model.profileImageUrl ??
                      '');
              _model.profileData = Map<String, dynamic>.from(cachedProfile);
            });
          } else {
            if (kDebugMode)
              debugPrint(
                  'Cached dashboard profile belongs to different user (cachedId=$cachedId currentId=$currentId) - skipping cache apply');
          }
        } catch (e) {
          if (kDebugMode)
            debugPrint('Error verifying cached profile ownership: $e');
        }
      }

      if (cached != null && mounted) {
        try {
          // If a cached profile was found and we decided not to apply it
          // because it belongs to another user, skip applying dashboard data
          // as well. Otherwise it's safe to apply.
          final cachedProfileId = cachedProfile?['_id']?.toString();
          final currentId = _model.profileData?['_id']?.toString();
          if (cachedProfile != null &&
              cachedProfileId != null &&
              currentId != null &&
              cachedProfileId != currentId) {
            if (kDebugMode)
              debugPrint(
                  'Cached dashboard data belongs to a different user (cachedId=$cachedProfileId currentId=$currentId) - skipping dashboard cache');
          } else {
            setState(() {
              // expected payload keys: analytics, recentBookings, recentReviews, pendingJobs, averageRating
              _model.analytics =
                  Map<String, dynamic>.from(cached['analytics'] ?? cached);
              _model.recentBookings = (cached['recentBookings'] is List)
                  ? List<Map<String, dynamic>>.from(cached['recentBookings'])
                  : (cached['recentBookings'] ?? _model.recentBookings ?? []);
              _model.recentReviews = (cached['recentReviews'] is List)
                  ? List<Map<String, dynamic>>.from(cached['recentReviews'])
                  : (cached['recentReviews'] ?? _model.recentReviews ?? []);
              _model.pendingJobs = (cached['pendingJobs'] is int)
                  ? cached['pendingJobs']
                  : int.tryParse((cached['pendingJobs'] ?? '').toString()) ??
                      _model.pendingJobs;
              _model.averageRating = (cached['averageRating'] is num)
                  ? (cached['averageRating'] as num).toDouble()
                  : double.tryParse(
                          (cached['averageRating'] ?? '').toString()) ??
                      _model.averageRating;
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
      // Previously we used a cached 'kycVerified' boolean to pre-mark users as
      // verified. To ensure KYC only counts when the server has approved it,
      // avoid trusting that cached boolean here. Instead keep local state false
      // until authoritative server confirmation arrives. We still read the
      // saved kyc status (e.g., 'pending') elsewhere via _initKycStatus().
      // This avoids prematurely marking users as verified based on stale cache.
      // final cached = await TokenStorage.getKycVerified();
      // if (cached != null && mounted) {
      //   setState(() {
      //     _model.isVerified = cached;
      //     _kycVerifiedLocal = cached;
      //   });
      // }
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to read cached kyc flag: $e');
    }
  }

  /// Apply `kycDetails` from a `/api/users/me` response as the
  /// authoritative KYC state. Persists to TokenStorage and updates local
  /// state so the dashboard's KYC card matches the backend on next build.
  ///
  /// Treats `null` profile, missing `kycDetails`, or status == `not_submitted`
  /// (the doc's explicit "no record yet" value) as "no KYC submitted" —
  /// status is cleared in storage and local state, so the dashboard falls
  /// back to the Continue Setup card.
  ///
  /// Returns the resolved status string (or null) so callers can short-
  /// circuit further fetches (e.g. skip `_fetchAuthoritativeKycStatus` when
  /// we already have authoritative data from profile).
  Future<String?> _applyKycFromProfile(Map<String, dynamic>? profile) async {
    if (profile == null) return _kycStatus;
    final details = profile['kycDetails'];
    if (details is! Map) {
      if (kDebugMode) {
        debugPrint('[Dashboard] profile has no kycDetails block');
      }
      return _kycStatus;
    }

    final rawStatus = details['status']?.toString();
    final rawReason = details['failureReason']?.toString();
    final isEmpty = rawStatus == null || rawStatus.isEmpty;
    final isNotSubmitted = rawStatus?.toLowerCase() == 'not_submitted';
    final String? status =
        (isEmpty || isNotSubmitted) ? null : rawStatus;
    final String? reason =
        (rawReason == null || rawReason.isEmpty || rawReason.toLowerCase() == 'null')
            ? null
            : rawReason;
    final sl = status?.toLowerCase();
    final keepReason = sl == 'rejected' || sl == 'failed';

    if (kDebugMode) {
      debugPrint(
          '[Dashboard] applyKycFromProfile -> status=$status reason=${keepReason ? reason : null}');
    }

    try {
      if (status != null) {
        await TokenStorage.saveKycStatus(status);
      } else {
        await TokenStorage.deleteKycStatus();
      }
      await TokenStorage.saveKycFailureReason(keepReason ? reason : null);
    } catch (e) {
      if (kDebugMode) debugPrint('[Dashboard] persist kycDetails failed: $e');
    }

    if (mounted) {
      setState(() {
        _kycStatus = status;
        _kycFailureReason = keepReason ? reason : null;
        _kycVerifiedLocal = sl == 'approved' ||
            sl == 'verified' ||
            sl == 'approved_by_admin' ||
            sl == 'success';
        if (_kycVerifiedLocal && !_model.isVerified) {
          _model.isVerified = true;
        }
        // Ensure the card render gate is open so the resolved variant
        // shows up immediately (no flash of empty/Continue Setup).
        _kycChecked = true;
      });
      try {
        _computeProfileCompletion();
      } catch (_) {}
      // Profile may have moved us off pending (e.g. server processed
      // Dojah while the app was backgrounded). Cancel any retries that
      // were targeting a now-stale pending state, and schedule fresh
      // ones if we're still pending.
      final statusL = status?.toLowerCase();
      final stillPending = statusL == 'pending' ||
          statusL == 'pending_review' ||
          statusL == 'in_review';
      if (!stillPending) {
        _cancelKycPendingRetry();
      } else if (!_kycRetryScheduled) {
        _maybeScheduleKycPendingRetry();
      }
    }
    return status;
  }

  /// Third-line defense for KYC state. Only called when both
  /// `/api/users/me` (profile.kycDetails) and `/api/kyc/status` failed to
  /// produce a record — typically when the backend is mid-write and the
  /// transient 404 race we've seen is in effect.
  ///
  /// Scoped intentionally to the LOGGED-IN user's own id (artisan _id when
  /// available, otherwise userId). This keeps the call safe to make from
  /// the dashboard (no possibility of leaking another user's status) and
  /// follows the user's "defense mechanism" framing — it's a self-check,
  /// not a lookup of other artisans.
  ///
  /// Returns the resolved status (and applies it + persists to storage)
  /// when the endpoint returned a real submitted record. Returns null when
  /// the endpoint confirms there's no record (`not_submitted` or empty),
  /// letting the caller proceed with state-clearing.
  Future<String?> _fetchArtisanKycStatusFallback() async {
    try {
      // Prefer the artisan profile _id since it's the doc's canonical id;
      // fall back to userId (also accepted per the doc).
      final artisanId = (_artisanProfile?['_id'] ??
              _artisanProfile?['id'] ??
              _currentUserId)
          ?.toString();
      if (artisanId == null || artisanId.isEmpty) {
        if (kDebugMode) {
          debugPrint(
              '[Dashboard] artisan-status fallback skipped — no artisan/user id available');
        }
        return null;
      }
      final token = await TokenStorage.getToken();
      final data = await KycService.getArtisanKycStatus(
        artisanIdOrUserId: artisanId,
        token: token,
      );
      if (data == null) return null;

      final rawStatus = data['status']?.toString();
      final rawReason = data['failureReason']?.toString();
      final isEmpty = rawStatus == null || rawStatus.isEmpty;
      final isNotSubmitted = rawStatus?.toLowerCase() == 'not_submitted';
      if (isEmpty || isNotSubmitted) {
        if (kDebugMode) {
          debugPrint(
              '[Dashboard] artisan-status fallback confirms no record (status=$rawStatus)');
        }
        return null;
      }
      final reason =
          (rawReason == null || rawReason.isEmpty || rawReason.toLowerCase() == 'null')
              ? null
              : rawReason;
      final sl = rawStatus.toLowerCase();
      final keepReason = sl == 'rejected' || sl == 'failed';
      final verified = sl == 'approved' ||
          sl == 'verified' ||
          sl == 'approved_by_admin' ||
          sl == 'success';

      try {
        await TokenStorage.saveKycStatus(rawStatus);
        await TokenStorage.saveKycFailureReason(keepReason ? reason : null);
      } catch (_) {}

      if (mounted) {
        setState(() {
          _kycStatus = rawStatus;
          _kycFailureReason = keepReason ? reason : null;
          _kycVerifiedLocal = verified;
          if (verified && !_model.isVerified) _model.isVerified = true;
          _kycChecked = true;
        });
        try {
          _computeProfileCompletion();
        } catch (_) {}
      }
      return rawStatus;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Dashboard] artisan-status fallback failed: $e');
      }
      // On network/timeout/etc. don't return a fake null — return null but
      // log so callers know we couldn't confirm. The caller already only
      // clears state when ALL sources agree there's no record, so a thrown
      // fallback won't cause an over-eager wipe.
      return null;
    }
  }

  Future<void> _initKycStatus() async {
    try {
      // Read status and reason in parallel — both live in TokenStorage and
      // are written together by the onboarding flow, so we want them
      // hydrated as a unit.
      final results = await Future.wait([
        TokenStorage.getKycStatus(),
        TokenStorage.getKycFailureReason(),
      ]);
      if (!mounted) return;
      setState(() {
        _kycStatus = results[0];
        _kycFailureReason = results[1];
        _kycChecked = true;
      });
      // Kick off the documented pending-retry loop (replay verify-reference
      // in the background) when we land here with a pending status. Safe
      // to call unconditionally — the method itself bails when status
      // isn't pending or when a retry chain is already running.
      _maybeScheduleKycPendingRetry();
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to read saved kyc status: $e');
      if (mounted) {
        setState(() {
          _kycChecked = true;
        });
      }
    }
  }

  /// If the dashboard is rendering a pending KYC card AND we have a saved
  /// Dojah `referenceId` from onboarding, schedule a background replay of
  /// `POST /api/kyc/dojah/verify-reference` per the documented
  /// pending-resolution flow. Caps at `_kycMaxRetryAttempts` and respects
  /// the `retryAfterSeconds` hint that the backend returns on a still-
  /// pending response. Bails immediately when status flips to
  /// approved/rejected, when the artisan refreshes (which calls
  /// `_fetchAuthoritativeKycStatus` directly), or when this widget
  /// unmounts. Idempotent — re-running while a chain is in flight is a
  /// no-op.
  void _maybeScheduleKycPendingRetry({Duration? initialDelay}) {
    if (!mounted || _kycRetryScheduled) return;
    final s = _kycStatus?.toLowerCase();
    final isPending =
        s == 'pending' || s == 'pending_review' || s == 'in_review';
    if (!isPending) return;

    _kycRetryScheduled = true;
    _kycRetryAttempts = 0;
    final delay = initialDelay ?? _kycRetryDefaultDelay;
    if (kDebugMode) {
      debugPrint(
          '[Dashboard] KYC pending — scheduling verify-reference retry #1 in ${delay.inSeconds}s');
    }
    _kycRetryTimer?.cancel();
    _kycRetryTimer = Timer(delay, _runKycPendingRetry);
  }

  Future<void> _runKycPendingRetry() async {
    if (!mounted) {
      _kycRetryScheduled = false;
      return;
    }
    // Snapshot the status at fire-time. The user may have refreshed or
    // the auth-status fetch may have already moved us off pending.
    final s = _kycStatus?.toLowerCase();
    final isPending =
        s == 'pending' || s == 'pending_review' || s == 'in_review';
    if (!isPending) {
      _cancelKycPendingRetry();
      return;
    }

    _kycRetryAttempts++;
    if (_kycRetryAttempts > _kycMaxRetryAttempts) {
      if (kDebugMode) {
        debugPrint(
            '[Dashboard] KYC pending-retry: hit cap ($_kycMaxRetryAttempts) — backing off. Refresh/reopen will pick up later.');
      }
      _cancelKycPendingRetry();
      return;
    }

    final referenceId = await TokenStorage.getKycReferenceId();
    if (referenceId == null || referenceId.isEmpty) {
      if (kDebugMode) {
        debugPrint(
            '[Dashboard] KYC pending-retry: no saved referenceId — nothing to replay');
      }
      _cancelKycPendingRetry();
      return;
    }
    final token = await TokenStorage.getToken();
    if (token == null || token.isEmpty) {
      _cancelKycPendingRetry();
      return;
    }

    if (kDebugMode) {
      debugPrint(
          '[Dashboard] KYC pending-retry attempt $_kycRetryAttempts/$_kycMaxRetryAttempts referenceId=$referenceId');
    }

    Map<String, dynamic>? result;
    try {
      result = await KycService.verifyDojahReference(
        referenceId: referenceId,
        token: token,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Dashboard] KYC pending-retry network error: $e');
      }
      // Schedule another attempt — network errors are transient.
      _scheduleNextKycRetry(_kycRetryDefaultDelay);
      return;
    }

    if (!mounted) {
      _kycRetryScheduled = false;
      return;
    }

    final newStatus = result['status']?.toString();
    final newReason = result['failureReason']?.toString();
    final sl = newStatus?.toLowerCase();
    final stillPending = sl == 'pending' || sl == 'pending_review';

    if (kDebugMode) {
      debugPrint(
          '[Dashboard] KYC pending-retry result: status=$newStatus reason=$newReason');
    }

    if (!stillPending && newStatus != null && newStatus.isNotEmpty) {
      // Terminal — persist + update local state, then stop retrying.
      try {
        await TokenStorage.saveKycStatus(newStatus);
        if (sl == 'rejected' || sl == 'failed') {
          await TokenStorage.saveKycFailureReason(newReason);
        } else {
          await TokenStorage.saveKycFailureReason(null);
        }
        // Wipe the referenceId — the KYC record is finalised; no further
        // verify-reference replays should happen for this submission.
        await TokenStorage.saveKycReferenceId(null);
      } catch (_) {}
      if (mounted) {
        setState(() {
          _kycStatus = newStatus;
          _kycFailureReason =
              (sl == 'rejected' || sl == 'failed') ? newReason : null;
          final approved = sl == 'approved' ||
              sl == 'verified' ||
              sl == 'success' ||
              sl == 'approved_by_admin';
          _kycVerifiedLocal = approved;
          if (approved) _model.isVerified = true;
        });
        try {
          _computeProfileCompletion();
        } catch (_) {}
      }
      _cancelKycPendingRetry();
      return;
    }

    // Still pending — schedule another attempt. Honour
    // `retryAfterSeconds` when present, otherwise use the default.
    Duration nextDelay = _kycRetryDefaultDelay;
    try {
      final raw = result['retryAfterSeconds'];
      final secs = raw is num
          ? raw.toInt()
          : (raw is String ? int.tryParse(raw) : null);
      if (secs != null) {
        // Clamp to a sane band so a bad value can't pin us at 0s or 10min.
        nextDelay = Duration(seconds: secs.clamp(2, 30));
      }
    } catch (_) {}
    _scheduleNextKycRetry(nextDelay);
  }

  void _scheduleNextKycRetry(Duration delay) {
    if (!mounted) {
      _kycRetryScheduled = false;
      return;
    }
    if (_kycRetryAttempts >= _kycMaxRetryAttempts) {
      _cancelKycPendingRetry();
      return;
    }
    if (kDebugMode) {
      debugPrint(
          '[Dashboard] KYC pending-retry: next attempt in ${delay.inSeconds}s');
    }
    _kycRetryTimer?.cancel();
    _kycRetryTimer = Timer(delay, _runKycPendingRetry);
  }

  void _cancelKycPendingRetry() {
    _kycRetryTimer?.cancel();
    _kycRetryTimer = null;
    _kycRetryScheduled = false;
    _kycRetryAttempts = 0;
  }

  Future<void> _loadInitialData() async {
    // Ensure we fetch the authoritative profile first, then apply any cached
    // dashboard/profile data scoped to that profile, then fetch live dashboard
    // data. This prevents cached data from a different user being applied to
    // a newly-created account.
    final profile = await _loadProfile();
    // Apply cached dashboard/profile only after we have the current profile
    // (so we can verify the cached payload belongs to the same user).
    await _loadCachedDashboard(currentProfile: profile);
    unawaited(_loadDashboardData(profile: profile));
    unawaited(_fetchAuthoritativeKycStatus());

    // Legacy onboard reminder popup. Replaced by the dedicated
    // ArtisanOnboardingWidget post-OTP flow + just-in-time action prompts;
    // the dashboard no longer nags. Kept commented for reference.
    // Future.delayed(const Duration(seconds: 3), () {
    //   try {
    //     _maybeShowOnboardReminder();
    //   } catch (_) {}
    // });
  }

  // Legacy: show a one-time (or until dismissed) reminder to new artisans who
  // haven't set location, completed profile, or done KYC. The dialog offers
  // direct actions to open the location bottom sheet, profile page, or KYC flow.
  // Replaced by ArtisanOnboardingWidget; kept here for reference/rollback.
  // ignore: unused_element
  Future<void> _maybeShowOnboardReminder() async {
    if (!mounted) return;
    try {
      final already = await TokenStorage.getOnboardReminderShown();
      if (already == true) return; // user opted out or already handled

      // Verify this user is an artisan (best-effort): check stored role or profile data.
      final role = await TokenStorage.getRole();
      final bool isArtisanRole =
          (role != null && role.toLowerCase() == 'artisan') ||
              (_model.profileData != null &&
                  (_model.profileData!['role']?.toString().toLowerCase() ==
                          'artisan' ||
                      (_model.profileData!['roles'] is List &&
                          (_model.profileData!['roles'] as List)
                              .contains('artisan'))));
      if (!isArtisanRole) return;

      // Check missing items
      final hasLocation = (_model.userLocation != null &&
          _model.userLocation!.trim().isNotEmpty);
      final needsProfile =
          _profileCompletion < 0.8; // encourage >80% completion
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

      final message =
          'To be more visible to customers and get more jobs, please ${missing.join(', ')}.';

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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                        child: Icon(Icons.info_outline,
                            color: colorScheme.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Complete your setup',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.85)),
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
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
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
                          side: BorderSide(
                              color: colorScheme.onSurface.withOpacity(0.12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          Navigator.of(ctx).pop();
                          try {
                            await context.pushNamed(
                                ArtisanProfileupdateWidget.routeName);
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
                        label: Text(_kycStatus == 'pending'
                            ? 'KYC request pending'
                            : 'Complete KYC'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colorScheme.primary,
                          side: BorderSide(
                              color: colorScheme.onSurface.withOpacity(0.12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: (_kycStatus == 'pending')
                            ? null
                            : () async {
                                Navigator.of(ctx).pop();
                                try {
                                  final status =
                                      await TokenStorage.getKycStatus();
                                  if (status == 'pending') {
                                    await showDialog<void>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title:
                                            const Text('Awaiting KYC approval'),
                                        content: const Text(
                                            'Your KYC request is pending admin review. We will notify you when it is approved.'),
                                        actions: [
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.of(ctx).pop(),
                                              child: const Text('OK'))
                                        ],
                                      ),
                                    );
                                  } else {
                                    // Legacy reminder dialog (function is
                                    // currently unreferenced — `// ignore:
                                    // unused_element`) but keep the route in
                                    // sync with the new onboarding flow so it
                                    // works correctly if ever re-enabled.
                                    await Navigator.of(context).push(
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                const ArtisanOnboardingWidget()));
                                    await TokenStorage.saveOnboardReminderShown(
                                        true);
                                  }
                                } catch (_) {}
                              },
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      TextButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                        },
                        child: Text('Remind me later',
                            style: theme.textTheme.labelLarge?.copyWith(
                                color: colorScheme.onSurface.withOpacity(0.8))),
                      ),
                      TextButton(
                        onPressed: () async {
                          await TokenStorage.saveOnboardReminderShown(true);
                          Navigator.of(ctx).pop();
                        },
                        child: Text('Don\'t show again',
                            style: theme.textTheme.labelLarge?.copyWith(
                                color: colorScheme.onSurface.withOpacity(0.8))),
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
    // Order matters: profile must finish before kyc/status fires so that
    // _fetchAuthoritativeKycStatus can read `_currentUserProfile.kycDetails`
    // and ignore the transient 404 "No KYC record" we've seen from
    // /api/kyc/status immediately after a fresh submission. Without this
    // ordering, pull-to-refresh would race and occasionally wipe pending
    // state, forcing the user to refresh again — the very bug this code
    // exists to fix.
    await Future.wait([
      _loadProfile(),
      _loadDashboardData(),
    ]);
    await _fetchAuthoritativeKycStatus();
    // refresh complete
  }

  Future<Map<String, dynamic>?> _loadProfile() async {
    if (!mounted) return null;

    try {
      final profile = await UserService.getProfile();
      if (profile == null) return null;
      _currentUserProfile = Map<String, dynamic>.from(profile);
      _currentUserId = _extractUserId(_currentUserProfile);

      String? resolvedLocation;
      try {
        final loc = await UserService.getCanonicalLocation();
        final addr =
            (loc?['address'] ?? loc?['name'] ?? loc?['label'])?.toString();
        if (addr != null && addr.isNotEmpty) {
          resolvedLocation = addr;
        }
      } catch (_) {}
      resolvedLocation ??= profile['location']?.toString();
      if ((resolvedLocation == null || resolvedLocation.isEmpty) &&
          profile['address'] is Map &&
          profile['address']['city'] != null) {
        resolvedLocation = profile['address']['city'].toString();
      }
      if ((resolvedLocation == null || resolvedLocation.isEmpty) &&
          profile['city'] != null) {
        resolvedLocation = profile['city'].toString();
      }

      // Primary user fields
      if (mounted) {
        setState(() {
          _model.displayName =
              (profile['name'] ?? profile['fullName'] ?? profile['username'])
                      ?.toString() ??
                  'Artisan';
          _model.profileImageUrl = (profile['profileImage'] is Map)
              ? profile['profileImage']['url']
              : (profile['profileImage'] ?? profile['photo'] ?? '');
          _model.profileData = Map<String, dynamic>.from(profile);
          if (resolvedLocation != null && resolvedLocation.isNotEmpty) {
            _model.userLocation = resolvedLocation;
          }
        });
      }

      // Extract verification status and save locally
      bool normalizedKyc = false;
      try {
        final v = profile['isVerified'] ??
            profile['verified'] ??
            profile['kycVerified'];
        if (v is bool)
          normalizedKyc = v;
        else if (v != null) {
          final s = v.toString().toLowerCase();
          normalizedKyc = (s == 'true' || s == '1');
        }
      } catch (_) {}

      // Do not mark the app-level verified flag based on the local profile
      // object alone. KYC must be confirmed by the authoritative kyc/status
      // endpoint. We keep normalizedKyc available for diagnostics but do not
      // call TokenStorage.saveKycVerified(normalizedKyc) nor set
      // _model.isVerified here.
      if (kDebugMode)
        debugPrint(
            'Local profile reported kyc verified: $normalizedKyc (waiting for authoritative confirmation)');

      // The backend now ships a `kycDetails` block on `/api/users/me`
      // (see dojah-kyc-status-updates.md). This is the most reliable
      // KYC source — `/api/kyc/status` has been observed returning
      // a transient 404 "No KYC record" right after a fresh submission,
      // which would otherwise wipe local pending state and force the
      // user to refresh the dashboard before the pending card appears.
      // Applying `kycDetails` here makes the dashboard self-healing.
      try {
        await _applyKycFromProfile(profile);
      } catch (e) {
        if (kDebugMode) debugPrint('applyKycFromProfile failed: $e');
      }

      // Fetch artisan profile (if any) for artisan-specific fields
      try {
        bool _isArtisanDocument(Map<String, dynamic>? doc) {
          if (doc == null) return false;
          try {
            final markers = [
              'trade',
              'portfolio',
              'pricing',
              'serviceArea',
              'availability',
              'experience',
              'bio'
            ];
            for (final m in markers) {
              if (doc.containsKey(m) && doc[m] != null) return true;
            }
            if (doc['user'] is Map) {
              final u = Map<String, dynamic>.from(doc['user']);
              final role =
                  (u['role'] ?? u['type'] ?? '').toString().toLowerCase();
              if (role.contains('artisan')) return true;
            }
            final r = (doc['role'] ?? doc['type'] ?? doc['accountType'] ?? '')
                .toString()
                .toLowerCase();
            if (r.contains('artisan')) return true;
          } catch (_) {}
          return false;
        }

        Map<String, dynamic>? artisan;
        if (_currentUserId != null && _currentUserId!.isNotEmpty) {
          artisan = await ArtistService.getByUserId(_currentUserId!);
        } else {
          artisan = await ArtistService.getMyProfile();
        }
        // print(artisan);
        if (artisan != null && _isArtisanDocument(artisan)) {
          if (mounted)
            setState(() {
              _artisanProfile = artisan;
              _hasArtisanProfile = true;
            });
        } else {
          // If getMyProfile returned null or looked like a user object, attempt to resolve via user id
          try {
            String? userId = _currentUserId;
            if (userId == null || userId.isEmpty) {
              try {
                userId = await TokenStorage.getUserId();
              } catch (_) {
                userId = null;
              }
            }
            if (userId != null && userId.isNotEmpty) {
              debugPrint('ssf');
              final byUser = await ArtistService.getByUserId(userId);
              debugPrint('Artisan profile existence check: $byUser');
              if (byUser != null && _isArtisanDocument(byUser)) {
                if (mounted)
                  setState(() {
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
            if (kDebugMode)
              debugPrint('Artisan profile existence check failed: $e');
            if (mounted) setState(() => _hasArtisanProfile = false);
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Failed to fetch artisan profile: $e');
      }

      // If the artisan profile contains an admin-verified flag, prefer that as
      // authoritative proof of KYC verification. Some server flows set
      // verification on the artisan document before the user object is
      // updated, so check the artisan document for 'isVerified'/'verified' or
      // 'kycVerified' and update local state accordingly.
      //
      // GUARD (added 2026-05-11): per the dojah-kyc-status-updates doc,
      // `/api/users/me`'s `kycDetails.status` is the authoritative KYC
      // truth. We've observed cases where the artisan document still
      // carries `verified: true` (legacy / stale / out-of-sync) even
      // though kycDetails.status is "pending" or "rejected" — that
      // would paint a "KYC verified" badge while the card variant shows
      // pending/rejected, confusing the artisan. Only honor the artisan
      // flag when kycDetails ALSO agrees (approved) or is missing
      // entirely (legacy backend with no kycDetails yet).
      try {
        final details = profile['kycDetails'];
        final detailsStatus = (details is Map)
            ? details['status']?.toString().toLowerCase()
            : null;
        final kycDetailsContradictsApproved = detailsStatus != null &&
            detailsStatus.isNotEmpty &&
            detailsStatus != 'approved' &&
            detailsStatus != 'verified' &&
            detailsStatus != 'success' &&
            detailsStatus != 'approved_by_admin';

        final ap = _artisanProfile;
        if (ap != null && !kycDetailsContradictsApproved) {
          bool artisanVerified = false;
          try {
            final cand =
                ap['isVerified'] ?? ap['verified'] ?? ap['kycVerified'];
            if (cand is bool)
              artisanVerified = cand;
            else if (cand != null) {
              final sl = cand.toString().toLowerCase();
              artisanVerified = (sl == 'true' ||
                  sl == '1' ||
                  sl == 'approved' ||
                  sl == 'verified');
            }
            // also check nested user object inside artisan document
            if (!artisanVerified && ap['user'] is Map) {
              final u = Map<String, dynamic>.from(ap['user']);
              final ucand =
                  u['isVerified'] ?? u['verified'] ?? u['kycVerified'];
              if (ucand is bool)
                artisanVerified = ucand;
              else if (ucand != null) {
                final sl = ucand.toString().toLowerCase();
                artisanVerified = (sl == 'true' ||
                    sl == '1' ||
                    sl == 'approved' ||
                    sl == 'verified');
              }
            }
          } catch (_) {}

          if (artisanVerified && mounted) {
            setState(() {
              _kycVerifiedLocal = true;
              _model.isVerified = true;
              _kycStatus = 'approved';
            });
            try {
              await TokenStorage.saveKycStatus('approved');
            } catch (_) {}
          }
        } else if (ap != null && kycDetailsContradictsApproved) {
          // Active drift case — log loudly so we can spot stale artisan
          // docs in the wild without having to dig.
          if (kDebugMode) {
            final ac = ap['isVerified'] ?? ap['verified'] ?? ap['kycVerified'];
            debugPrint(
                '[Dashboard] ignoring artisan.verified=$ac because kycDetails.status=$detailsStatus is authoritative');
          }
          // Belt-and-braces: ensure the AppBar badge isn't lit just
          // because the artisan doc disagrees with kycDetails.
          if (_model.isVerified && mounted) {
            setState(() {
              _model.isVerified = false;
              _kycVerifiedLocal = false;
            });
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('artisan verification detection failed: $e');
      }

      // Compute completion percentage using both user profile and artisan-specific profile
      _computeProfileCompletion();
      // Save profile cache for fast subsequent loads
      try {
        final toSave = _model.profileData != null
            ? Map<String, dynamic>.from(_model.profileData!)
            : <String, dynamic>{};
        await TokenStorage.saveDashboardProfile(toSave);
      } catch (e) {
        if (kDebugMode)
          debugPrint('Failed to save dashboard profile cache: $e');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error loading profile: $e');
    } finally {
      if (mounted) setState(() => _loadingProfile = false);
    }
    return _currentUserProfile;
  }

  // Fetch authoritative KYC status from server without blocking profile load
  Future<void> _fetchAuthoritativeKycStatus() async {
    try {
      final kycUri = Uri.parse('$API_BASE_URL/api/kyc/status');
      // ApiClient.get doesn't log requests/responses (unlike KycService),
      // so add an explicit trace here so we can see whether this endpoint
      // is being called and what it returned. This is the only way to spot
      // the documented /api/kyc/status 404 race vs the kycDetails block on
      // /api/users/me — without it the call runs silently.
      if (kDebugMode) {
        debugPrint('[Dashboard] _fetchAuthoritativeKycStatus -> GET $kycUri');
      }
      final resp = await ApiClient.get(kycUri.toString(),
          headers: {'Content-Type': 'application/json'});
      final status = resp['status'] as int? ?? 0;
      final body = resp['body']?.toString() ?? '';
      if (kDebugMode) {
        debugPrint(
            '[Dashboard] _fetchAuthoritativeKycStatus <- status=$status body=$body');
      }

      if (body.isNotEmpty) {
        try {
          final decoded = jsonDecode(body);

          // `/api/kyc/status` has been observed returning 404 / "No KYC
          // record" right after a fresh submission while `/api/users/me`
          // correctly reports `kycDetails.status = "pending"`. Per the
          // backend's dojah-kyc-status-updates doc, `kycDetails` on the
          // user profile is the authoritative source — so before wiping
          // local state, check whether the cached profile (just refreshed
          // by `_loadProfile`) actually has a kycDetails block. If yes,
          // trust profile and IGNORE the 404. Only clear when both
          // endpoints agree there's no record.
          if (decoded is Map &&
              (decoded['success'] == false || status >= 400) &&
              (decoded['message']
                      ?.toString()
                      .toLowerCase()
                      .contains('no kyc record') ==
                  true)) {
            final cachedDetails = _currentUserProfile?['kycDetails'];
            final cachedStatus = (cachedDetails is Map)
                ? cachedDetails['status']?.toString()
                : null;
            final hasProfileKyc = cachedStatus != null &&
                cachedStatus.isNotEmpty &&
                cachedStatus.toLowerCase() != 'not_submitted';

            if (hasProfileKyc) {
              if (kDebugMode) {
                debugPrint(
                    '[Dashboard] /api/kyc/status 404 ignored — profile.kycDetails.status=$cachedStatus is authoritative');
              }
              // Don't clear anything. _loadProfile -> _applyKycFromProfile
              // has already set the right state.
              return;
            }

            // Third-line defense: before nuking local state, try the new
            // `/api/kyc/artisan/:id/status` endpoint with the current user's
            // id. This endpoint is the doc's dedicated "check artisan KYC"
            // route — using it as a cross-check guards against the same
            // backend race we already saw between /api/users/me and
            // /api/kyc/status. We only trust it when it returns a concrete
            // submitted status; "not_submitted" or null still falls through
            // to the clear-state path.
            final artisanCheckStatus =
                await _fetchArtisanKycStatusFallback();
            if (artisanCheckStatus != null) {
              if (kDebugMode) {
                debugPrint(
                    '[Dashboard] /api/kyc/status 404 ignored — /api/kyc/artisan/:id/status returned $artisanCheckStatus');
              }
              return;
            }

            if (kDebugMode)
              debugPrint(
                  'No KYC record found (all three endpoints agree). Clearing local KYC status.');
            await TokenStorage.deleteKycStatus();
            await TokenStorage.deleteKycVerified();

            if (mounted) {
              setState(() {
                _kycVerifiedLocal = false;
                _kycStatus = null;
                _kycFailureReason = null;
                _model.isVerified = false;
              });
              try {
                _computeProfileCompletion();
              } catch (_) {}
            }
            return;
          }
        } catch (_) {}
      }

      if (status >= 200 && status < 300 && body.isNotEmpty) {
        try {
          final decoded = jsonDecode(body);
          bool verified = false;
          String? parsedStatus;
          String? parsedFailureReason;

          if (decoded is Map) {
            final data = decoded['data'] ?? decoded;

            // 1) If server returns a data.status string (e.g. 'pending'|'approved'), prefer that
            try {
              final s = (data is Map) ? data['status'] : null;
              if (s != null) parsedStatus = s.toString();
            } catch (_) {}

            // failureReason — populated by the backend on rejected /
            // failed submissions. Stored alongside the status so the
            // dashboard's rejected card can show the artisan a specific
            // reason instead of generic copy.
            try {
              final r = (data is Map) ? data['failureReason'] : null;
              if (r != null && r.toString().isNotEmpty) {
                parsedFailureReason = r.toString();
              }
            } catch (_) {}

            // 2) If a boolean 'verified' is present, use it
            try {
              final v = (data is Map) ? data['verified'] : null;
              if (v != null) {
                if (v is bool)
                  verified = v;
                else {
                  final sl = v.toString().toLowerCase();
                  verified = (sl == 'true' ||
                      sl == '1' ||
                      sl == 'verified' ||
                      sl == 'approved');
                }
              }
            } catch (_) {}

            // 3) Fallback: top-level decoded['verified'] or decoded['status']
            if (!verified) {
              try {
                if (decoded['verified'] != null) {
                  final v = decoded['verified'];
                  if (v is bool)
                    verified = v;
                  else {
                    final sl = v.toString().toLowerCase();
                    verified = (sl == 'true' ||
                        sl == '1' ||
                        sl == 'verified' ||
                        sl == 'approved');
                  }
                }
              } catch (_) {}
            }
            if (parsedStatus == null) {
              try {
                final top = decoded['status'];
                if (top != null) parsedStatus = top.toString();
              } catch (_) {}
            }
            if (parsedFailureReason == null) {
              try {
                final r = decoded['failureReason'];
                if (r != null && r.toString().isNotEmpty) {
                  parsedFailureReason = r.toString();
                }
              } catch (_) {}
            }

            // STATUS WINS over `verified`. We've observed the backend
            // sending `verified: true` alongside `status: "pending"` and
            // `verifiedAt: null` — i.e. a flat-out contradiction. When
            // they disagree, status is the truth (matches the
            // dojah-kyc-status-updates doc's "approved/pending/rejected"
            // contract). Override `verified` to be derived purely from
            // status when status is present.
            if (parsedStatus != null) {
              final sl = parsedStatus.toLowerCase();
              final statusSaysApproved = sl == 'approved' ||
                  sl == 'verified' ||
                  sl == 'success' ||
                  sl == 'approved_by_admin';
              if (verified && !statusSaysApproved) {
                if (kDebugMode) {
                  debugPrint(
                      '[Dashboard] /api/kyc/status returned verified=true but status=$parsedStatus — trusting status, forcing verified=false');
                }
              }
              verified = statusSaysApproved;
            }
          }

          // Treat the backend's explicit 'not_submitted' the same as null
          // locally — it means there's no KYC record yet, and the dashboard
          // card-routing logic expects a null status for that case.
          final ps = parsedStatus;
          if (ps != null && ps.toLowerCase() == 'not_submitted') {
            parsedStatus = null;
            parsedFailureReason = null;
            try {
              await TokenStorage.deleteKycStatus();
            } catch (_) {}
          } else if (ps != null && ps.isNotEmpty) {
            // Persist the resolved status string for other parts of the app
            // that read TokenStorage.getKycStatus().
            try {
              if (mounted) await TokenStorage.saveKycStatus(ps);
            } catch (_) {}
          }

          // Keep the persisted failure reason in lockstep with the status:
          // populate it on rejected/failed, wipe it otherwise so a stale
          // reason from an earlier attempt doesn't reappear once the artisan
          // re-submits.
          try {
            final sl = parsedStatus?.toLowerCase();
            if (sl == 'rejected' || sl == 'failed') {
              await TokenStorage.saveKycFailureReason(parsedFailureReason);
            } else {
              await TokenStorage.saveKycFailureReason(null);
            }
          } catch (_) {}

          if (mounted) {
            setState(() {
              _kycVerifiedLocal = verified;
              _kycStatus = parsedStatus;
              final sl = parsedStatus?.toLowerCase();
              _kycFailureReason =
                  (sl == 'rejected' || sl == 'failed') ? parsedFailureReason : null;
              // Sync `_model.isVerified` in BOTH directions. Previously
              // this only flipped on (verified=true), which let a stale
              // earlier code path leave the AppBar badge lit even after
              // status told us we weren't verified. Now it tracks
              // `verified` exactly, so pending/rejected force the badge off.
              _model.isVerified = verified;
            });
            // Recompute profile completion so UI updates immediately when KYC status changes
            try {
              _computeProfileCompletion();
            } catch (_) {}
          }
        } catch (e) {
          if (kDebugMode) debugPrint('Failed parse kyc/status: $e');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('KYC status fetch failed: $e');
    }
  }

  Future<void> _loadDashboardData({Map<String, dynamic>? profile}) async {
    try {
      // Try role-aware central dashboard endpoint first (returns artisan-specific 'mine' data)
      try {
        final centralUrl = '$API_BASE_URL/api/admin/central?limit=10';
        final resp = await ApiClient.get(centralUrl,
            headers: {'Content-Type': 'application/json'});
        final status = resp['status'] as int? ?? 0;
        final body = resp['body']?.toString() ?? '';
        if (status >= 200 && status < 300 && body.isNotEmpty) {
          final decoded = jsonDecode(body);
          final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
          if (data is Map && data['mine'] is Map) {
            final mine = Map<String, dynamic>.from(data['mine']);
            // extract wallet metrics if present
            final wallet = mine['wallet'] is Map
                ? Map<String, dynamic>.from(mine['wallet'])
                : <String, dynamic>{};
            if (kDebugMode) {
              debugPrint(
                  '[Dashboard] GET $centralUrl -> wallet block: $wallet');
            }
            final bookings = (mine['bookings'] is List)
                ? List<Map<String, dynamic>>.from(mine['bookings'])
                : <Map<String, dynamic>>[];
            final reviews = (mine['reviews'] is List)
                ? List<Map<String, dynamic>>.from(mine['reviews'])
                : <Map<String, dynamic>>[];
            final transactions = (mine['transactions'] is List)
                ? List<Map<String, dynamic>>.from(mine['transactions'])
                : <Map<String, dynamic>>[];

            int computedCompleted = 0;
            int computedPending = 0;
            int computedEarnings = 0;
            for (final b in bookings) {
              try {
                final bk = b is Map
                    ? (b['booking'] is Map
                        ? Map<String, dynamic>.from(b['booking'])
                        : Map<String, dynamic>.from(b))
                    : <String, dynamic>{};
                final status = (bk['status'] ?? '').toString().toLowerCase();
                final priceVal =
                    bk['price'] ?? bk['amount'] ?? bk['priceAmount'] ?? 0;
                final price = priceVal is num
                    ? priceVal.toInt()
                    : int.tryParse(priceVal.toString()) ?? 0;
                if (status == 'pending') computedPending++;
                if (status == 'closed' ||
                    status == 'completed' ||
                    status == 'done' ||
                    status == 'paid') computedCompleted++;
                computedEarnings += price;
              } catch (_) {}
            }

            double avgRating = _model.averageRating;
            try {
              double sum = 0;
              int cnt = 0;
              for (final r in reviews) {
                final rv = r['rating'] ?? r['stars'] ?? r['score'];
                final val = rv == null ? null : double.tryParse(rv.toString());
                if (val != null) {
                  sum += val;
                  cnt++;
                }
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
            try {
              _startReviewsAutoScroll();
            } catch (_) {}
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
              if (kDebugMode)
                debugPrint('Failed to save dashboard data cache (central): $e');
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

      if ((_model.profileData == null || _model.profileData!['_id'] == null) &&
          profile != null &&
          mounted) {
        setState(() => _model.profileData = Map<String, dynamic>.from(profile));
      }

      final dashboardResults = await Future.wait([
        ArtistService.fetchArtisanBookings(artisanId, page: 1, limit: 5),
        ArtistService.fetchReviewsForArtisan(artisanId, page: 1, limit: 5),
      ]);
      final bookings = dashboardResults[0];
      final reviews = dashboardResults[1];

      // Calculate analytics
      int computedPending = 0;
      int computedCompleted = 0;
      int computedEarnings = 0;
      for (final b in bookings) {
        Map<String, dynamic> bk = {};
        try {
          final bmap = Map<String, dynamic>.from(b as Map);
          bk = bmap['booking'] is Map
              ? Map<String, dynamic>.from(bmap['booking'] as Map)
              : bmap;
        } catch (_) {}

        final status = (bk['status'] ?? '').toString().toLowerCase();
        final priceVal = bk['price'] ?? bk['amount'] ?? bk['priceAmount'] ?? 0;
        int price = 0;
        if (priceVal is int)
          price = priceVal;
        else
          price = int.tryParse(priceVal.toString()) ?? 0;

        if (status == 'pending') computedPending++;
        if (status == 'closed' ||
            status == 'completed' ||
            status == 'done' ||
            status == 'paid') computedCompleted++;
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
            if (val != null) {
              sum += val;
              cnt++;
            }
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
      try {
        _startReviewsAutoScroll();
      } catch (_) {}

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
          final id = _artisanProfile!['_id'] ??
              _artisanProfile!['id'] ??
              _artisanProfile!['userId'];
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

      // 2) Try to resolve by current user id first to avoid another profile fetch
      String? userId = _currentUserId;
      userId ??= _extractUserId(_model.profileData);
      if (userId == null || userId.isEmpty) {
        try {
          userId = await TokenStorage.getUserId();
        } catch (_) {
          userId = null;
        }
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

      // 3) Fallback to service helper
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

      // 4) Final fallback to a fresh token-storage user id lookup
      userId = null;
      try {
        userId = await TokenStorage.getUserId();
      } catch (_) {}
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
    _kycRetryTimer?.cancel();
    try {
      AppStateNotifier.instance.removeListener(_onGlobalAppStateChanged);
    } catch (_) {}
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
        color:
            isDark ? theme.colorScheme.surface : theme.colorScheme.background,
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isPositive
                        ? const Color(0xFFE8F5E8)
                        : const Color(0xFFFFF0F0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isPositive
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 12,
                        color: isPositive
                            ? const Color(0xFF16A34A)
                            : const Color(0xFFDC2626),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        change,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isPositive
                              ? const Color(0xFF16A34A)
                              : const Color(0xFFDC2626),
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

  // ---- Availability prompt helpers ---------------------------------------

  /// Returns true when the artisan profile has no availability set yet.
  /// Drives the visibility of the dashboard's availability prompt card.
  bool _artisanIsAvailabilityEmpty() {
    final av = _artisanProfile?['availability'];
    if (av == null) return true;
    if (av is List) return av.isEmpty;
    if (av is String) return av.trim().isEmpty;
    return true;
  }

  /// Hour-range presets that translate one tap into a complete weekly
  /// availability list. Format matches what the legacy profile-update flow
  /// stored: `Mon 09:00-17:00` etc. — readable AND parseable.
  static const Map<String, List<String>> _availabilityPresets = {
    'Weekdays 9–5': [
      'Mon 09:00-17:00',
      'Tue 09:00-17:00',
      'Wed 09:00-17:00',
      'Thu 09:00-17:00',
      'Fri 09:00-17:00',
    ],
    'Mon–Sat 8–6': [
      'Mon 08:00-18:00',
      'Tue 08:00-18:00',
      'Wed 08:00-18:00',
      'Thu 08:00-18:00',
      'Fri 08:00-18:00',
      'Sat 08:00-18:00',
    ],
    'Available 24/7': [
      'Mon 00:00-23:59',
      'Tue 00:00-23:59',
      'Wed 00:00-23:59',
      'Thu 00:00-23:59',
      'Fri 00:00-23:59',
      'Sat 00:00-23:59',
      'Sun 00:00-23:59',
    ],
  };

  Future<void> _openAvailabilitySheet() async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final onSurface = colorScheme.onSurface;
    final isDark = theme.brightness == Brightness.dark;
    // Sheet sits on top of the screen, so use cardColor (auto-adapts:
    // white in light, dark surface in dark).
    final sheetBg = theme.cardColor;
    // Preset tiles need a slight contrast against the sheet background.
    // In light mode the sheet is white so tiles can stay cardColor with
    // a 1px border. In dark mode tiles share cardColor too — the border
    // alone gives enough separation.
    final tileBorder = onSurface.withOpacity(0.12);
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: sheetBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: onSurface.withOpacity(isDark ? 0.18 : 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Set your availability',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: onSurface),
              ),
              const SizedBox(height: 6),
              Text(
                'Pick the option that fits you best. You can change it anytime.',
                style: TextStyle(
                    fontSize: 13,
                    color: onSurface.withOpacity(0.65),
                    height: 1.4),
              ),
              const SizedBox(height: 18),
              ..._availabilityPresets.entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    onTap: () => Navigator.of(sheetCtx).pop(entry.key),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: tileBorder,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.check_rounded,
                                color: colorScheme.primary, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.key,
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: onSurface),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${entry.value.length} day${entry.value.length == 1 ? '' : 's'} per week',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: onSurface.withOpacity(0.65),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.arrow_forward_rounded,
                              color: onSurface.withOpacity(0.45), size: 18),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
    if (picked == null) return;
    final list = _availabilityPresets[picked];
    if (list == null) return;
    await _saveAvailability(list);
  }

  Future<void> _saveAvailability(List<String> availability) async {
    try {
      final res = await ArtistService.updateMyProfile({
        'availability': availability,
      });
      if (!mounted) return;
      if (res != null) {
        setState(() {
          _artisanProfile ??= <String, dynamic>{};
          _artisanProfile!['availability'] = availability;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Availability saved'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        try {
          _computeProfileCompletion();
        } catch (_) {}
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't save availability. Please try again."),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('saveAvailability error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't save availability. Please try again."),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Single benefit row used inside the onboarding progress card.
  Widget _buildOnboardBenefit({
    required ThemeData theme,
    required Color successColor,
    required String text,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.check_circle_rounded, size: 18, color: successColor),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurface.withOpacity(0.85),
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  /// State-aware card sitting under the wallet on the dashboard. Shape
  /// switches on KYC status so the artisan always sees the right next step:
  ///   - pending / pending_review  -> "We're reviewing it" reassurance card
  ///   - rejected / failed / rejected_by_admin -> "Couldn't verify" card with retry CTA
  ///   - approved                  -> hidden (artisan is functionally set)
  ///   - null + incomplete setup   -> existing progress / "Continue setup" card
  /// Returns `SizedBox.shrink()` (rendering nothing) until `_kycChecked` is
  /// true so we don't briefly render the 0%-progress variant before the
  /// persisted status has been read from storage. The card was previously
  /// flashing right after the artisan finished onboarding because the server
  /// fetch hadn't returned yet on a fresh dashboard mount.
  Widget _buildKycStatusCard(
      ThemeData theme, ColorScheme colorScheme, FlutterFlowTheme ff) {
    if (!_kycChecked) return const SizedBox.shrink();

    final s = _kycStatus?.toLowerCase();
    final isApproved = s == 'approved' ||
        s == 'verified' ||
        s == 'success' ||
        s == 'approved_by_admin';
    if (isApproved) return const SizedBox.shrink();

    final isPending = s == 'pending' ||
        s == 'pending_review' ||
        s == 'in_review' ||
        s == 'submitted';
    final isRejected = s == 'rejected' ||
        s == 'failed' ||
        s == 'rejected_by_admin' ||
        s == 'declined';
    // The backend now returns 'not_submitted' as an explicit string when
    // the artisan has never started KYC. Treat it the same as a null
    // status so the Continue Setup branch picks it up.
    final isNotSubmitted = s == null || s.isEmpty || s == 'not_submitted';

    if (isPending) return _buildKycPendingCard(theme, colorScheme);
    if (isRejected) return _buildKycRejectedCard(theme, colorScheme);

    // No KYC submitted yet — show the existing onboarding progress card so
    // long as the artisan still has setup to finish. Once everything is done
    // (including KYC) `_isKycSectionComplete()` flips and the card hides.
    if (isNotSubmitted &&
        _profileCompletion < 1.0 &&
        !_isKycSectionComplete()) {
      return _buildContinueSetupCard(theme, colorScheme, ff);
    }
    return const SizedBox.shrink();
  }

  /// Reassurance card for artisans whose KYC submission is awaiting review.
  /// No CTA — they've done their part; the wait is on us. We push a notification
  /// when status flips so they don't need to keep refreshing.
  Widget _buildKycPendingCard(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.onSurface.withOpacity(0.1),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.hourglass_top_rounded,
                    color: colorScheme.primary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Verification pending',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "We'll notify you once it's done",
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            "Thanks for submitting your details, our team is reviewing them now. This usually takes a few minutes, occasionally longer during peak periods. You can keep using the app; we'll send a notification the moment your verification is complete.",
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.78),
              height: 1.45,
              fontSize: 13.5,
            ),
          ),
        ],
      ),
    );
  }

  /// Failure-state card. KYC came back rejected — we tell the artisan plainly,
  /// surface the backend's specific failureReason when available (e.g.
  /// "Selfie verification failed or confidence below threshold (41.2/90)"),
  /// and offer a one-tap retry that drops them back into the onboarding flow's
  /// identity-verification section.
  Widget _buildKycRejectedCard(ThemeData theme, ColorScheme colorScheme) {
    final errorColor = theme.colorScheme.error;
    final reason = _kycFailureReason?.trim();
    final hasReason = reason != null && reason.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: errorColor.withOpacity(0.35),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: errorColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.error_outline_rounded,
                    color: errorColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Verification didn't match",
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Please try again',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: errorColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            "We couldn't verify your identity with the details you submitted. Make sure your face is well-lit, your NIN is correct, then try again.",
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.78),
              height: 1.45,
              fontSize: 13.5,
            ),
          ),
          // When the backend returned a specific reason (confidence score,
          // NIN mismatch, etc.) show it in a tinted callout so it stands
          // apart from the generic copy and the artisan can act on it.
          if (hasReason) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: errorColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: errorColor.withOpacity(0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 16, color: errorColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      reason,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.85),
                        fontSize: 12.5,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: errorColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              onPressed: () async {
                try {
                  await context.push(ArtisanOnboardingWidget.routePath);
                } catch (_) {
                  if (!mounted) return;
                  try {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ArtisanOnboardingWidget(),
                      ),
                    );
                  } catch (_) {}
                }
                if (!mounted) return;
                try {
                  await _refreshData();
                } catch (_) {}
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Redo verification',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(width: 6),
                  Icon(Icons.refresh_rounded, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Pre-KYC progress card. Only shown when there's no KYC record yet AND the
  /// artisan still has setup steps left. Tapping "Continue setup" reopens the
  /// onboarding flow (it knows how to resume from wherever they stopped).
  Widget _buildContinueSetupCard(
      ThemeData theme, ColorScheme colorScheme, FlutterFlowTheme ff) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.onSurface.withOpacity(0.1),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.bolt_rounded,
                    color: colorScheme.primary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Almost there!',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${(_profileCompletion * 100).toInt()}% complete',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _profileCompletion,
              minHeight: 6,
              backgroundColor: colorScheme.primary.withOpacity(0.12),
              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            "Finish setting up so clients can start finding and booking you. It's quick and seamless — most artisans wrap it up in under 3 minutes.",
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.78),
              height: 1.45,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 14),
          _buildOnboardBenefit(
            theme: theme,
            successColor: ff.success,
            text: 'Get found by clients in your area',
          ),
          const SizedBox(height: 8),
          _buildOnboardBenefit(
            theme: theme,
            successColor: ff.success,
            text: 'Start receiving booking requests',
          ),
          const SizedBox(height: 8),
          _buildOnboardBenefit(
            theme: theme,
            successColor: ff.success,
            text: 'Build trust with a verified badge',
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              onPressed: () async {
                try {
                  await context.push(ArtisanOnboardingWidget.routePath);
                } catch (_) {
                  if (!mounted) return;
                  try {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ArtisanOnboardingWidget(),
                      ),
                    );
                  } catch (_) {}
                }
                if (!mounted) return;
                try {
                  await _refreshData();
                } catch (_) {}
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Continue setup',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(width: 6),
                  Icon(Icons.arrow_forward_rounded, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Legacy menu item used by the removed PROFILE SETUP card. Kept for
  // rollback per the project's "comment, don't remove" preference.
  // ignore: unused_element
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
    final titleColor =
        enabled ? null : theme.colorScheme.onSurface.withOpacity(0.4);
    final subtitleColor = enabled
        ? theme.colorScheme.onSurface.withOpacity(0.6)
        : theme.colorScheme.onSurface.withOpacity(0.35);

    return ListTile(
      onTap: effectiveOnTap,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: (iconColor ?? theme.colorScheme.primary)
              .withOpacity(enabled ? 0.1 : 0.04),
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
          _model.displayName = (cachedProfile['name'] ??
                      cachedProfile['fullName'] ??
                      cachedProfile['username'])
                  ?.toString() ??
              _model.displayName;
          _model.profileImageUrl = (cachedProfile['profileImage'] is Map)
              ? cachedProfile['profileImage']['url']
              : (cachedProfile['profileImage'] ??
                  cachedProfile['photo'] ??
                  _model.profileImageUrl ??
                  '');
          _model.profileData = Map<String, dynamic>.from(cachedProfile);
          _loadingProfile = false; // we have something to display
        });
      }

      final cached = await TokenStorage.getDashboardData();
      if (cached != null && mounted) {
        setState(() {
          _model.analytics =
              Map<String, dynamic>.from(cached['analytics'] ?? cached);
          _model.recentBookings = (cached['recentBookings'] is List)
              ? List<Map<String, dynamic>>.from(cached['recentBookings'])
              : (cached['recentBookings'] ?? _model.recentBookings ?? []);
          _model.recentReviews = (cached['recentReviews'] is List)
              ? List<Map<String, dynamic>>.from(cached['recentReviews'])
              : (cached['recentReviews'] ?? _model.recentReviews ?? []);
          _model.pendingJobs = (cached['pendingJobs'] is int)
              ? cached['pendingJobs']
              : int.tryParse((cached['pendingJobs'] ?? '').toString()) ??
                  _model.pendingJobs;
          _model.averageRating = (cached['averageRating'] is num)
              ? (cached['averageRating'] as num).toDouble()
              : double.tryParse((cached['averageRating'] ?? '').toString()) ??
                  _model.averageRating;
        });
        // Start the reviews carousel if we have cached reviews
        try {
          _startReviewsAutoScroll();
        } catch (_) {}
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
        final int initialPage =
            base * 1000; // large offset to allow back/forward
        _reviewsPageController =
            PageController(initialPage: initialPage, viewportFraction: 0.92);
      }

      _reviewsAutoScrollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (!mounted || _reviewsPageController == null) return;
        try {
          _reviewsPageController!.nextPage(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeInOut);
        } catch (_) {
          try {
            final next = (_reviewsPageController!.page?.toInt() ??
                    (_reviewsPageController!.initialPage)) +
                1;
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
      try {
        _reviewsPageController?.dispose();
      } catch (_) {}
      _reviewsPageController = null;
    } catch (_) {}
  }

  // Fetch a user record by id for reviewer display (cached)
  Future<Map<String, dynamic>?> _fetchReviewUserById(String id) async {
    if (id.isEmpty) return null;
    try {
      if (_reviewUserCache.containsKey(id)) return _reviewUserCache[id];
      final token = await TokenStorage.getToken();
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (token != null && token.isNotEmpty)
        headers['Authorization'] = 'Bearer $token';
      final url = '$API_BASE_URL/api/users/$id';
      final res = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode >= 200 &&
          res.statusCode < 300 &&
          res.body.isNotEmpty) {
        final d = jsonDecode(res.body);
        Map<String, dynamic>? data;
        if (d is Map && d['data'] is Map)
          data = Map<String, dynamic>.from(d['data']);
        else if (d is Map) data = Map<String, dynamic>.from(d);
        if (data != null) {
          final user = <String, dynamic>{};
          user['name'] = (data['name'] ??
                      data['fullName'] ??
                      data['displayName'] ??
                      data['username'])
                  ?.toString() ??
              '';
          var img = data['profileImage'] ??
              data['avatar'] ??
              data['photo'] ??
              data['image'] ??
              data['picture'];
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
    final bool _isNestedNavBar =
        context.findAncestorWidgetOfExactType<NavBarPage>() != null;
    if (!_isNestedNavBar) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          NavigationUtils.safePushReplacement(
              context, NavBarPage(initialPage: 'homePage'));
        } catch (_) {
          try {
            Navigator.of(context).pushReplacement(MaterialPageRoute(
                builder: (_) => NavBarPage(initialPage: 'homePage')));
          } catch (_) {}
        }
      });
      // show a small loader while we navigate
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(
            child: SizedBox(
                width: 36, height: 36, child: CircularProgressIndicator())),
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

    final int avgPerJob =
        (jobsCompleted > 0) ? (earnings / jobsCompleted).round() : 0;

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
                          Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                  color: colorScheme.surface,
                                  shape: BoxShape.circle))
                        else
                          InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () {},
                            child: Container(
                              width: 40,
                              height: 40,
                              clipBehavior: Clip.antiAlias,
                              decoration:
                                  const BoxDecoration(shape: BoxShape.circle),
                              child: Builder(builder: (ctx) {
                                final url = _model.profileImageUrl;
                                if (url != null &&
                                    url.toString().startsWith('http')) {
                                  return CachedNetworkImage(
                                      imageUrl: url.toString(),
                                      fit: BoxFit.cover,
                                      placeholder: (c, u) => Container(
                                          color: colorScheme.surface));
                                }
                                final name = (_model.displayName ?? '');
                                final initials = name
                                    .split(' ')
                                    .where((s) => s.isNotEmpty)
                                    .map((s) => s[0])
                                    .take(2)
                                    .join()
                                    .toUpperCase();
                                if (initials.isNotEmpty) {
                                  return Container(
                                    decoration: BoxDecoration(
                                        color: colorScheme.primary
                                            .withOpacity(0.1),
                                        shape: BoxShape.circle),
                                    child: Center(
                                        child: Text(initials,
                                            style: TextStyle(
                                                color: colorScheme.primary,
                                                fontWeight: FontWeight.w600))),
                                  );
                                }
                                return Container(
                                    decoration: BoxDecoration(
                                        color: colorScheme.surface,
                                        shape: BoxShape.circle),
                                    child: Icon(Icons.person_outline,
                                        color: colorScheme.onSurface
                                            .withOpacity(0.5),
                                        size: 20));
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
                                      style: theme.textTheme.bodyLarge
                                          ?.copyWith(
                                              fontWeight: FontWeight.w600),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (_model.isVerified == true)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                          color: Colors.green.withAlpha(30),
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.verified,
                                              size: 14, color: Colors.green),
                                          const SizedBox(width: 6),
                                          Text('KYC verified',
                                              style: theme.textTheme.labelSmall
                                                  ?.copyWith(
                                                      color: Colors.green,
                                                      fontWeight:
                                                          FontWeight.w600)),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              InkWell(
                                onTap: () async {
                                  try {
                                    await _openLocationBottomSheet();
                                  } catch (_) {}
                                },
                                borderRadius: BorderRadius.circular(6),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.location_on_outlined,
                                        size: 14,
                                        color: colorScheme.onSurface
                                            .withOpacity(0.6)),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        _model.userLocation ??
                                            _model.profileData?['city']
                                                ?.toString() ??
                                            'Location not set',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                                color: colorScheme.onSurface
                                                    .withOpacity(0.6)),
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
                      animation:
                          _notifAnimController ?? AlwaysStoppedAnimation(1.0),
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _notifPulse?.value ?? 1.0,
                          child: Text(
                            _unreadNotifications > 99
                                ? '99+'
                                : '$_unreadNotifications',
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      elevation: 0,
                    ),
                    child: FlutterFlowIconButton(
                      borderRadius: 20,
                      buttonSize: 44,
                      fillColor: colorScheme.surface,
                      icon: Icon(Icons.notifications_outlined,
                          color: colorScheme.onSurface, size: 22),
                      onPressed: () async {
                        try {
                          await context
                              .pushNamed(NotificationPageWidget.routeName);
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
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Performance Overview',
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'This month',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: colorScheme.onSurface
                                                .withOpacity(0.6),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: colorScheme.primary
                                            .withOpacity(0.1),
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
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
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
                                            width: 70,
                                            height: 70,
                                            child: Stack(
                                              alignment: Alignment.center,
                                              children: [
                                                SizedBox(
                                                  width: 80,
                                                  height: 80,
                                                  child:
                                                      CircularProgressIndicator(
                                                    value:
                                                        (_model.averageRating /
                                                                5)
                                                            .clamp(0.0, 1.0),
                                                    strokeWidth: 5,
                                                    valueColor:
                                                        AlwaysStoppedAnimation<
                                                                Color>(
                                                            colorScheme
                                                                .primary),
                                                    backgroundColor: colorScheme
                                                        .primary
                                                        .withOpacity(0.12),
                                                  ),
                                                ),
                                                Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      _model.averageRating
                                                          .toStringAsFixed(1),
                                                      style: theme.textTheme
                                                          .headlineSmall
                                                          ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                    Text(
                                                      '/5',
                                                      style: theme
                                                          .textTheme.bodySmall
                                                          ?.copyWith(
                                                        color: colorScheme
                                                            .onSurface
                                                            .withOpacity(0.6),
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
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              color: colorScheme.onSurface
                                                  .withOpacity(0.6),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Stats
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _buildStatRow(
                                            context: context,
                                            icon: Icons.work_outline,
                                            label: 'Jobs Completed',
                                            value:
                                                '${analytics['jobsCompleted'] ?? 0}',
                                            color: colorScheme.primary,
                                          ),
                                          const SizedBox(height: 12),
                                          _buildStatRow(
                                            context: context,
                                            icon: Icons.rate_review_outlined,
                                            label: 'Total Reviews',
                                            value:
                                                '${analytics['reviews'] ?? 0}',
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
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Earnings Summary',
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Total revenue generated',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: colorScheme.onSurface
                                                .withOpacity(0.6),
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
                                            colorScheme.primary
                                                .withOpacity(0.8),
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
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Total Earnings',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              color: colorScheme.onSurface
                                                  .withOpacity(0.6),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            '₦${analytics['earnings'] ?? 0}',
                                            style: theme
                                                .textTheme.headlineMedium
                                                ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Avg. per Job',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              color: colorScheme.onSurface
                                                  .withOpacity(0.6),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            '₦${avgPerJob}',
                                            style: theme.textTheme.titleLarge
                                                ?.copyWith(
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
                                        context.pushNamed(
                                            UserWalletpageWidget.routeName);
                                      } catch (_) {}
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: colorScheme.primary,
                                      foregroundColor: colorScheme.onPrimary,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 16),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: Text(
                                      'View Wallet',
                                      style:
                                          theme.textTheme.titleMedium?.copyWith(
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

                        // KYC-aware status card. Replaces the old multi-item
                        // PROFILE SETUP section. The card variant depends on
                        // KYC status (read from TokenStorage on init, then
                        // refreshed from the server):
                        //   - pending / pending_review  -> "Verification pending" card
                        //   - rejected / failed         -> "Verification didn't match" card with retry CTA
                        //   - approved                  -> nothing (artisan is set)
                        //   - null + setup incomplete   -> existing "Continue setup" progress card
                        //   - !_kycChecked              -> nothing (avoid 0%-flash before status loads)
                        _buildKycStatusCard(theme, colorScheme, ff),

                        // Availability prompt card — shown when the artisan
                        // hasn't set their weekly availability yet. Quick
                        // bottom-sheet flow with one-tap presets so the
                        // setup is seamless.
                        if (_artisanIsAvailabilityEmpty()) ...[
                          const SizedBox(height: 16),
                          Container(
                            decoration: BoxDecoration(
                              color: theme.cardColor,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: colorScheme.onSurface.withOpacity(0.1),
                                width: 1,
                              ),
                            ),
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: colorScheme.primary
                                            .withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(Icons.schedule_rounded,
                                          color: colorScheme.primary, size: 24),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Set your availability',
                                            style: theme.textTheme.titleMedium
                                                ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Quick — takes about 10 seconds',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              color: colorScheme.primary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  "Let clients know when you're available so bookings land at the right times.",
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color:
                                        colorScheme.onSurface.withOpacity(0.78),
                                    height: 1.45,
                                    fontSize: 13.5,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: colorScheme.primary,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation: 0,
                                    ),
                                    onPressed: _openAvailabilitySheet,
                                    child: const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          'Set availability',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        SizedBox(width: 6),
                                        Icon(Icons.arrow_forward_rounded,
                                            size: 18),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        // Recent Bookings Section
                        if (_model.recentBookings != null &&
                            _model.recentBookings!.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          Padding(
                            padding:
                                const EdgeInsets.only(left: 4.0, bottom: 12),
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
                                  padding:
                                      const EdgeInsets.fromLTRB(20, 20, 20, 16),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Recent Bookings',
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      GestureDetector(
                                        onTap: () {
                                          try {
                                            context.pushNamed(
                                                BookingPageWidget.routeName);
                                          } catch (_) {}
                                        },
                                        child: Text(
                                          'View All',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: colorScheme.primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                ..._model.recentBookings!.take(3).map((item) {
                                  final service = (item['booking']
                                              ?['service'] ??
                                          item['service'] ??
                                          'Job')
                                      .toString();
                                  final status = (item['booking']?['status'] ??
                                          item['status'] ??
                                          '')
                                      .toString();

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
                                      statusColor = colorScheme.onSurface
                                          .withOpacity(0.6);
                                  }

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20),
                                    child: Column(
                                      children: [
                                        ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          leading: Container(
                                            width: 40,
                                            height: 40,
                                            decoration: BoxDecoration(
                                              color: colorScheme.primary
                                                  .withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(10),
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
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              color: colorScheme.onSurface
                                                  .withOpacity(0.6),
                                            ),
                                          ),
                                          trailing: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color:
                                                  statusColor.withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              status,
                                              style: theme.textTheme.labelSmall
                                                  ?.copyWith(
                                                color: statusColor,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (_model.recentBookings!
                                                .indexOf(item) <
                                            _model.recentBookings!
                                                    .take(3)
                                                    .length -
                                                1)
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 60),
                                            child: Divider(
                                              height: 1,
                                              color: colorScheme.onSurface
                                                  .withOpacity(0.1),
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
                        if (_model.recentReviews != null &&
                            _model.recentReviews!.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          Padding(
                            padding:
                                const EdgeInsets.only(left: 4.0, bottom: 12),
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
                                if (notification is ScrollStartNotification &&
                                    notification.dragDetails != null) {
                                  // user started a drag -> pause autoplay
                                  try {
                                    _pauseReviewsAutoScroll();
                                  } catch (_) {}
                                } else if (notification
                                    is ScrollEndNotification) {
                                  // user stopped scrolling -> resume autoplay
                                  try {
                                    _startReviewsAutoScroll();
                                  } catch (_) {}
                                }
                                return false;
                              },
                              child: PageView.builder(
                                controller: _reviewsPageController ??
                                    PageController(viewportFraction: 0.92),
                                physics: const BouncingScrollPhysics(),
                                itemBuilder: (context, index) {
                                  final reviews = _model.recentReviews!;
                                  final r = reviews[index % reviews.length];
                                  final comment = (r['comment'] ??
                                          r['text'] ??
                                          r['message'] ??
                                          '')
                                      .toString();
                                  final rating = double.tryParse(
                                          (r['rating'] ?? r['stars'] ?? '0')
                                              .toString()) ??
                                      0.0;

                                  // Derive a reviewer id if available (many API shapes)
                                  String? reviewerId;
                                  try {
                                    final candidates = [
                                      r['customerId'],
                                      r['customer_id'],
                                      r['userId'],
                                      r['user_id'],
                                      r['authorId'],
                                      r['author']
                                    ];
                                    for (final c in candidates) {
                                      if (c == null) continue;
                                      if (c is String && c.isNotEmpty) {
                                        reviewerId = c;
                                        break;
                                      }
                                      if (c is Map && c['_id'] != null) {
                                        reviewerId = c['_id'].toString();
                                        break;
                                      }
                                    }
                                    if ((reviewerId == null ||
                                            reviewerId.isEmpty) &&
                                        r['customer'] is Map) {
                                      final cc = Map<String, dynamic>.from(
                                          r['customer']);
                                      if (cc['_id'] != null)
                                        reviewerId = cc['_id'].toString();
                                    }
                                    if ((reviewerId == null ||
                                            reviewerId.isEmpty) &&
                                        r['user'] is Map) {
                                      final uu =
                                          Map<String, dynamic>.from(r['user']);
                                      if (uu['_id'] != null)
                                        reviewerId = uu['_id'].toString();
                                    }
                                  } catch (_) {
                                    reviewerId = null;
                                  }

                                  // Try inline image/name first (existing fallbacks)
                                  String? inlineImageUrl;
                                  String inlineName = (r['customerName'] ??
                                          r['customer']?['name'] ??
                                          r['customerUser']?['name'] ??
                                          r['user']?['name'] ??
                                          r['reviewer']?['name'] ??
                                          'Customer')
                                      .toString();

                                  try {
                                    final candidate = r['customer'] ??
                                        r['customerUser'] ??
                                        r['user'] ??
                                        r['reviewer'] ??
                                        {};
                                    if (candidate is Map) {
                                      final img = candidate['profileImage'] ??
                                          candidate['avatar'] ??
                                          candidate['photo'] ??
                                          candidate['image'] ??
                                          candidate['picture'];
                                      if (img is Map)
                                        inlineImageUrl = img['url']?.toString();
                                      else if (img != null)
                                        inlineImageUrl = img.toString();
                                    }
                                  } catch (_) {
                                    inlineImageUrl = null;
                                  }

                                  // Use cached fetched user record when available; otherwise trigger background fetch
                                  Map<String, dynamic>? fetchedUser;
                                  if (reviewerId != null &&
                                      reviewerId.isNotEmpty) {
                                    fetchedUser = _reviewUserCache[reviewerId];
                                    if (fetchedUser == null) {
                                      // Fetch in background; don't await to avoid delaying build
                                      _fetchReviewUserById(reviewerId)
                                          .then((u) {
                                        if (u != null && mounted)
                                          setState(() {});
                                      });
                                    }
                                  }

                                  final displayName = (fetchedUser != null &&
                                          (fetchedUser['name'] as String)
                                              .trim()
                                              .isNotEmpty)
                                      ? fetchedUser['name'] as String
                                      : inlineName;
                                  final reviewerImageUrl = (fetchedUser !=
                                              null &&
                                          (fetchedUser['profileImage']
                                                  as String)
                                              .isNotEmpty)
                                      ? fetchedUser['profileImage'] as String
                                      : inlineImageUrl;

                                  final initials = displayName
                                      .split(' ')
                                      .where((s) => s.isNotEmpty)
                                      .map((s) => s[0])
                                      .take(2)
                                      .join()
                                      .toUpperCase();

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8.0, vertical: 4.0),
                                    child: Card(
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                      child: Padding(
                                        padding: const EdgeInsets.all(12.0),
                                        child: Row(
                                          children: [
                                            if (reviewerImageUrl != null &&
                                                reviewerImageUrl
                                                    .startsWith('http'))
                                              Container(
                                                width: 44,
                                                height: 44,
                                                clipBehavior: Clip.antiAlias,
                                                decoration: BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10)),
                                                child: CachedNetworkImage(
                                                  imageUrl: reviewerImageUrl,
                                                  fit: BoxFit.cover,
                                                  placeholder: (c, u) =>
                                                      Container(
                                                          color: ff.warning
                                                              .withOpacity(
                                                                  0.08)),
                                                  errorWidget: (c, u, e) =>
                                                      Container(
                                                    color: ff.warning
                                                        .withOpacity(0.08),
                                                    child: Center(
                                                        child: Text(initials,
                                                            style: theme
                                                                .textTheme
                                                                .bodyMedium
                                                                ?.copyWith(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700))),
                                                  ),
                                                ),
                                              )
                                            else
                                              Container(
                                                width: 44,
                                                height: 44,
                                                decoration: BoxDecoration(
                                                  color: ff.warning
                                                      .withOpacity(0.12),
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    initials.isNotEmpty
                                                        ? initials
                                                        : 'C',
                                                    style: theme
                                                        .textTheme.bodyMedium
                                                        ?.copyWith(
                                                            fontWeight:
                                                                FontWeight
                                                                    .w700),
                                                  ),
                                                ),
                                              ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          displayName,
                                                          style: theme.textTheme
                                                              .bodyMedium
                                                              ?.copyWith(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Row(
                                                        children: [
                                                          Icon(
                                                              Icons
                                                                  .star_rate_rounded,
                                                              size: 14,
                                                              color:
                                                                  ff.warning),
                                                          const SizedBox(
                                                              width: 4),
                                                          Text(
                                                              rating
                                                                  .toStringAsFixed(
                                                                      1),
                                                              style: theme
                                                                  .textTheme
                                                                  .bodySmall
                                                                  ?.copyWith(
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w600)),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Text(
                                                    comment,
                                                    style: theme
                                                        .textTheme.bodySmall
                                                        ?.copyWith(
                                                            color: colorScheme
                                                                .onSurface
                                                                .withOpacity(
                                                                    0.7)),
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
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
            padding:
                EdgeInsets.only(bottom: MediaQuery.of(ctx2).viewInsets.bottom),
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
                  title: Text('Set location',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  subtitle: Text('Choose how to set your service address',
                      style: theme.textTheme.bodySmall),
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
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: loading
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    color: colorScheme.onPrimary,
                                    strokeWidth: 2))
                            : Icon(Icons.my_location_rounded),
                        label: Text(
                            loading
                                ? 'Detecting location...'
                                : 'Use device location',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(color: colorScheme.onPrimary)),
                        onPressed: loading
                            ? null
                            : () async {
                                setModalState(() {
                                  loading = true;
                                  statusText = '';
                                });
                                final ok = await LocationPermissionService
                                    .ensureLocationPermissions(context);
                                if (!ok) {
                                  setModalState(() => loading = false);
                                  if (mounted)
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content: Text(
                                                'Location permission denied')));
                                  return;
                                }

                                try {
                                  final pos =
                                      await Geolocator.getCurrentPosition(
                                          locationSettings:
                                              const LocationSettings(
                                                  accuracy:
                                                      LocationAccuracy.best));
                                  // Reverse geocode using Google Maps Geocoding API to get human-readable address
                                  String? address;
                                  try {
                                    final key = GOOGLE_MAPS_API_KEY;
                                    if (key.isNotEmpty) {
                                      final url = Uri.parse(
                                          'https://maps.googleapis.com/maps/api/geocode/json?latlng=${pos.latitude},${pos.longitude}&key=$key');
                                      final resp = await http
                                          .get(url)
                                          .timeout(const Duration(seconds: 10));
                                      if (resp.statusCode == 200 &&
                                          resp.body.isNotEmpty) {
                                        final body = jsonDecode(resp.body);
                                        if (body is Map &&
                                            body['results'] is List &&
                                            (body['results'] as List)
                                                .isNotEmpty) {
                                          final feat =
                                              (body['results'] as List).first;
                                          if (feat is Map &&
                                              feat['formatted_address'] !=
                                                  null) {
                                            address = feat['formatted_address']
                                                .toString();
                                          }
                                        }
                                      }
                                    }
                                  } catch (e) {
                                    // ignore reverse-geocode failure; we'll still save coords
                                  }

                                  await TokenStorage.saveLocation(
                                      address: address,
                                      latitude: pos.latitude,
                                      longitude: pos.longitude);
                                  if (!mounted) return;
                                  setState(() {
                                    // Update displayed location on the dashboard header
                                    _model.userLocation = address ??
                                        '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
                                  });
                                  Navigator.of(ctx2).pop();
                                  if (mounted)
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                            content: Text(address != null
                                                ? 'Location set: $address'
                                                : 'Location coordinates saved')));
                                } catch (e) {
                                  if (mounted)
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content: Text(
                                                'Failed to obtain device location')));
                                } finally {
                                  setModalState(() {
                                    loading = false;
                                  });
                                }
                              },
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colorScheme.onSurface,
                          minimumSize: Size(double.infinity, 48),
                          side: BorderSide(
                              color: colorScheme.onSurface.withOpacity(0.12)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: Icon(Icons.edit_location_outlined),
                        label: Text('Edit profile address',
                            style: theme.textTheme.bodyLarge),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          try {
                            NavigationUtils.safePush(
                                context, EditProfileUserWidget());
                          } catch (_) {}
                        },
                      ),
                      const SizedBox(height: 8),
                      if (statusText.isNotEmpty)
                        Align(
                            alignment: Alignment.centerLeft,
                            child: Text(statusText,
                                style: theme.textTheme.bodySmall)),
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

  // Compute profile completion as the max of:
  //   (a) the server-reported `profileCompletion`/`profileProgress` from
  //       GET /api/artisans/me, and
  //   (b) a local fraction derived from the same 4 onboarding sections the
  //       artisan_onboarding_widget tracks. This mirrors the onboarding
  //       screen's `_completionFraction` getter so both surfaces converge
  //       on the same percentage even when the server hasn't yet processed
  //       the latest save.
  void _computeProfileCompletion() {
    try {
      double serverValue = 0.0;
      final raw = _artisanProfile?['profileCompletion'] ??
          _artisanProfile?['profileProgress'];
      if (raw != null) {
        if (raw is num) {
          serverValue = raw.toDouble();
        } else {
          serverValue = double.tryParse(raw.toString()) ?? 0.0;
        }
        if (serverValue > 1.0) serverValue = serverValue / 100.0;
        serverValue = serverValue.clamp(0.0, 1.0);
      }

      // Local section completion — mirrors what artisan_onboarding's
      // `_hydrateFromServer` writes into its `_completed` array.
      final sections = <bool>[
        _isTradeSectionComplete(),
        _isWorkSectionComplete(),
        _isShowcaseSectionComplete(),
        _isKycSectionComplete(),
      ];
      final localFraction = sections.where((c) => c).length / sections.length;

      // Take whichever is higher, clamp to 0..1.
      final completion =
          (localFraction > serverValue ? localFraction : serverValue)
              .clamp(0.0, 1.0);
      if (mounted) setState(() => _profileCompletion = completion);
    } catch (e) {
      if (kDebugMode) debugPrint('Error computing profile completion: $e');
      if (mounted) setState(() => _profileCompletion = 0.0);
    }
  }

  // ---- Per-section completion helpers ------------------------------------
  // Each maps to one of the 4 onboarding sections so the dashboard's progress
  // bar matches what the onboarding screen shows. The matching logic in
  // artisan_onboarding_widget.dart's `_hydrateFromServer` is the source of
  // truth — keep these in sync if those rules change.

  /// Section 1: Trade, Services & Prices.
  /// Onboarding requires category + services + experience. Dashboard
  /// approximates with `trade` + `experience` (services aren't fetched
  /// here, but in practice they're saved together so the result tallies).
  bool _isTradeSectionComplete() {
    final p = _artisanProfile;
    if (p == null) return false;
    final trade = p['trade'];
    final hasTrade = (trade is List && trade.isNotEmpty) ||
        (trade is String && trade.trim().isNotEmpty);
    return hasTrade && p['experience'] != null;
  }

  /// Section 2: Work Radius & Profile.
  bool _isWorkSectionComplete() {
    final sa = _artisanProfile?['serviceArea'];
    if (sa is! Map) return false;
    final coords = sa['coordinates'];
    return coords is List &&
        coords.length >= 2 &&
        coords[0] != null &&
        coords[1] != null;
  }

  /// Section 3: Showcase Your Work (optional but counts when populated).
  bool _isShowcaseSectionComplete() {
    final p = _artisanProfile;
    if (p == null) return false;
    final port = p['portfolio'];
    if (port is List && port.isNotEmpty) return true;
    final certs = p['certifications'];
    if (certs is List && certs.isNotEmpty) return true;
    return false;
  }

  /// Section 4: Identity Verification — submitted (any non-rejected status).
  bool _isKycSectionComplete() {
    final s = _kycStatus;
    return s == 'approved' || s == 'pending' || s == 'pending_review';
  }
}
