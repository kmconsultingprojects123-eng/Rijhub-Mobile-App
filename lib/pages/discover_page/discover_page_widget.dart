// ignore_for_file: unnecessary_type_check, unused_element

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/artist_service.dart';
import '../../services/user_service.dart';
import '../artisan_detail_page/artisan_detail_page_widget.dart';
import '../../mapbox_config.dart';
import '../../utils/navigation_utils.dart';
import '/main.dart';
import '../../api_config.dart';

class DiscoverPageWidget extends StatefulWidget {
  const DiscoverPageWidget({Key? key}) : super(key: key);
  // Route identifiers used by the app router
  static const String routeName = 'DiscoverPage';
  static const String routePath = '/discoverPage';

  @override
  State<DiscoverPageWidget> createState() => _DiscoverPageWidgetState();
}

class _DiscoverPageWidgetState extends State<DiscoverPageWidget> with SingleTickerProviderStateMixin {
  // UI state
  final ScrollController _scrollController = ScrollController();
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  List<Map<String, dynamic>> _artisans = [];
  List<Map<String, dynamic>> _cachedArtisans = [];
  bool _loading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _page = 1;

  // Map features state
  bool _showUserLocation = true;
  bool _showArtisanMarkers = true;
  double _mapZoom = 13.0;
  LatLngBounds? _visibleBounds;

  // user location
  List<double>? _userCoords;
  String? _userLocation;

  // search/UX
  String _query = '';
  String? _lastMessage;
  Timer? _debounce;

  // default center
  static const double DEFAULT_LAT = 9.0820;
  static const double DEFAULT_LON = 8.6753;

  // Map style - adaptable to theme
  String get _mapStyle {
    final brightness = MediaQuery.of(context).platformBrightness;
    if (MAPBOX_ACCESS_TOKEN.isNotEmpty) {
      return brightness == Brightness.dark
          ? 'mapbox/dark-v10' // Dark style for Mapbox
          : 'mapbox/streets-v11'; // Light style for Mapbox
    } else {
      // For OpenStreetMap, we can't change style, but we'll use different tile layers
      return brightness == Brightness.dark ? 'cartodbdark' : 'openstreetmap';
    }
  }

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(_onSearchFocusChange);
    _scrollController.addListener(_onScroll);
    _mapController.mapEventStream.listen(_onMapEvent);
    _init();
  }

  void _onMapEvent(MapEvent event) {
    if (event is MapEventMoveEnd) {
      _mapZoom = _mapController.camera.zoom;
      _visibleBounds = _mapController.camera.visibleBounds;
    }
  }

  Future<void> _init() async {
    // load cached artisans if any
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('cached_artisans_json');
      if (raw != null && raw.isNotEmpty) {
        final parsed = jsonDecode(raw);
        if (parsed is List) {
          _cachedArtisans = parsed.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e)).toList();
        }
      }
    } catch (_) {}

    // show cached quickly
    if (_cachedArtisans.isNotEmpty) {
      setState(() {
        _artisans = List<Map<String, dynamic>>.from(_cachedArtisans);
        _lastMessage = 'Showing cached results';
      });
      unawaited(_fitMapToArtisans());
    }

    // attempt to get canonical/device location
    try {
      final loc = await UserService.getCanonicalLocation();
      if (loc is Map) {
        final lat = loc['latitude'];
        final lon = loc['longitude'];
        final addr = loc['address'] as String?;
        if (lat is num && lon is num) {
          _userCoords = [lat.toDouble(), lon.toDouble()];
          if (addr != null && addr.isNotEmpty) _userLocation = addr;
        }
      }
    } catch (_) {}

    try {
      final pos = await _determinePosition();
      if (pos != null) {
        _userCoords = [pos.latitude, pos.longitude];
        _userLocation = null;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('cached_location_lat', pos.latitude);
        await prefs.setDouble('cached_location_lon', pos.longitude);
      }
    } catch (_) {}

    // initial load
    await _loadArtisans(next: false, showLoading: true);
  }

  Future<Position?> _determinePosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      if (permission == LocationPermission.deniedForever) return null;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
      );
      return pos;
    } catch (_) {
      return null;
    }
  }

  void _onSearchFocusChange() {
    if (_searchFocus.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          final screenH = MediaQuery.of(context).size.height;
          final maxExtent = screenH * 0.55;
          final minExtent = screenH * 0.20;
          final collapseOffset = (maxExtent - minExtent).clamp(0.0, double.infinity);
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              collapseOffset,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        } catch (_) {}
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          if (_scrollController.hasClients && _scrollController.offset <= 20.0) {
            _scrollController.animateTo(
              0.0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        } catch (_) {}
      });
    }
  }

  void _onScroll() {
    try {
      if (!_scrollController.hasClients) return;
      final pos = _scrollController.position;
      final max = pos.maxScrollExtent;
      final currentOffset = pos.pixels;

      if (max > 0) {
        final threshold = max * 0.8;
        if (currentOffset >= threshold && !_isLoadingMore && _hasMore && !_loading) {
          _loadArtisans(next: true);
        }
      }
    } catch (_) {}
  }

  Future<void> _loadArtisans({bool next = false, bool showLoading = true}) async {
    if (showLoading && _loading) return;
    if (next && !_hasMore) return;

    if (showLoading) setState(() => _loading = true);
    if (next) _isLoadingMore = true;

    final pageToLoad = next ? _page + 1 : 1;
    try {
      List<Map<String, dynamic>> res = [];
      final q = _query.trim();
      if (q.isNotEmpty) {
        final byTrade = await ArtistService.fetchArtisans(page: pageToLoad, limit: 20, trade: q);
        final byLoc = await ArtistService.fetchArtisans(page: pageToLoad, limit: 20, location: q);
        final Map<String, Map<String, dynamic>> merged = {};
        for (final a in byTrade) {
          final id = (a['_id'] ?? a['id'] ?? UniqueKey().toString()).toString();
          merged[id] = a is Map<String, dynamic> ? Map<String, dynamic>.from(a) : <String, dynamic>{};
        }
        for (final a in byLoc) {
          final id = (a['_id'] ?? a['id'] ?? UniqueKey().toString()).toString();
          if (!merged.containsKey(id)) merged[id] = a is Map<String, dynamic> ? Map<String, dynamic>.from(a) : <String, dynamic>{};
        }
        res = merged.values.map((e) => Map<String, dynamic>.from(e)).toList();
      } else {
        final loc = _userLocation;
        res = await ArtistService.fetchArtisans(
          page: pageToLoad,
          limit: 20,
          location: loc,
          lat: _userCoords != null ? _userCoords![0] : null,
          lon: _userCoords != null ? _userCoords![1] : null,
          radiusKm: 100,
        );
      }

      final only = <Map<String, dynamic>>[];
      for (final r in res) {
        if (r is Map<String, dynamic>) only.add(Map<String, dynamic>.from(r));
      }

      if (!mounted) return;
      setState(() {
        if (next) {
          _artisans.addAll(only);
          _page = pageToLoad;
        } else {
          _artisans = only;
          _page = 1;
        }
        _hasMore = only.length >= 20;
        _lastMessage = '${_artisans.length} artisans found';
      });

      // cache first page
      if (!next) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('cached_artisans_json', jsonEncode(_artisans));
        } catch (_) {}
      }

      if (_artisans.isNotEmpty) await _fitMapToArtisans();
    } on SocketException catch (_) {
      if (mounted) setState(() => _lastMessage = null);
    } catch (_) {
      if (mounted) setState(() => _lastMessage = null);
    } finally {
      if (mounted) {
        setState(() {
          if (showLoading) _loading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _fitMapToArtisans() async {
    final points = <ll.LatLng>[];
    for (final a in _artisans) {
      final c = _extractLatLon(a);
      if (c != null) points.add(c);
    }
    if (points.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          if (_userCoords != null) _mapController.move(ll.LatLng(_userCoords![0], _userCoords![1]), 12.0);
          else _mapController.move(ll.LatLng(DEFAULT_LAT, DEFAULT_LON), 6.0);
        } catch (_) {}
      });
      return;
    }

    double minLat = points.first.latitude, maxLat = points.first.latitude;
    double minLng = points.first.longitude, maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    const padding = 0.05;
    minLat -= padding;
    maxLat += padding;
    minLng -= padding;
    maxLng += padding;

    final centerLat = (minLat + maxLat) / 2.0;
    final centerLng = (minLng + maxLng) / 2.0;

    double spanLat = (maxLat - minLat).abs();
    double spanLng = (maxLng - minLng).abs();
    final span = max(spanLat, spanLng);
    double zoom;
    if (span < 0.01) zoom = 15.0;
    else if (span < 0.05) zoom = 14.0;
    else if (span < 0.2) zoom = 12.5;
    else if (span < 1.0) zoom = 10.5;
    else zoom = 8.0;

    try {
      _mapController.move(ll.LatLng(centerLat, centerLng), zoom);
    } catch (_) {}
  }

  ll.LatLng? _extractLatLon(Map<String, dynamic> a) {
    try {
      final coords = a['coordinates'] ?? a['coords'] ?? a['locationCoordinates'];
      if (coords is List && coords.length >= 2) {
        final v0 = coords[0];
        final v1 = coords[1];
        if (v0 is num && v1 is num) return ll.LatLng(v0.toDouble(), v1.toDouble());
      }
      final lat = a['latitude'] ?? a['lat'] ?? a['location']?['lat'];
      final lon = a['longitude'] ?? a['lon'] ?? a['location']?['lng'];
      if (lat is num && lon is num) return ll.LatLng(lat.toDouble(), lon.toDouble());
    } catch (_) {}
    return null;
  }

  String _initialsFromName(String name) {
    try {
      final parts = name.trim().split(RegExp(r"\s+"));
      if (parts.isEmpty) return '';
      if (parts.length == 1) return parts.first.substring(0, min(2, parts.first.length)).toUpperCase();
      return (parts.first[0] + parts.last[0]).toUpperCase();
    } catch (_) {
      return '';
    }
  }

  // Enhanced marker builder with better styling
  Widget _buildMarker(Map<String, dynamic> a) {
    final theme = Theme.of(context);
    final img = _profileImageUrl(a);
    final isUrl = img.isNotEmpty && (img.startsWith('http://') || img.startsWith('https://') || img.startsWith('data:') || img.startsWith('file://'));
    final rating = _extractRating(a);
    final isRated = rating != null && rating >= 4.0;

    return GestureDetector(
      onTap: () async {
        try {
          await NavigationUtils.safePush(
            context,
            ArtisanDetailPageWidget(artisan: _artisanWithUserId(a), openHire: true),
          );
        } catch (_) {}
      },
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          shape: BoxShape.circle,
          border: Border.all(
            color: isRated ? Colors.amber : theme.colorScheme.primary,
            width: 2.0,
          ),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.onSurface.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            ClipOval(
              child: isUrl
                  ? Image.network(
                img,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: theme.colorScheme.primaryContainer,
                  child: Center(
                    child: Text(
                      _initialsFromName((a['name'] ?? a['fullName'] ?? '').toString()),
                      style: TextStyle(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              )
                  : Container(
                color: theme.colorScheme.primaryContainer,
                child: Center(
                  child: Text(
                    _initialsFromName((a['name'] ?? a['fullName'] ?? '').toString()),
                    style: TextStyle(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
            if (isRated)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.amber,
                    shape: BoxShape.circle,
                    border: Border.all(color: theme.colorScheme.surface, width: 1),
                  ),
                  child: const Icon(Icons.star_rounded, size: 10, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Enhanced map features widget
  Widget _buildMapFeatures(BuildContext ctx) {
    final theme = Theme.of(ctx);
    return Positioned(
      right: 12,
      bottom: 12,
      child: Column(
        children: [
          _buildMapFeatureButton(
            icon: Icons.my_location_rounded,
            onPressed: _zoomToUserLocation,
            tooltip: 'Find my location',
          ),
          const SizedBox(height: 8),
          _buildMapFeatureButton(
            icon: Icons.zoom_in_map_rounded,
            onPressed: _fitMapToArtisans,
            tooltip: 'Fit to artisans',
          ),
          const SizedBox(height: 8),
          _buildMapFeatureButton(
            icon: _showArtisanMarkers ? Icons.location_on_rounded : Icons.location_off_rounded,
            onPressed: () => setState(() => _showArtisanMarkers = !_showArtisanMarkers),
            tooltip: _showArtisanMarkers ? 'Hide markers' : 'Show markers',
          ),
        ],
      ),
    );
  }

  Widget _buildMapFeatureButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
  }) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.onSurface.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: theme.colorScheme.primary),
        tooltip: tooltip,
        style: IconButton.styleFrom(
          backgroundColor: theme.colorScheme.surface,
          shape: const CircleBorder(),
        ),
      ),
    );
  }

  void _zoomToUserLocation() {
    if (_userCoords != null) {
      _mapController.move(ll.LatLng(_userCoords![0], _userCoords![1]), 15.0);
    }
  }

  String _normalizeImageUrl(String url) {
    try {
      var u = url.trim();
      if (u.isEmpty) return '';
      if (u.startsWith('data:')) return u;
      if (u.startsWith('http://') || u.startsWith('https://')) return u;
      if (u.startsWith('//')) return 'https:$u';
      if (u.startsWith('/')) {
        final base = API_BASE_URL.endsWith('/') ? API_BASE_URL.substring(0, API_BASE_URL.length - 1) : API_BASE_URL;
        if (base.isNotEmpty) return base + u;
        return u;
      }
      final domainLike = RegExp(r'^[\w\.-]+\.[a-zA-Z]{2,}(/|$)');
      if (domainLike.hasMatch(u)) return 'https://' + u;
      final base = API_BASE_URL.endsWith('/') ? API_BASE_URL.substring(0, API_BASE_URL.length - 1) : API_BASE_URL;
      if (base.isNotEmpty) return base + '/' + u;
      return u;
    } catch (_) {
      return url;
    }
  }

  String _profileImageUrl(Map<String, dynamic> a) {
    try {
      final candidates = [
        'profileImage',
        'profile_image',
        'profilePicture',
        'profile_picture',
        'avatar',
        'image',
        'photo',
        'picture',
        'thumbnail',
        'imageUrl',
        'image_url',
        'photoUrl',
        'photo_url',
        'img'
      ];

      for (final k in candidates) {
        final v = a[k];
        if (v is String && v.isNotEmpty) return v;
      }

      for (final nk in ['profile', 'user', 'owner']) {
        if (a[nk] is Map) {
          final m = Map<String, dynamic>.from(a[nk] as Map);
          for (final k in candidates) {
            final v = m[k];
            if (v is String && v.isNotEmpty) return _normalizeImageUrl(v);
          }
          if (m['photos'] is List && (m['photos'] as List).isNotEmpty) {
            final first = (m['photos'] as List).first;
            if (first is String && first.isNotEmpty) return _normalizeImageUrl(first);
            if (first is Map) {
              final url = (first['url'] ?? first['src'] ?? first['path']);
              if (url is String && url.isNotEmpty) return _normalizeImageUrl(url);
            }
          }
          if (m['profileImage'] is Map) {
            final url = (m['profileImage']['url'] ?? m['profileImage']['src'] ?? m['profileImage']['path']);
            if (url is String && url.isNotEmpty) return _normalizeImageUrl(url);
          }
          if (m['avatar'] is Map) {
            final url = (m['avatar']['url'] ?? m['avatar']['src'] ?? m['avatar']['path']);
            if (url is String && url.isNotEmpty) return _normalizeImageUrl(url);
          }
        }
      }

      for (final nk in ['artisanAuthDetails', 'artisanAuth', 'authDetails']) {
        if (a[nk] is Map) {
          final m = Map<String, dynamic>.from(a[nk] as Map);
          for (final k in candidates) {
            final v = m[k];
            if (v is String && v.isNotEmpty) return _normalizeImageUrl(v);
          }
          if (m['profileImage'] is Map) {
            final url = (m['profileImage']['url'] ?? m['profileImage']['src'] ?? m['profileImage']['path']);
            if (url is String && url.isNotEmpty) return _normalizeImageUrl(url);
          }
          if (m['photos'] is List && (m['photos'] as List).isNotEmpty) {
            final first = (m['photos'] as List).first;
            if (first is String && first.isNotEmpty) return _normalizeImageUrl(first);
            if (first is Map) {
              final url = (first['url'] ?? first['src'] ?? first['path']);
              if (url is String && url.isNotEmpty) return _normalizeImageUrl(url);
            }
          }
        }
      }

      if (a['photos'] is List && (a['photos'] as List).isNotEmpty) {
        final first = (a['photos'] as List).first;
        if (first is String && first.isNotEmpty) return first;
        if (first is Map) {
          final url = (first['url'] ?? first['src'] ?? first['path']);
          if (url is String && url.isNotEmpty) return url;
        }
      }
      if (a['images'] is List && (a['images'] as List).isNotEmpty) {
        final first = (a['images'] as List).first;
        if (first is String && first.isNotEmpty) return first;
        if (first is Map) {
          final url = (first['url'] ?? first['src'] ?? first['path']);
          if (url is String && url.isNotEmpty) return url;
        }
      }

      if (a['user'] is Map) {
        final m = Map<String, dynamic>.from(a['user']);
        for (final k in candidates) {
          final v = m[k];
          if (v is String && v.isNotEmpty) return v;
        }
      }
    } catch (_) {}
    return '';
  }

  String? _extractUserIdFromArtisan(Map<String, dynamic> a) {
    try {
      final candidates = [
        'userId',
        'user_id',
        'ownerId',
        'owner_id',
        'owner',
        'user',
        'artisanUser',
        'createdBy',
        'createdById',
        'created_by'
      ];
      for (final k in candidates) {
        final v = a[k];
        if (v == null) continue;
        if (v is String && v.isNotEmpty) return v;
        if (v is Map) {
          if (v['_id'] != null && v['_id'].toString().isNotEmpty) return v['_id'].toString();
          if (v['id'] != null && v['id'].toString().isNotEmpty) return v['id'].toString();
        }
      }

      final nestedKeys = ['profile', 'artisanAuthDetails', 'userInfo', 'artisan', 'owner'];
      for (final nk in nestedKeys) {
        final nv = a[nk];
        if (nv is Map) {
          if (nv['userId'] is String && nv['userId'].toString().isNotEmpty) return nv['userId'].toString();
          if (nv['_id'] != null && nv['_id'].toString().isNotEmpty) return nv['_id'].toString();
          if (nv['user'] is Map && nv['user']['_id'] != null) return nv['user']['_id'].toString();
        }
      }

      final topId = a['_id']?.toString();
      String? found;
      void search(dynamic node) {
        try {
          if (node == null) return;
          if (node is Map) {
            if (node['_id'] != null) {
              final cand = node['_id'].toString();
              if (cand.isNotEmpty && cand != topId) {
                found ??= cand;
                return;
              }
            }
            for (final v in node.values) {
              if (found != null) return;
              search(v);
            }
          } else if (node is List) {
            for (final e in node) {
              if (found != null) return;
              search(e);
            }
          }
        } catch (_) {}
      }

      search(a);
      final f = found;
      if (f != null && f.isNotEmpty) return f;
    } catch (_) {}
    return null;
  }

  Map<String, dynamic> _artisanWithUserId(Map<String, dynamic> a) {
    try {
      final copy = Map<String, dynamic>.from(a);
      if (copy['userId'] != null && copy['userId'].toString().isNotEmpty) return copy;
      final uid = _extractUserIdFromArtisan(a);
      if (uid != null && uid.isNotEmpty) copy['userId'] = uid;
      return copy;
    } catch (_) {
      return Map<String, dynamic>.from(a);
    }
  }

  void _searchNow() {
    _debounce?.cancel();
    _page = 1;
    _hasMore = true;
    _loadArtisans(next: false, showLoading: true);
  }

  Widget _skeletonCard() {
    final theme = Theme.of(context);
    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 120,
                    height: 16,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 80,
                    height: 12,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
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

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    final isQueryEmpty = _query.trim().isEmpty;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 80.0),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_search_rounded,
              size: 64,
              color: theme.colorScheme.primary.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              isQueryEmpty ? 'No artisans nearby' : 'No artisans found',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                isQueryEmpty
                    ? 'Try expanding your search radius or searching by trade/location.'
                    : 'No artisans found for "$_query". Try a different keyword.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: _increaseRadiusAndReload,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: theme.colorScheme.primary),
                  ),
                  child: Text(
                    'Expand Search',
                    style: TextStyle(color: theme.colorScheme.primary),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _onRefreshPressed,
                  child: const Text('Refresh'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool _isNestedNavBar = context.findAncestorWidgetOfExactType<NavBarPage>() != null;
    if (!_isNestedNavBar) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          NavigationUtils.safePushReplacement(
            context,
            NavBarPage(initialPage: 'DiscoverPage'),
          );
        } catch (_) {
          try {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => NavBarPage(initialPage: 'DiscoverPage'),
              ),
            );
          } catch (_) {}
        }
      });
    }

    final theme = Theme.of(context);
    final screenH = MediaQuery.of(context).size.height;
    final headerMax = screenH * 0.55;
    final headerMin = screenH * 0.20;
    final double extraBottom = MediaQuery.of(context).padding.bottom + kBottomNavigationBarHeight + 24.0;

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: RefreshIndicator(
        onRefresh: () => _loadArtisans(next: false, showLoading: true),
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: MapHeaderDelegate(
                maxExtentHeight: headerMax,
                minExtentHeight: headerMin,
                mapBuilder: (ctx) => _buildMap(),
                searchBuilder: (ctx) => _buildSearchBar(),
                featuresBuilder: _buildMapFeatures,
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Available Artisans',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onBackground,
                      ),
                    ),
                    if (_lastMessage != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _lastMessage!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_loading && _page == 1)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                      (_, __) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: _skeletonCard(),
                  ),
                  childCount: 4,
                ),
              )
            else if (_artisans.isEmpty)
              SliverFillRemaining(
                hasScrollBody: true,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: _buildEmptyState(),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                      (context, index) {
                    if (index >= _artisans.length) {
                      return _isLoadingMore
                          ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: _skeletonCard(),
                      )
                          : const SizedBox.shrink();
                    }
                    final item = _artisans[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: _artisanCard(item),
                    );
                  },
                  childCount: _artisans.length + (_hasMore ? 1 : 0),
                ),
              ),
            SliverToBoxAdapter(
              // Add extra bottom spacing to ensure last card isn't covered by the nav bar
              child: SizedBox(height: extraBottom),
            ),
          ],
        ),
      ),
    );
  }

  // Enhanced artisan card with better UI
  Widget _artisanCard(Map<String, dynamic> artisan) {
    final theme = Theme.of(context);
    final name = _displayName(artisan);
    final trades = _tradesList(artisan);
    final locationText = _locationText(artisan);
    final imgUrl = _profileImageUrl(artisan);
    final rating = _extractRating(artisan);

    return InkWell(
      onTap: () => _showArtisanProfile(artisan),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outline.withOpacity(0.1),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile image with rating badge
            Stack(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.primaryContainer.withOpacity(0.2),
                  ),
                  child: ClipOval(
                    child: imgUrl.isNotEmpty
                        ? Image.network(
                      imgUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Center(
                        child: Text(
                          _initialsFromName(name),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onPrimaryContainer,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    )
                        : Center(
                      child: Text(
                        _initialsFromName(name),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onPrimaryContainer,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ),
                ),
                // Rating star badge (moved to top-right to avoid overlap with KYC badge)
                if (rating != null && rating >= 4.0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.amber,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.colorScheme.surface,
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.star_rounded,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),

                // KYC verified badge (bottom-right)
                if (_isKycVerified(artisan))
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: theme.colorScheme.surface, width: 1.5),
                      ),
                      child: const Icon(
                        Icons.verified_rounded,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            // Artisan details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (rating != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 88),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.star_rounded,
                                  size: 16,
                                  color: Colors.amber.shade600,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      rating.toStringAsFixed(rating % 1 == 0 ? 0 : 1),
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: theme.colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (locationText.isNotEmpty)
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            locationText,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withOpacity(0.7),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  // Trades/chips
                  if (trades.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: trades.take(3).map((t) {
                        final label = _formatTradeLabel(t);
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            label,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w500,
                              color: theme.colorScheme.primary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // View button (no box shadow)
            ElevatedButton(
              onPressed: () async => await NavigationUtils.safePush(
                context,
                ArtisanDetailPageWidget(
                  artisan: _artisanWithUserId(artisan),
                  openHire: true,
                ),
              ),
              style: ElevatedButton.styleFrom(
                elevation: 0,
                shadowColor: Colors.transparent,
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              child: const Text('View'),
            ),
          ],
        ),
      ),
    );
  }

  // Enhanced map widget with theme adaptation
  Widget _buildMap() {
    final brightness = MediaQuery.of(context).platformBrightness;
    final theme = Theme.of(context);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _userCoords != null
            ? ll.LatLng(_userCoords![0], _userCoords![1])
            : ll.LatLng(DEFAULT_LAT, DEFAULT_LON),
        initialZoom: 13.0,
        onPositionChanged: (pos, _) {
          try {
            final center = pos.center;
            if (center == null) return;
            double lat = center.latitude;
            double lon = center.longitude;
            lat = lat.clamp(4.271, 13.892);
            lon = lon.clamp(2.676, 14.678);
            if (lat != center.latitude || lon != center.longitude) {
              _mapController.move(ll.LatLng(lat, lon), pos.zoom ?? 13.0);
            }
          } catch (_) {}
        },
      ),
      children: [
        // Map tiles with theme adaptation
        if (MAPBOX_ACCESS_TOKEN.isNotEmpty)
          TileLayer(
            urlTemplate: 'https://api.mapbox.com/styles/v1/${brightness == Brightness.dark ? 'mapbox/dark-v10' : 'mapbox/streets-v11'}/tiles/256/{z}/{x}/{y}?access_token=$MAPBOX_ACCESS_TOKEN',
            additionalOptions: const {'accessToken': MAPBOX_ACCESS_TOKEN},
            tileSize: 256,
            maxNativeZoom: 19,
            maxZoom: 19,
          )
        else if (brightness == Brightness.dark)
          TileLayer(
            urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
            subdomains: const ['a', 'b', 'c'],
            userAgentPackageName: 'com.example.app',
            tileSize: 256,
            maxNativeZoom: 19,
            maxZoom: 19,
          )
        else
          TileLayer(
            urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
            subdomains: const ['a', 'b', 'c'],
            userAgentPackageName: 'com.example.app',
            tileSize: 256,
            maxNativeZoom: 19,
            maxZoom: 19,
          ),

        // Markers
        if (_showArtisanMarkers)
          MarkerLayer(
            markers: [
              if (_userCoords != null && _showUserLocation)
                Marker(
                  width: 42,
                  height: 42,
                  point: ll.LatLng(_userCoords![0], _userCoords![1]),
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.colorScheme.onPrimary,
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.onSurface.withOpacity(0.3),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(
                        Icons.person_pin_circle_rounded,
                        size: 20,
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ),
              ..._artisans.map((a) {
                final latlon = _extractLatLon(a);
                if (latlon == null) return Marker(
                  width: 0,
                  height: 0,
                  point: ll.LatLng(0, 0),
                  child: const SizedBox.shrink(),
                );
                return Marker(
                  width: 48,
                  height: 48,
                  point: latlon,
                  child: _buildMarker(a),
                );
              }).where((m) => m.point.latitude != 0 || m.point.longitude != 0).toList(),
            ],
          ),

        // Zoom indicator (replaces removed ScaleLayer)
        Positioned(
          left: 8,
          bottom: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withOpacity(0.9),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Zoom: ${_mapZoom.toStringAsFixed(1)}',
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 12, color: theme.colorScheme.onSurface),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    final theme = Theme.of(context);
    final brightness = MediaQuery.of(context).platformBrightness;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.onSurface.withOpacity(brightness == Brightness.dark ? 0.3 : 0.1),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextFormField(
        controller: _searchController,
        focusNode: _searchFocus,
        onTap: () {
          _searchFocus.requestFocus();
        },
        onChanged: (v) {
          _query = v;
          _debounce?.cancel();
          _debounce = Timer(
            const Duration(milliseconds: 400),
                () => _searchNow(),
          );
        },
        onFieldSubmitted: (v) {
          _query = v;
          _searchNow();
          _searchFocus.unfocus();
        },
        style: TextStyle(
          color: theme.colorScheme.onSurface,
        ),
        decoration: InputDecoration(
          hintText: 'Search artisans by trade or location...',
          hintStyle: TextStyle(
            color: theme.colorScheme.onSurface.withOpacity(0.5),
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: theme.colorScheme.onSurface.withOpacity(0.7),
          ),
          border: InputBorder.none,
          filled: true,
          fillColor: theme.colorScheme.surface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          suffixIcon: _query.isNotEmpty
              ? GestureDetector(
            onTap: () {
              _searchController.clear();
              _query = '';
              _searchNow();
            },
            child: Icon(
              Icons.clear_rounded,
              color: theme.colorScheme.onSurface.withOpacity(0.5),
            ),
          )
              : null,
        ),
      ),
    );
  }

  // Helper methods
  String _displayName(Map<String, dynamic> a) {
    final candidates = [
      'name',
      'fullName',
      'full_name',
      'displayName',
      'display_name',
      'firstName',
      'first_name',
      'lastName',
      'last_name',
      'username',
      'user_name'
    ];

    for (final k in candidates) {
      if (a[k] != null && a[k].toString().trim().isNotEmpty) return a[k].toString();
    }

    final first = (a['firstName'] ?? a['first_name'] ?? a['firstname'])?.toString();
    final last = (a['lastName'] ?? a['last_name'] ?? a['lastname'])?.toString();
    if ((first?.trim().isNotEmpty ?? false) || (last?.trim().isNotEmpty ?? false)) {
      return '${first ?? ''} ${last ?? ''}'.trim();
    }

    if (a['user'] is Map) {
      final u = Map<String, dynamic>.from(a['user']);
      for (final k in candidates) {
        if (u[k] != null && u[k].toString().trim().isNotEmpty) return u[k].toString();
      }
      final uf = (u['firstName'] ?? u['first_name'] ?? u['firstname'])?.toString();
      final ul = (u['lastName'] ?? u['last_name'] ?? u['lastname'])?.toString();
      if ((uf?.trim().isNotEmpty ?? false) || (ul?.trim().isNotEmpty ?? false)) {
        return '${uf ?? ''} ${ul ?? ''}'.trim();
      }
    }
    if (a['profile'] is Map) {
      final p = Map<String, dynamic>.from(a['profile']);
      for (final k in candidates) {
        if (p[k] != null && p[k].toString().trim().isNotEmpty) return p[k].toString();
      }
    }

    return 'Unknown Artisan';
  }

  List<String> _tradesList(Map<String, dynamic> a) {
    final t = a['trade'] ?? a['trades'] ?? a['skills'] ?? a['categories'];
    if (t is List) return t.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
    if (t is String) {
      final parts = t.split(RegExp(r'[;,\|]')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      if (parts.isNotEmpty) return parts;
    }
    if (a['profile'] is Map && a['profile']['trade'] != null) {
      return _tradesList(Map<String, dynamic>.from({'trade': a['profile']['trade']}));
    }
    return <String>[];
  }

  // Safe formatting for trade labels (handles JSON list strings)
  String _formatTradeLabel(dynamic t) {
    try {
      final label = t?.toString() ?? '';
      final trimmed = label.trim();
      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        final parsed = jsonDecode(trimmed);
        if (parsed is List) {
          return parsed.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).join(', ');
        }
      }
      return label;
    } catch (_) {
      try {
        final s = t?.toString() ?? '';
        if (s.startsWith('[') && s.endsWith(']')) return s.substring(1, s.length - 1);
        return s;
      } catch (_) {
        return t?.toString() ?? '';
      }
    }
  }

  String _locationText(Map<String, dynamic> a) {
    final locKeys = [
      'location',
      'locationText',
      'location_text',
      'city',
      'city_name',
      'town',
      'address',
      'area',
      'locality'
    ];
    for (final k in locKeys) {
      final v = a[k];
      if (v is String && v.isNotEmpty) return v;
    }

    final locObj = a['location'] ?? a['address'] ?? a['profile']?['location'] ?? a['profile']?['address'];
    if (locObj is Map) {
      final city = locObj['city'] ?? locObj['town'] ?? locObj['locality'] ?? locObj['name'] ?? locObj['area'];
      final state = locObj['state'] ?? locObj['region'] ?? locObj['state_name'];
      if (city != null && state != null) return '$city, $state';
      if (city != null) return city.toString();
      if (locObj['address'] != null) return locObj['address'].toString();
    }

    if (a['city'] != null) return a['city'].toString();
    if (a['state'] != null) return a['state'].toString();
    if (a['area'] != null) return a['area'].toString();
    return '';
  }

  double? _extractRating(Map<String, dynamic> a) {
    try {
      final candidates = [
        'rating',
        'ratings',
        'avgRating',
        'averageRating',
        'ratingAverage',
        'ratingValue',
        'score',
        'rating_count'
      ];
      for (final k in candidates) {
        final v = a[k];
        if (v is num) return v.toDouble();
        if (v is String && v.isNotEmpty) {
          final parsed = double.tryParse(v);
          if (parsed != null) return parsed;
        }
      }
      if (a['stats'] is Map && a['stats']['rating'] != null) {
        final v = a['stats']['rating'];
        if (v is num) return v.toDouble();
      }
      if (a['profile'] is Map) {
        final p = a['profile'] as Map<String, dynamic>;
        for (final k in candidates) {
          final v = p[k];
          if (v is num) return v.toDouble();
          if (v is String) {
            final parsed = double.tryParse(v);
            if (parsed != null) return parsed;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  // Heuristic to determine if an artisan is KYC verified
  bool _isKycVerified(Map<String, dynamic> a) {
    try {
      final candidates = [
        'kycVerified',
        'kyc_verified',
        'isKycVerified',
        'is_verified',
        'verified',
        'isVerified',
        'kycStatus',
        'kyc_status'
      ];

      for (final k in candidates) {
        final v = a[k];
        if (v == null) continue;
        if (v is bool && v) return true;
        if (v is num && v > 0) return true;
        if (v is String) {
          final lv = v.toLowerCase();
          if (lv == 'true' || lv == 'verified' || lv == 'yes' || lv == '1') return true;
        }
      }

      if (a['profile'] is Map) {
        return _isKycVerified(Map<String, dynamic>.from(a['profile']));
      }
    } catch (_) {}
    return false;
  }

  Future<void> _showArtisanProfile(Map<String, dynamic> artisan) async {
    try {
      await NavigationUtils.safePush(
        context,
        ArtisanDetailPageWidget(
          artisan: _artisanWithUserId(artisan),
          openHire: true,
        ),
      );
    } catch (_) {}
  }

  void _increaseRadiusAndReload() {
    _loadArtisans(next: false, showLoading: true);
  }

  Future<void> _onRefreshPressed() async {
    await _loadArtisans(next: false, showLoading: true);
  }
}

class MapHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double maxExtentHeight;
  final double minExtentHeight;
  final WidgetBuilder mapBuilder;
  final WidgetBuilder searchBuilder;
  final WidgetBuilder? featuresBuilder;

  MapHeaderDelegate({
    required this.maxExtentHeight,
    required this.minExtentHeight,
    required this.mapBuilder,
    required this.searchBuilder,
    this.featuresBuilder,
  });

  @override
  double get minExtent => minExtentHeight;

  @override
  double get maxExtent => maxExtentHeight;

  @override
  bool shouldRebuild(covariant MapHeaderDelegate oldDelegate) {
    return oldDelegate.maxExtentHeight != maxExtentHeight ||
        oldDelegate.minExtentHeight != minExtentHeight;
  }

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final t = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    final theme = Theme.of(context);
    final overlayEnd = theme.colorScheme.onSurface.withOpacity(0.08 * t);

    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Map
          mapBuilder(context),

          // Gradient overlay
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    overlayEnd,
                  ],
                  stops: const [0.0, 0.3],
                ),
              ),
            ),
          ),

          // Search bar
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 20,
            right: 20,
            child: searchBuilder(context),
          ),

          // Map features (buttons)
          if (featuresBuilder != null)
            Positioned(
              right: 12,
              bottom: 12 + (shrinkOffset * 0.5), // Moves up slightly as header collapses
              child: featuresBuilder!(context),
            ),
        ],
      ),
    );
  }
}
