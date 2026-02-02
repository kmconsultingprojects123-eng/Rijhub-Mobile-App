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
import '../payment_init/payment_init_page_widget.dart';
import '../../utils/app_notification.dart';

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
  // fallback primary color used when theme primary is unavailable
  final Color _defaultPrimaryColor = const Color(0xFFA20025);

  // formerly tracked whether the hire sheet was auto-opened; removed auto-open behavior
  // keep the field removed to avoid unused-field warnings

  // Expose a theme-aware primary color getter (falls back to _defaultPrimaryColor)
  Color get primaryColor =>
      FlutterFlowTheme.of(context).primary ?? _defaultPrimaryColor;

  // New state for live data
  Map<String, dynamic>? _artisanData;
  bool _loading = false;
  String? _errorMessage;

  // --- New state for reviews & reviewer name cache ---
  List<Map<String, dynamic>> _reviews = [];
  bool _loadingReviews = false;
  double? _averageRating;
  int _reviewCount = 0;
  final Map<String, String> _userNameCache = {}; // userId -> display name

  String? _authToken; // cached token to avoid querying storage repeatedly

    @override
    void initState() {
    super.initState();
    // Attempt to load fresh artisan data from server if we have an id
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // prefer explicit userId when present in the widget payload
      final widgetUserId = _widgetUserId();
      final id = _artisanIdFromWidget();
      if (kDebugMode) {
        try { debugPrint('ArtisanDetailPage.initState -> widget.artisan = ${widget.artisan}'); } catch (_) {}
      }
      if (kDebugMode) {
        try { debugPrint('ArtisanDetailPage.initState -> resolved artisanId from widget: $id'); } catch (_) {}
      }
      // Kick off a short initialization that fetches the token and then loads artisan + reviews in parallel
      _unawaited(_initializePage(id, widgetUserId: widgetUserId));
    });
    }

    // Initialization sequence: get token once then concurrently fetch artisan and reviews
    Future<void> _initializePage(String? id, {String? widgetUserId}) async {
    try {
      _authToken = await TokenStorage.getToken();
    } catch (_) {
      _authToken = null;
    }
    if (id != null && id.isNotEmpty) {
      // Fetch canonical artisan profile only if this id looks like an artisan document id (i.e. top-level _id/id present on widget.artisan)
      bool looksLikeArtisanId = false;
      try {
        final wa = widget.artisan;
        if (wa is Map) {
          if (wa.containsKey('_id') || wa.containsKey('id') || wa.containsKey('artisanId')) looksLikeArtisanId = true;
        }
      } catch (_) {}

      if (looksLikeArtisanId) {
        // Fetch the canonical artisan profile in background so the UI can render immediately with the passed payload.
        _unawaited(_fetchArtisanById(id, token: _authToken));
      }

      // For reviews and other user-scoped operations prefer an explicit userId when present (from Discover).
      // Defer loading reviews briefly to improve first-contentful-paint and reduce blocking network work.
      final resolvedForReviews = (widgetUserId != null && widgetUserId.isNotEmpty) ? widgetUserId : (_resolvedArtisanId() ?? id);
      _unawaited(Future.delayed(const Duration(milliseconds: 400), () => _loadReviewsForArtisan(resolvedForReviews, token: _authToken)));
    }
    }

    // Helper: prefer an explicit userId passed in the original widget.artisan payload
    String? _widgetUserId() {
    try {
      final wa = widget.artisan;
      if (wa is Map) {
        // explicit fields
        final uid = (wa['userId'] ?? wa['user_id'])?.toString();
        if (uid != null && uid.isNotEmpty) return uid;
        // nested user object
        if (wa['user'] is Map) {
          final u = wa['user'] as Map<String, dynamic>;
          final nu = (u['_id'] ?? u['id'])?.toString();
          if (nu != null && nu.isNotEmpty) return nu;
        }
      }
    } catch (_) {}
    return null;
    }

  // Helper to determine which artisan data to use (fetched or passed-in)
  Map<String, dynamic> get _artisan => _artisanData ?? widget.artisan;

    // Extract a possible artisan id from the provided map
    String? _artisanIdFromWidget() {
    try {
      final m = _coerceToMap(widget.artisan);
      if (m == null) return null;
      // prefer artisan document identifiers for fetching artisan profile
      final candidates = ['_id', 'id', 'artisanId', 'userId'];
      for (final k in candidates) {
        if (m.containsKey(k) && m[k] != null) return m[k].toString();
      }
      // Fallback: try to find any nested id-like field (user/customer/_id) within the provided object
      try {
        final nested = _findUserReferenceId(widget.artisan);
        if (nested != null && nested.isNotEmpty) return nested;
      } catch (_) {}
    } catch (_) {}
    return null;
    }

  Future<void> _loadArtisanDataIfNeeded() async {
    final id = _artisanIdFromWidget();
    if (id == null) return; // nothing to fetch
    // If already have full data (e.g. name & pricing) skip refetch unless you want fresh
    if (_artisanData != null) return;

    await _fetchArtisanById(id);
  }

  Future<void> _fetchArtisanById(String id, {String? token}) async {
    // Use provided token or cached _authToken
    token ??= _authToken;
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      // Normalize base URL (ensure scheme present and no trailing slash)
      final base = _normalizeBaseUrl(API_BASE_URL);
      final uri = Uri.parse('$base/api/artisans/$id');
      final headers = <String, String>{'Accept': 'application/json'};
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      final resp = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 12));

      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        if (body is Map && (body['success'] == true || body.containsKey('data'))) {
          final data = body['data'] ?? body;
          if (data is Map) {
            if (!mounted) return;
            setState(() {
              _artisanData = Map<String, dynamic>.from(data.cast<String, dynamic>());
            });
            // Attempt to synchronously fetch referenced user name (await so UI updates quickly)
            try {
              String? refUserId;
              final artMap = Map<String, dynamic>.from(data.cast<String, dynamic>());
              final refCandidates = ['user', 'userId', 'owner', 'createdBy'];
              for (final k in refCandidates) {
                final v = artMap[k];
                if (v == null) continue;
                if (v is Map && v['_id'] != null) {
                  refUserId = v['_id'].toString();
                  break;
                }
                if (v is String && v.isNotEmpty) {
                  refUserId = v;
                  break;
                }
              }
            if (refUserId != null && refUserId.isNotEmpty) {
                // Fetch referenced user display name in background; don't await to avoid delaying profile render.
                _unawaited(_fetchUserById(refUserId, token: token).then((name) {
                  if (name != null && name.isNotEmpty && mounted) {
                    setState(() {
                      _userNameCache[refUserId!] = name;
                      // also set canonical name on artisan data so _extractName can return it immediately
                      if (_artisanData != null &&
                          (_artisanData!['name'] == null ||
                              _artisanData!['name'].toString().trim().isEmpty)) {
                        _artisanData!['name'] = name;
                      }
                    });
                  }
                }));
              }
            } catch (_) {}
            return;
          }
        }
        // Unexpected payload
        final pretty = resp.body;
        setState(() {
          _errorMessage = 'Unable to load artisan details.';
        });
        debugPrint('Artisan fetch unexpected response: ${resp.statusCode} $pretty');
      } else if (resp.statusCode == 404) {
        setState(() {
          _errorMessage = 'Artisan profile not found.';
        });
      } else if (resp.statusCode == 401) {
        setState(() {
          _errorMessage = 'Authentication failed. Please sign in again.';
        });
      } else {
        String msg = 'Failed to load artisan (code ${resp.statusCode}).';
        try {
          final body = jsonDecode(resp.body);
          if (body is Map && body['message'] != null) {
            msg = body['message'].toString();
          }
        } catch (_) {}
        setState(() {
          _errorMessage = msg;
        });
      }
    } on TimeoutException {
      setState(() {
        _errorMessage = 'Network timeout while loading artisan details.';
      });
    } catch (e, st) {
      debugPrint('Error fetching artisan: $e\n$st');
      setState(() {
        _errorMessage = 'An unexpected error occurred while loading artisan details.';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  /// Load reviews for an artisan using ArtistService.fetchReviewsForArtisan and compute average
  Future<void> _loadReviewsForArtisan(String artisanId, {String? token}) async {
    // use cached token if available
    token ??= _authToken;
    if (artisanId.isEmpty) return;
    setState(() {
      _loadingReviews = true;
      _reviews = [];
      _averageRating = null;
      _reviewCount = 0;
    });
    try {
      // Fetch reviews using ArtistService which may itself need token - if ArtistService supports passing token, update accordingly.
      // Load a small initial page of reviews to speed up the first load; provide a 'load more' UI later if needed.
      final fetched = await ArtistService.fetchReviewsForArtisan(artisanId, page: 1, limit: 10);
      if (kDebugMode) {
        try { debugPrint('ArtisanDetailPage._loadReviewsForArtisan -> requested artisanId=$artisanId fetchedCount=${fetched.length}'); } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _reviews = fetched;
        _reviewCount = fetched.length;
      });
      // Prefetch reviewer names in parallel (bounded)
      try {
        final ids = <String>{};
        // Limit the number of prefetches to avoid long parallel waits on many reviewers; pick first 10 unique ids.
        int prefetchCount = 0;
        for (final r in fetched) {
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
          if (idStr.isNotEmpty && !_userNameCache.containsKey(idStr) && prefetchCount < 10) {
            ids.add(idStr);
            prefetchCount++;
          }
        }
        // Launch parallel fetches and await them so the cache fills sooner (fire-and-forget overall)
        final futures = ids.map((id) => _fetchUserById(id, token: token));
        _unawaited(Future.wait(futures).then((results) {
          if (!mounted) return;
          final updates = <String, String>{};
          int i = 0;
          for (final id in ids) {
            final name = results.elementAt(i++);
            if (name != null && name.isNotEmpty) {
              updates[id] = name;
            }
          }
          if (updates.isNotEmpty) {
            setState(() {
              _userNameCache.addAll(updates);
            });
          }
        }));
      } catch (e) {
        debugPrint('prefetch reviewer names failed: $e');
      }
      // compute average
      double sum = 0;
      int cnt = 0;
      for (final r in fetched) {
        final rv = r['rating'] ?? r['stars'] ?? r['score'];
        final val = rv == null ? null : double.tryParse(rv.toString());
        if (val != null) {
          sum += val;
          cnt++;
        }
      }
      if (cnt > 0) {
        final avg = (sum / cnt).clamp(0.0, 5.0);
        if (mounted) {
          setState(() {
            _averageRating = avg;
          });
        }
      }
    } catch (e) {
      debugPrint('Failed to load reviews: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loadingReviews = false;
        });
      }
    }
  }

  /// Resolve reviewer display name from a review object. If the review contains a nested user/customer map, use that. Otherwise fetch user by id once and cache the result.
  Future<String> _resolveReviewerName(Map<String, dynamic> review) async {
    try {
      // Common nested keys
      final nestedKeys = ['customer', 'user', 'reviewer', 'author', 'createdBy'];
      for (final k in nestedKeys) {
        if (review[k] is Map) {
          final m = Map<String, dynamic>.from(review[k]);
          final name = (m['name'] ??
              m['fullName'] ??
              m['displayName'] ??
              m['username'])
              ?.toString();
          if (name != null && name.trim().isNotEmpty) return name.trim();
        }
      }

      // Otherwise try id fields
      final idCandidates = [
        'customerId',
        'customer_id',
        'customer',
        'userId',
        'user_id',
        'authorId'
      ];
      for (final k in idCandidates) {
        final v = review[k];
        if (v == null) continue;
        if (v is String && v.isNotEmpty) {
          if (_userNameCache.containsKey(v)) return _userNameCache[v]!;
          final name = await _fetchUserById(v);
          if (name != null && name.isNotEmpty) {
            _userNameCache[v] = name;
            return name;
          }
        }
        if (v is Map && v['_id'] != null) {
          final id = v['_id'].toString();
          if (_userNameCache.containsKey(id)) return _userNameCache[id]!;
          final name = await _fetchUserById(id);
          if (name != null && name.isNotEmpty) {
            _userNameCache[id] = name;
            return name;
          }
        }
      }
    } catch (e) {
      debugPrint('resolveReviewerName failed: $e');
    }
    return 'User';
  }

  /// Fetch a user record by id (simple helper local to this page). Returns display name or null.
  Future<String?> _fetchUserById(String id, {String? token}) async {
    if (id.isEmpty) return null;
    // use cached token unless one is explicitly provided
    token ??= _authToken;
    try {
      final base = _normalizeBaseUrl(API_BASE_URL);
      final uri = Uri.parse('$base/api/users/$id');
      final headers = <String, String>{'Accept': 'application/json'};
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
      final resp = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode >= 200 && resp.statusCode < 300 && resp.body.isNotEmpty) {
        final body = jsonDecode(resp.body);
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
          if (name != null && name.trim().isNotEmpty) return name.trim();
        }
      }
    } catch (e) {
      debugPrint('fetchUserById error: $e');
    }
    return null;
  }

  /// Helper to intentionally ignore a Future and attach an error handler to avoid unhandled exceptions.
  void _unawaited(Future<dynamic> f) {
    try {
      f.catchError((_) {});
    } catch (_) {}
  }

  // Recursively search a node for a potential user reference id (Map with _id or plain id string)
  String? _findUserReferenceId(dynamic node) {
    try {
      if (node == null) return null;
      if (node is Map) {
        // direct id fields
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
        // common nested user object
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
        // descend into map values
        for (final v in node.values) {
          final found = _findUserReferenceId(v);
          if (found != null && found.isNotEmpty) return found;
        }
      } else if (node is List) {
        for (final e in node) {
          final found = _findUserReferenceId(e);
          if (found != null && found.isNotEmpty) return found;
        }
      }
    } catch (e) {
      debugPrint('findUserReferenceId error: $e');
    }
    return null;
  }

  String _extractName(Map<String, dynamic> src) {
    try {
      // 1) direct top-level name fields
      final top = src['name'];
      if (top != null && top.toString().trim().isNotEmpty) {
        return top.toString().trim();
      }

      // 2) known nested auth details
      final authKeys = [
        'artisanAuthDetails',
        'artisanAuthdDetails',
        'artisanAuthdetails',
        'artisan_auth_details'
      ];
      for (final k in authKeys) {
        final a = src[k];
        if (a is Map &&
            a['name'] != null &&
            a['name'].toString().trim().isNotEmpty) {
          return a['name'].toString().trim();
        }
      }

      // 3) common nested user object names
      final possibleKeys = ['user', 'userId', 'owner', 'artisan', 'artisanUser'];
      for (final k in possibleKeys) {
        final p = src[k];
        if (p is Map &&
            p['name'] != null &&
            p['name'].toString().trim().isNotEmpty) {
          return p['name'].toString().trim();
        }
      }

      // 4) Try to resolve from referenced user id using cache, otherwise find recursively and kick off background fetch and show a loading label
      try {
        String? id = _findUserReferenceId(src);
        if (id != null && id.isNotEmpty) {
          if (_userNameCache.containsKey(id)) return _userNameCache[id]!;
          _unawaited(_fetchUserById(id).then((n) {
            if (n != null && n.isNotEmpty && mounted) {
              setState(() {
                _userNameCache[id!] = n;
              });
            }
          }));
          return 'Loading...';
        }
      } catch (_) {}
    } catch (_) {}
    return 'Unknown';
  }

  String? _extractProfileImage(Map<String, dynamic> src) {
    try {
      // First, check common direct image fields
      final directKeys = [
        'profilePicture',
        'profileImage',
        'avatar',
        'photo',
        'image'
      ];
      for (final k in directKeys) {
        final value = src[k];
        final url = _toAbsoluteImageUrl(value);
        if (url != null) return url;
      }

      // Check nested structures
      if (src['user'] is Map) {
        final user = src['user'];
        for (final k in directKeys) {
          final value = user[k];
          final url = _toAbsoluteImageUrl(value);
          if (url != null) return url;
        }
      }

      // Check profileImage as a Map
      if (src['profileImage'] is Map) {
        final profileImage = src['profileImage'];
        final urlKeys = ['url', 'src', 'path', 'imageUrl'];
        for (final k in urlKeys) {
          final value = profileImage[k];
          final url = _toAbsoluteImageUrl(value);
          if (url != null) return url;
        }
      }

      // Check portfolio for any image
      if (src['portfolio'] is List && (src['portfolio'] as List).isNotEmpty) {
        final firstPortfolio = src['portfolio'][0];
        if (firstPortfolio is Map) {
          if (firstPortfolio['images'] is List &&
              (firstPortfolio['images'] as List).isNotEmpty) {
            final firstImage = (firstPortfolio['images'] as List)[0];
            final url = _toAbsoluteImageUrl(firstImage);
            if (url != null) return url;
          }
        }
      }
    } catch (e) {
      debugPrint('Error extracting profile image: $e');
    }
    return null;
  }

  // New helper: derive a user-friendly location string from the artisan record (tries many common keys)
  String _displayLocation() {
    final src = _artisan;
    try {
      // common direct fields
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

      // nested user/profile fields
      if (src['user'] is Map) {
        final u = src['user'] as Map<String, dynamic>;
        for (final k in ['location', 'city', 'address', 'state', 'area', 'region']) {
          final v = u[k];
          if (v != null && v.toString().trim().isNotEmpty) {
            return v.toString().trim();
          }
        }
        // the user may have an address object
        if (u['address'] is Map) {
          final a = u['address'] as Map<String, dynamic>;
          final parts = <String>[];
          for (final k in ['city', 'town', 'state', 'lga', 'area', 'country']) {
            final v = a[k];
            if (v != null && v.toString().trim().isNotEmpty) {
              parts.add(v.toString().trim());
            }
          }
          if (parts.isNotEmpty) return parts.join(', ');
        }
      }

      // try to find address in nested structures
      final possible = _findKey(src, ['location', 'address', 'city', 'state', 'area']);
      if (possible != null) {
        if (possible is String) {
          final s = possible.trim();
          if (s.isNotEmpty) return s;
        } else if (possible is Map) {
          final parts = <String>[];
          for (final k in ['city', 'town', 'state', 'lga', 'area', 'country', 'address']) {
            final v = possible[k];
            if (v != null && v.toString().trim().isNotEmpty) {
              parts.add(v.toString().trim());
            }
          }
          if (parts.isNotEmpty) return parts.join(', ');
        } else if (possible is List && possible.isNotEmpty) {
          final first = possible[0];
          if (first != null && first.toString().trim().isNotEmpty) {
            return first.toString().trim();
          }
        }
      }
    } catch (e) {
      debugPrint('displayLocation error: $e');
    }
    return 'Not specified';
  }

  Widget _buildInfoItem(dynamic icon, String title, String value) {
    final theme = FlutterFlowTheme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor,
          width: 1,
        ),
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
            // Accept either an IconData or a Widget for flexibility (e.g., Naira text)
            child: (icon is IconData)
                ? Icon(icon, size: 20, color: primaryColor)
                : Center(child: icon as Widget),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.bodySmall.copyWith(
                    color: theme.secondaryText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: theme.bodyMedium.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewItem(
      String reviewerName, String review, double rating, String date) {
    final theme = FlutterFlowTheme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).dividerColor,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    reviewerName.isNotEmpty
                        ? reviewerName[0].toUpperCase()
                        : 'U',
                    style: TextStyle(
                      color: primaryColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reviewerName,
                      style: theme.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        ...List.generate(5, (index) {
                          return Icon(
                            index < rating.floor()
                                ? Icons.star
                                : Icons.star_border,
                            size: 16,
                            color: Colors.amber,
                          );
                        }),
                        const SizedBox(width: 8),
                        Text(
                          date,
                          style: theme.bodySmall.copyWith(
                            color: theme.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            review,
            style: theme.bodyMedium.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.85),
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // Recursive helper to find the first matching key in nested Maps/Lists.
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

  // Safely coerce a dynamic decoded JSON value into a Map<String,dynamic> if possible
  Map<String, dynamic>? _coerceToMap(dynamic v) {
    try {
      if (v == null) return null;
      if (v is Map) return Map<String, dynamic>.from(v.cast<String, dynamic>());
    } catch (_) {}
    return null;
  }

  // Theme helpers to make colors adapt to light/dark mode
  Color _surfaceColor() => Theme.of(context).colorScheme.surface;
  Color _borderColor() => Theme.of(context).dividerColor;
  Color _onSurface([double opacity = 1.0]) =>
      Theme.of(context).colorScheme.onSurface.withOpacity(opacity);

  // Get appropriate text color based on theme
  Color _textColor([double opacity = 1.0]) =>
      Theme.of(context).colorScheme.onSurface.withOpacity(opacity);

  // Get secondary text color based on theme
  Color _secondaryTextColor() =>
      Theme.of(context).colorScheme.onSurface.withOpacity(0.7);

  Future<void> _showHireSheet(BuildContext ctx) async {
    final artisan = _artisan;
    final TextEditingController _priceCtrl = TextEditingController();
    final TextEditingController _scheduleCtrl = TextEditingController();
    DateTime? _selectedDate;
    bool _submitting = false;
    bool _showDateRequiredMessage = false;

    try {
      final pricing =
          artisan['pricing'] ?? artisan['pricingDetails'] ?? artisan['price'];
      if (pricing is Map && pricing['perJob'] != null) {
        _priceCtrl.text = pricing['perJob'].toString();
      }
    } catch (_) {}

    await showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final theme = FlutterFlowTheme.of(context);

            String displayPriceNumeric = '';
            try {
              final pricing =
                  artisan['pricing'] ?? artisan['pricingDetails'] ?? artisan['price'];
              if (pricing is Map && pricing['perJob'] != null) {
                displayPriceNumeric = NumberFormat('#,##0', 'en_US').format(
                    num.tryParse(pricing['perJob'].toString()) ?? 0);
                _priceCtrl.text = pricing['perJob'].toString();
              } else if (pricing != null && pricing.toString().isNotEmpty) {
                displayPriceNumeric = NumberFormat('#,##0', 'en_US')
                    .format(num.tryParse(pricing.toString()) ?? 0);
                _priceCtrl.text = pricing.toString();
              }
            } catch (_) {}

            final confirmLabel = displayPriceNumeric.isNotEmpty
                ? 'Pay ₦$displayPriceNumeric'
                : 'Confirm & Pay';

            return GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                  top: MediaQuery.of(context).padding.top,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Dismissible area
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          color: Colors.transparent,
                        ),
                      ),
                    ),

                    // Bottom Sheet Content
                    Container(
                      decoration: BoxDecoration(
                        color: _surfaceColor(),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(24),
                          topRight: Radius.circular(24),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.12),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Drag indicator
                              Container(
                                width: 40,
                                height: 4,
                                margin: const EdgeInsets.only(bottom: 24),
                                decoration: BoxDecoration(
                                  color: _borderColor(),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),

                              // Header
                              Row(
                                children: [
                                  Container(
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      color: primaryColor.withOpacity(0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Icon(
                                        Icons.calendar_today_outlined,
                                        color: primaryColor,
                                        size: 28,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Book ${_displayName()}',
                                          style: theme.titleLarge?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 22,
                                            color: _onSurface(1.0),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Select a date to schedule your service',
                                          style: theme.bodyLarge?.copyWith(
                                            color: _onSurface(0.7),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 32),

                              // Date Picker with improved UX
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Instruction text
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8.0, left: 4),
                                    child: Row(
                                      children: [
                                        Text(
                                          'Select Service Date',
                                          style: theme.bodyMedium.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: _onSurface(0.9),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '*',
                                          style: theme.bodyMedium.copyWith(
                                            color: Colors.red,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Date picker box
                                  GestureDetector(
                                    onTap: () async {
                                      final now = DateTime.now();
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: now.add(const Duration(days: 1)),
                                        firstDate: now,
                                        lastDate:
                                        now.add(const Duration(days: 365)),
                                        builder: (context, child) {
                                          // Adapt the date picker colors to current brightness so
                                          // text is readable in both light and dark themes.
                                          final theme = Theme.of(context);
                                          final isDark = theme.brightness == Brightness.dark;
                                          final cs = isDark
                                              ? ColorScheme.dark(
                                                  primary: primaryColor,
                                                  onPrimary: Colors.white,
                                                  surface: _surfaceColor(),
                                                  onSurface: _onSurface(1.0),
                                                )
                                              : ColorScheme.light(
                                                  primary: primaryColor,
                                                  onPrimary: Colors.white,
                                                  surface: _surfaceColor(),
                                                  onSurface: _onSurface(1.0),
                                                );

                                          return Theme(
                                            data: theme.copyWith(
                                              colorScheme: cs,
                                              dialogBackgroundColor: _surfaceColor(),
                                              // Ensure button/text colors inside the dialog adapt
                                              textButtonTheme: TextButtonThemeData(
                                                style: TextButton.styleFrom(
                                                  foregroundColor: primaryColor,
                                                ),
                                              ),
                                            ),
                                            child: child!,
                                          );
                                        },
                                      );
                                      if (picked != null) {
                                        if (context.mounted) {
                                          setState(() {
                                            _selectedDate = picked;
                                            _scheduleCtrl.text = DateFormat(
                                                'EEE, MMM d, yyyy')
                                                .format(picked.toLocal());
                                            _showDateRequiredMessage = false;
                                          });
                                        }
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: _selectedDate != null
                                            ? Colors.green.withOpacity(0.05)
                                            : Theme.of(context)
                                            .colorScheme
                                            .surfaceVariant ??
                                            _surfaceColor(),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: _selectedDate != null
                                              ? Colors.green.withOpacity(0.5)
                                              : (_showDateRequiredMessage
                                              ? Colors.red.withOpacity(0.5)
                                              : _borderColor()),
                                          width: _selectedDate != null || _showDateRequiredMessage ? 2 : 1.5,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.calendar_month_outlined,
                                            color: _selectedDate != null
                                                ? Colors.green
                                                : (_showDateRequiredMessage
                                                ? Colors.red
                                                : Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withOpacity(0.6)),
                                            size: 24,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Tap to select date',
                                                  style: theme.bodySmall.copyWith(
                                                    color: _selectedDate != null
                                                        ? Colors.green
                                                        : (_showDateRequiredMessage
                                                        ? Colors.red.withOpacity(0.8)
                                                        : theme.secondaryText),
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  _selectedDate != null
                                                      ? _scheduleCtrl.text
                                                      : 'No date selected',
                                                  style: theme.bodyLarge?.copyWith(
                                                    fontWeight: FontWeight.w500,
                                                    color: _selectedDate != null
                                                        ? _onSurface(1.0)
                                                        : _onSurface(0.5),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (_selectedDate != null)
                                            Icon(
                                              Icons.check_circle,
                                              color: Colors.green,
                                              size: 22,
                                            ),
                                          if (_showDateRequiredMessage && _selectedDate == null)
                                            Icon(
                                              Icons.error_outline,
                                              color: Colors.red,
                                              size: 22,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),

                                  // Helper/Error message
                                  if (_showDateRequiredMessage && _selectedDate == null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6.0, left: 4),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.info_outline,
                                            color: Colors.red,
                                            size: 14,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Please select a date to proceed',
                                            style: theme.bodySmall.copyWith(
                                              color: Colors.red,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                  // Success message when date is selected
                                  if (_selectedDate != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6.0, left: 4),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.check_circle_outline,
                                            color: Colors.green,
                                            size: 14,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Date selected! You can now proceed to payment',
                                            style: theme.bodySmall.copyWith(
                                              color: Colors.green,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),

                              const SizedBox(height: 24),

                              // Price Display
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceVariant ??
                                      _surfaceColor(),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _borderColor(),
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: Colors.green.withOpacity(0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Text(
                                          '₦',
                                          style: TextStyle(
                                            color: Colors.green,
                                            fontSize: 20,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Service Price',
                                            style: theme.bodySmall.copyWith(
                                              color: theme.secondaryText,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            displayPriceNumeric.isNotEmpty
                                                ? '₦$displayPriceNumeric'
                                                : 'Price not available',
                                            style: theme.titleMedium?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 20,
                                              color: _onSurface(1.0),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (displayPriceNumeric.isNotEmpty)
                                      // Show Naira symbol instead of the default dollar icon
                                      Text(
                                        '₦',
                                        style: TextStyle(
                                          color: Colors.green,
                                          fontSize: 20,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                  ],
                                ),
                              ),

                              // Progress indicator/status message
                              const SizedBox(height: 24),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _selectedDate != null
                                      ? Colors.green.withOpacity(0.05)
                                      : Colors.orange.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _selectedDate != null
                                        ? Colors.green.withOpacity(0.2)
                                        : Colors.orange.withOpacity(0.2),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _selectedDate != null
                                          ? Icons.check_circle_outline
                                          : Icons.schedule_outlined,
                                      color: _selectedDate != null
                                          ? Colors.green
                                          : Colors.orange,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _selectedDate != null
                                            ? 'Ready to proceed! All requirements are met.'
                                            : 'Step 1: Select a service date to continue',
                                        style: theme.bodyMedium.copyWith(
                                          color: _selectedDate != null
                                              ? Colors.green
                                              : Colors.orange,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 32),

                              // Action Buttons
                              Column(
                                children: [
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _selectedDate != null
                                            ? primaryColor
                                            : Colors.grey,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 18),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                          BorderRadius.circular(14),
                                        ),
                                        elevation: _selectedDate != null ? 2 : 0,
                                        shadowColor: _selectedDate != null
                                            ? primaryColor.withOpacity(0.3)
                                            : Colors.transparent,
                                      ),
                                      onPressed: _submitting
                                          ? null
                                          : () async {
                                        if (_selectedDate == null) {
                                          // Show error message and animate the date picker
                                          setState(() {
                                            _showDateRequiredMessage = true;
                                          });
                                          // Optional: Add a shake animation effect
                                          await Future.delayed(const Duration(milliseconds: 300));
                                          setState(() {
                                            _showDateRequiredMessage = true;
                                          });
                                          return;
                                        }

                                        // Payment logic here (same as original)
                                        final pText =
                                        _priceCtrl.text.trim();
                                        if (pText.isEmpty ||
                                            num.tryParse(pText) == null) {
                                          AppNotification.showError(
                                              context, 'Invalid price');
                                          return;
                                        }
                                        if (context.mounted) {
                                          setState(
                                                  () => _submitting = true);
                                        }
                                        final token =
                                        await TokenStorage.getToken();
                                        if (token == null ||
                                            token.isEmpty) {
                                          if (context.mounted) {
                                            setState(() =>
                                            _submitting = false);
                                          }
                                          Navigator.of(context).pop();
                                          AppNotification.showError(
                                              context,
                                              'You must be logged in to hire an artisan');
                                          return;
                                        }

                                        // Payment initialization: call the documented server endpoint
                                        // POST /api/bookings/hire -- server will create a Booking and initialize payment
                                        // See `API_DOCS (2).md` — POST /api/bookings/hire: "create a booking and initialize process (protected)".
                                        // Required body keys (per docs): `artisanId`, `schedule`, `price`, `email`.
                                        final base = _normalizeBaseUrl(API_BASE_URL);
                                        final uri = Uri.parse('$base/api/bookings/hire');
                                        final headers = {
                                          'Content-Type': 'application/json',
                                          'Authorization': 'Bearer $token',
                                        };

                                        String? userEmail;
                                        try {
                                          final profile =
                                          await UserService
                                              .getProfile();
                                          if (profile != null) {
                                            if (profile['email']
                                            is String &&
                                                (profile['email']
                                                as String)
                                                    .contains('@')) {
                                              userEmail =
                                              profile['email']
                                              as String;
                                            } else if (profile['user']
                                            is Map &&
                                                profile['user']['email']
                                                is String) {
                                              userEmail = profile['user']
                                              ['email'] as String;
                                            } else if (profile['data']
                                            is Map &&
                                                profile['data']['email']
                                                is String) {
                                              userEmail = profile['data']
                                              ['email'] as String;
                                            }
                                          }
                                        } catch (_) {
                                          userEmail = null;
                                        }

                                        final parsedPrice = num.tryParse(
                                            pText.toString().replaceAll(
                                                RegExp(r'[^0-9.-]'),
                                                '')) ??
                                            0;
                                        final body = <String, dynamic>{
                                          'artisanId': artisan['userId'] ??
                                              artisan['_id'] ??
                                              artisan['id'],
                                          'schedule': _selectedDate!
                                              .toUtc()
                                              .toIso8601String(),
                                          'price': parsedPrice,
                                          'amount': parsedPrice,
                                        };

                                        if (userEmail != null &&
                                            userEmail.contains('@')) {
                                          body['email'] = userEmail;
                                        } else {
                                          try {
                                            final prof = await UserService
                                                .getProfile();
                                            final e1 = prof?['email'] ??
                                                prof?['contact'] ??
                                                prof?['username'];
                                            if (e1 != null &&
                                                e1.toString().contains(
                                                    '@')) {
                                              body['email'] =
                                                  e1.toString();
                                            }
                                          } catch (_) {}
                                          if (body['email'] == null) {
                                            try {
                                              final e2 = (artisan[
                                              'email'] ??
                                                  (artisan['user']
                                                  is Map
                                                      ? artisan['user']
                                                  ['email']
                                                      : null));
                                              if (e2 != null &&
                                                  e2.toString().contains(
                                                      '@')) {
                                                body['email'] =
                                                    e2.toString();
                                              }
                                            } catch (_) {}
                                          }
                                        }

                                        try {
                                          final resp = await http
                                              .post(uri,
                                              headers: headers,
                                              body: jsonEncode(body))
                                              .timeout(const Duration(
                                              seconds: 30));
                                          final status = resp.statusCode;
                                          final respBody = resp.body
                                              .isNotEmpty
                                              ? jsonDecode(resp.body)
                                              : null;

                                          if (status >= 200 &&
                                              status < 300 &&
                                              respBody is Map &&
                                              respBody['success'] ==
                                                  true) {
                                            Map<String, dynamic>? dataMap;
                                            try {
                                              if (respBody['data']
                                              is Map) {
                                                dataMap = Map<String,
                                                    dynamic>.from(
                                                    respBody['data']);
                                              }
                                            } catch (_) {
                                              dataMap = null;
                                            }

                                            dynamic paymentNode;
                                            if (dataMap != null) {
                                              paymentNode = dataMap[
                                              'payment'] ??
                                                  dataMap['paymentData'] ??
                                                  dataMap[
                                                  'payment_details'] ??
                                                  dataMap[
                                                  'paymentResponse'] ??
                                                  _findKey(dataMap, [
                                                    'payment',
                                                    'paymentData',
                                                    'payment_details',
                                                    'payment_response'
                                                  ]);
                                            }
                                            paymentNode ??= _findKey(
                                                respBody, [
                                              'payment',
                                              'paymentData',
                                              'payment_details',
                                              'payment_response'
                                            ]);

                                            Map<String, dynamic>?
                                            paymentMap;
                                            try {
                                              if (paymentNode is Map) {
                                                paymentMap = Map<String,
                                                    dynamic>.from(
                                                    paymentNode);
                                              }
                                            } catch (_) {
                                              paymentMap = null;
                                            }

                                            String? authUrl;
                                            if (paymentMap != null) {
                                              authUrl = (paymentMap[
                                              'authorization_url'] ??
                                                  paymentMap[
                                                  'authorizationUrl'] ??
                                                  paymentMap[
                                                  'auth_url'] ??
                                                  paymentMap['url'] ??
                                                  paymentMap[
                                                  'access_url'])
                                                  ?.toString();
                                            }

                                            if (ctx.mounted) {
                                              Navigator.of(ctx).pop();
                                            }

                                            if (authUrl != null &&
                                                authUrl.isNotEmpty) {
                                              try {
                                                final paymentPayload =
                                                    paymentMap ??
                                                        dataMap ??
                                                        _coerceToMap(
                                                            respBody);
                                                if (ctx.mounted &&
                                                    paymentPayload !=
                                                        null) {
                                                  // Try to collect bookingId and threadId from server response so the payment flow
                                                  // can reuse them (avoid double-creation and ensure threadId is passed to BookingPage)
                                                  Map<String, dynamic>? bookingPayload;
                                                  try {
                                                    if (dataMap != null) {
                                                      final bid = (dataMap['_id']?.toString() ?? dataMap['booking']?['_id']?.toString());
                                                      final tid = (dataMap['threadId']?.toString() ?? dataMap['chat']?['_id']?.toString() ?? dataMap['chat']?['id']?.toString());
                                                      bookingPayload = <String, dynamic>{};
                                                      if (bid != null && bid.isNotEmpty) bookingPayload['_id'] = bid;
                                                      if (tid != null && tid.isNotEmpty) bookingPayload['threadId'] = tid;
                                                      if (dataMap['chat'] is Map) bookingPayload['chat'] = dataMap['chat'];
                                                    }
                                                  } catch (_) { bookingPayload = null; }

                                                  // If the payload is quote-based, explicitly tag it so downstream
                                                  // booking creation treats it as a quote flow.
                                                  Map<String, dynamic>? pm;
                                                  try {
                                                    pm = paymentPayload is Map ? Map<String, dynamic>.from(paymentPayload) : null;
                                                    if (pm != null) {
                                                      final hasQuote = (pm['quoteId'] != null || pm['acceptedQuote'] != null || (dataMap != null && dataMap['acceptedQuote'] != null));
                                                      if (hasQuote) {
                                                        final meta = pm['metadata'] is Map ? Map<String, dynamic>.from(pm['metadata']) : <String, dynamic>{};
                                                        meta['bookingSource'] = meta['bookingSource'] ?? 'quote';
                                                        pm['metadata'] = meta;
                                                        pm['bookingSource'] = pm['bookingSource'] ?? 'quote';
                                                      }
                                                    }
                                                  } catch (_) { pm = null; }

                                                  final effectivePaymentPayload = pm ?? paymentPayload;

                                                  Navigator.of(ctx).push(
                                                      MaterialPageRoute(
                                                        builder: (_) =>
                                                            PaymentInitPageWidget(
                                                              payment: effectivePaymentPayload,
                                                              booking: bookingPayload,
                                                              // include the parsedPrice so PaymentInitPageWidget can resolve amount reliably
                                                              // include artisanId so the post-payment booking creation knows which artisan to hire
                                                              quote: {
                                                                'amount': parsedPrice,
                                                                'price': parsedPrice,
                                                                'total': parsedPrice,
                                                                'artisanId': artisan['userId'] ?? artisan['_id'] ?? artisan['id'],
                                                              },
                                                            ),
                                                      ));
                                                }
                                              } catch (_) {
                                                if (ctx.mounted) {
                                                  ScaffoldMessenger.of(
                                                      ctx)
                                                      .showSnackBar(
                                                    const SnackBar(
                                                        content: Text(
                                                            'Proceed to payment')),
                                                  );
                                                }
                                                return;
                                              }
                                              return;
                                            }
                                            if (ctx.mounted) {
                                              ScaffoldMessenger.of(ctx)
                                                  .showSnackBar(
                                                const SnackBar(
                                                    content: Text(
                                                        'Proceed to payment')),
                                              );
                                            }
                                            return;
                                          } else {
                                            final msg = (respBody is Map &&
                                                respBody['message'] !=
                                                    null)
                                                ? respBody['message']
                                                .toString()
                                                : 'Failed to create booking (HTTP ${status})';
                                            if (ctx.mounted) {
                                              ScaffoldMessenger.of(ctx)
                                                  .showSnackBar(
                                                SnackBar(
                                                    content: Text(msg)),
                                              );
                                            }
                                          }
                                        } on TimeoutException catch (e) {
                                          if (ctx.mounted) {
                                            ScaffoldMessenger.of(ctx)
                                                .showSnackBar(
                                              SnackBar(
                                                content: const Text(
                                                    'Request timed out. Please check your network and try again.'),
                                                action:
                                                SnackBarAction(
                                                  label: 'Retry',
                                                  onPressed: () {
                                                    if (ctx.mounted) {
                                                      Navigator.of(ctx)
                                                          .pop();
                                                      Future.delayed(
                                                          const Duration(
                                                              milliseconds:
                                                              200),
                                                              () {
                                                            if (mounted) {
                                                              _showHireSheet(
                                                                  context);
                                                            }
                                                          });
                                                    }
                                                  },
                                                ),
                                              ),
                                            );
                                          }
                                        } catch (e) {
                                          if (ctx.mounted) {
                                            ScaffoldMessenger.of(ctx)
                                                .showSnackBar(
                                              SnackBar(
                                                  content: Text(
                                                      'Error creating booking: $e')),
                                            );
                                          }
                                        } finally {
                                          if (context.mounted) {
                                            setState(() =>
                                            _submitting = false);
                                          }
                                        }
                                      },
                                      child: _submitting
                                          ? SizedBox(
                                        height: 24,
                                        width: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                          : Row(
                                        mainAxisAlignment:
                                        MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            _selectedDate != null
                                                ? Icons.payment_outlined
                                                : Icons.calendar_today_outlined,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            _selectedDate != null
                                                ? confirmLabel
                                                : 'Select Date First',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withOpacity(0.78),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 18),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                          BorderRadius.circular(14),
                                        ),
                                        side: BorderSide(
                                          color: _borderColor(),
                                          width: 1.5,
                                        ),
                                      ),
                                      onPressed: () => Navigator.of(context).pop(),
                                      child: Text(
                                        'Cancel',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withOpacity(0.78),
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Instruction footer
                                  const SizedBox(height: 16),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                    child: Text(
                                      'You need to select a service date before proceeding to payment',
                                      textAlign: TextAlign.center,
                                      style: theme.bodySmall.copyWith(
                                        color: theme.secondaryText,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Returns the best available display name for the artisan: prefer fetched _artisanData.name, then cached referenced user name, then _extractName fallback.
  String _displayName() {
    final src = _artisan;
    try {
      // 1) prefer explicit name on fetched artisan data
      final explicit =
      (src['name'] ?? src['fullName'] ?? src['displayName']);
      if (explicit != null && explicit.toString().trim().isNotEmpty) {
        return explicit.toString().trim();
      }

      // 2) look for a referenced user id anywhere and see if we have it cached
      final refId = _findUserReferenceId(src);
      if (refId != null && refId.isNotEmpty) {
        if (_userNameCache.containsKey(refId)) return _userNameCache[refId]!;
        // kick off background fetch if not cached
        _unawaited(_fetchUserById(refId).then((n) {
          if (n != null && n.isNotEmpty && mounted) {
            setState(() {
              _userNameCache[refId] = n;
            });
          }
        }));
        return 'Loading...';
      }
    } catch (_) {}
    // Fallback to existing heuristic
    return _extractName(src);
  }

  // New helper to detect whether an artisan (or its referenced user) is KYC/verified.
  bool _isVerified() {
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

      // Common top-level keys
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

      // Nested user object
      if (src['user'] is Map) {
        final u = src['user'] as Map<String, dynamic>;
        for (final k in keys) {
          if (u.containsKey(k) && check(u[k])) return true;
        }
        // sometimes verification info is nested
        final ver =
            u['verification'] ?? u['kyc'] ?? u['verificationStatus'];
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

  // Helper to read a user's trade/profession from common fields
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
        // sometimes under profile or details
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

  // Returns the best-known artisan id from either fetched data or the original widget payload
    String? _resolvedArtisanId() {
    try {
      // Prefer explicit userId when available (we want the user collection id for user-scoped operations like reviews)
      final src = _artisanData ?? widget.artisan;
      if (src is Map) {
        if (src['userId'] != null && src['userId'].toString().isNotEmpty) return src['userId'].toString();
        if (src['user'] is Map) {
          final u = src['user'] as Map<String, dynamic>;
          if ((u['_id'] ?? u['id']) != null) return (u['_id'] ?? u['id']).toString();
        }
        // fallback to artisan document ids
        final candidates = ['_id', 'id', 'artisanId', 'customerId'];
        for (final k in candidates) {
          if (src.containsKey(k) && src[k] != null) return src[k].toString();
        }
      }
      // fallback: search nested structures
      final found = _findUserReferenceId(widget.artisan);
      if (found != null && found.isNotEmpty) return found;
    } catch (_) {}
    return null;
    }

  @override
  Widget build(BuildContext context) {
    final artisan = _artisan;
    final theme = FlutterFlowTheme.of(context);
    final profileImage = _extractProfileImage(artisan);

    // Use MediaQuery for responsive design
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 375;
    final isLargeScreen = screenWidth > 600;

    // Responsive font sizes
    final titleFontSize = isSmallScreen ? 18.0 : (isLargeScreen ? 22.0 : 20.0);
    final bodyFontSize = isSmallScreen ? 14.0 : (isLargeScreen ? 16.0 : 15.0);
    final smallFontSize = isSmallScreen ? 12.0 : (isLargeScreen ? 14.0 : 13.0);

    // Responsive padding
    final horizontalPadding = isSmallScreen ? 16.0 : (isLargeScreen ? 24.0 : 20.0);
    final verticalPadding = isSmallScreen ? 16.0 : (isLargeScreen ? 24.0 : 20.0);

    // Responsive spacing
    final smallSpacing = isSmallScreen ? 8.0 : 12.0;
    final mediumSpacing = isSmallScreen ? 12.0 : 16.0;
    final largeSpacing = isSmallScreen ? 16.0 : 24.0;

    // Responsive image size
    final profileImageSize = isSmallScreen ? 70.0 : (isLargeScreen ? 90.0 : 80.0);

    // Helper function to safely convert any value to string
    String safeToString(dynamic value) {
      if (value == null) return '';
      if (value is String) return value;
      if (value is int || value is double) return value.toString();
      return value.toString();
    }

    // Helper function to safely get string from artisan data
    String safeGetString(String key,
        {String defaultValue = 'Not specified'}) {
      try {
        final value = artisan[key];
        if (value == null) return defaultValue;
        return safeToString(value);
      } catch (_) {
        return defaultValue;
      }
    }

    // Helper function to safely get nested string from artisan data
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

    // If the widget was provided with an id, prefer to fetch the canonical artisan profile
    // in the background; however, if the widget already contains useful artisan data (name, trade, etc.)
    // render immediately to improve perceived speed. Only show a blocking loading screen when the
    // payload is minimal (e.g., contains only an id).
    final providedId = _artisanIdFromWidget();
    final bool widgetHasRichData = _isWidgetPayloadRich(widget.artisan);
    if (providedId != null && _artisanData == null && !widgetHasRichData) {
      // This is a minimal payload (likely only an id) — show a loading / retry state while fetching.
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
                  Text(_errorMessage!, textAlign: TextAlign.center, style: theme.bodyLarge),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () async {
                      setState(() { _loading = true; _errorMessage = null; });
                      await _fetchArtisanById(providedId, token: _authToken);
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
            // Header - Responsive
            Container(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: mediumSpacing),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: _borderColor(),
                    width: 1,
                  ),
                ),
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

            // Inline loading indicator / error banner
            if (_loading)
              LinearProgressIndicator(
                backgroundColor: Colors.transparent,
                color: primaryColor,
                minHeight: 2,
              ),
            if (_errorMessage != null && _errorMessage!.isNotEmpty)
              Container(
                width: double.infinity,
                color: Theme.of(context).colorScheme.error.withOpacity(0.08),
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: smallSpacing),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w600,
                      fontSize: smallFontSize),
                  textAlign: TextAlign.center,
                ),
              ),

            // Content - Responsive
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding, vertical: verticalPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Profile Header - Responsive
                      Container(
                        padding: EdgeInsets.all(mediumSpacing),
                        decoration: BoxDecoration(
                          color: _surfaceColor(),
                          borderRadius: BorderRadius.circular(isSmallScreen ? 16 : 20),
                        ),
                        child: Row(
                          children: [
                            // Profile Image with fallback - Responsive
                            Container(
                              width: profileImageSize,
                              height: profileImageSize,
                              child: ClipOval(
                                child: profileImage != null
                                    ? CachedNetworkImage(
                                  imageUrl: profileImage,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) =>
                                      Container(
                                        color:
                                        primaryColor.withOpacity(0.1),
                                        child: Center(
                                          child: Icon(
                                            Icons.person_outline,
                                            size: isSmallScreen ? 32 : 40,
                                            color: primaryColor
                                                .withOpacity(0.5),
                                          ),
                                        ),
                                      ),
                                  errorWidget: (context, url, error) {
                                    // Fallback to icon if image fails to load
                                    return Container(
                                      color:
                                      primaryColor.withOpacity(0.1),
                                      child: Center(
                                        child: Icon(
                                          Icons.person_outline,
                                          size: isSmallScreen ? 32 : 40,
                                          color: primaryColor
                                              .withOpacity(0.5),
                                        ),
                                      ),
                                    );
                                  },
                                )
                                    : Container(
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
                              ),
                            ),
                            SizedBox(width: mediumSpacing),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Name with verification badge on the same line
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      // Artisan name
                                      Flexible(
                                        child: Text(
                                          _displayName(),
                                          style: theme.headlineSmall
                                              ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            fontSize: titleFontSize,
                                            color: _textColor(1.0),
                                          ),
                                          maxLines: isSmallScreen ? 1 : 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      // Verification badge - closer to the name
                                      if (_isVerified()) ...[
                                        SizedBox(width: isSmallScreen ? 4 : 6),
                                        Container(
                                          padding: EdgeInsets.all(isSmallScreen ? 2 : 3),
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
                                  // Show resolved artisan id for debugging / transparency
                                  const SizedBox(height: 6),
                                  // Show best-effort userId under the name. Prefer the explicit userId passed from Discover, then referenced user id, then resolved artisan id.
                                  Builder(builder: (ctx) {
                                    try {
                                      final src = _artisan;
                                      final wa = widget.artisan;

                                      // 1) Prefer explicit userId passed via Discover (widget.artisan)
                                      String? candidate;
                                      if (wa is Map) {
                                        candidate = (wa['userId'] ?? wa['user_id'])?.toString();
                                        if ((candidate == null || candidate.isEmpty) && wa['user'] is Map) {
                                          final u = wa['user'] as Map<String, dynamic>;
                                          candidate = (u['_id'] ?? u['id'])?.toString();
                                        }
                                      }

                                      // 2) If not found, check current _artisan top-level explicit fields
                                      if (candidate == null || candidate.isEmpty) {
                                        candidate = (src['userId'] ?? src['user_id'])?.toString();
                                        if ((candidate == null || candidate.isEmpty) && src['user'] is Map) {
                                          final u = src['user'] as Map<String, dynamic>;
                                          candidate = (u['_id'] ?? u['id'])?.toString();
                                        }
                                      }

                                      // 3) As a last resort, try to find any referenced id that looks like a user reference
                                      if (candidate == null || candidate.isEmpty) {
                                        final foundRef = _findUserReferenceId(wa) ?? _findUserReferenceId(src);
                                        // avoid returning the artisan's own _id as a 'userId' unless nothing else available
                                        final topId = src['_id']?.toString() ?? src['id']?.toString();
                                        if (foundRef != null && foundRef.isNotEmpty && foundRef != topId) {
                                          candidate = foundRef;
                                        }
                                      }

                                      final displayId = (candidate != null && candidate.isNotEmpty) ? candidate : null;
                                      if (displayId != null) {
                                        return Text(
                                          'User ID: $displayId',
                                          style: theme.bodySmall.copyWith(
                                            color: theme.secondaryText,
                                            fontSize: isSmallScreen ? 11 : 12,
                                          ),
                                        );
                                      }

                                      // If we reach here, show an explicit message that no userId (user collection id) is available.
                                      return Text('User ID: N/A', style: theme.bodySmall.copyWith(color: theme.secondaryText, fontSize: isSmallScreen ? 11 : 12));
                                    } catch (_) {
                                      return Text('User ID: N/A', style: theme.bodySmall.copyWith(color: theme.secondaryText, fontSize: isSmallScreen ? 11 : 12));
                                    }
                                  }),
                                   SizedBox(height: isSmallScreen ? 4 : 6),
                                   // category row + trade pill
                                   Wrap(
                                    spacing: smallSpacing,
                                    runSpacing: isSmallScreen ? 4 : 6,
                                    children: [
                                      // Only show the trade pill; remove the default 'ARTISAN' category text
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
                                            borderRadius: BorderRadius.circular(16),
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
                                  Row(
                                    children: [
                                      // dynamic star display: use _averageRating if available
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

                      // SINGLE Book Now Button - Responsive
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                                vertical: isSmallScreen ? 14 : 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(isSmallScreen ? 10 : 12),
                            ),
                            elevation: 0,
                            shadowColor: Colors.transparent,
                          ),
                          onPressed: () => _showHireSheet(context),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.calendar_today_outlined,
                                  size: isSmallScreen ? 18 : 20),
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

                      // About Section - Responsive
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
                          borderRadius: BorderRadius.circular(isSmallScreen ? 12 : 16),
                          border: Border.all(
                            color: _borderColor(),
                            width: 1.5,
                          ),
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

                      // Info Section - Responsive
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
                          // Location
                          _buildInfoItem(
                            Icons.location_on_outlined,
                            'Location',
                            _displayLocation(),
                          ),
                          SizedBox(height: smallSpacing),
                          // Experience
                          _buildInfoItem(
                            Icons.work_outline,
                            'Experience',
                            safeGetString('experience',
                                defaultValue: safeGetString(
                                    'yearsOfExperience',
                                    defaultValue: 'Not specified')),
                          ),
                          SizedBox(height: smallSpacing),
                          // Pricing
                          _buildInfoItem(
                            // Use a Naira text widget for the pricing icon
                            Text(
                              '₦',
                              style: TextStyle(
                                color: primaryColor,
                                fontWeight: FontWeight.w700,
                                fontSize: isSmallScreen ? 14 : 16,
                              ),
                            ),
                            'Pricing',
                            safeGetNestedString(['pricing', 'perJob'],
                                defaultValue: 'Contact for pricing'),
                          ),
                        ],
                      ),

                      SizedBox(height: largeSpacing),

                      // Reviews Section - Responsive
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
                              padding: EdgeInsets.symmetric(vertical: mediumSpacing),
                              child: Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: primaryColor,
                                ),
                              ),
                            ),
                          ] else if (_reviews.isEmpty) ...[
                            Padding(
                              padding: EdgeInsets.symmetric(vertical: mediumSpacing),
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
                                  reviewDate = DateFormat('MMM d, yyyy')
                                      .format(DateTime.parse(
                                      review['createdAt'].toString()));
                                }
                              } catch (_) {}
                              final reviewRating =
                                  review['rating'] ?? review['stars'] ?? 0;

                              // Prefer common comment fields (API may use comment, review, content, message, or text)
                              final reviewComment = (review['comment'] ?? review['review'] ?? review['content'] ?? review['message'] ?? review['text'] ?? '').toString();

                              return Padding(
                                padding: EdgeInsets.only(bottom: smallSpacing),
                                child: Container(
                                  padding: EdgeInsets.all(mediumSpacing),
                                  decoration: BoxDecoration(
                                    color: _surfaceColor(),
                                    borderRadius: BorderRadius.circular(isSmallScreen ? 12 : 16),
                                    border: Border.all(
                                      color: _borderColor(),
                                      width: 1,
                                    ),
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
                                              color: primaryColor.withOpacity(0.1),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Center(
                                              child: Text(
                                                reviewerName.isNotEmpty
                                                    ? reviewerName[0].toUpperCase()
                                                    : 'U',
                                                style: TextStyle(
                                                  color: primaryColor,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: isSmallScreen ? 14 : 16,
                                                ),
                                              ),
                                            ),
                                          ),
                                          SizedBox(width: smallSpacing),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  reviewerName,
                                                  style: theme.bodyMedium.copyWith(
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: bodyFontSize,
                                                  ),
                                                ),
                                                SizedBox(height: 2),
                                                Row(
                                                  children: [
                                                    ...List.generate(5, (index) {
                                                      return Icon(
                                                        index < reviewRating.floor()
                                                            ? Icons.star
                                                            : Icons.star_border,
                                                        size: isSmallScreen ? 14 : 16,
                                                        color: Colors.amber,
                                                      );
                                                    }),
                                                    SizedBox(width: isSmallScreen ? 6 : 8),
                                                    Text(
                                                      reviewDate,
                                                      style: theme.bodySmall.copyWith(
                                                        color: _secondaryTextColor(),
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
                                      // Show the review comment (prefer 'comment' but fall back to other fields)
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
                                      ] else ...[
                                        // Fallback to any short content-like fields already present
                                        Text(
                                          review['review'] ?? review['content'] ?? '',
                                          style: theme.bodyMedium.copyWith(
                                            color: _textColor(0.85),
                                            fontSize: bodyFontSize,
                                          ),
                                          maxLines: 3,
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
            ),
          ],
        ),
    ),
      );
    }
  }

  // Ensure API_BASE_URL is a usable absolute base (adds missing '//' if needed,
  // enforces http/https, and strips trailing slashes).
  String _normalizeBaseUrl(String raw) {
    if (raw.isEmpty) return '';
    var base = raw.trim();
    // Fix malformed scheme cases like 'http:159.198...' or 'http:/example.com'
    if (base.startsWith('http:') && !base.startsWith('http://')) {
      base = base.replaceFirst('http:', 'http://');
    }
    if (base.startsWith('https:') && !base.startsWith('https://')) {
      base = base.replaceFirst('https:', 'https://');
    }
    // If no scheme, assume https
    if (!base.startsWith(RegExp(r'https?://'))) base = 'https://$base';
    // strip trailing slashes
    base = base.replaceAll(RegExp(r'/+$'), '');
    return base;
  }

  // Convert candidate image/path strings into absolute URLs or null if invalid.
  String? _toAbsoluteImageUrl(dynamic candidate) {
    try {
      if (candidate == null) return null;
      if (candidate is String) {
        var s = candidate.trim();
        if (s.isEmpty) return null;
        // Reject map-like strings e.g. '{_id: ...}'
        if (s.startsWith('{') || s.contains('{') || s.contains('}')) {
          return null;
        }
        // If already absolute
        if (s.startsWith('http://') || s.startsWith('https://')) return s;
        // If starts with '/', append to base
        final base = _normalizeBaseUrl(API_BASE_URL);
        if (s.startsWith('/')) return '$base$s';
        // If looks like a filename with extension, append under /uploads
        if (s.contains('.') && !s.contains(' ')) {
          return '$base/uploads/$s';
        }
        // If it's a bare id or something else, don't treat as image
        return null;
      }
      // If candidate is Map containing url-like fields, try those
      if (candidate is Map) {
        final urlKeys = ['url', 'src', 'path', 'imageUrl', 'file'];
        for (final k in urlKeys) {
          final v = candidate[k];
          final res = _toAbsoluteImageUrl(v);
          if (res != null) return res;
        }
      }
    } catch (_) {}
    return null;
  }

  // Heuristic: determine whether the artisan (or its referenced user) is KYC/verified.
    // Heuristic: determine whether the given payload (or widget.artisan) contains rich data.
    bool _isWidgetPayloadRich([dynamic wa]) {
    try {
      final payload = wa;
      if (payload == null) return false;
      if (payload is! Map) return false;
      final Map<String, dynamic> m = Map<String, dynamic>.from(payload.cast<String, dynamic>());
      final richKeys = ['name','fullName','displayName','bio','profilePicture','profileImage','avatar','trade','profession','pricing','pricingDetails','portfolio'];
      for (final k in richKeys) {
        if (m.containsKey(k) && m[k] != null) {
          final v = m[k];
          if (v is String && v.trim().isNotEmpty) return true;
          if (v is Map || v is List) return true;
        }
      }
    } catch (_) {}
    return false;
    }
