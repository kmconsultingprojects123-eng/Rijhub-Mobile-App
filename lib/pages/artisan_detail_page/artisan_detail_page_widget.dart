import 'dart:convert';
import 'package:flutter/material.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../../api_config.dart';
import '../../services/token_storage.dart';
import '../../services/user_service.dart';
import '../../services/artist_service.dart';
import '../../services/my_service_service.dart';
import '../../pages/payment_init/payment_init_page_widget.dart';
import '../../utils/app_notification.dart';
import '../../utils/auth_guard.dart';

class ArtisanDetailPageWidget extends StatefulWidget {
  const ArtisanDetailPageWidget(
      {super.key, required this.artisan, this.openHire = false});

  final Map<String, dynamic> artisan;
  final bool openHire;

  static String routeName = 'ArtisanDetailPage';
  static String routePath = '/artisanDetailPage';

  @override
  State<ArtisanDetailPageWidget> createState() =>
      _ArtisanDetailPageWidgetState();
}

class _ArtisanDetailPageWidgetState extends State<ArtisanDetailPageWidget> {
  // Constants
  static const Color _defaultPrimaryColor = Color(0xFFA20025);
  static const Duration _timeout = Duration(seconds: 12);
  static const int _maxPreviewReviews = 10;

  // Color helpers
  Color get primaryColor =>
      FlutterFlowTheme.of(context).primary ?? _defaultPrimaryColor;

  // State
  Map<String, dynamic>? _artisanData;
  bool _loading = false;
  String? _errorMessage;

  // Reviews state
  List<Map<String, dynamic>> _reviews = [];
  bool _loadingReviews = false;
  double? _averageRating;
  int _reviewCount = 0;
  final Map<String, String> _userNameCache = {}; // userId -> display name

  String? _authToken; // cached token

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final widgetUserId = _widgetUserId();
      final id = _artisanIdFromWidget();
      // If the provided widget.artisan payload doesn't include a top-level name, attempt
      // to extract and apply any nested user name quickly so the UI shows a name immediately.
      try {
        final m = _coerceToMap(widget.artisan);
        if (m != null) {
          final explicit = (m['name'] ?? m['fullName'] ?? m['displayName']);
          if (!(explicit?.toString().trim().isNotEmpty ?? false)) {
            // No explicit name in provided payload -> try to extract nested user name or prefetch.
            try {
              _fetchReferencedUserName(Map<String, dynamic>.from(m));
            } catch (_) {}
          }
        }
      } catch (_) {}

      _unawaited(_initializePage(id, widgetUserId: widgetUserId));
    });
  }

  @override
  void dispose() {
    // Clean up any pending operations
    super.dispose();
  }

  // MARK: - Initialization
  Future<void> _initializePage(String? id, {String? widgetUserId}) async {
    try {
      _authToken = await TokenStorage.getToken();
    } catch (_) {
      _authToken = null;
    }

    if (id?.isNotEmpty ?? false) {
      bool looksLikeArtisanId = false;
      try {
        final wa = widget.artisan;
        if (wa is Map) {
          if (wa.containsKey('_id') ||
              wa.containsKey('id') ||
              wa.containsKey('artisanId')) {
            looksLikeArtisanId = true;
          }
        }
      } catch (_) {}

      if (looksLikeArtisanId) {
        _unawaited(_fetchArtisanById(id!, token: _authToken));
      }

      final resolvedForReviews = (widgetUserId?.isNotEmpty ?? false)
          ? widgetUserId
          : (_resolvedArtisanId() ?? id!);
      _unawaited(Future.delayed(
          const Duration(milliseconds: 400),
          () =>
              _loadReviewsForArtisan(resolvedForReviews!, token: _authToken)));
    }
  }

  String? _widgetUserId() {
    try {
      final wa = widget.artisan;
      if (wa is Map) {
        final uid = (wa['userId'] ?? wa['user_id'])?.toString();
        if (uid?.isNotEmpty ?? false) return uid;

        if (wa['user'] is Map) {
          final u = wa['user'] as Map<String, dynamic>;
          final nu = (u['_id'] ?? u['id'])?.toString();
          if (nu?.isNotEmpty ?? false) return nu;
        }
      }
    } catch (_) {}
    return null;
  }

  Map<String, dynamic> get _artisan => _artisanData ?? widget.artisan;

  String? _artisanIdFromWidget() {
    try {
      final m = _coerceToMap(widget.artisan);
      if (m == null) return null;

      final candidates = ['_id', 'id', 'artisanId', 'userId'];
      for (final k in candidates) {
        if (m.containsKey(k) && m[k] != null) return m[k].toString();
      }

      final nested = _findUserReferenceId(widget.artisan);
      if (nested?.isNotEmpty ?? false) return nested;
    } catch (_) {}
    return null;
  }

  // MARK: - Data Fetching
  Future<void> _fetchArtisanById(String id, {String? token}) async {
    token ??= _authToken;
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final base = _normalizeBaseUrl(API_BASE_URL);
      final uri = Uri.parse('$base/api/artisans/$id');
      final headers = <String, String>{'Accept': 'application/json'};
      if (token?.isNotEmpty ?? false) {
        headers['Authorization'] = 'Bearer $token';
      }

      final resp = await http.get(uri, headers: headers).timeout(_timeout);

      if (resp.statusCode == 200) {
        final body = _safeParseJson(resp.body);
        if (body is Map &&
            (body['success'] == true || body.containsKey('data'))) {
          final data = body['data'] ?? body;
          if (data is Map) {
            if (!mounted) return;
            setState(() {
              _artisanData =
                  Map<String, dynamic>.from(data.cast<String, dynamic>());
            });

            // Ensure we pass a Map<String, dynamic> (decoded JSON may be Map<dynamic,dynamic>)
            _fetchReferencedUserName(
                Map<String, dynamic>.from(data.cast<String, dynamic>()),
                token: token);
            return;
          }
        }

        if (_artisanData == null) {
          setState(() => _errorMessage = 'Unable to load artisan details.');
          debugPrint(
              'Artisan fetch unexpected response: ${resp.statusCode} ${resp.body}');
        } else {
          // We already have data to display; don't overwrite UI with an error banner.
          debugPrint(
              'Artisan fetch unexpected response (kept existing data): ${resp.statusCode} ${resp.body}');
        }
      } else {
        _handleFetchError(resp);
      }
    } on TimeoutException {
      if (_artisanData == null) {
        setState(() =>
            _errorMessage = 'Network timeout while loading artisan details.');
      } else {
        debugPrint(
            'Network timeout while refreshing artisan details (kept existing data)');
      }
    } catch (e, st) {
      debugPrint('Error fetching artisan: $e\n$st');
      if (_artisanData == null) {
        setState(() => _errorMessage =
            'An unexpected error occurred while loading artisan details.');
      } else {
        // Keep existing UI; log the failure for diagnostics.
        debugPrint(
            'Unexpected error while refreshing artisan (kept existing data)');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _handleFetchError(http.Response resp) {
    String msg = 'Failed to load artisan (code ${resp.statusCode}).';
    try {
      final body = jsonDecode(resp.body);
      if (body is Map && body['message'] != null) {
        msg = body['message'].toString();
      }
    } catch (_) {}
    if (_artisanData == null) {
      setState(() => _errorMessage = msg);
    } else {
      debugPrint('Fetch error while keeping existing data: $msg');
    }
  }

  void _fetchReferencedUserName(Map<String, dynamic> data, {String? token}) {
    try {
      String? refUserId;
      final artMap = Map<String, dynamic>.from(data.cast<String, dynamic>());
      final refCandidates = ['user', 'userId', 'owner', 'createdBy'];

      // Helper to extract id from a Map using common id keys
      String? _extractIdFromMap(Map m) {
        try {
          for (final k in ['_id', 'id', 'userId', 'user_id', 'uid']) {
            if (m.containsKey(k) && m[k] != null) return m[k].toString();
          }
        } catch (_) {}
        return null;
      }

      // Helper to build a display name from a nested user map
      String? _buildNameFromMap(Map m) {
        try {
          // Direct name fields
          final direct = (m['name'] ??
              m['fullName'] ??
              m['displayName'] ??
              m['username'] ??
              m['nameFull']);
          if (direct != null && direct.toString().trim().isNotEmpty)
            return direct.toString().trim();

          // first + last variants
          final first = (m['firstName'] ??
              m['firstname'] ??
              m['first_name'] ??
              m['givenName']);
          final last = (m['lastName'] ??
              m['lastname'] ??
              m['last_name'] ??
              m['familyName']);
          if (first != null || last != null) {
            final f = first?.toString().trim() ?? '';
            final l = last?.toString().trim() ?? '';
            final combined = ('$f ${l}'.trim());
            if (combined.isNotEmpty) return combined;
          }

          // nested profile/details maps
          for (final k in ['profile', 'details', 'personal', 'contact']) {
            final nested = m[k];
            if (nested is Map) {
              final nm = _buildNameFromMap(nested);
              if (nm != null && nm.trim().isNotEmpty) return nm;
            }
          }

          // fallback to email local-part or phone
          final email = m['email'] ?? m['emailAddress'];
          if (email != null && email.toString().contains('@')) {
            final local = email.toString().split('@').first;
            if (local.trim().isNotEmpty) return local.trim();
          }

          final phone = m['phone'] ?? m['telephone'] ?? m['phoneNumber'];
          if (phone != null && phone.toString().trim().isNotEmpty)
            return phone.toString().trim();
        } catch (_) {}
        return null;
      }

      for (final k in refCandidates) {
        final v = artMap[k];
        if (v == null) continue;

        // If the reference is already a nested object with a readable name, use it.
        if (v is Map) {
          final possibleName = _buildNameFromMap(v) ??
              (v['name'] ?? v['fullName'] ?? v['displayName'])?.toString();
          if (possibleName != null && possibleName.trim().isNotEmpty) {
            // Determine a stable id to cache under: prefer nested id, else try to find any user ref id
            final nestedIdForCache =
                _extractIdFromMap(v) ?? _findUserReferenceId(artMap) ?? k;
            if (mounted) {
              setState(() {
                _userNameCache[nestedIdForCache] = possibleName.trim();
                // If we haven't loaded the full artisan data yet, materialize a lightweight map from the widget payload
                // so the UI shows the name immediately.
                if (_artisanData == null) {
                  try {
                    final baseWidgetMap = _coerceToMap(widget.artisan) ??
                        Map<String, dynamic>.from(artMap);
                    _artisanData = Map<String, dynamic>.from(baseWidgetMap);
                  } catch (_) {
                    _artisanData = Map<String, dynamic>.from(artMap);
                  }
                }
                if (_artisanData != null &&
                    (_artisanData!['name'] == null ||
                        _artisanData!['name'].toString().trim().isEmpty)) {
                  _artisanData!['name'] = possibleName.trim();
                }
              });
            }
            return; // we found a name in the payload; no need to network fetch
          }

          // Otherwise try to get an id from nested map
          final nestedId = _extractIdFromMap(v);
          if (nestedId != null && nestedId.isNotEmpty) {
            refUserId = nestedId;
            break;
          }
        }

        if (v is String && v.isNotEmpty) {
          refUserId = v;
          break;
        }
      }

      if (refUserId?.isNotEmpty ?? false) {
        final resolvedId = refUserId!;
        _unawaited(_fetchUserById(resolvedId, token: token).then((name) {
          try {
            if (name?.isNotEmpty ?? false) {
              if (!mounted) return;
              setState(() {
                _userNameCache[resolvedId] = name!;
                if (_artisanData != null &&
                    (_artisanData!['name'] == null ||
                        _artisanData!['name'].toString().trim().isEmpty)) {
                  _artisanData!['name'] = name;
                }
              });
            }
          } catch (_) {}
        }).catchError((_) {}));
      }
    } catch (_) {}
  }

  Future<void> _loadReviewsForArtisan(String artisanId, {String? token}) async {
    token ??= _authToken;
    if (artisanId.isEmpty) return;

    setState(() {
      _loadingReviews = true;
      _reviews = [];
      _averageRating = null;
      _reviewCount = 0;
    });

    try {
      final fetched = await ArtistService.fetchReviewsForArtisan(artisanId,
          page: 1, limit: _maxPreviewReviews);

      if (!mounted) return;

      setState(() {
        _reviews = fetched;
        _reviewCount = fetched.length;
      });

      _prefetchReviewerNames(fetched, token: token);
      _calculateAverageRating(fetched);
    } catch (e) {
      debugPrint('Failed to load reviews: $e');
    } finally {
      if (mounted) setState(() => _loadingReviews = false);
    }
  }

  void _prefetchReviewerNames(List<Map<String, dynamic>> reviews,
      {String? token}) {
    try {
      final ids = <String>{};
      int prefetchCount = 0;

      for (final r in reviews) {
        final reviewerId = r['customerId'] ??
            r['userId'] ??
            r['customer'] ??
            r['authorId'] ??
            r['author'];
        if (reviewerId == null) continue;

        final idStr = reviewerId is String
            ? reviewerId
            : (reviewerId is Map && reviewerId['_id'] != null
                ? reviewerId['_id'].toString()
                : reviewerId.toString());

        if (idStr.isNotEmpty &&
            !_userNameCache.containsKey(idStr) &&
            prefetchCount < 10) {
          ids.add(idStr);
          prefetchCount++;
        }
      }

      final futures = ids.map((id) => _fetchUserById(id, token: token));
      _unawaited(Future.wait(futures).then((results) {
        if (!mounted) return;
        final updates = <String, String>{};
        int i = 0;
        for (final id in ids) {
          final name = results.elementAt(i++);
          if (name?.isNotEmpty ?? false) {
            updates[id] = name!;
          }
        }
        if (updates.isNotEmpty) {
          setState(() => _userNameCache.addAll(updates));
        }
      }));
    } catch (e) {
      debugPrint('prefetch reviewer names failed: $e');
    }
  }

  void _calculateAverageRating(List<Map<String, dynamic>> reviews) {
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

    if (cnt > 0 && mounted) {
      setState(() => _averageRating = (sum / cnt).clamp(0.0, 5.0));
    }
  }

  Future<String?> _fetchUserById(String id, {String? token}) async {
    if (id.isEmpty) return null;
    token ??= _authToken;

    try {
      final base = _normalizeBaseUrl(API_BASE_URL);
      final uri = Uri.parse('$base/api/users/$id');
      final headers = <String, String>{'Accept': 'application/json'};
      if (token?.isNotEmpty ?? false) {
        headers['Authorization'] = 'Bearer $token';
      }

      final resp = await http.get(uri, headers: headers).timeout(_timeout);

      if (resp.statusCode >= 200 &&
          resp.statusCode < 300 &&
          resp.body.isNotEmpty) {
        final body = _safeParseJson(resp.body);
        Map<String, dynamic>? data;
        if (body is Map && body['data'] is Map) {
          data = Map<String, dynamic>.from(body['data']);
        } else if (body is Map) {
          data = Map<String, dynamic>.from(body);
        }

        if (data != null) {
          final name = (data['name'] ??
                  data['fullName'] ??
                  data['displayName'] ??
                  data['username'])
              ?.toString();
          if (name?.trim().isNotEmpty ?? false) return name!.trim();
        }
      }
    } catch (e) {
      debugPrint('fetchUserById error: $e');
    }
    return null;
  }

  void _unawaited(Future<dynamic> f) {
    try {
      f.catchError((_) {});
    } catch (_) {}
  }

  // MARK: - Helper Methods
  String? _findUserReferenceId(dynamic node) {
    try {
      if (node == null) return null;
      if (node is Map) {
        for (final k in [
          '_id',
          'id',
          'userId',
          'user_id',
          'owner',
          'customerId',
          'customer_id'
        ]) {
          if (node[k] != null) {
            final v = node[k];
            if (v is String && v.isNotEmpty) return v;
            if (v is Map && v['_id'] != null) return v['_id'].toString();
          }
        }

        for (final k in [
          'user',
          'userInfo',
          'artisanUser',
          'owner',
          'createdBy',
          'customer'
        ]) {
          if (node[k] != null) {
            final v = node[k];
            if (v is String && v.isNotEmpty) return v;
            if (v is Map && v['_id'] != null) return v['_id'].toString();
          }
        }

        for (final v in node.values) {
          final found = _findUserReferenceId(v);
          if (found?.isNotEmpty ?? false) return found;
        }
      } else if (node is List) {
        for (final e in node) {
          final found = _findUserReferenceId(e);
          if (found?.isNotEmpty ?? false) return found;
        }
      }
    } catch (e) {
      debugPrint('findUserReferenceId error: $e');
    }
    return null;
  }

  // Returns true when we have any effective artisan data to show: either fetched _artisanData or a rich widget payload.
  bool _hasEffectiveArtisan() {
    try {
      if (_artisanData != null) return true;
      if (_isWidgetPayloadRich(widget.artisan)) return true;
    } catch (_) {}
    return false;
  }

  String _extractName(Map<String, dynamic> src) {
    try {
      final top = src['name'];
      if (top?.toString().trim().isNotEmpty ?? false) {
        return top.toString().trim();
      }

      final authKeys = [
        'artisanAuthDetails',
        'artisanAuthdDetails',
        'artisanAuthdetails',
        'artisan_auth_details'
      ];
      for (final k in authKeys) {
        final a = src[k];
        if (a is Map && a['name']?.toString().trim().isNotEmpty == true) {
          return a['name'].toString().trim();
        }
      }

      final possibleKeys = [
        'user',
        'userId',
        'owner',
        'artisan',
        'artisanUser'
      ];
      for (final k in possibleKeys) {
        final p = src[k];
        if (p is Map && p['name']?.toString().trim().isNotEmpty == true) {
          return p['name'].toString().trim();
        }
      }

      final id = _findUserReferenceId(src);
      if (id?.isNotEmpty ?? false) {
        if (_userNameCache.containsKey(id)) return _userNameCache[id]!;
        _unawaited(_fetchUserById(id!).then((n) {
          if (n?.isNotEmpty ?? false && mounted) {
            setState(() => _userNameCache[id!] = n!);
          }
        }));
        return 'Loading...';
      }
    } catch (_) {}
    return 'Unknown';
  }

  String? _extractProfileImage(Map<String, dynamic> src) {
    try {
      final directKeys = [
        'profilePicture',
        'profileImage',
        'avatar',
        'photo',
        'image'
      ];
      for (final k in directKeys) {
        final url = _toAbsoluteImageUrl(src[k]);
        if (url != null) return url;
      }

      if (src['user'] is Map) {
        final user = src['user'];
        for (final k in directKeys) {
          final url = _toAbsoluteImageUrl(user[k]);
          if (url != null) return url;
        }
      }

      if (src['profileImage'] is Map) {
        final profileImage = src['profileImage'];
        for (final k in ['url', 'src', 'path', 'imageUrl']) {
          final url = _toAbsoluteImageUrl(profileImage[k]);
          if (url != null) return url;
        }
      }

      if (src['portfolio'] is List && (src['portfolio'] as List).isNotEmpty) {
        final firstPortfolio = src['portfolio'][0];
        if (firstPortfolio is Map &&
            firstPortfolio['images'] is List &&
            (firstPortfolio['images'] as List).isNotEmpty) {
          final firstImage = (firstPortfolio['images'] as List)[0];
          return _toAbsoluteImageUrl(firstImage);
        }
      }
    } catch (e) {
      debugPrint('Error extracting profile image: $e');
    }
    return null;
  }

  String _displayLocation() {
    final src = _artisan;
    try {
      for (final k in [
        'location',
        'city',
        'town',
        'address',
        'state',
        'lga',
        'area',
        'region',
        'country'
      ]) {
        final v = src[k];
        if (v != null) {
          final s = v.toString().trim();
          if (s.isNotEmpty) return s;
        }
      }

      if (src['user'] is Map) {
        final u = src['user'] as Map<String, dynamic>;
        for (final k in [
          'location',
          'city',
          'address',
          'state',
          'area',
          'region'
        ]) {
          final v = u[k];
          if (v?.toString().trim().isNotEmpty == true) {
            return v.toString().trim();
          }
        }

        if (u['address'] is Map) {
          final a = u['address'] as Map<String, dynamic>;
          final parts = <String>[];
          for (final k in ['city', 'town', 'state', 'lga', 'area', 'country']) {
            final v = a[k];
            if (v?.toString().trim().isNotEmpty == true) {
              parts.add(v.toString().trim());
            }
          }
          if (parts.isNotEmpty) return parts.join(', ');
        }
      }

      final possible =
          _findKey(src, ['location', 'address', 'city', 'state', 'area']);
      if (possible != null) {
        if (possible is String) {
          final s = possible.trim();
          if (s.isNotEmpty) return s;
        } else if (possible is Map) {
          final parts = <String>[];
          for (final k in [
            'city',
            'town',
            'state',
            'lga',
            'area',
            'country',
            'address'
          ]) {
            final v = possible[k];
            if (v?.toString().trim().isNotEmpty == true) {
              parts.add(v.toString().trim());
            }
          }
          if (parts.isNotEmpty) return parts.join(', ');
        } else if (possible is List && possible.isNotEmpty) {
          final first = possible[0];
          if (first?.toString().trim().isNotEmpty == true) {
            return first.toString().trim();
          }
        }
      }
    } catch (e) {
      debugPrint('displayLocation error: $e');
    }
    return 'Not specified';
  }

  dynamic _findKey(dynamic node, List<String> keys) {
    try {
      if (node == null) return null;
      if (node is Map) {
        for (final k in keys) {
          if (node.containsKey(k) && node[k] != null) return node[k];
        }
        for (final v in node.values) {
          final f = _findKey(v, keys);
          if (f != null) return f;
        }
      } else if (node is List) {
        for (final e in node) {
          final f = _findKey(e, keys);
          if (f != null) return f;
        }
      }
    } catch (_) {}
    return null;
  }

  Map<String, dynamic>? _coerceToMap(dynamic v) {
    try {
      if (v == null) return null;
      if (v is Map) return Map<String, dynamic>.from(v.cast<String, dynamic>());
    } catch (_) {}
    return null;
  }

  // MARK: - UI Helpers
  Color _surfaceColor() => Theme.of(context).colorScheme.surface;
  Color _borderColor() => Theme.of(context).dividerColor;
  Color _textColor([double opacity = 1.0]) =>
      Theme.of(context).colorScheme.onSurface.withOpacity(opacity);
  Color _secondaryTextColor() =>
      Theme.of(context).colorScheme.onSurface.withOpacity(0.7);

  bool get _isVerified {
    try {
      final src = _artisan;
      bool check(dynamic v) {
        if (v == null) return false;
        if (v is bool) return v;
        if (v is num) return v == 1 || v == 1.0;
        final s = v.toString().toLowerCase();
        return s == 'true' ||
            s == 'verified' ||
            s == 'kyc_verified' ||
            s == 'kyc' ||
            s == 'complete' ||
            s == 'completed' ||
            s == 'approved' ||
            s == 'active';
      }

      final keys = [
        'isVerified',
        'verified',
        'kycVerified',
        'kyc_verified',
        'kycStatus',
        'verificationStatus',
        'is_kyc_verified',
        'isKycVerified',
        'status'
      ];

      for (final k in keys) {
        if (src.containsKey(k) && check(src[k])) return true;
      }

      if (src['user'] is Map) {
        final u = src['user'] as Map<String, dynamic>;
        for (final k in keys) {
          if (u.containsKey(k) && check(u[k])) return true;
        }

        final ver = u['verification'] ?? u['kyc'] ?? u['verificationStatus'];
        if (ver is Map) {
          final v = ver['status'] ?? ver['verified'] ?? ver['isVerified'];
          if (check(v)) return true;
        }
      }
    } catch (e) {
      debugPrint('isVerified check error: $e');
    }
    return false;
  }

  String? _getTrade() {
    try {
      final src = _artisan;
      final keys = [
        'trade',
        'profession',
        'speciality',
        'specialty',
        'skill',
        'skills',
        'occupation',
        'title',
        'category'
      ];

      for (final k in keys) {
        if (src[k] != null) {
          final v = src[k];
          if (v is String && v.trim().isNotEmpty) return v.trim();
          if (v is List && v.isNotEmpty) return v[0].toString().trim();
        }
      }

      if (src['user'] is Map) {
        final u = src['user'] as Map<String, dynamic>;
        for (final k in keys) {
          if (u[k] != null) {
            final v = u[k];
            if (v is String && v.trim().isNotEmpty) return v.trim();
            if (v is List && v.isNotEmpty) return v[0].toString().trim();
          }
        }

        final nested = u['profile'] ?? u['details'];
        if (nested is Map) {
          for (final k in keys) {
            if (nested[k] != null) {
              final v = nested[k];
              if (v is String && v.trim().isNotEmpty) return v.trim();
              if (v is List && v.isNotEmpty) return v[0].toString().trim();
            }
          }
        }
      }
    } catch (e) {
      debugPrint('getTrade error: $e');
    }
    return null;
  }

  String? _resolvedArtisanId() {
    try {
      final src = _artisanData ?? widget.artisan;
      if (src is Map) {
        if (src['userId']?.toString().isNotEmpty == true)
          return src['userId'].toString();
        if (src['user'] is Map) {
          final u = src['user'] as Map<String, dynamic>;
          if ((u['_id'] ?? u['id']) != null)
            return (u['_id'] ?? u['id']).toString();
        }
        for (final k in ['_id', 'id', 'artisanId', 'customerId']) {
          if (src.containsKey(k) && src[k] != null) return src[k].toString();
        }
      }
      final nested = _findUserReferenceId(widget.artisan);
      if (nested?.isNotEmpty ?? false) return nested;
    } catch (_) {}
    return null;
  }

  String _displayName() {
    final src = _artisan;
    try {
      final explicit = (src['name'] ?? src['fullName'] ?? src['displayName']);
      if (explicit?.toString().trim().isNotEmpty == true) {
        return explicit.toString().trim();
      }

      final refId = _findUserReferenceId(src);
      if (refId?.isNotEmpty ?? false) {
        if (_userNameCache.containsKey(refId)) return _userNameCache[refId]!;
        _unawaited(_fetchUserById(refId!).then((n) {
          if (n?.isNotEmpty ?? false && mounted) {
            setState(() => _userNameCache[refId!] = n!);
          }
        }));
        return 'Loading...';
      }
    } catch (_) {}
    return _extractName(src);
  }

  // MARK: - UI Build Methods
  Widget _buildInfoItem(dynamic icon, String title, String value) {
    final theme = FlutterFlowTheme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: _surfaceColor(),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor(), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: (icon is IconData)
                ? Icon(icon, size: 20, color: primaryColor)
                : Center(child: icon as Widget),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style:
                        theme.bodySmall.copyWith(color: theme.secondaryText)),
                const SizedBox(height: 4),
                Text(value,
                    style:
                        theme.bodyMedium.copyWith(fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // MARK: - Enhanced Hire Sheet with Improved Styling
  Future<Map<String, dynamic>?> _showHireSheet_impl(BuildContext ctx) async {
    final artisan = _artisan;
    final TextEditingController _scheduleCtrl = TextEditingController();

    try {
      // Ensure we have fresh artisan data
      await _loadArtisanDataIfNeeded();

      // Fetch services (job subcategories) merged with artisan-specific prices when available
      final List<Map<String, dynamic>> services =
          await _fetchJobSubcategoriesForArtisan(artisan, ctx);

      // showModalBottomSheet returns dynamic; we'll return a Map with services+schedule when Pay is pressed
      final result = await showModalBottomSheet<Map<String, dynamic>>(
        context: ctx,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (context) {
          final theme = FlutterFlowTheme.of(context);

          // Local mutable state
          final Set<String> selected = {};
          int stepIndex = 0;
          DateTime? chosenDateTime;
          bool _showDateTimeError = false;

          num _toNum(dynamic v) {
            if (v == null) return 0;
            if (v is num) return v;
            return num.tryParse(v.toString()) ?? 0;
          }

          // Compute total as the sum of selected service unit prices
          num _computeTotal() {
            num sum = 0;
            for (final s in services) {
              final tid =
                  (s['tempId'] ?? s['_id'] ?? s['id'])?.toString() ?? '';
              if (tid.isEmpty) continue;
              if (!selected.contains(tid)) continue;
              final unit =
                  _toNum(s['price'] ?? s['unitPrice'] ?? s['amount'] ?? 0);
              sum += unit;
            }
            return sum;
          }

          String _formatCurrency(num v) {
            try {
              return NumberFormat.currency(symbol: '₦', decimalDigits: 0)
                  .format(v);
            } catch (_) {
              return '₦$v';
            }
          }

          Future<void> _pickDateTime(
              BuildContext ctx, StateSetter setModalState) async {
            final now = DateTime.now();
            final date = await showDatePicker(
              context: ctx,
              initialDate: now.add(const Duration(days: 1)),
              firstDate: now,
              lastDate: now.add(const Duration(days: 365)),
              builder: (context, child) {
                return Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: ColorScheme.light(
                      primary: primaryColor,
                      onPrimary: Colors.white,
                      surface: Colors.white,
                      onSurface: Colors.black,
                    ),
                  ),
                  child: child!,
                );
              },
            );
            if (date == null) return;

            final time = await showTimePicker(
              context: ctx,
              initialTime: TimeOfDay(hour: 9, minute: 0),
              builder: (context, child) {
                return Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: ColorScheme.light(
                      primary: primaryColor,
                      onPrimary: Colors.white,
                      surface: Colors.white,
                      onSurface: Colors.black,
                    ),
                  ),
                  child: child!,
                );
              },
            );
            if (time == null) return;

            final dt = DateTime(
                date.year, date.month, date.day, time.hour, time.minute);
            setModalState(() {
              chosenDateTime = dt;
              _scheduleCtrl.text =
                  DateFormat('EEE, MMM d, yyyy • h:mm a').format(dt);
              _showDateTimeError = false;
            });
          }

          Widget _buildServiceRow(
              Map<String, dynamic> s, StateSetter setModalState) {
            final tid = (s['tempId'] ?? s['_id'] ?? s['id'])?.toString() ?? '';

            String _resolveName(Map<String, dynamic> src) {
              try {
                final directKeys = [
                  'name',
                  'title',
                  'label',
                  'serviceName',
                  'subCategoryName',
                  'subCategoryTitle'
                ];
                for (final k in directKeys) {
                  final v = src[k];
                  if (v != null) {
                    final s = v.toString().trim();
                    if (s.isNotEmpty) return s;
                  }
                }

                final nested = src['subCategory'] ??
                    src['sub_category'] ??
                    src['subCategoryObj'];
                if (nested is Map) {
                  for (final k in ['name', 'title', 'label']) {
                    final v = nested[k];
                    if (v != null) {
                      final s = v.toString().trim();
                      if (s.isNotEmpty) return s;
                    }
                  }
                }

                // If the raw payload includes a subCategoryId object with a name, prefer that
                try {
                  final raw = src['raw'] ?? src;
                  if (raw is Map) {
                    final sc = raw['subCategoryId'] ??
                        raw['sub_category_id'] ??
                        raw['subCategory'] ??
                        raw['sub'];
                    if (sc is Map) {
                      final v = sc['name'] ?? sc['title'] ?? sc['label'];
                      if (v != null && v.toString().trim().isNotEmpty)
                        return v.toString().trim();
                    }
                  }
                } catch (_) {}
              } catch (_) {}
              // Fallback label when nothing else is available
              return 'Service';
            }

            final name = _resolveName(s);
            final unit =
                _toNum(s['price'] ?? s['unitPrice'] ?? s['amount'] ?? 0);
            final priceText =
                unit > 0 ? _formatCurrency(unit) : 'Price not set';
            final isSelected = selected.contains(tid);

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? primaryColor.withOpacity(0.05)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? primaryColor : _borderColor(),
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    setModalState(() {
                      if (isSelected) {
                        selected.remove(tid);
                      } else {
                        selected.add(tid);
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color:
                                isSelected ? primaryColor : Colors.transparent,
                            border: Border.all(
                              color: isSelected
                                  ? primaryColor
                                  : Colors.grey.shade400,
                              width: 2,
                            ),
                          ),
                          child: isSelected
                              ? const Icon(Icons.check,
                                  size: 16, color: Colors.white)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: theme.bodyMedium.copyWith(
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: isSelected ? primaryColor : null,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                priceText,
                                style: theme.bodySmall.copyWith(
                                  color: isSelected
                                      ? primaryColor
                                      : theme.secondaryText,
                                  fontWeight: isSelected
                                      ? FontWeight.w500
                                      : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          Widget _buildStepIndicator() {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          stepIndex >= 0 ? primaryColor : Colors.grey.shade300,
                    ),
                    child: Center(
                      child: Text(
                        '1',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 40,
                    height: 2,
                    color: stepIndex >= 1 ? primaryColor : Colors.grey.shade300,
                  ),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          stepIndex >= 1 ? primaryColor : Colors.grey.shade300,
                    ),
                    child: Center(
                      child: Text(
                        '2',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          Widget _buildStepContent(StateSetter setModalState) {
            if (stepIndex == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Text(
                    'Select Services',
                    style: theme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Choose one or more services you need',
                    style: theme.bodyMedium.copyWith(
                      color: theme.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (services.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            // Intentionally show only text when there are no services — removed extra info icon
                            const SizedBox(height: 4),
                            Text(
                              'No services available',
                              style: theme.bodyLarge,
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 340),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: services.length,
                        itemBuilder: (context, idx) =>
                            _buildServiceRow(services[idx], setModalState),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: primaryColor.withOpacity(0.2)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Selected Total',
                          style: theme.bodyLarge
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          _formatCurrency(_computeTotal()),
                          style: theme.titleMedium.copyWith(
                            color: primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }

            // Step 2: Date & Time
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text(
                  'Schedule Booking',
                  style: theme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Select date and time for your service',
                  style: theme.bodyMedium.copyWith(
                    color: theme.secondaryText,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  decoration: BoxDecoration(
                    color: _surfaceColor(),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _showDateTimeError ? Colors.red : _borderColor(),
                      width: _showDateTimeError ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      InkWell(
                        onTap: () => _pickDateTime(context, setModalState),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: primaryColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.calendar_month_outlined,
                                  color: primaryColor,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Date & Time',
                                      style: theme.bodySmall.copyWith(
                                        color: theme.secondaryText,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _scheduleCtrl.text.isEmpty
                                          ? 'Tap to select'
                                          : _scheduleCtrl.text,
                                      style: theme.bodyLarge.copyWith(
                                        fontWeight: _scheduleCtrl.text.isEmpty
                                            ? FontWeight.normal
                                            : FontWeight.w600,
                                        color: _scheduleCtrl.text.isEmpty
                                            ? theme.secondaryText
                                            : null,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_scheduleCtrl.text.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_showDateTimeError)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, left: 16),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'Please select date and time to continue',
                          style: theme.bodySmall.copyWith(color: Colors.red),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        primaryColor.withOpacity(0.1),
                        Colors.transparent
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: primaryColor.withOpacity(0.2)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total Amount',
                        style: theme.bodyLarge
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _formatCurrency(_computeTotal()),
                            style: theme.headlineSmall?.copyWith(
                              color: primaryColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${selected.length} service${selected.length != 1 ? 's' : ''}',
                            style: theme.bodySmall
                                .copyWith(color: theme.secondaryText),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          }

          Widget _buildActionButtons(StateSetter setModalState) {
            return Row(
              children: [
                if (stepIndex > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setModalState(() => stepIndex = 0),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(color: primaryColor.withOpacity(0.5)),
                      ),
                      child: Text(
                        'Back',
                        style: TextStyle(color: primaryColor),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: (stepIndex == 0 && selected.isEmpty)
                        ? null
                        : (stepIndex == 1 && _scheduleCtrl.text.isEmpty)
                            ? null
                            : () async {
                                if (stepIndex == 0) {
                                  setModalState(() => stepIndex = 1);
                                  return;
                                }

                                // Validate date/time is selected
                                if (_scheduleCtrl.text.isEmpty ||
                                    chosenDateTime == null) {
                                  setModalState(
                                      () => _showDateTimeError = true);
                                  return;
                                }

                                // Build payload and submit booking
                                // We build two lists: one minimal shape the server expects (subCategoryId, quantity)
                                // and a richer client-side metadata list (name, price) used for UI and payment metadata.
                                final payloadServices =
                                    <Map<String, dynamic>>[]; // client metadata
                                final serverServices = <Map<String,
                                    dynamic>>[]; // server-friendly shape
                                String? categoryIdForBody;

                                for (final s in services) {
                                  final tid =
                                      (s['tempId'] ?? s['_id'] ?? s['id'])
                                              ?.toString() ??
                                          '';
                                  if (tid.isEmpty) continue;
                                  if (!selected.contains(tid)) continue;

                                  final realSubId = (s['subCategoryId'] ??
                                              s['sub_category_id'] ??
                                              s['subCategory'] ??
                                              s['sub'] ??
                                              null)
                                          ?.toString() ??
                                      tid;

                                  // Try to capture categoryId from the service entry if available
                                  try {
                                    final c = s['categoryId'] ??
                                        s['category'] ??
                                        s['docCategoryId'] ??
                                        s['categoryIdRaw'];
                                    if (c != null &&
                                        (categoryIdForBody == null ||
                                            categoryIdForBody.isEmpty)) {
                                      categoryIdForBody = c is Map
                                          ? (c['_id'] ?? c['id'])?.toString()
                                          : c.toString();
                                    }
                                    // also inspect raw object
                                    final raw = s['raw'];
                                    if ((categoryIdForBody == null ||
                                            categoryIdForBody.isEmpty) &&
                                        raw is Map) {
                                      final rc = raw['categoryId'] ??
                                          raw['category'] ??
                                          raw['mainCategory'];
                                      if (rc != null)
                                        categoryIdForBody = rc is Map
                                            ? (rc['_id'] ?? rc['id'])
                                                ?.toString()
                                            : rc.toString();
                                    }
                                  } catch (_) {}

                                  // Resolve a friendly service name, preferring the raw subCategoryId.name when available
                                  String? svcName;
                                  try {
                                    final raw = s['raw'];
                                    if (raw is Map) {
                                      final sc = raw['subCategoryId'] ??
                                          raw['sub_category_id'] ??
                                          raw['subCategory'] ??
                                          raw['sub'];
                                      if (sc is Map) {
                                        svcName = (sc['name'] ??
                                                sc['title'] ??
                                                sc['label'])
                                            ?.toString();
                                      }
                                    }
                                  } catch (_) {}
                                  svcName = svcName ??
                                      (s['name'] ??
                                              s['serviceName'] ??
                                              s['subCategoryName'])
                                          ?.toString();

                                  // Include price so client-side checkout can list accurate amounts
                                  num price = 0;
                                  try {
                                    final p = s['price'] ??
                                        s['unitPrice'] ??
                                        s['amount'] ??
                                        s['rate'] ??
                                        0;
                                    if (p is num)
                                      price = p;
                                    else
                                      price = num.tryParse(p.toString()) ?? 0;
                                  } catch (_) {}

                                  final clientEntry = <String, dynamic>{
                                    'subCategoryId': realSubId,
                                    if (svcName != null) 'name': svcName,
                                    'price': price,
                                  };

                                  final serverEntry = <String, dynamic>{
                                    'subCategoryId': realSubId,
                                    'quantity': 1,
                                  };

                                  payloadServices.add(clientEntry);
                                  serverServices.add(serverEntry);
                                }

                                // Show loading indicator
                                setModalState(() {});

                                try {
                                  // Ensure we have auth token
                                  String? token = _authToken;
                                  if (token == null || token.isEmpty) {
                                    token = await TokenStorage.getToken();
                                    _authToken = token;
                                  }

                                  // Build request body. Use server-friendly services shape (subCategoryId + quantity)
                                  // Booking API expects userId (user._id), not artisan document _id
                                  final body = <String, dynamic>{
                                    'artisanId': artisan['userId'] ??
                                        (artisan['user'] is Map
                                            ? (artisan['user'] as Map)['_id']
                                            : null) ??
                                        artisan['_id'] ??
                                        artisan['id'] ??
                                        artisan['artisanId'],
                                    'services': serverServices,
                                    'schedule': chosenDateTime!
                                        .toUtc()
                                        .toIso8601String(),
                                    'clientTotal': _computeTotal(),
                                  };
                                  if (categoryIdForBody != null &&
                                      categoryIdForBody.isNotEmpty) {
                                    body['categoryId'] = categoryIdForBody;
                                  }

                                  // Add email if available
                                  try {
                                    final profile =
                                        await UserService.getProfile();
                                    final email = profile?['email']?.toString();
                                    if (email != null && email.isNotEmpty)
                                      body['email'] = email;
                                  } catch (_) {}

                                  final headers = <String, String>{
                                    'Content-Type': 'application/json',
                                  };
                                  if (token != null && token.isNotEmpty) {
                                    headers['Authorization'] = 'Bearer $token';
                                  }

                                  final normalizedBase =
                                      _normalizeBaseUrl(API_BASE_URL);
                                  final uri = Uri.parse(
                                      '$normalizedBase/api/bookings/hire');

                                  // Log request details (avoid printing Authorization token value)
                                  try {
                                    final headersForLog =
                                        Map<String, String>.from(headers);
                                    if (headersForLog
                                        .containsKey('Authorization')) {
                                      headersForLog['Authorization'] =
                                          '<REDACTED>';
                                    }
                                    debugPrint('Booking POST -> uri: $uri');
                                    debugPrint(
                                        'Booking POST -> headers: ${jsonEncode(headersForLog)}');
                                    // Also log client-side service objects (names/prices) selected in the bottom sheet
                                    try {
                                      debugPrint(
                                          'Booking POST -> payloadServices: ${jsonEncode(payloadServices)}');
                                    } catch (_) {}
                                    debugPrint(
                                        'Booking POST -> body: ${jsonEncode(body)}');
                                  } catch (_) {}

                                  // Show a non-dismissible processing dialog while the request is being sent
                                  try {
                                    showDialog<void>(
                                      context: context,
                                      barrierDismissible: false,
                                      builder: (ctx) => WillPopScope(
                                        onWillPop: () async => false,
                                        child: Dialog(
                                          insetPadding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 40),
                                          child: Padding(
                                            padding: const EdgeInsets.all(20.0),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const CircularProgressIndicator(),
                                                const SizedBox(width: 16),
                                                Expanded(
                                                    child: Text(
                                                        'Processing booking...',
                                                        style:
                                                            FlutterFlowTheme.of(
                                                                    ctx)
                                                                .bodyMedium)),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  } catch (_) {}

                                  http.Response resp;
                                  try {
                                    resp = await http
                                        .post(
                                          uri,
                                          headers: headers,
                                          body: jsonEncode(body),
                                        )
                                        .timeout(const Duration(seconds: 12));
                                  } finally {
                                    // Ensure we close the processing dialog even if request throws
                                    try {
                                      Navigator.of(context, rootNavigator: true)
                                          .pop();
                                    } catch (_) {}
                                  }

                                  if (resp.statusCode >= 200 &&
                                      resp.statusCode < 300) {
                                    // Log the raw HTTP response so we can trace server behavior from the client
                                    try {
                                      debugPrint(
                                          'Booking submission response -> status=${resp.statusCode} body=${resp.body}');
                                    } catch (_) {}
                                    final decoded = _safeParseJson(resp.body);
                                    Map<String, dynamic>? paymentNode;
                                    Map<String, dynamic>? bookingNode;

                                    if (decoded is Map) {
                                      if (decoded['data'] is Map) {
                                        final data = decoded['data'] as Map;
                                        bookingNode =
                                            Map<String, dynamic>.from(data);
                                        if (data['payment'] is Map) {
                                          paymentNode =
                                              Map<String, dynamic>.from(
                                                  data['payment']);
                                        }
                                      } else {
                                        bookingNode =
                                            Map<String, dynamic>.from(decoded);
                                        if (decoded['payment'] is Map) {
                                          paymentNode =
                                              Map<String, dynamic>.from(
                                                  decoded['payment']);
                                        }
                                      }
                                    }

                                    // Log parsed nodes to help trace why navigation to payment may not happen
                                    try {
                                      debugPrint(
                                          'Booking parsed paymentNode: ${paymentNode != null ? jsonEncode(paymentNode) : '<null>'}');
                                    } catch (_) {
                                      try {
                                        debugPrint(
                                            'Booking parsed paymentNode: <unserializable>');
                                      } catch (_) {}
                                    }
                                    try {
                                      debugPrint(
                                          'Booking parsed bookingNode: ${bookingNode != null ? jsonEncode(bookingNode) : '<null>'}');
                                    } catch (_) {
                                      try {
                                        debugPrint(
                                            'Booking parsed bookingNode: <unserializable>');
                                      } catch (_) {}
                                    }

                                    // Close the modal
                                    Navigator.of(context).pop();

                                    if (paymentNode != null &&
                                        paymentNode.isNotEmpty) {
                                      // Attach selected services and client total to payment/booking nodes so checkout can render them
                                      try {
                                        paymentNode['metadata'] =
                                            (paymentNode['metadata'] is Map)
                                                ? Map<String, dynamic>.from(
                                                    paymentNode['metadata'])
                                                : <String, dynamic>{};
                                        paymentNode['metadata']['services'] =
                                            payloadServices;
                                        paymentNode['metadata']['clientTotal'] =
                                            body['clientTotal'];
                                      } catch (_) {}

                                      try {
                                        if (bookingNode == null)
                                          bookingNode = <String, dynamic>{};
                                        bookingNode!['services'] =
                                            payloadServices;
                                        bookingNode!['clientTotal'] =
                                            body['clientTotal'];
                                      } catch (_) {}

                                      try {
                                        // Log the exact payload being passed to the payment page
                                        try {
                                          debugPrint(
                                              'Navigating to PaymentInitPageWidget with payment metadata: ${jsonEncode(paymentNode)}');
                                        } catch (_) {}
                                        // Inform the user they'll be redirected to payment
                                        try {
                                          AppNotification.showInfo(context,
                                              'Redirecting to payment...');
                                        } catch (_) {}
                                        await Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                PaymentInitPageWidget(
                                              payment: paymentNode!,
                                              booking: bookingNode,
                                            ),
                                          ),
                                        );
                                        // After returning from payment page, optionally inform user
                                        try {
                                          AppNotification.showInfo(context,
                                              'Returned from payment flow');
                                        } catch (_) {}
                                      } catch (e) {
                                        debugPrint(
                                            'Navigation to PaymentInitPageWidget failed: $e');
                                        rethrow;
                                      }
                                    } else {
                                      // No payment required or payment node not returned; still attach services to booking node for downstream UI
                                      try {
                                        if (bookingNode == null)
                                          bookingNode = <String, dynamic>{};
                                        bookingNode!['services'] =
                                            payloadServices;
                                        bookingNode!['clientTotal'] =
                                            body['clientTotal'];
                                      } catch (_) {}
                                      AppNotification.showSuccess(context,
                                          'Booking created successfully');
                                    }
                                  } else {
                                    String message = 'Failed to create booking';
                                    try {
                                      final errorBody = jsonDecode(resp.body);
                                      if (errorBody is Map &&
                                          errorBody['message'] != null) {
                                        message =
                                            errorBody['message'].toString();
                                      }
                                    } catch (_) {}
                                    AppNotification.showError(context, message);
                                  }
                                } on TimeoutException {
                                  AppNotification.showError(context,
                                      'Network timeout. Please try again.');
                                } catch (e, st) {
                                  debugPrint(
                                      'Booking submission error: $e\n$st');
                                  AppNotification.showError(context,
                                      'An error occurred. Please try again.');
                                }
                              },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child: stepIndex == 0
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('Next (${selected.length} selected)'),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward, size: 18),
                            ],
                          )
                        : Text('Pay ${_formatCurrency(_computeTotal())}'),
                  ),
                ),
              ],
            );
          }

          return StatefulBuilder(
            builder: (context, setModalState) {
              return Container(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 8,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                ),
                decoration: BoxDecoration(
                  color: _surfaceColor(),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 20,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Drag handle
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),

                      // Header with artisan name
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: primaryColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.handyman_outlined,
                                color: primaryColor,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Book with',
                                    style: theme.bodySmall.copyWith(
                                      color: theme.secondaryText,
                                    ),
                                  ),
                                  Text(
                                    _displayName(),
                                    style: theme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
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

                      _buildStepIndicator(),

                      Flexible(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: _buildStepContent(setModalState),
                        ),
                      ),

                      const SizedBox(height: 20),

                      _buildActionButtons(setModalState),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );

      return result;
    } finally {
      try {
        _scheduleCtrl.dispose();
      } catch (_) {}
    }
  }

  // Compatibility wrapper
  Future<void> _showHireSheet(BuildContext ctx) async {
    try {
      await _showHireSheet_impl(ctx);
    } catch (_) {}
  }

  /// Fetch job subcategories for the artisan's primary category and merge any artisan-specific prices.
  Future<List<Map<String, dynamic>>> _fetchJobSubcategoriesForArtisan(
      Map<String, dynamic> artisan, BuildContext context,
      {String? token}) async {
    token ??= _authToken;

    try {
      // First, check if the artisan payload already contains per-artisan offerings
      final possibleLists = <dynamic>[
        artisan['services'],
        artisan['artisanServices'],
        artisan['artisan_service'],
        artisan['serviceOptions'],
        artisan['offerings'],
        artisan['pricing'] is Map ? artisan['pricing']['services'] : null,
        artisan['pricingDetails'],
        artisan['service_list'],
        artisan['serviceList'],
        artisan['artisan_service_entries'],
        artisan['artisan_services'],
        artisan['service_entries'],
        artisan['serviceItems'],
        artisan['myServices'],
      ];

      final List<Map<String, dynamic>> extracted = [];

      for (final cand in possibleLists) {
        if (cand == null) continue;
        if (cand is List && cand.isNotEmpty) {
          bool flattenedAny = false;
          for (final e in cand) {
            if (e == null) continue;
            if (e is Map && (e['services'] is List)) {
              // This is an ArtisanService-style doc: flatten its nested services
              final doc = Map<String, dynamic>.from(e.cast<String, dynamic>());
              final artisanServiceId = (doc['_id'] ?? doc['id'])?.toString();
              final dynamic categoryRaw =
                  doc['categoryId'] ?? doc['mainCategory'] ?? doc['category'];
              String? categoryId;
              if (categoryRaw is Map)
                categoryId =
                    (categoryRaw['_id'] ?? categoryRaw['id'])?.toString();
              else
                categoryId = categoryRaw?.toString();

              final servicesArr = doc['services'] as List<dynamic>;
              for (final s in servicesArr) {
                if (s == null || s is! Map) continue;
                final sub =
                    Map<String, dynamic>.from(s.cast<String, dynamic>());
                final subRaw = sub['subCategoryId'] ??
                    sub['sub_category_id'] ??
                    sub['subCategory'] ??
                    sub['sub'] ??
                    sub['_id'] ??
                    sub['id'];
                String? subId;
                String? subName =
                    (sub['name'] ?? sub['title'] ?? sub['label'])?.toString();
                if (subRaw is Map) {
                  subId = (subRaw['_id'] ?? subRaw['id'])?.toString();
                  subName = subName ??
                      (subRaw['name'] ?? subRaw['title'])?.toString();
                } else {
                  subId = subRaw == null ? null : subRaw.toString();
                }
                final rawPrice = sub['price'] ??
                    sub['amount'] ??
                    sub['unitPrice'] ??
                    sub['rate'] ??
                    sub['cost'];
                num? price;
                if (rawPrice != null) {
                  if (rawPrice is num)
                    price = rawPrice;
                  else
                    price = num.tryParse(rawPrice.toString());
                }
                final tempId = (subId != null && subId.isNotEmpty)
                    ? subId
                    : ('artisan_${artisan['_id'] ?? artisan['id'] ?? DateTime.now().millisecondsSinceEpoch}__${(sub['_id'] ?? sub['id'])?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString()}');
                extracted.add({
                  'tempId': tempId,
                  if (subId != null) 'subCategoryId': subId,
                  'name': subName ?? sub['serviceName'] ?? 'Unnamed service',
                  if (price != null) 'price': price,
                  if (subId != null) 'artisanServiceId': artisanServiceId,
                  'categoryId': categoryId,
                  'raw': sub,
                });
                flattenedAny = true;
              }
            }
          }
          if (flattenedAny) return extracted;

          for (final e in cand) {
            if (e == null) continue;
            if (e is! Map) continue;
            final m = Map<String, dynamic>.from(e.cast<String, dynamic>());

            String? subId;
            String? name;
            num? price;
            String? currency;
            String? artisanServiceId;

            subId = (m['subCategoryId'] ??
                    m['sub_category_id'] ??
                    m['subCategory'] ??
                    m['sub'] ??
                    m['id'] ??
                    m['_id'])
                ?.toString();
            name =
                (m['name'] ?? m['title'] ?? m['label'] ?? m['subCategoryName'])
                    ?.toString();

            final nestedSub =
                m['subCategory'] ?? m['sub_category'] ?? m['subCategoryObj'];
            if ((subId == null || subId.isEmpty) && nestedSub is Map) {
              subId = (nestedSub['_id'] ?? nestedSub['id'])?.toString();
              name =
                  name ?? (nestedSub['name'] ?? nestedSub['title'])?.toString();
            }

            final rawPrice = m['price'] ??
                m['amount'] ??
                m['unitPrice'] ??
                m['rate'] ??
                m['cost'];
            num? svcPrice;
            if (rawPrice != null) {
              if (rawPrice is num)
                svcPrice = rawPrice;
              else
                svcPrice = num.tryParse(rawPrice.toString());
            }
            currency =
                (m['currency'] ?? m['curr'] ?? m['currencyCode'])?.toString() ??
                    'NGN';
            artisanServiceId =
                (m['artisanServiceId'] ?? m['artisanService'] ?? m['parentId'])
                    ?.toString();

            final tempId = (subId != null && subId.isNotEmpty)
                ? subId
                : ('artisan_${artisan['_id'] ?? artisan['id'] ?? DateTime.now().millisecondsSinceEpoch}__${(m['serviceEntryId'] ?? m['id'] ?? m['_id'])?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString()}');

            extracted.add({
              'tempId': tempId,
              if (subId != null) 'subCategoryId': subId,
              'name': name ??
                  m['serviceName'] ??
                  m['subCategoryName'] ??
                  'Unnamed service',
              if (svcPrice != null) 'price': svcPrice,
              'currency': currency,
              if (artisanServiceId != null)
                'artisanServiceId': artisanServiceId,
              'raw': m,
            });
          }
        }
        if (extracted.isNotEmpty) return extracted;
      }

      // No per-artisan offerings present in payload — fall back to the global subcategories fetch
      String? categoryId;
      for (final k in [
        'categoryId',
        'category',
        'jobCategory',
        'category_id',
        'jobCategoryId'
      ]) {
        final v = artisan[k];
        if (v == null) continue;
        if (v is String && v.isNotEmpty) {
          categoryId = v;
          break;
        }
        if (v is Map && (v['_id'] ?? v['id']) != null) {
          categoryId = (v['_id'] ?? v['id']).toString();
          break;
        }
      }
      if (categoryId == null || categoryId.isEmpty) return [];

      // Try to fetch per-artisan offerings from public ArtisanService endpoints
      try {
        String? artisanId = (artisan['_id'] ??
                artisan['id'] ??
                artisan['artisanId'] ??
                artisan['userId'])
            ?.toString();
        if (artisanId == null || artisanId.isEmpty) {
          final userObj = artisan['user'];
          if (userObj is Map)
            artisanId = (userObj['_id'] ?? userObj['id'])?.toString();
        }

        if (artisanId != null && artisanId.isNotEmpty) {
          final base = _normalizeBaseUrl(API_BASE_URL);

          Future<List<Map<String, dynamic>>> tryQuery({String? catId}) async {
            try {
              final queryParam = catId != null ? '&categoryId=$catId' : '';
              final qUri = Uri.parse(
                  '$base/api/artisan-services?artisanId=$artisanId$queryParam');
              final qResp =
                  await http.get(qUri).timeout(const Duration(seconds: 10));
              if (qResp.statusCode >= 200 &&
                  qResp.statusCode < 300 &&
                  qResp.body.isNotEmpty) {
                final body = jsonDecode(qResp.body);
                List<dynamic>? docs;
                if (body is List)
                  docs = body;
                else if (body is Map && body['data'] is List)
                  docs = List<dynamic>.from(body['data']);
                else if (body is Map && body['items'] is List)
                  docs = List<dynamic>.from(body['items']);
                else if (body is Map && body['services'] is List) docs = [body];

                if (docs != null && docs.isNotEmpty) {
                  final List<Map<String, dynamic>> flattened = [];
                  for (final doc in docs) {
                    if (doc == null) continue;
                    if (doc is! Map) continue;
                    final d =
                        Map<String, dynamic>.from(doc.cast<String, dynamic>());
                    final artisanServiceId = (d['_id'] ?? d['id'])?.toString();
                    final docCategoryId = (d['categoryId'] ??
                            d['mainCategory'] ??
                            d['category']) is Map
                        ? ((d['categoryId'] ??
                                    d['mainCategory'] ??
                                    d['category'])['_id'] ??
                                (d['categoryId'] ??
                                    d['mainCategory'] ??
                                    d['category'])['id'])
                            ?.toString()
                        : (d['categoryId'] ??
                                d['mainCategory'] ??
                                d['category'])
                            ?.toString();
                    final servicesArr =
                        d['services'] ?? d['serviceList'] ?? d['items'];
                    if (servicesArr is List) {
                      for (final s in servicesArr) {
                        if (s == null || s is! Map) continue;
                        final sub = Map<String, dynamic>.from(
                            s.cast<String, dynamic>());
                        final subRaw = sub['subCategoryId'] ??
                            sub['sub_category_id'] ??
                            sub['_id'] ??
                            sub['id'];
                        String? subId;
                        String? subName =
                            (sub['name'] ?? sub['title'] ?? sub['label'])
                                ?.toString();
                        if (subRaw is Map) {
                          subId = (subRaw['_id'] ?? subRaw['id'])?.toString();
                          subName = subName ??
                              (subRaw['name'] ?? subRaw['title'])?.toString();
                        } else {
                          subId = subRaw?.toString();
                        }
                        final rawPrice = sub['price'] ??
                            sub['amount'] ??
                            sub['unitPrice'] ??
                            sub['rate'] ??
                            sub['cost'];
                        num? price;
                        if (rawPrice != null) {
                          if (rawPrice is num)
                            price = rawPrice;
                          else
                            price = num.tryParse(rawPrice.toString());
                        }
                        final tempId = (subId != null && subId.isNotEmpty)
                            ? subId
                            : ('artisan_${artisanId}__${(sub['_id'] ?? sub['id'])?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString()}');
                        if (catId != null &&
                            docCategoryId != null &&
                            docCategoryId != catId) continue;
                        flattened.add({
                          'tempId': tempId,
                          if (subId != null) 'subCategoryId': subId,
                          'name': subName ?? 'Unnamed service',
                          if (price != null) 'price': price,
                          'currency': sub['currency'] ?? 'NGN',
                          'artisanServiceId': artisanServiceId,
                          'categoryId': docCategoryId,
                          'raw': sub,
                        });
                      }
                    }
                  }
                  return flattened;
                }
              }
            } catch (_) {}
            return [];
          }

          if (categoryId != null && categoryId.isNotEmpty) {
            final byCategory = await tryQuery(catId: categoryId);
            if (byCategory.isNotEmpty) return byCategory;
          }
          final byArtisan = await tryQuery();
          if (byArtisan.isNotEmpty) return byArtisan;

          try {
            final qUri = Uri.parse('$base/api/artisan-services/$artisanId');
            final qResp =
                await http.get(qUri).timeout(const Duration(seconds: 10));
            if (qResp.statusCode >= 200 &&
                qResp.statusCode < 300 &&
                qResp.body.isNotEmpty) {
              final body = jsonDecode(qResp.body);
              if (body is Map && body['data'] is Map) {
                final d = Map<String, dynamic>.from(body['data']);
                final artisanServiceId = (d['_id'] ?? d['id'])?.toString();
                final docCategoryId = (d['categoryId'] ??
                        d['mainCategory'] ??
                        d['category']) is Map
                    ? ((d['categoryId'] ??
                                d['mainCategory'] ??
                                d['category'])['_id'] ??
                            (d['categoryId'] ??
                                d['mainCategory'] ??
                                d['category'])['id'])
                        ?.toString()
                    : (d['categoryId'] ?? d['mainCategory'] ?? d['category'])
                        ?.toString();
                final servicesArr =
                    d['services'] ?? d['serviceList'] ?? d['items'];
                if (servicesArr is List) {
                  final flattened = <Map<String, dynamic>>[];
                  for (final s in servicesArr) {
                    if (s == null || s is! Map) continue;
                    final sub =
                        Map<String, dynamic>.from(s.cast<String, dynamic>());
                    final subRaw = sub['subCategoryId'] ??
                        sub['sub_category_id'] ??
                        sub['_id'] ??
                        sub['id'];
                    String? subId;
                    String? subName =
                        (sub['name'] ?? sub['title'] ?? sub['label'])
                            ?.toString();
                    if (subRaw is Map) {
                      subId = (subRaw['_id'] ?? subRaw['id'])?.toString();
                      subName = subName ??
                          (subRaw['name'] ?? subRaw['title'])?.toString();
                    } else {
                      subId = subRaw?.toString();
                    }
                    final rawPrice =
                        sub['price'] ?? sub['amount'] ?? sub['unitPrice'];
                    num? price;
                    if (rawPrice != null) {
                      if (rawPrice is num)
                        price = rawPrice;
                      else
                        price = num.tryParse(rawPrice.toString());
                    }
                    final tempId = (subId != null && subId.isNotEmpty)
                        ? subId
                        : ('artisan_${artisanId}__${(sub['_id'] ?? sub['id'])?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString()}');
                    flattened.add({
                      'tempId': tempId,
                      if (subId != null) 'subCategoryId': subId,
                      'name': subName ?? 'Unnamed service',
                      if (price != null) 'price': price,
                      'currency': sub['currency'] ?? 'NGN',
                      'artisanServiceId': artisanServiceId,
                      'categoryId': docCategoryId,
                      'raw': sub,
                    });
                  }
                  return flattened;
                }
              }
            }
          } catch (_) {}
        }
      } catch (_) {}

      // If we still have nothing, try MyServiceService.fetchMyServices() as a last-resort
      String? resolvedAid = (artisan['_id'] ??
              artisan['id'] ??
              artisan['artisanId'] ??
              artisan['userId'])
          ?.toString();
      if (resolvedAid == null || resolvedAid.isEmpty) {
        final userObj = artisan['user'];
        if (userObj is Map)
          resolvedAid = (userObj['_id'] ?? userObj['id'])?.toString();
      }
      try {
        final mySvc = MyServiceService();
        final apiResp = await mySvc.fetchMyServices(context: context);
        if (apiResp.ok && apiResp.data != null) {
          List<dynamic>? docs;
          if (apiResp.data is List)
            docs = apiResp.data as List<dynamic>;
          else if (apiResp.data is Map && apiResp.data['data'] is List)
            docs = List<dynamic>.from(apiResp.data['data']);
          else if (apiResp.data is Map && apiResp.data['items'] is List)
            docs = List<dynamic>.from(apiResp.data['items']);
          else if (apiResp.data is Map && apiResp.data['services'] is List)
            docs = [apiResp.data];

          if (docs != null && docs.isNotEmpty) {
            final List<Map<String, dynamic>> flattened = [];
            for (final doc in docs) {
              if (doc == null || doc is! Map) continue;
              final d = Map<String, dynamic>.from(doc.cast<String, dynamic>());
              final servicesArr =
                  d['services'] ?? d['serviceList'] ?? d['items'];
              final artisanServiceId = (d['_id'] ?? d['id'])?.toString();
              final docCategoryId = (d['categoryId'] ?? d['category']) is Map
                  ? ((d['categoryId'] ?? d['category'])['_id'] ??
                          (d['categoryId'] ?? d['category'])['id'])
                      ?.toString()
                  : (d['categoryId'] ?? d['category'])?.toString();
              if (servicesArr is List) {
                for (final s in servicesArr) {
                  if (s == null || s is! Map) continue;
                  final sub =
                      Map<String, dynamic>.from(s.cast<String, dynamic>());
                  final subRaw = sub['subCategoryId'] ??
                      sub['sub_category_id'] ??
                      sub['_id'] ??
                      sub['id'];
                  String? subId;
                  String? subName =
                      (sub['name'] ?? sub['title'] ?? sub['label'])?.toString();
                  if (subRaw is Map) {
                    subId = (subRaw['_id'] ?? subRaw['id'])?.toString();
                    subName = subName ??
                        (subRaw['name'] ?? subRaw['title'])?.toString();
                  } else {
                    subId = subRaw?.toString();
                  }
                  final rawPrice =
                      sub['price'] ?? sub['amount'] ?? sub['unitPrice'];
                  num? price;
                  if (rawPrice != null) {
                    if (rawPrice is num)
                      price = rawPrice;
                    else
                      price = num.tryParse(rawPrice.toString());
                  }
                  final tempId = (subId != null && subId.isNotEmpty)
                      ? subId
                      : ('artisan_${resolvedAid ?? 'me'}__${(sub['_id'] ?? sub['id'])?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString()}');
                  flattened.add({
                    'tempId': tempId,
                    if (subId != null) 'subCategoryId': subId,
                    'name': subName ?? 'Unnamed service',
                    if (price != null) 'price': price,
                    'currency': sub['currency'] ?? 'NGN',
                    'artisanServiceId': artisanServiceId,
                    'categoryId': docCategoryId,
                    'raw': sub,
                  });
                }
              }
              if (flattened.isNotEmpty) return flattened;
            }
          }
        }
      } catch (_) {}
    } catch (e) {
      debugPrint('fetchJobSubcategoriesForArtisan error: $e');
    }
    return [];
  }

  Future<void> _loadArtisanDataIfNeeded() async {
    final id = _artisanIdFromWidget();
    if (id == null) return;
    if (_artisanData != null) return;
    await _fetchArtisanById(id);
  }

  // MARK: - Build
  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final artisan = _artisan;
    final profileImage = _extractProfileImage(artisan);

    // Responsive sizing
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 375;
    final isLargeScreen = screenWidth > 600;

    // Responsive font sizes
    final titleFontSize = isSmallScreen ? 18.0 : (isLargeScreen ? 22.0 : 20.0);
    final bodyFontSize = isSmallScreen ? 14.0 : (isLargeScreen ? 16.0 : 15.0);
    final smallFontSize = isSmallScreen ? 12.0 : (isLargeScreen ? 14.0 : 13.0);

    // Responsive padding
    final horizontalPadding =
        isSmallScreen ? 16.0 : (isLargeScreen ? 24.0 : 20.0);
    final verticalPadding =
        isSmallScreen ? 16.0 : (isLargeScreen ? 24.0 : 20.0);

    // Responsive spacing
    final smallSpacing = isSmallScreen ? 8.0 : 12.0;
    final mediumSpacing = isSmallScreen ? 12.0 : 16.0;
    final largeSpacing = isSmallScreen ? 16.0 : 24.0;

    // Responsive image size
    final profileImageSize =
        isSmallScreen ? 70.0 : (isLargeScreen ? 90.0 : 80.0);

    // Helper functions
    String safeToString(dynamic value) {
      if (value == null) return '';
      if (value is String) return value;
      if (value is int || value is double) return value.toString();
      return value.toString();
    }

    String safeGetString(String key, {String defaultValue = 'Not specified'}) {
      try {
        final value = artisan[key];
        if (value == null) return defaultValue;
        return safeToString(value);
      } catch (_) {
        return defaultValue;
      }
    }

    String safeGetNestedString(List<String> keys,
        {String defaultValue = 'Not specified'}) {
      try {
        dynamic value = artisan;
        for (final key in keys) {
          if (value is Map && value.containsKey(key)) {
            value = value[key];
          } else {
            return defaultValue;
          }
        }
        return safeToString(value);
      } catch (_) {
        return defaultValue;
      }
    }

    // Check if we need loading screen
    final providedId = _artisanIdFromWidget();
    final bool widgetHasRichData = _isWidgetPayloadRich(widget.artisan);

    if (providedId != null && _artisanData == null && !widgetHasRichData) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: Center(
            child: _loading
                ? const CircularProgressIndicator()
                : (_errorMessage != null
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_errorMessage!,
                                textAlign: TextAlign.center,
                                style: theme.bodyLarge),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: () async {
                                setState(() {
                                  _loading = true;
                                  _errorMessage = null;
                                });
                                await _fetchArtisanById(providedId,
                                    token: _authToken);
                              },
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink()),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding, vertical: mediumSpacing),
              decoration: BoxDecoration(
                border:
                    Border(bottom: BorderSide(color: _borderColor(), width: 1)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back_rounded,
                      color: theme.primary,
                      size: isSmallScreen ? 22 : 24,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Artisan Profile',
                          style: theme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                            fontSize: titleFontSize - 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Loading/error indicators
            if (_loading)
              LinearProgressIndicator(
                backgroundColor: Colors.transparent,
                color: primaryColor,
                minHeight: 2,
              ),
            if ((_errorMessage?.isNotEmpty ?? false) && !_hasEffectiveArtisan())
              Container(
                width: double.infinity,
                color: Theme.of(context).colorScheme.error.withOpacity(0.08),
                padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding, vertical: smallSpacing),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w600,
                      fontSize: smallFontSize),
                  textAlign: TextAlign.center,
                ),
              ),

            // Main content
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding, vertical: verticalPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Profile Header
                    Container(
                      padding: EdgeInsets.all(mediumSpacing),
                      decoration: BoxDecoration(
                        color: _surfaceColor(),
                        borderRadius:
                            BorderRadius.circular(isSmallScreen ? 16 : 20),
                      ),
                      child: Row(
                        children: [
                          // Profile Image
                          Container(
                            width: profileImageSize,
                            height: profileImageSize,
                            child: ClipOval(
                              child: profileImage != null
                                  ? CachedNetworkImage(
                                      imageUrl: profileImage,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => Container(
                                        color: primaryColor.withOpacity(0.1),
                                        child: Center(
                                          child: Icon(
                                            Icons.person_outline,
                                            size: isSmallScreen ? 32 : 40,
                                            color:
                                                primaryColor.withOpacity(0.5),
                                          ),
                                        ),
                                      ),
                                      errorWidget: (context, url, error) =>
                                          Container(
                                        color: primaryColor.withOpacity(0.1),
                                        child: Center(
                                          child: Icon(
                                            Icons.person_outline,
                                            size: isSmallScreen ? 32 : 40,
                                            color:
                                                primaryColor.withOpacity(0.5),
                                          ),
                                        ),
                                      ),
                                    )
                                  : Container(
                                      color: primaryColor.withOpacity(0.1),
                                      child: Center(
                                        child: Icon(
                                          Icons.person_outline,
                                          size: isSmallScreen ? 32 : 40,
                                          color: primaryColor.withOpacity(0.5),
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                          SizedBox(width: mediumSpacing),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Name with verification badge
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        _displayName(),
                                        style: theme.headlineSmall?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          fontSize: titleFontSize,
                                          color: _textColor(1.0),
                                        ),
                                        maxLines: isSmallScreen ? 1 : 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (_isVerified) ...[
                                      SizedBox(width: isSmallScreen ? 4 : 6),
                                      Container(
                                        padding: EdgeInsets.all(
                                            isSmallScreen ? 2 : 3),
                                        decoration: BoxDecoration(
                                          color: Colors.green.withOpacity(0.12),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.verified,
                                          color: Colors.green,
                                          size: isSmallScreen ? 14 : 16,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),

                                SizedBox(height: 6),

                                // Trade pill
                                Wrap(
                                  spacing: smallSpacing,
                                  runSpacing: isSmallScreen ? 4 : 6,
                                  children: [
                                    Builder(builder: (context) {
                                      final trade = _getTrade();
                                      if (trade == null || trade.isEmpty) {
                                        return const SizedBox.shrink();
                                      }
                                      return Container(
                                        padding: EdgeInsets.symmetric(
                                            horizontal: isSmallScreen ? 8 : 10,
                                            vertical: isSmallScreen ? 4 : 6),
                                        decoration: BoxDecoration(
                                          color: primaryColor.withOpacity(0.12),
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                        child: Text(
                                          trade,
                                          style: theme.bodySmall.copyWith(
                                            color: primaryColor,
                                            fontWeight: FontWeight.w600,
                                            fontSize: smallFontSize,
                                          ),
                                        ),
                                      );
                                    }),
                                  ],
                                ),

                                SizedBox(height: mediumSpacing),

                                // Rating stars
                                Row(
                                  children: [
                                    ...List.generate(5, (index) {
                                      final fullStars =
                                          (_averageRating ?? 0).floor();
                                      return Icon(
                                        index < fullStars
                                            ? Icons.star_rounded
                                            : Icons.star_border,
                                        size: isSmallScreen ? 14 : 16,
                                        color: Colors.amber,
                                      );
                                    }),
                                    SizedBox(width: isSmallScreen ? 6 : 8),
                                    if (_loadingReviews)
                                      SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2)),
                                    SizedBox(width: isSmallScreen ? 4 : 6),
                                    Flexible(
                                      child: Text(
                                        _averageRating != null
                                            ? '${_averageRating!.toStringAsFixed(1)} (${_reviewCount} reviews)'
                                            : (_loadingReviews
                                                ? 'Loading'
                                                : 'No reviews yet'),
                                        style: theme.bodyMedium.copyWith(
                                          color: _secondaryTextColor(),
                                          fontSize: smallFontSize,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: largeSpacing),

                    // Book Now Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                              vertical: isSmallScreen ? 14 : 16),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(isSmallScreen ? 10 : 12),
                          ),
                          elevation: 0,
                          shadowColor: Colors.transparent,
                        ),
                        onPressed: () async {
                          if (!await ensureSignedInForAction(context)) return;
                          _showHireSheet(context);
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.calendar_today_outlined,
                              size: isSmallScreen ? 18 : 20,
                            ),
                            SizedBox(width: isSmallScreen ? 8 : 10),
                            Text(
                              'Book Now',
                              style: TextStyle(
                                fontSize: bodyFontSize,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    SizedBox(height: largeSpacing),

                    // About Section
                    Padding(
                      padding: EdgeInsets.only(left: 8.0, bottom: smallSpacing),
                      child: Text(
                        'ABOUT',
                        style: TextStyle(
                          fontSize: smallFontSize - 2,
                          fontWeight: FontWeight.w600,
                          color: _secondaryTextColor(),
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.all(mediumSpacing),
                      decoration: BoxDecoration(
                        color: _surfaceColor(),
                        borderRadius:
                            BorderRadius.circular(isSmallScreen ? 12 : 16),
                        border: Border.all(color: _borderColor(), width: 1.5),
                      ),
                      child: Text(
                        safeGetString('bio',
                            defaultValue:
                                'No bio available. This artisan hasn\'t added a description yet.'),
                        style: theme.bodyLarge?.copyWith(
                          color: _textColor(0.85),
                          height: 1.6,
                          fontSize: bodyFontSize,
                        ),
                      ),
                    ),

                    SizedBox(height: largeSpacing),

                    // Info Section
                    Padding(
                      padding: EdgeInsets.only(left: 8.0, bottom: smallSpacing),
                      child: Text(
                        'INFORMATION',
                        style: TextStyle(
                          fontSize: smallFontSize - 2,
                          fontWeight: FontWeight.w600,
                          color: _secondaryTextColor(),
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    Column(
                      children: [
                        _buildInfoItem(
                          Icons.location_on_outlined,
                          'Location',
                          _displayLocation(),
                        ),
                        SizedBox(height: smallSpacing),
                        _buildInfoItem(
                          Icons.work_outline,
                          'Experience',
                          safeGetString('experience',
                              defaultValue: safeGetString('yearsOfExperience',
                                  defaultValue: 'Not specified')),
                        ),
                        SizedBox(height: smallSpacing),
                        _buildInfoItem(
                          Text(
                            '₦',
                            style: TextStyle(
                              color: primaryColor,
                              fontWeight: FontWeight.w700,
                              fontSize: isSmallScreen ? 14 : 16,
                            ),
                          ),
                          'Service Charge',
                          safeGetNestedString(['pricing', 'perJob'],
                              defaultValue: 'Contact for pricing'),
                        ),
                      ],
                    ),

                    SizedBox(height: largeSpacing),

                    // Reviews Section
                    Padding(
                      padding: EdgeInsets.only(left: 8.0, bottom: smallSpacing),
                      child: Text(
                        'REVIEWS',
                        style: TextStyle(
                          fontSize: smallFontSize - 2,
                          fontWeight: FontWeight.w600,
                          color: _secondaryTextColor(),
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    Column(
                      children: [
                        if (_loadingReviews) ...[
                          Padding(
                            padding:
                                EdgeInsets.symmetric(vertical: mediumSpacing),
                            child: Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: primaryColor,
                              ),
                            ),
                          ),
                        ] else if (_reviews.isEmpty) ...[
                          Padding(
                            padding:
                                EdgeInsets.symmetric(vertical: mediumSpacing),
                            child: Center(
                              child: Text(
                                'No reviews yet',
                                style: theme.bodyLarge?.copyWith(
                                  color: _secondaryTextColor(),
                                  fontSize: bodyFontSize,
                                ),
                              ),
                            ),
                          ),
                        ] else ...[
                          ..._reviews.map((review) {
                            final reviewerId =
                                review['customerId'] ?? review['userId'];
                            final reviewerName = reviewerId != null &&
                                    reviewerId.toString().isNotEmpty
                                ? (_userNameCache[reviewerId.toString()] ??
                                    'User')
                                : 'User';
                            String reviewDate = 'Unknown date';
                            try {
                              if (review['createdAt'] != null) {
                                reviewDate = DateFormat('MMM d, yyyy').format(
                                    DateTime.parse(
                                        review['createdAt'].toString()));
                              }
                            } catch (_) {}
                            final reviewRating =
                                review['rating'] ?? review['stars'] ?? 0;
                            final reviewComment = (review['comment'] ??
                                    review['review'] ??
                                    review['content'] ??
                                    review['message'] ??
                                    review['text'] ??
                                    '')
                                .toString();

                            return Padding(
                              padding: EdgeInsets.only(bottom: smallSpacing),
                              child: Container(
                                padding: EdgeInsets.all(mediumSpacing),
                                decoration: BoxDecoration(
                                  color: _surfaceColor(),
                                  borderRadius: BorderRadius.circular(
                                      isSmallScreen ? 12 : 16),
                                  border: Border.all(
                                      color: _borderColor(), width: 1),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: isSmallScreen ? 36 : 40,
                                          height: isSmallScreen ? 36 : 40,
                                          decoration: BoxDecoration(
                                            color:
                                                primaryColor.withOpacity(0.1),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Center(
                                            child: Text(
                                              reviewerName.isNotEmpty
                                                  ? reviewerName[0]
                                                      .toUpperCase()
                                                  : 'U',
                                              style: TextStyle(
                                                color: primaryColor,
                                                fontWeight: FontWeight.w600,
                                                fontSize:
                                                    isSmallScreen ? 14 : 16,
                                              ),
                                            ),
                                          ),
                                        ),
                                        SizedBox(width: smallSpacing),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                reviewerName,
                                                style:
                                                    theme.bodyMedium.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: bodyFontSize,
                                                ),
                                              ),
                                              SizedBox(height: 2),
                                              Row(
                                                children: [
                                                  ...List.generate(5, (index) {
                                                    return Icon(
                                                      index <
                                                              reviewRating
                                                                  .floor()
                                                          ? Icons.star
                                                          : Icons.star_border,
                                                      size: isSmallScreen
                                                          ? 14
                                                          : 16,
                                                      color: Colors.amber,
                                                    );
                                                  }),
                                                  SizedBox(
                                                      width: isSmallScreen
                                                          ? 6
                                                          : 8),
                                                  Text(
                                                    reviewDate,
                                                    style: theme.bodySmall
                                                        .copyWith(
                                                      color:
                                                          _secondaryTextColor(),
                                                      fontSize: smallFontSize,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: smallSpacing),
                                    if (reviewComment.isNotEmpty) ...[
                                      Text(
                                        reviewComment,
                                        style: theme.bodyMedium.copyWith(
                                          color: _textColor(0.85),
                                          fontSize: bodyFontSize,
                                        ),
                                        maxLines: 4,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
                      ],
                    ),

                    SizedBox(height: isSmallScreen ? 40 : 60),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// MARK: - Global Helpers
String _normalizeBaseUrl(String raw) {
  var base = (raw ?? '').toString().trim();
  if (base.isEmpty) return '';

  // If someone passed a value with a leading slash (e.g. '/rijhub.com'),
  // strip those to avoid producing 'https:///rijhub.com' when we prepend scheme.
  base = base.replaceFirst(RegExp(r'^/+'), '');

  // Fix common malformed schemes like 'http:/example.com' or 'https:/example.com'
  if (base.startsWith('http:/') && !base.startsWith('http://'))
    base = base.replaceFirst('http:/', 'http://');
  if (base.startsWith('https:/') && !base.startsWith('https://'))
    base = base.replaceFirst('https:/', 'https://');

  // If scheme missing, prepend https://
  if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(base))
    base = 'https://$base';

  // Collapse repeated scheme prefixes like 'https://https://example.com'
  try {
    final m = RegExp(r'^(https?://)+', caseSensitive: false).firstMatch(base);
    if (m != null) {
      final prefix = m.group(0) ?? '';
      if (base.toLowerCase().startsWith('https'))
        base = base.replaceFirst(prefix, 'https://');
      else
        base = base.replaceFirst(prefix, 'http://');
    }
  } catch (_) {}

  // Normalize duplicate slashes after the scheme
  try {
    final parts = base.split('://');
    if (parts.length >= 2) {
      final scheme = parts[0];
      var rest = parts.sublist(1).join('://');
      rest = rest.replaceAll(RegExp(r'/{2,}'), '/');
      base = '$scheme://$rest';
    }
  } catch (_) {}

  // Remove trailing slashes
  base = base.replaceAll(RegExp(r'/+$'), '');

  return base;
}

String? _toAbsoluteImageUrl(dynamic candidate) {
  try {
    if (candidate == null) return null;
    if (candidate is String) {
      final s = candidate.trim();
      if (s.isEmpty) return null;
      if (s.startsWith('http://') || s.startsWith('https://')) return s;
      final base = _normalizeBaseUrl(API_BASE_URL);
      if (s.startsWith('/')) return '$base$s';
      return '$base/$s';
    }
    if (candidate is Map) {
      for (final k in ['url', 'src', 'path', 'imageUrl']) {
        final v = candidate[k];
        final res = _toAbsoluteImageUrl(v);
        if (res != null) return res;
      }
    }
  } catch (_) {}
  return null;
}

bool _isWidgetPayloadRich([dynamic wa]) {
  try {
    if (wa == null) return false;
    if (wa is! Map) return false;
    final m = Map<String, dynamic>.from(wa.cast<String, dynamic>());
    for (final k in ['name', 'bio', 'pricing', 'services', 'artisanServices']) {
      if (m.containsKey(k) && m[k] != null) return true;
    }
  } catch (_) {}
  return false;
}

// Safe JSON parser that converts decoded Maps to Map<String, dynamic>
dynamic _safeParseJson(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final parsed = jsonDecode(raw);
    if (parsed is Map)
      return Map<String, dynamic>.from(parsed.cast<String, dynamic>());
    if (parsed is List) {
      return parsed.map((e) {
        if (e is Map)
          return Map<String, dynamic>.from(e.cast<String, dynamic>());
        return e;
      }).toList();
    }
    return parsed;
  } catch (_) {
    return null;
  }
}
