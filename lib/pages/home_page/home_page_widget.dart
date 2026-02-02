// Backup note: previous content overwritten to restore a stable Home page UI.
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'package:badges/badges.dart' as badges;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';
import 'dart:convert';
import 'home_page_model.dart';
import '../../services/announcement_service.dart';
import '../../services/api_client.dart';
import '../../state/app_state_notifier.dart';
import '../../services/user_service.dart';
import '../../api_config.dart';
import '../../utils/navigation_utils.dart';
import '../../widgets/network_error_widget.dart';
import '../../services/token_storage.dart';
import 'package:flutter/services.dart'; // <-- added
import 'package:geolocator/geolocator.dart';
import '../../utils/location_permission.dart';
import 'package:http/http.dart' as http;
import '../../mapbox_config.dart';
import '../../services/artist_service.dart';
import '../artisan_detail_page/artisan_detail_page_widget.dart';
import '/main.dart';
export 'home_page_model.dart';

class HomePageWidget extends StatefulWidget {
  const HomePageWidget({super.key});

  static String routeName = 'homePage';
  static String routePath = '/homePage';

  @override
  State<HomePageWidget> createState() => _HomePageWidgetState();
}

class _HomePageWidgetState extends State<HomePageWidget> with TickerProviderStateMixin {
  late HomePageModel _model;
  final scaffoldKey = GlobalKey<ScaffoldState>();

  // Network error/retry state
  bool _showNetworkError = false;
  DateTime? _lastSuccessfulLoad;
  Timer? _networkCheckTimer;

  // Per-section failure flags so we can do partial retries
  bool _adsFailed = false;
  bool _marqueeFailed = false;
  bool _notificationsFailed = false;
  bool _profileFailed = false;

    // Carousel
    late PageController _adPageController;
    int _adPageIndex = 0;
    // Absolute page index for infinite scrolling
    int _adPageAbsoluteIndex = 0;
    Timer? _adTimer;
    bool _isUserScrolling = false;

    // Artisans carousel state
    List<Map<String, dynamic>> _artisans = [];
    bool _loadingArtisans = false;
    String? _artisanError;
    // Auto-scroll/page state for artisans carousel
    late PageController _artisanPageController;
    int _artisanPageIndex = 0;
    Timer? _artisanTimer;
    bool _artisanUserScrolling = false;
    // Absolute page index for infinite scrolling (same approach as ads)
    int _artisanPageAbsoluteIndex = 0;

    List<String> _adImages = [];
    final List<String> _defaultAds = [
    // Prefer the requested carl_1.webp (bundled asset). If it isn't available,
    // the carousel will fall back to app_logo_RH.jpg at render-time.
    'assets/images/carl_1.webp',
    'assets/images/carl_1.webp',
    'assets/images/carl_1.webp',
    'assets/images/carl_1.webp',
    'assets/images/carl_1.webp',
  ];
  bool _loadingAds = true;

  // Marquee
  AnimationController? _marqueeController;
  String _marqueeText = 'Hot deals today — Up to 50% off on selected services! • Book now and save.';
  bool _loadingMarquee = true;

  // Profile
  Map<String, dynamic>? _profile;
  bool _loadingProfile = true;

  // Notifications
  int _unreadNotifications = 0;
  AnimationController? _notifAnimController;
  Animation<double>? _notifPulse;
  Timer? _notifTimer;

  // Cached values read from TokenStorage for quick UI display
  String? _profileImageUrlCached;
  Map<String, dynamic>? _cachedLocation;

    @override
    void initState() {
    super.initState();
    _model = createModel(context, () => HomePageModel());
    // Initialize artisans page controller early to avoid races when data loads quickly
    _artisanPageController = PageController(initialPage: 0, viewportFraction: 0.94);
    // load a small set of artisans to show on home page
    _loadHomeArtisans();
    _adPageController = PageController(initialPage: 0);
    _marqueeController = AnimationController(vsync: this, duration: const Duration(seconds: 12));
    _notifAnimController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _notifPulse = Tween<double>(begin: 1.0, end: 1.06).animate(CurvedAnimation(parent: _notifAnimController!, curve: Curves.easeInOut));

    // Listen to global AppState changes so we update the local _profile live
    AppStateNotifier.instance.addListener(_onAppStateChanged);

    _loadAds();
    _loadMarquee();
    _fetchUnreadNotifications();
    _notifTimer = Timer.periodic(const Duration(seconds: 30), (_) { if (mounted) _fetchUnreadNotifications(); });

    // profile from app state (best-effort)
    _profile = AppStateNotifier.instance.profile != null ? Map<String, dynamic>.from(AppStateNotifier.instance.profile!) : null;
    _loadingProfile = _profile == null;
    if (_profile == null) {
      UserService.getProfile().then((p) {
        if (!mounted) return;
        setState(() { _profile = p != null ? Map<String, dynamic>.from(p) : null; _loadingProfile = false; });
      }).catchError((_) { if (mounted) setState(() { _loadingProfile = false; }); });
    }

    _marqueeController?.addStatusListener((s) { if (s == AnimationStatus.completed) _marqueeController?.repeat(); });

    // Load cached profile image and cached canonical location (fast, synchronous UI)
    _loadCachedProfileAndLocation();

    // periodic connectivity probe: auto-retry failed sections when network returns
    _networkCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!mounted) return;
      await _checkConnectivity();
    });
    // initial probe
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkConnectivity());
    }

  Future<void> _setLastSuccess() async {
    if (!mounted) return;
    setState(() { _lastSuccessfulLoad = DateTime.now(); _showNetworkError = false; });
  }

  Future<void> _checkConnectivity() async {
    try {
      final resp = await ApiClient.get('https://www.google.com/generate_204', headers: {'Cache-Control': 'no-cache'}).timeout(const Duration(seconds: 8));
      final status = resp['status'] as int? ?? 0;
      if (status >= 200 && status < 400) {
        if (mounted) setState(() => _showNetworkError = false);
        await _retryFailedSections();
        await _setLastSuccess();
      } else {
        if (mounted) setState(() => _showNetworkError = true);
      }
    } catch (_) {
      if (mounted) setState(() => _showNetworkError = true);
    }
  }

  Future<void> _retryFailedSections() async {
    if (_adsFailed) await _loadAds();
    if (_marqueeFailed) await _loadMarquee();
    if (_notificationsFailed) await _fetchUnreadNotifications();
    if (_profileFailed) {
      try {
        final p = await UserService.getProfile();
        if (mounted) setState(() { _profile = p != null ? Map<String,dynamic>.from(p) : null; _loadingProfile = false; _profileFailed = false; });
        await _setLastSuccess();
      } catch (_) { if (mounted) setState(() => _profileFailed = true); }
    }
  }

  Future<void> _retryAll() async {
    if (!mounted) return;
    setState(() {
      _adsFailed = _marqueeFailed = _notificationsFailed = _profileFailed = false;
      _showNetworkError = false;
      _loadingAds = true;
      _loadingMarquee = true;
      _loadingProfile = true;
    });
    await Future.wait([
      _loadAds(),
      _loadMarquee(),
      _fetchUnreadNotifications(),
      UserService.getProfile().then((p) { if (mounted) setState(() { _profile = p != null ? Map<String,dynamic>.from(p) : null; _loadingProfile = false; _profileFailed = false; }); }).catchError((e) { if (mounted) setState(() { _profileFailed = true; _loadingProfile = false; }); })
    ]);
    await _setLastSuccess();
  }

  void _openNetworkSettings() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Open Network Settings'),
      content: const Text('Please open your device network settings to enable Wi‑Fi or mobile data.'),
      actions: [ TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')) ],
    ));
  }

  void _onAppStateChanged() {
    if (!mounted) return;
    try {
      final p = AppStateNotifier.instance.profile;
      setState(() {
        _profile = p != null ? Map<String, dynamic>.from(p) : null;
        _loadingProfile = false;
      });
      // Refresh cached image/location derived from the new app state
      _loadCachedProfileAndLocation();
    } catch (_) {}
  }

  // When app state updates, refresh cached image/location for header display
  Future<void> _loadCachedProfileAndLocation() async {
    try {
      // Update cached location (from TokenStorage)
      final loc = await TokenStorage.getLocation();
      if (!mounted) return;
      setState(() => _cachedLocation = Map<String, dynamic>.from(loc));
    } catch (_) {}

    try {
      // If we have coords but no address, try reverse-geocoding to a human-readable place
      try {
        final current = _cachedLocation;
        if (current != null) {
          final addr = current['address'] as String?;
          final lat = current['latitude'] as double?;
          final lon = current['longitude'] as double?;
          if ((addr == null || addr.isEmpty) && lat != null && lon != null) {
            try {
              final url = Uri.parse('https://api.mapbox.com/geocoding/v5/mapbox.places/\$lon,\$lat.json?access_token=\$MAPBOX_ACCESS_TOKEN&limit=1'
                  .replaceAll('\$lat', lat.toString()).replaceAll('\$lon', lon.toString()));
              final resp = await http.get(url).timeout(const Duration(seconds: 8));
              if (resp.statusCode == 200 && resp.body.isNotEmpty) {
                final body = jsonDecode(resp.body);
                if (body is Map && body['features'] is List && (body['features'] as List).isNotEmpty) {
                  final feat = (body['features'] as List).first;
                  if (feat is Map && feat['place_name'] != null) {
                    final place = feat['place_name'].toString();
                    await TokenStorage.saveLocation(address: place, latitude: lat, longitude: lon);
                    if (!mounted) return;
                    setState(() => _cachedLocation = {'address': place, 'latitude': lat, 'longitude': lon});
                  }
                }
              }
            } catch (_) {}
          }
        }
      } catch (_) {}

      // Derive a profile image URL from current in-memory profile if available
      final url = _extractProfileImageUrl(_profile ?? AppStateNotifier.instance.profile);
      if (url != null && url.isNotEmpty) {
        if (!mounted) return;
        setState(() => _profileImageUrlCached = url);
        return;
      }

      // If not in profile, try stored Google profile (if any)
      try {
        final google = await TokenStorage.getGoogleProfile();
        if (!mounted) return;
        if (google != null && google['picture'] != null) {
          setState(() => _profileImageUrlCached = google['picture'].toString());
          return;
        }
      } catch (_) {}

      // No cached image found
      if (!mounted) return;
      setState(() => _profileImageUrlCached = null);
    } catch (_) {}
  }

    String? _extractProfileImageUrl(Map<String, dynamic>? p) {
    if (p == null) return null;
    try {
      final keys = ['profileImageUrl', 'profileImage', 'avatar', 'image', 'photo', 'picture', 'pictureUrl', 'imageUrl', 'avatarUrl'];
      for (final k in keys) {
        if (p.containsKey(k) && p[k] != null) {
          final v = p[k];
          // If value is a string URL, return it (only accept http/https/data or protocol-relative)
          if (v is String && v.isNotEmpty && (v.startsWith('http://') || v.startsWith('https://') || v.startsWith('data:') || v.startsWith('//'))) return v;
          // If the backend stores an object e.g. { 'url': 'https://...' } or { 'path': 'uploads/..' }
          if (v is Map) {
            final candidateKeys = ['url', 'path', 'imageUrl', 'src'];
            for (final ck in candidateKeys) {
              if (v.containsKey(ck) && v[ck] != null) {
                final cs = v[ck];
                if (cs is String && cs.isNotEmpty) return cs;
              }
            }
          }
        }
      }
      // Check nested shapes under 'user' or 'data'
      for (final rootKey in ['user', 'data']) {
        if (p[rootKey] is Map) {
          final u = Map<String, dynamic>.from(p[rootKey]);
          for (final k in keys) {
            if (u.containsKey(k) && u[k] != null) {
              final v = u[k];
              if (v is String && v.isNotEmpty && (v.startsWith('http://') || v.startsWith('https://') || v.startsWith('data:') || v.startsWith('//'))) return v;
              if (v is Map) {
                final candidateKeys = ['url', 'path', 'imageUrl', 'src'];
                for (final ck in candidateKeys) {
                  if (v.containsKey(ck) && v[ck] != null) {
                    final cs = v[ck];
                    if (cs is String && cs.isNotEmpty) return cs;
                  }
                }
              }
            }
          }
        }
      }
    } catch (_) {}
    return null;
    }

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
                              _cachedLocation = {'address': address, 'latitude': pos.latitude, 'longitude': pos.longitude};
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
                          NavigationUtils.safePush(context, EditProfileUserWidget());
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

  // Normalize image URLs: if a relative/path-only URL is provided by the backend,
  // prefix it with API_BASE_URL so CachedNetworkImage can fetch it. Also handle
  // protocol-relative URLs (//cdn.example.com/...). Returns null for empty input.
  String? _normalizeImageUrl(String? url) {
    if (url == null) return null;
    final s = url.toString().trim();
    if (s.isEmpty) return null;
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    if (s.startsWith('//')) return 'https:$s';
    // If URL looks like a data URI, return as-is
    if (s.startsWith('data:')) return s;
    // Otherwise treat as a path relative to API_BASE_URL
    try {
      var base = API_BASE_URL ?? '';
      if (base.isEmpty) return s; // Best-effort: return original if base unknown
      // Ensure single slash between base and path
      final endsWithSlash = base.endsWith('/');
      final startsWithSlash = s.startsWith('/');
      if (endsWithSlash && startsWithSlash) return base.substring(0, base.length - 1) + s;
      if (!endsWithSlash && !startsWithSlash) return '$base/$s';
      return base + s;
    } catch (_) {
      return s;
    }
  }

    @override
    void dispose() {
    // Remove global app state listener to avoid leaks
    try { AppStateNotifier.instance.removeListener(_onAppStateChanged); } catch (_) {}
    _adTimer?.cancel();
    _adPageController.dispose();
    _artisanTimer?.cancel();
    _artisanPageController.dispose();
    _marqueeController?.dispose();
    _notifAnimController?.dispose();
    _notifTimer?.cancel();
    _networkCheckTimer?.cancel();
    _model.dispose();
    super.dispose();
    }

  Future<void> _loadAds() async {
    setState(() { _loadingAds = true; _adsFailed = false; });
    try {
      final urls = [
        '$API_BASE_URL/api/ads',
        '$API_BASE_URL/api/announcements/ads',
        '$API_BASE_URL/api/ads/carousel',
      ];
      List<String> found = [];
      for (final url in urls) {
        try {
          final resp = await ApiClient.get(url, headers: {'Content-Type': 'application/json'});
          final status = resp['status'] as int? ?? 0;
          final body = resp['body']?.toString() ?? '';
          if (status >= 200 && status < 300 && body.isNotEmpty) {
            final decoded = jsonDecode(body);
            if (decoded is Map && decoded['data'] is List) {
              for (final it in decoded['data']) {
                final u = _tryExtractImage(it);
                if (u != null) found.add(u);
              }
            } else if (decoded is List) {
              for (final it in decoded) {
                final u = _tryExtractImage(it);
                if (u != null) found.add(u);
              }
            }
          }
        } catch (_) {}
        if (found.isNotEmpty) break;
      }
      if (mounted) {
        setState(() {
          _adImages = found.isNotEmpty ? found : List<String>.from(_defaultAds);
          _loadingAds = false;
          _adsFailed = false;
        });

        // Jump to a high start index to allow infinite swiping both directions.
        final int count = _adImages.isNotEmpty ? _adImages.length : _defaultAds.length;
        if (count > 0) {
          final start = count * 1000; // arbitrary large offset
          _adPageAbsoluteIndex = start;
          if (_adPageController.hasClients) {
            _adPageController.jumpToPage(start);
          } else {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              try { _adPageController.jumpToPage(start); } catch (_) {}
            });
          }
        }

        _startAdTimer();
        await _setLastSuccess();
      }
    } catch (e) {
      if (mounted) setState(() { _adImages = List<String>.from(_defaultAds); _loadingAds = false; _adsFailed = true; });
      _startAdTimer();
    }
  }

  void _startAdTimer() {
    _adTimer?.cancel();
    _adTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || _adImages.isEmpty || _isUserScrolling) return;
      final int count = _adImages.isNotEmpty ? _adImages.length : _defaultAds.length;
      final nextAbs = _adPageAbsoluteIndex + 1;
      try {
        _adPageController.animateToPage(nextAbs, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
        setState(() {
          _adPageAbsoluteIndex = nextAbs;
          if (count > 0) _adPageIndex = _adPageAbsoluteIndex % count;
        });
      } catch (_) {}
    });
  }

  Future<void> _loadMarquee() async {
    try {
      final remote = await AnnouncementService.getMarqueeText();
      if (mounted) setState(() { if (remote != null && remote.trim().isNotEmpty) _marqueeText = remote.trim().replaceAll('\n', ' '); _loadingMarquee = false; _marqueeFailed = false; });
      _marqueeController?.repeat();
      await _setLastSuccess();
    } catch (_) { if (mounted) setState(() => _loadingMarquee = false); if (mounted) setState(() => _marqueeFailed = true); }
  }

  Future<void> _fetchUnreadNotifications() async {
    try {
      final resp = await ApiClient.get('$API_BASE_URL/api/notifications?unread=true', headers: {'Content-Type': 'application/json'});
      final status = resp['status'] as int? ?? 0;
      final body = resp['body']?.toString() ?? '';
      int count = 0;
      if (status >= 200 && status < 300 && body.isNotEmpty) {
        final decoded = jsonDecode(body);
        if (decoded is Map && decoded['data'] is List) count = (decoded['data'] as List).length;
        else if (decoded is List) count = decoded.length;
      }
      if (mounted) setState(() { _unreadNotifications = count; if (_unreadNotifications>0) _notifAnimController?.repeat(reverse: true); else _notifAnimController?.stop(); _notificationsFailed = false; });
    } catch (_) {}
  }

  String? _tryExtractImage(dynamic it) {
    try {
      if (it == null) return null;
      if (it is String && it.isNotEmpty) return it;
      if (it is Map) {
        for (final k in ['image','url','src','path','imageUrl','media','thumbnail']) {
          if (it.containsKey(k) && it[k] != null && it[k].toString().trim().isNotEmpty) return it[k].toString();
        }
      }
    } catch (_) {}
    return null;
  }

  String _displayName() {
    final p = _profile;
    if (p == null) return 'Hello, Guest!';
    final name = (p['name'] ?? p['fullName'] ?? p['firstName'] ?? p['username'])?.toString() ?? '';
    return name.trim().isEmpty ? 'Hello, Guest!' : 'Hello, ${name.trim()}';
  }

  String _displayLocation() {
    try {
      // Prefer explicit profile address if available
      final p = _profile ?? AppStateNotifier.instance.profile;
      if (p != null) {
        final addr = (p['serviceArea'] is Map ? (p['serviceArea']['address'] ?? p['serviceArea']['name']) : null) ?? p['location'] ?? p['address'] ?? p['lga'] ?? p['city'];
        if (addr != null && addr.toString().trim().isNotEmpty) return addr.toString();
      }

      // Prefer cached canonical location saved in TokenStorage
      if (_cachedLocation != null) {
        try {
          final addr = _cachedLocation!['address'] as String?;
          // final lat = _cachedLocation!['latitude'] as double?;
          // final lon = _cachedLocation!['longitude'] as double?;
          if (addr != null && addr.isNotEmpty) return addr;
          // If no address is available, don't show raw coordinates; prompt user to set a location
          return 'Tap to set location';
        } catch (_) {}
      }

      // Fallback to any AppState cached 'location' string
      try {
        final cached = AppStateNotifier.instance.profile == null ? null : AppStateNotifier.instance.profile!['location'];
        if (cached != null && cached.toString().isNotEmpty) return cached.toString();
      } catch (_) {}

      return 'Tap to set location';
    } catch (_) {
      return 'Tap to set location';
    }
  }

  // --- Add helper to load asset bytes at runtime (returns null if missing) ---
  Future<Uint8List?> _loadAssetBytes(String path) async {
    try {
      final data = await rootBundle.load(path);
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // Ensure this page is hosted inside NavBarPage so bottom navigation appears.
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
    }

    // If network error is active, show full-page NetworkErrorWidget
    if (_showNetworkError) {
      return NetworkErrorWidget(
        title: 'Connection Lost',
        message: 'Unable to reach our services. Please check your internet connection.',
        primaryAction: RetryButton(onPressed: () async { await _retryAll(); }),
        secondaryAction: SettingsButton(onPressed: _openNetworkSettings),
        showOfflineContent: false,
        lastSuccessfulLoad: _lastSuccessfulLoad,
      );
    }

    return GestureDetector(
      onTap: () { FocusScope.of(context).unfocus(); },
      child: Scaffold(
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
                    // Profile Info (stable layout: avatar | expanded name/location | actions)
                    // Avatar
                    if (_loadingProfile)
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          shape: BoxShape.circle,
                        ),
                      )
                    else
                      GestureDetector(
                        onTap: () { /* open profile */ },
                        child: Container(
                          width: 44,
                          height: 44,
                          clipBehavior: Clip.antiAlias,
                          decoration: const BoxDecoration(shape: BoxShape.circle),
                          child: Builder(builder: (ctx) {
                            final raw = _profileImageUrlCached ?? _extractProfileImageUrl(_profile ?? AppStateNotifier.instance.profile) ?? _profile?['profileImageUrl']?.toString() ?? _profile?['avatar']?.toString();
                            final url = _normalizeImageUrl(raw);
                            if (url != null && url.isNotEmpty && (url.startsWith('http://') || url.startsWith('https://') || url.startsWith('data:'))) {
                              // Use CachedNetworkImage but provide a fallback widget in case of errors.
                              return CachedNetworkImage(
                                imageUrl: url,
                                fit: BoxFit.cover,
                                placeholder: (c, u) => Container(color: colorScheme.surface),
                                errorWidget: (c, u, e) {
                                  // If the network image fails, show initials if available or the bundled app logo as a final fallback.
                                  final nameFail = (_profile?['name'] ?? '')?.toString() ?? '';
                                  final initialsFail = nameFail.split(' ').where((s) => s.isNotEmpty).map((s) => s[0]).take(2).join().toUpperCase();
                                  if (initialsFail.isNotEmpty) {
                                    return Container(
                                      decoration: BoxDecoration(
                                        color: colorScheme.primary.withOpacity(0.12),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(child: Text(initialsFail, style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.w600))),
                                    );
                                  }
                                  return FutureBuilder<Uint8List?>(
                                    future: _loadAssetBytes('assets/images/app_logo_RH.jpg'),
                                    builder: (ctx2, snap2) {
                                      if (snap2.hasData && snap2.data != null) {
                                        return Image.memory(snap2.data!, fit: BoxFit.cover);
                                      }
                                      return Container(
                                        color: colorScheme.surface,
                                        child: Center(
                                          child: Icon(Icons.person, color: colorScheme.onSurface.withOpacity(0.28)),
                                        ),
                                      );
                                    },
                                  );
                                },
                              );
                            }
                            final name = (_profile?['name'] ?? '')?.toString() ?? '';
                            final initials = name.split(' ').where((s) => s.isNotEmpty).map((s) => s[0]).take(2).join().toUpperCase();
                            if (initials.isNotEmpty) {
                              return Container(
                                decoration: BoxDecoration(
                                  color: colorScheme.primary.withOpacity(0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(child: Text(initials, style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.w600))),
                              );
                            }

                            // Avoid direct Image.asset to prevent uncaught "Asset not found" errors.
                            // Try loading the bundled logo bytes; if missing show neutral placeholder.
                            return FutureBuilder<Uint8List?>(
                              future: _loadAssetBytes('assets/images/app_logo_RH.jpg'),
                              builder: (ctx2, snap) {
                                if (snap.hasData && snap.data != null) {
                                  return Image.memory(snap.data!, fit: BoxFit.cover);
                                }
                                return Container(
                                  color: colorScheme.surface,
                                  child: Center(
                                    child: Icon(Icons.person, color: colorScheme.onSurface.withOpacity(0.28)),
                                  ),
                                );
                              },
                            );
                          }),
                        ),
                      ),

                    const SizedBox(width: 12),

                    // Expanded middle: name + location (ensures proper flex constraints)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_displayName(), style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Row(children: [
                            Icon(Icons.location_on_outlined, size: 14, color: colorScheme.onSurface.withAlpha((0.65 * 255).round())),
                            const SizedBox(width: 6),
                            Expanded(
                              child: InkWell(
                                onTap: _openLocationBottomSheet,
                                child: Text(
                                  _displayLocation(),
                                  style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurface.withAlpha((0.65 * 255).round())),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ]),
                        ],
                      ),
                    ),

                    // Actions (search + notifications)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () => NavigationUtils.safePush(context, SearchPageWidget()),
                          icon: Icon(Icons.search_rounded, color: colorScheme.primary, size: 24),
                        ),
                        const SizedBox(width: 6),
                        ScaleTransition(
                          scale: _notifPulse ?? const AlwaysStoppedAnimation(1.0),
                          child: badges.Badge(
                            badgeContent: Text(_unreadNotifications>99 ? '99+' : '$_unreadNotifications', style: TextStyle(fontSize: 10, color: colorScheme.onPrimary, fontWeight: FontWeight.w600)),
                            showBadge: _unreadNotifications>0,
                            child: IconButton(
                              onPressed: () => NavigationUtils.safePush(context, NotificationPageWidget()),
                              icon: Icon(Icons.notifications_none_rounded, color: colorScheme.primary, size: 24),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Main Content
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Padding(
                    // Add bottom padding so content isn't hidden by bottom nav bars
                    padding: EdgeInsets.fromLTRB(
                      20.0,
                      0.0,
                      20.0,
                      // include device bottom inset + extra spacing (nav bar height + margin)

                      MediaQuery.of(context).padding.bottom + kBottomNavigationBarHeight + 64.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 24.0),

                        // Carousel
                        SizedBox(
                          height: 160,
                          child: NotificationListener<ScrollNotification>(
                            onNotification: (n) {
                              if (n is ScrollStartNotification) {
                                _isUserScrolling = true;
                                _adTimer?.cancel();
                              } else if (n is ScrollEndNotification) {
                                _isUserScrolling = false;
                                _startAdTimer();
                              }
                              return false;
                            },
                            child: PageView.builder(
                              controller: _adPageController,
                              // While loading show a small finite number of placeholder pages.
                              // Once loaded, allow the builder to be unbounded (infinite) by omitting itemCount.
                              itemCount: _loadingAds ? 3 : null,
                              onPageChanged: (absIndex) {
                                if (!mounted) return;
                                final int count = _adImages.isNotEmpty ? _adImages.length : _defaultAds.length;
                                setState(() {
                                  _adPageAbsoluteIndex = absIndex;
                                  if (count > 0) _adPageIndex = absIndex % count;
                                });
                              },
                              itemBuilder: (context, index) {
                                if (_loadingAds) {
                                  return Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 4),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surface,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  );
                                }

                                final int count = _adImages.isNotEmpty ? _adImages.length : _defaultAds.length;
                                final rawSrc = (count > 0)
                                    ? (_adImages.isNotEmpty ? _adImages[index % count] : _defaultAds[index % count])
                                    : _defaultAds.first;
                                final resolved = _resolveAdSource(rawSrc);
                                final src = resolved['src'] as String?;
                                final isAsset = resolved['isAsset'] as bool? ?? false;

                                return Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: Container(
                                      color: colorScheme.surface,
                                      child: (src == null)
                                          ? Container(color: colorScheme.surface)
                                          : (isAsset
                                          ?
                                      // Use FutureBuilder to load asset bytes safely (avoids crash when asset missing).
                                      FutureBuilder<Uint8List?>(
                                        future: _loadAssetBytes(src),
                                        builder: (ctx, snap) {
                                          if (snap.connectionState == ConnectionState.waiting) {
                                            return Container(color: colorScheme.surface);
                                          }
                                          if (snap.hasData && snap.data != null) {
                                            return Image.memory(snap.data!, fit: BoxFit.cover);
                                          }
                                          // primary asset missing: try fallback bundled logo
                                          return FutureBuilder<Uint8List?>(
                                            future: _loadAssetBytes('assets/images/app_logo_RH.jpg'),
                                            builder: (ctx2, snap2) {
                                              if (snap2.hasData && snap2.data != null) {
                                                return Image.memory(snap2.data!, fit: BoxFit.cover);
                                              }
                                              return Container(
                                                color: colorScheme.surface,
                                                child: Center(
                                                  child: Icon(
                                                    Icons.broken_image_rounded,
                                                    color: colorScheme.onSurface.withOpacity(0.4),
                                                  ),
                                                ),
                                              );
                                            },
                                          );
                                        },
                                      )
                                          : CachedNetworkImage(
                                        imageUrl: src,
                                        fit: BoxFit.cover,
                                        placeholder: (c, u) => Container(color: colorScheme.surface),
                                        // If a network image fails, prefer showing the bundled carl_1 asset,
                                        // falling back to app_logo_RH if carl_1 is not available.
                                        errorWidget: (c, u, e) => FutureBuilder<Uint8List?>(
                                          future: _loadAssetBytes('assets/images/carl_1.webp'),
                                          builder: (ctx3, snap3) {
                                            if (snap3.hasData && snap3.data != null) {
                                              return Image.memory(snap3.data!, fit: BoxFit.cover);
                                            }
                                            return FutureBuilder<Uint8List?>(
                                              future: _loadAssetBytes('assets/images/app_logo_RH.jpg'),
                                              builder: (ctx4, snap4) {
                                                if (snap4.hasData && snap4.data != null) {
                                                  return Image.memory(snap4.data!, fit: BoxFit.cover);
                                                }
                                                return Container(color: colorScheme.surface);
                                              },
                                            );
                                          },
                                        ),
                                      )),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),

                        // Carousel Indicators
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate((_adImages.isNotEmpty ? _adImages.length : _defaultAds.length), (i) {
                            final active = i == _adPageIndex;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              width: active ? 20 : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: active ? colorScheme.primary : colorScheme.onSurface.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                            );
                          }),
                        ),

                        const SizedBox(height: 24),

                        // Announcement Banner (marquee) — use explicit app primary color
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFA20025).withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFFA20025).withOpacity(0.18),
                            ),
                          ),
                          child: _loadingMarquee
                              ? Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFA20025).withOpacity(0.28),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Container(
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFA20025).withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ],
                          )
                              : Row(
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                color: const Color(0xFFA20025),
                                size: 16,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final textStyle = TextStyle(
                                      color: const Color(0xFFA20025),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    );
                                    final tp = TextPainter(
                                      text: TextSpan(text: _marqueeText, style: textStyle),
                                      textDirection: Directionality.of(context),
                                    )..layout();
                                    final textWidth = tp.width;

                                    if (textWidth <= constraints.maxWidth) {
                                      return Text(
                                        _marqueeText,
                                        style: textStyle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      );
                                    }

                                    return ClipRect(
                                      child: AnimatedBuilder(
                                        animation: _marqueeController ?? kAlwaysDismissedAnimation,
                                        builder: (context, child) {
                                          final totalDistance = constraints.maxWidth + textWidth;
                                          final dx = constraints.maxWidth - (totalDistance * (_marqueeController?.value ?? 0));
                                          return Transform.translate(
                                            offset: Offset(dx, 0),
                                            child: SizedBox(
                                              width: textWidth,
                                              child: Text(
                                                _marqueeText,
                                                style: textStyle,
                                                maxLines: 1,
                                                overflow: TextOverflow.visible,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Services Section - Redesigned
                        Container(
                          padding: const EdgeInsets.all(0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Header with improved styling
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Services',
                                        style: theme.textTheme.titleLarge?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 22,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Choose from our trusted services',
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          color: colorScheme.onSurface.withOpacity(0.6),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      color: colorScheme.primary.withOpacity(0.1),
                                    ),
                                    child: TextButton(
                                      onPressed: () => NavigationUtils.safePush(context, AllServicepageWidget()),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            'See All',
                                            style: TextStyle(
                                              color: colorScheme.primary,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Icon(
                                            Icons.arrow_forward_rounded,
                                            color: colorScheme.primary,
                                            size: 16,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 24),

                              // Services Grid - responsive fixed column counts to avoid overly narrow cells
                              Builder(builder: (context) {
                                final sw = MediaQuery.of(context).size.width;
                                int cols = 4;
                                double aspect = 0.95;
                                // Use two columns for phone widths (makes grid denser and consistent)
                                if (sw < 700) {
                                  cols = 2;
                                  aspect = 1.15; // slightly taller items on phones
                                } else if (sw < 1000) {
                                  cols = 4;
                                  aspect = 1.0;
                                } else {
                                  cols = 6;
                                  aspect = 1.05;
                                }

                                return GridView.builder(
                                  physics: const NeverScrollableScrollPhysics(),
                                  shrinkWrap: true,
                                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: cols,
                                    crossAxisSpacing: 16,
                                    mainAxisSpacing: 20,
                                    childAspectRatio: aspect,
                                  ),
                                  itemCount: 8,
                                  itemBuilder: (context, index) => _buildServiceCard(context, index),
                                );
                              }),
                            ],
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Support Card (tappable)
                        InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => NavigationUtils.safePush(context, const SupportPageWidget()),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: colorScheme.primary.withOpacity(0.1),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Need Help?',
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Contact our support team',
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          color: colorScheme.onSurface.withOpacity(0.6),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    color: colorScheme.onPrimary,
                                    size: 24,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Artisans horizontal carousel section
                        const SizedBox(height: 32),
                        Builder(
                          builder: (context) {
                            final theme = Theme.of(context);
                            final colorScheme = theme.colorScheme;
                            if (_loadingArtisans) {
                              // Show horizontal shimmer/placeholder pages using PageView
                              return SizedBox(
                                height: 140,
                                child: PageView.builder(
                                  controller: _artisanPageController,
                                  itemCount: 3,
                                  onPageChanged: (p) {},
                                  itemBuilder: (ctx, i) => Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                    child: Card(
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      color: theme.cardColor,
                                      child: Container(
                                        padding: const EdgeInsets.all(12),
                                        child: Row(
                                          children: [
                                            Container(width: 64, height: 64, decoration: BoxDecoration(color: colorScheme.surface.withOpacity(0.18), shape: BoxShape.circle)),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Container(width: 80, height: 14, color: colorScheme.surface.withOpacity(0.18)),
                                                  const SizedBox(height: 8),
                                                  Container(width: 60, height: 12, color: colorScheme.surface.withOpacity(0.12)),
                                                  const SizedBox(height: 8),
                                                  Container(width: 40, height: 12, color: colorScheme.surface.withOpacity(0.10)),
                                                ],
                                              ),
                                            ),
                                            Column(mainAxisAlignment: MainAxisAlignment.center, children: [Container(width: 80, height: 32, decoration: BoxDecoration(color: colorScheme.primary.withOpacity(0.10), borderRadius: BorderRadius.circular(10)))])
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }
                            if (_artisanError != null) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12.0),
                                child: Center(
                                  child: Text(_artisanError!, style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.error)),
                                ),
                              );
                            }
                            if (_artisans.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12.0),
                                child: Center(
                                  child: Text('No artisans found.', style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface.withOpacity(0.7))),
                                ),
                              );
                            }

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(left: 2, bottom: 8),
                                  child: Text('Top Artisans', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                                ),
                                SizedBox(
                                  height: 140,
                                  child: NotificationListener<ScrollNotification>(
                                    onNotification: (n) {
                                      if (n is ScrollStartNotification) {
                                        _artisanUserScrolling = true;
                                        _artisanTimer?.cancel();
                                      } else if (n is ScrollEndNotification) {
                                        _artisanUserScrolling = false;
                                        _startArtisanTimer();
                                      }
                                      return false;
                                    },
                                    child: PageView.builder(
                                      controller: _artisanPageController,
                                      // When loading we show a small fixed number of placeholder pages.
                                      // Once loaded, omit itemCount to allow infinite builder indices.
                                      itemCount: _loadingArtisans ? 3 : null,
                                      onPageChanged: (absIndex) {
                                        if (!mounted) return;
                                        final int count = _artisans.length;
                                        setState(() {
                                          _artisanPageAbsoluteIndex = absIndex;
                                          if (count > 0) _artisanPageIndex = absIndex % count;
                                        });
                                      },
                                      itemBuilder: (ctx, index) {
                                        if (_loadingArtisans) {
                                          return Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                            child: Card(
                                              elevation: 0,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                              color: theme.cardColor,
                                              child: Container(
                                                padding: const EdgeInsets.all(12),
                                                child: Row(
                                                  children: [
                                                    Container(width: 64, height: 64, decoration: BoxDecoration(color: colorScheme.surface.withOpacity(0.18), shape: BoxShape.circle)),
                                                    const SizedBox(width: 12),
                                                    Expanded(
                                                      child: Column(
                                                        mainAxisAlignment: MainAxisAlignment.center,
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Container(width: 80, height: 14, color: colorScheme.surface.withOpacity(0.18)),
                                                          const SizedBox(height: 8),
                                                          Container(width: 60, height: 12, color: colorScheme.surface.withOpacity(0.12)),
                                                          const SizedBox(height: 8),
                                                          Container(width: 40, height: 12, color: colorScheme.surface.withOpacity(0.10)),
                                                        ],
                                                      ),
                                                    ),
                                                    Column(mainAxisAlignment: MainAxisAlignment.center, children: [Container(width: 80, height: 32, decoration: BoxDecoration(color: colorScheme.primary.withOpacity(0.10), borderRadius: BorderRadius.circular(10)))])
                                                  ],
                                                ),
                                              ),
                                            ),
                                          );
                                        }

                                        final int count = _artisans.length;
                                        if (count == 0) return const SizedBox.shrink();
                                        final int idx = index % count;
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                          child: _buildArtisanCard(context, _artisans[idx]),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),

                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

    Widget _buildServiceCard(BuildContext context, int index) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // Define service data with consistent colors
    final List<Map<String, dynamic>> services = [
      {
        'icon': FFIcons.kcapentry,
        'label': 'Carpentry',
        'color': Color(0xFFFF6B35), // Orange
        'iconColor': Color(0xFFFF6B35),
      },
      {
        'icon': FFIcons.kcatering,
        'label': 'Catering',
        'color': Color(0xFF00C9A7), // Teal
        'iconColor': Color(0xFF00C9A7),
      },
      {
        'icon': FFIcons.kcleaning,
        'label': 'Cleaning',
        'color': Color(0xFF4CD964), // Green
        'iconColor': Color(0xFF4CD964),
      },
      {
        'icon': FFIcons.kelectrictian,
        'label': 'Electrician',
        'color': Color(0xFF5E5CE6), // Purple
        'iconColor': Color(0xFF5E5CE6),
      },
      {
        'icon': FFIcons.kgardener,
        'label': 'Gardener',
        'color': Color(0xFF32D74B), // Lime Green
        'iconColor': Color(0xFF32D74B),
      },
      {
        'icon': FFIcons.kmechanic,
        'label': 'Mechanic',
        'color': Color(0xFFFF375F), // Pink
        'iconColor': Color(0xFFFF375F),
      },
      {
        'icon': FFIcons.kmaintainace,
        'label': 'Maintenance',
        'color': Color(0xFF64D2FF), // Light Blue
        'iconColor': Color(0xFF64D2FF),
      },
      {
        'icon': FFIcons.ktailor,
        'label': 'Tailor',
        'color': Color(0xFFBF5AF2), // Purple Pink
        'iconColor': Color(0xFFBF5AF2),
      },
    ];

    final service = services[index];

    return Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => NavigationUtils.safePush(context, SearchPageWidget(initialQuery: service['label'] as String)),
          splashColor: service['color'].withOpacity(0.1) as Color,
          highlightColor: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? Colors.grey.shade800
                    : Colors.grey.shade200,
                width: 1.5,
              ),
              color: isDark ? Colors.grey.shade900.withOpacity(0.5) : Colors.white,
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final double w = constraints.maxWidth.isFinite ? constraints.maxWidth : 100.0;
                  final double h = constraints.maxHeight.isFinite ? constraints.maxHeight : 100.0;
                  // Icon diameter scales with available width but is clamped
                  final double iconDiameter = w * 0.5 < 40 ? (w * 0.5).clamp(24.0, 56.0) : (w * 0.45).clamp(28.0, 56.0);
                  final double spacing = (w * 0.06).clamp(6.0, 12.0);

                  // If vertical space is very small, favor single-line label and hide the small status chip
                  final bool compact = h < 90 || w < 90;

                  // Reduce icon size further in very compact mode to avoid overflow
                  double adjustedIconDiameter = iconDiameter;
                  if (compact) adjustedIconDiameter = iconDiameter.clamp(22.0, 40.0);

                  // Compute icon inner size based on adjusted diameter (will be recomputed as finalIconInner later)

                  // Font and text height (keep predictable heights to avoid overflow)
                  final double fontSize = (w * 0.075).clamp(10.0, 13.0);
                  double textHeight = compact ? (fontSize * 1.3) : (fontSize * 2.4);

                  // Ensure content fits into available height. Compute soft caps based on h.
                  final double maxIconByHeight = h * 0.55;
                  final double maxTextByHeight = h * 0.28;

                  double finalIconDiameter = adjustedIconDiameter.clamp(18.0, maxIconByHeight);
                  // recompute inner size
                  double finalIconInner = (finalIconDiameter * 0.55).clamp(14.0, 32.0);

                  // Cap text height so icon + spacing + text + status <= h
                  textHeight = textHeight.clamp(10.0, maxTextByHeight);

                  // recompute spacing to be smaller if necessary
                  double finalSpacing = spacing;
                  final double estimatedTotal = finalIconDiameter + finalSpacing + textHeight + (compact ? 0.0 : 20.0);
                  if (estimatedTotal > h) {
                    // shrink spacing first, then icon, then text
                    finalSpacing = (spacing * (h / estimatedTotal)).clamp(4.0, spacing);
                    final double remaining = h - finalSpacing - (compact ? 0.0 : 20.0);
                    finalIconDiameter = finalIconDiameter.clamp(18.0, remaining * 0.65);
                    textHeight = (remaining - finalIconDiameter).clamp(10.0, remaining * 0.6);
                    finalIconInner = (finalIconDiameter * 0.55).clamp(14.0, 32.0);
                  }

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: finalIconDiameter,
                        height: finalIconDiameter,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.cardColor,
                        ),
                        child: Center(
                          child: Icon(
                            service['icon'] as IconData,
                            color: FlutterFlowTheme.of(context).primary,
                            size: finalIconInner,
                          ),
                        ),
                      ),

                      SizedBox(height: finalSpacing),

                      // Label - use a bounded SizedBox so the height is predictable
                      SizedBox(
                        height: textHeight,
                        child: Text(
                          service['label'] as String,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                            fontSize: fontSize,
                          ),
                          maxLines: compact ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                      // Small status indicator (always shown). In compact mode we reduce padding and font size.
                      SizedBox(height: compact ? 6 : 8),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: compact ? 1 : 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurface.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: theme.dividerColor.withOpacity(0.08)),
                        ),
                        child: Text(
                          'Available',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withOpacity(0.7),
                            fontSize: compact ? 9 : 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        )
    );
    }

        Future<void> _loadHomeArtisans() async {
        if (_loadingArtisans) return;
        setState(() { _loadingArtisans = true; _artisanError = null; });
        try {
          final list = await ArtistService.fetchArtisans(page: 1, limit: 10);
          if (!mounted) return;
          setState(() {
            _artisans = List<Map<String, dynamic>>.from(list);
            _loadingArtisans = false;
            _artisanError = null;
          });
      // Jump to a high start index to allow infinite swiping both directions.
      final int count = _artisans.length;
      if (count > 0) {
        final start = count * 1000; // arbitrary large offset
        _artisanPageAbsoluteIndex = start;
        if (_artisanPageController.hasClients) {
          _artisanPageController.jumpToPage(start);
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            try { _artisanPageController.jumpToPage(start); } catch (_) {}
          });
        }
      }
      // Start auto-scroll for artisans carousel once we have data
       _startArtisanTimer();
        } catch (e) {
          if (!mounted) return;
          setState(() { _loadingArtisans = false; _artisanError = 'Failed to load artisans'; });
        }
        }

      void _startArtisanTimer() {
        _artisanTimer?.cancel();
        // don't start if not enough items
        if (!mounted || _artisans.length < 2) return;
        _artisanTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || _artisans.isEmpty || _artisanUserScrolling) return;
      final count = _artisans.length;
      final nextAbs = _artisanPageAbsoluteIndex + 1;
      try {
        _artisanPageController.animateToPage(nextAbs, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
        setState(() {
          _artisanPageAbsoluteIndex = nextAbs;
          if (count > 0) _artisanPageIndex = _artisanPageAbsoluteIndex % count;
        });
      } catch (_) {}
     });
   }

    Widget _buildArtisanCard(BuildContext context, Map<String, dynamic> artisan) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final name = _artisanDisplayName(artisan);
    final ratingVal = (artisan['rating'] is num) ? (artisan['rating'] as num).toDouble() : (artisan['avgRating'] is num ? (artisan['avgRating'] as num).toDouble() : 0.0);
    final profileRaw = _artisanProfileImage(artisan);
    final profileUrl = _normalizeImageUrl(profileRaw?.toString());

    // Robustly extract trade/service label and avoid printing list `[]` when backend returns an array
    final dynamic tradeRaw = artisan['trade'] ?? artisan['service'] ?? artisan['profession'] ?? artisan['occupation'];
    String trade = 'Service';
    try {
      if (tradeRaw is String && tradeRaw.trim().isNotEmpty) {
        trade = tradeRaw.trim();
      } else if (tradeRaw is List && tradeRaw.isNotEmpty) {
        trade = tradeRaw.map((e) {
          if (e == null) return '';
          if (e is String) return e.trim();
          if (e is Map) return (e['name'] ?? e['label'] ?? e['title'] ?? '').toString().trim();
          return e.toString().trim();
        }).where((s) => s.isNotEmpty).join(', ');
        if (trade.isEmpty) trade = 'Service';
      } else if (tradeRaw is Map) {
        trade = (tradeRaw['name'] ?? tradeRaw['label'] ?? tradeRaw['title'] ?? tradeRaw['service'] ?? tradeRaw['trade'])?.toString() ?? 'Service';
      } else if (tradeRaw != null) {
        trade = tradeRaw.toString();
      }
    } catch (_) { trade = 'Service'; }

    return LayoutBuilder(builder: (ctx, constraints) {
      final cardWidth = (MediaQuery.of(ctx).size.width - 40).clamp(280.0, 820.0);
      return SizedBox(
        width: cardWidth,
        height: 140,
        child: GestureDetector(
          onTap: () => NavigationUtils.safePush(context, ArtisanDetailPageWidget(artisan: artisan)),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: theme.dividerColor.withOpacity(0.06))),
            color: theme.cardColor,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Avatar
                  ClipOval(
                    child: SizedBox(
                      width: 64,
                      height: 64,
                      child: profileUrl != null
                          ? CachedNetworkImage(
                              imageUrl: profileUrl,
                              fit: BoxFit.cover,
                              placeholder: (c, u) => Container(color: colorScheme.surface),
                              errorWidget: (c, u, e) {
                                final initials = name.split(' ').where((s) => s.isNotEmpty).map((s) => s[0]).take(2).join().toUpperCase();
                                return Container(
                                  color: colorScheme.surface,
                                  child: Center(child: Text(initials, style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.w600))),
                                );
                              },
                            )
                          : Container(
                              color: colorScheme.surface,
                              child: Center(child: Text(name.split(' ').where((s) => s.isNotEmpty).map((s) => s[0]).take(2).join().toUpperCase(), style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.w600))),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Name + rating
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            // Name + verified badge close to the name
                            Expanded(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                                  ),
                                  if (artisan['verified'] == true || artisan['isVerified'] == true || artisan['is_verified'] == true) ...[
                                    const SizedBox(width: 4),
                                    Icon(Icons.verified, color: Colors.green, size: 16),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Ratings: show stars and numeric count on a single responsive line
                        if (ratingVal > 0) ...[
                          LayoutBuilder(builder: (ctx2, cons) {
                            final double starSize = (cons.maxWidth.isFinite && cons.maxWidth < 220) ? 12.0 : 14.0;
                            final int filled = ratingVal.round().clamp(0, 5);
                            return Row(
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: List.generate(5, (i) => Icon(i < filled ? Icons.star : Icons.star_border, color: Colors.amber, size: starSize)),
                                ),
                                const SizedBox(width: 8),
                                Text(ratingVal.toStringAsFixed(1), style: theme.textTheme.bodySmall),
                              ],
                            );
                          }),
                          const SizedBox(height: 6),
                        ] else ...[
                          Text('No ratings', style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurface.withOpacity(0.6))),
                        ],
                        const SizedBox(height: 8),
                        // Trade pill (single-line, no brackets). Trade string is already normalized above.
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(trade, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.primary, fontWeight: FontWeight.w600)),
                        ),
                       ],
                     ),
                   ),

                  // Book Now button
                   Column(
                     mainAxisAlignment: MainAxisAlignment.center,
                     children: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                          shadowColor: Colors.transparent,
                        ),
                        onPressed: () => NavigationUtils.safePush(context, ArtisanDetailPageWidget(artisan: artisan, openHire: true)),
                        child: const Text('Book Now'),
                      ),
                     ],
                   ),
                ],
              ),
            ),
          ),
        ),
      );
    });
    }

  // Robust helper to extract a human display name from various artisan/user shapes
  String _artisanDisplayName(Map<String, dynamic>? a) {
    if (a == null) return 'Unknown';
    try {
      // candidate keys in order of preference
      final nameKeys = ['name', 'fullName', 'displayName', 'username', 'firstName', 'firstname', 'lastName'];

      // try top-level simple keys
      for (final k in nameKeys) {
        if (a.containsKey(k) && a[k] != null) {
          final v = a[k];
          if (v is String && v.trim().isNotEmpty) return v.trim();
        }
      }

      // try composing firstName + lastName
      final first = (a['firstName'] ?? a['firstname'])?.toString() ?? '';
      final last = (a['lastName'] ?? a['lastname'])?.toString() ?? '';
      if (first.trim().isNotEmpty || last.trim().isNotEmpty) return ('${first.trim()} ${last.trim()}').trim();

      // check common nested roots
      final nestedRoots = ['user', 'owner', 'data', 'profile', 'person', 'artisan'];
      for (final root in nestedRoots) {
        if (a[root] is Map) {
          final m = Map<String, dynamic>.from(a[root]);
          for (final k in nameKeys) {
            if (m.containsKey(k) && m[k] != null) {
              final v = m[k];
              if (v is String && v.trim().isNotEmpty) return v.trim();
            }
          }
          final f = (m['firstName'] ?? m['firstname'])?.toString() ?? '';
          final l = (m['lastName'] ?? m['lastname'])?.toString() ?? '';
          if (f.trim().isNotEmpty || l.trim().isNotEmpty) return ('${f.trim()} ${l.trim()}').trim();
        }
      }

      // Sometimes API returns an embedded user object as a JSON-string
      for (final root in nestedRoots) {
        if (a[root] is String) {
          try {
            final parsed = jsonDecode(a[root] as String);
            if (parsed is Map) {
              final out = _artisanDisplayName(Map<String, dynamic>.from(parsed));
              if (out != 'Unknown') return out;
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
    return 'Unknown';
  }

  // Robust helper to extract an image URL/path for an artisan from various shapes
  String? _artisanProfileImage(Map<String, dynamic>? a) {
    if (a == null) return null;
    try {
      // candidate top-level keys
      final imgKeys = ['profileImage', 'profileImageUrl', 'avatar', 'image', 'photo', 'picture', 'pictureUrl', 'imageUrl', 'avatarUrl', 'thumbnail'];
      for (final k in imgKeys) {
        if (a.containsKey(k) && a[k] != null) {
          final v = a[k];
          if (v is String && v.trim().isNotEmpty) return v.trim();
          if (v is Map) {
            for (final ck in ['url', 'path', 'imageUrl', 'src']) {
              if (v.containsKey(ck) && v[ck] != null) {
                final cs = v[ck];
                if (cs is String && cs.trim().isNotEmpty) return cs.trim();
              }
            }
          }
        }
      }

      // nested roots
      final nestedRoots = ['user', 'owner', 'data', 'profile', 'person', 'artisan'];
      for (final root in nestedRoots) {
        if (a[root] is Map) {
          final m = Map<String, dynamic>.from(a[root]);
          final got = _artisanProfileImage(m);
          if (got != null && got.isNotEmpty) return got;
        }
      }

      // sometimes nested as json string
      for (final root in nestedRoots) {
        if (a[root] is String) {
          try {
            final parsed = jsonDecode(a[root] as String);
            if (parsed is Map) {
              final out = _artisanProfileImage(Map<String, dynamic>.from(parsed));
              if (out != null && out.isNotEmpty) return out;
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
    return null;
  }

  String _normalizeBaseUrl(String raw) {
    var base = (raw ?? '').toString().trim();
    if (base.isEmpty) return '';
    if (base.startsWith('http:') && !base.startsWith('http://')) base = base.replaceFirst('http:', 'http://');
    if (base.startsWith('https:') && !base.startsWith('https://')) base = base.replaceFirst('https:', 'https://');
    if (!base.startsWith(RegExp(r'https?://'))) base = 'https://$base';
    return base.replaceAll(RegExp(r'/+\$'), '').replaceAll(RegExp(r'/+ '), '');
  }

  Map<String, dynamic> _resolveAdSource(String? raw) {
    // returns {'src': String?, 'isAsset': bool}
    try {
      if (raw == null) return {'src': null, 'isAsset': false};
      var s = raw.trim();
      if (s.isEmpty) return {'src': null, 'isAsset': false};
      // Asset reference (bundled)
      if (s.startsWith('assets/')) return {'src': s, 'isAsset': true};
      // Full network URL
      if (s.startsWith('http://') || s.startsWith('https://'))
        return {'src': s, 'isAsset': false};
      // Leading slash path => treat as network path on API_BASE_URL
      final base = _normalizeBaseUrl(API_BASE_URL);
      if (s.startsWith('/')) return {'src': '$base$s', 'isAsset': false};
      // If looks like a filename with extension, assume uploads
      if (s.contains('.') && !s.contains(' '))
        return {'src': '$base/uploads/$s', 'isAsset': false};
      // Fallback: treat as network uploads path
      return {'src': '$base/uploads/$s', 'isAsset': false};
    } catch (_) {
      try {
        final s = raw?.toString() ?? '';
        return {
          'src': s.isNotEmpty ? s : null,
          'isAsset': s.startsWith('assets/')
        };
      } catch (_) {
        return {'src': null, 'isAsset': false};
      }
    }
  }
}

