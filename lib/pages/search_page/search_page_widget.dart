import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import 'search_page_model.dart';
export 'search_page_model.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../artisan_detail_page/artisan_detail_page_widget.dart';
import '../../services/artist_service.dart';
import '../../api_config.dart';
import '../../services/my_service_service.dart';

class SearchPageWidget extends StatefulWidget {
  const SearchPageWidget({super.key, this.initialQuery});

  final String? initialQuery;

  static String routeName = 'SearchPage';
  static String routePath = '/searchPage';

  @override
  State<SearchPageWidget> createState() => _SearchPageWidgetState();
}

class _SearchPageWidgetState extends State<SearchPageWidget> {
  late SearchPageModel _model;
  final scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _artisans = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  final int _limit = 12;
  bool _hasSearched = false;
  String? _selectedTrade;
  String? _selectedSubservice;
  String? _errorMessage;

  // Minimalist color scheme
  Color get _primaryColor => Theme.of(context).colorScheme.primary;
  Color get _textPrimary => Theme.of(context).colorScheme.onSurface;
  Color get _textSecondary =>
      Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.62);
  Color get _borderColor => Theme.of(context).colorScheme.outline;

  // Service and subcategory management
  List<Map<String, dynamic>> _allMainServices = [];
  List<Map<String, dynamic>> _popularServices = [];
  List<Map<String, dynamic>> _currentSubservices = [];
  final Map<String, List<Map<String, dynamic>>> _mainServiceSubservices = {};
  String? _currentMainCategory;
  String? _currentMainCategoryId;
  bool _isMainService = false;
  String? _lastSearchedQuery;

  // Cache for service data
  final Map<String, List<Map<String, dynamic>>> _subcategoryCache = {};
  final Map<String, List<String>> _serviceCache = {};

  static const Map<String, List<String>> _serviceKeywordAliases = {
    'mechanic': [
      'mechanic',
      'mechanics',
      'auto',
      'automobile',
      'car',
      'cars',
      'vehicle',
      'vehicles',
      'engine',
      'tyre',
      'tire',
      'battery',
      'brake'
    ],
    'plumbing': [
      'plumb',
      'plumber',
      'plumbing',
      'pipe',
      'drain',
      'leak',
      'water'
    ],
    'electrical': [
      'electric',
      'electrician',
      'electrical',
      'wiring',
      'light',
      'generator',
      'inverter'
    ],
    'cleaning': [
      'clean',
      'cleaner',
      'cleaning',
      'janitor',
      'laundry',
      'wash',
      'housekeeping'
    ],
    'carpentry': [
      'carpentry',
      'carpenter',
      'wood',
      'furniture',
      'cabinet',
      'wardrobe'
    ],
    'painting': [
      'paint',
      'painter',
      'painting',
      'screeding',
      'interior finish'
    ],
    'gardening': ['garden', 'gardener', 'lawn', 'landscape', 'flowers'],
    'tailoring': [
      'tailor',
      'tailoring',
      'fashion',
      'sew',
      'sewing',
      'dressmaker'
    ],
    'beauty': ['beauty', 'salon', 'hair', 'barber', 'makeup', 'spa'],
    'catering': [
      'cater',
      'catering',
      'chef',
      'food',
      'cook',
      'pastry',
      'baker'
    ],
    'moving': [
      'moving',
      'movers',
      'delivery',
      'dispatch',
      'logistics',
      'truck'
    ],
    'maintenance': ['maintenance', 'handyman', 'repair', 'fix', 'install'],
    'it': ['it', 'tech', 'computer', 'laptop', 'software', 'network'],
  };

  // Search tracking
  Timer? _searchDebounceTimer;

  void _resetSearchContext({
    bool clearQuery = false,
    bool clearLastQuery = false,
  }) {
    if (clearQuery) {
      _model.textController?.clear();
    }

    _currentMainCategory = null;
    _currentMainCategoryId = null;
    _currentSubservices = [];
    _isMainService = false;
    _selectedTrade = null;
    _selectedSubservice = null;

    if (clearLastQuery) {
      _lastSearchedQuery = null;
    }
  }

  String _activeSearchTerm() {
    if (_selectedSubservice != null && _selectedSubservice!.isNotEmpty) {
      final selected = _currentSubservices.where((subservice) {
        return (subservice['id']?.toString() ?? '') == _selectedSubservice;
      }).toList();
      if (selected.isNotEmpty) {
        return selected.first['name']?.toString() ?? '';
      }
    }

    if (_isMainService && _currentMainCategory != null) {
      return _currentMainCategory!;
    }

    return _model.textController?.text.trim() ?? '';
  }

  String? _artisanIdentityKey(Map<String, dynamic> artisan) {
    String? readId(dynamic value) {
      if (value == null) return null;
      final text = value.toString().trim();
      return text.isEmpty ? null : text;
    }

    try {
      for (final key in ['_id', 'id', 'artisanId', 'userId', 'user_id']) {
        final direct = readId(artisan[key]);
        if (direct != null) return '${key == 'userId' || key == 'user_id' ? 'user' : 'artisan'}:$direct';
      }

      for (final key in [
        'user',
        'owner',
        'artisan',
        'artisanUser',
        'artisanProfile',
        'artisanAuthDetails',
        'artisanAuthdDetails',
        'artisanAuthdetails',
      ]) {
        final nested = artisan[key];
        if (nested is Map) {
          final nestedId =
              readId(nested['_id']) ?? readId(nested['id']) ?? readId(nested['userId']);
          if (nestedId != null) return 'user:$nestedId';
        }
      }
    } catch (_) {}

    return null;
  }

  String _artisanSearchBlob(Map<String, dynamic> artisan) {
    final buffer = StringBuffer();

    void appendValue(dynamic value) {
      if (value == null) return;
      if (value is String) {
        final text = value.trim().toLowerCase();
        if (text.isNotEmpty) buffer.write(' $text');
        return;
      }
      if (value is num) {
        buffer.write(' ${value.toString().toLowerCase()}');
        return;
      }
      if (value is List) {
        for (final item in value) {
          appendValue(item);
        }
        return;
      }
      if (value is Map) {
        for (final entry in value.entries) {
          if (entry.key.toString().toLowerCase().contains('image')) continue;
          appendValue(entry.value);
        }
      }
    }

    appendValue(artisan['name']);
    appendValue(artisan['trade']);
    appendValue(artisan['occupation']);
    appendValue(artisan['bio']);
    appendValue(artisan['description']);
    appendValue(artisan['location']);
    appendValue(artisan['city']);
    appendValue(artisan['state']);
    appendValue(artisan['serviceArea']);
    appendValue(artisan['user']);
    appendValue(artisan['artisanProfile']);
    appendValue(artisan['artisanAuthDetails']);
    appendValue(artisan['services']);
    appendValue(artisan['skills']);
    appendValue(artisan['categories']);
    appendValue(artisan['subcategories']);

    return buffer.toString();
  }

  int _searchRelevanceScore(Map<String, dynamic> artisan, String query) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return 0;

    final name = [
      artisan['name'],
      if (artisan['user'] is Map) (artisan['user'] as Map)['name'],
      if (artisan['artisanAuthDetails'] is Map)
        (artisan['artisanAuthDetails'] as Map)['name'],
    ].whereType<Object>().map((e) => e.toString().trim().toLowerCase()).join(' ');

    final blob = _artisanSearchBlob(artisan);
    final tokens = _tokenizeQuery(normalizedQuery);

    var score = 0;
    if (name == normalizedQuery) score += 200;
    if (name.startsWith(normalizedQuery) && normalizedQuery.isNotEmpty) {
      score += 120;
    }
    if (name.contains(normalizedQuery) && normalizedQuery.isNotEmpty) {
      score += 80;
    }
    if (blob.contains(normalizedQuery) && normalizedQuery.isNotEmpty) {
      score += 40;
    }

    for (final token in tokens) {
      if (name.contains(token)) score += 20;
      if (blob.contains(token)) score += 8;
    }

    return score;
  }

  List<Map<String, dynamic>> _mergeUniqueArtisans(
    List<Map<String, dynamic>> existing,
    List<Map<String, dynamic>> incoming, {
    String? query,
  }) {
    final merged = <Map<String, dynamic>>[];
    final seen = <String>{};

    void addArtisan(Map<String, dynamic> artisan) {
      final key = _artisanIdentityKey(artisan);
      if (key != null) {
        if (!seen.add(key)) return;
      }
      merged.add(artisan);
    }

    for (final artisan in existing) {
      addArtisan(artisan);
    }
    for (final artisan in incoming) {
      addArtisan(artisan);
    }

    final normalizedQuery = query?.trim() ?? '';
    if (!_isMainService && normalizedQuery.isNotEmpty) {
      merged.sort((a, b) {
        final scoreDiff = _searchRelevanceScore(b, normalizedQuery) -
            _searchRelevanceScore(a, normalizedQuery);
        if (scoreDiff != 0) return scoreDiff;
        final nameA = (a['name'] ?? '').toString().toLowerCase();
        final nameB = (b['name'] ?? '').toString().toLowerCase();
        return nameA.compareTo(nameB);
      });
    }

    return merged;
  }

  List<String> _tokenizeQuery(String value) {
    return value
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.isNotEmpty)
        .toList();
  }

  Set<String> _keywordsForService(String name,
      {String? slug, List<Map<String, dynamic>>? subservices}) {
    final keywords = <String>{};

    void addText(String? text) {
      if (text == null || text.trim().isEmpty) return;
      final normalized = text.toLowerCase().trim();
      keywords.add(normalized);
      keywords.addAll(_tokenizeQuery(normalized));
      for (final entry in _serviceKeywordAliases.entries) {
        if (normalized.contains(entry.key) ||
            entry.value.any(normalized.contains)) {
          keywords.addAll(entry.value);
        }
      }
    }

    addText(name);
    addText(slug);
    for (final subservice in subservices ?? const <Map<String, dynamic>>[]) {
      addText(subservice['name']?.toString());
      addText(subservice['slug']?.toString());
    }

    return keywords;
  }

  Map<String, dynamic>? _inferServiceContextFromQuery(String query) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return null;

    final queryTokens = _tokenizeQuery(normalizedQuery).toSet();
    Map<String, dynamic>? bestMatch;
    double bestScore = 0;

    for (final service in _allMainServices) {
      final serviceId = service['id']?.toString() ?? '';
      final subservices =
          _mainServiceSubservices[serviceId] ?? const <Map<String, dynamic>>[];
      final keywords = _keywordsForService(
        service['name']?.toString() ?? '',
        slug: service['slug']?.toString(),
        subservices: subservices,
      );

      double score = 0;
      String? matchedSubserviceId;

      for (final keyword in keywords) {
        if (keyword == normalizedQuery) {
          score = 1.0;
          break;
        }
        if (keyword.contains(normalizedQuery) ||
            normalizedQuery.contains(keyword)) {
          score = score < 0.88 ? 0.88 : score;
        }
      }

      if (score < 1.0 && queryTokens.isNotEmpty) {
        final keywordTokens = keywords.expand(_tokenizeQuery).toSet();
        final overlap = queryTokens.intersection(keywordTokens).length;
        if (overlap > 0) {
          final tokenScore = overlap / queryTokens.length;
          score = tokenScore > score ? tokenScore : score;
        }
      }

      if (score < 0.88) {
        final similarity = _calculateSimilarity(
            normalizedQuery, service['name']?.toString() ?? '');
        score = similarity > score ? similarity : score;
      }

      for (final subservice in subservices) {
        final subName = subservice['name']?.toString() ?? '';
        final subSlug = subservice['slug']?.toString() ?? '';
        final subKeywords = _keywordsForService(subName, slug: subSlug);
        for (final keyword in subKeywords) {
          if (keyword == normalizedQuery) {
            score = 0.97;
            matchedSubserviceId = subservice['id']?.toString();
            break;
          }
          if (keyword.contains(normalizedQuery) ||
              normalizedQuery.contains(keyword)) {
            if (score < 0.9) {
              score = 0.9;
              matchedSubserviceId = subservice['id']?.toString();
            }
          }
        }
        if (matchedSubserviceId == null && score < 0.9) {
          final similarity = _calculateSimilarity(normalizedQuery, subName);
          if (similarity >= 0.62 && similarity > score) {
            score = similarity;
            matchedSubserviceId = subservice['id']?.toString();
          }
        }
      }

      if (score > bestScore) {
        bestScore = score;
        bestMatch = {
          'service': service,
          'subservices': subservices,
          'matchedSubserviceId': matchedSubserviceId,
        };
      }
    }

    return bestScore >= 0.45 ? bestMatch : null;
  }

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => SearchPageModel());

    _model.textController ??= TextEditingController();
    _model.textFieldFocusNode ??= FocusNode();

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 200 &&
          !_isLoadingMore &&
          _hasMore &&
          _hasSearched) {
        _fetchMore();
      }
    });

    // Load main services on init
    _loadMainServices();

    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _model.textController!.text = widget.initialQuery!;
        _processSearchQuery(widget.initialQuery!);
      });
    } else {
      // No initial query provided -> perform an initial load
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startSearch();
      });
    }

    _model.textController?.addListener(() {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _scrollController.dispose();
    _model.dispose();
    super.dispose();
  }

  /// Load all main services/categories from the API
  Future<void> _loadMainServices() async {
    try {
      final uri = Uri.parse(
          '$API_BASE_URL/api/job-categories?limit=100&includeSubcategories=true');
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        List<dynamic>? items;

        if (body is Map && body['data'] is List) {
          items = body['data'] as List<dynamic>;
        } else if (body is List) {
          items = body;
        }

        if (items != null && items.isNotEmpty) {
          final subserviceMap = <String, List<Map<String, dynamic>>>{};
          final mainServices = items
              .map((e) {
                if (e is! Map) return null;
                final m = Map<String, dynamic>.from(e.cast<String, dynamic>());
                final id = (m['_id'] ?? m['id'])?.toString();
                final nestedSubservices = _extractSubservices(
                  m['subcategories'] ?? m['children'] ?? m['items'],
                  categoryId: id,
                );
                if (id != null && id.isNotEmpty) {
                  subserviceMap[id] = nestedSubservices;
                }
                return {
                  'id': id,
                  'name': m['name'] ?? 'Service',
                  'slug': m['slug'] ?? '',
                  'type': 'main',
                };
              })
              .whereType<Map<String, dynamic>>()
              .toList();

          if (mounted) {
            setState(() {
              _allMainServices = mainServices;
              _mainServiceSubservices
                ..clear()
                ..addAll(subserviceMap);
              _updatePopularServices();
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading main services: $e');
    }
  }

  List<Map<String, dynamic>> _extractSubservices(dynamic rawItems,
      {String? categoryId}) {
    if (rawItems is! List) return <Map<String, dynamic>>[];

    final subservices = <Map<String, dynamic>>[];
    for (final item in rawItems) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item.cast<String, dynamic>());
      final subId = (map['_id'] ?? map['id'])?.toString() ?? '';
      final name = map['name']?.toString().trim() ?? '';
      if (subId.isEmpty || name.isEmpty) continue;
      subservices.add({
        'id': subId,
        'name': name,
        'slug': map['slug']?.toString() ?? '',
        'categoryId': categoryId,
      });
    }
    return subservices;
  }

  /// Update popular services based on search frequency
  void _updatePopularServices() {
    if (_allMainServices.isEmpty) return;

    // For now, just take first 5 as popular
    // You can enhance this with actual search frequency tracking
    final popular = _allMainServices.take(5).toList();
    popular.shuffle();

    if (mounted) {
      setState(() {
        _popularServices = popular;
      });
    }
  }

  /// Process search query to determine if it matches a main service
  /// Calculate string similarity score (0.0 to 1.0)
  double _calculateSimilarity(String s1, String s2) {
    final s1Lower = s1.toLowerCase().trim();
    final s2Lower = s2.toLowerCase().trim();

    if (s1Lower == s2Lower) return 1.0;
    if (s1Lower.isEmpty || s2Lower.isEmpty) return 0.0;

    // Substring match (high weight)
    if (s1Lower.contains(s2Lower) || s2Lower.contains(s1Lower)) return 0.85;

    // Character overlap similarity
    final chars1 = s1Lower.split('').toSet();
    final chars2 = s2Lower.split('').toSet();
    final intersection = chars1.intersection(chars2).length;
    final union = chars1.union(chars2).length;

    return union > 0 ? intersection / union : 0.0;
  }

  /// Process search query with intelligent Main Service mapping
  Future<void> _processSearchQuery(String query) async {
    final normalizedQuery = query.trim();

    if (normalizedQuery.isEmpty) {
      setState(() {
        _resetSearchContext();
      });
      _startSearch();
      return;
    }

    if (kDebugMode)
      debugPrint('SearchPage: Processing query: "$normalizedQuery"');

    final matchedContext = _inferServiceContextFromQuery(normalizedQuery);
    final matchedService = matchedContext?['service'] as Map<String, dynamic>?;

    if (matchedService != null && matchedService.isNotEmpty) {
      // Found a matching main service - map to it
      final serviceId = matchedService['id']?.toString() ?? '';
      final serviceName = matchedService['name']?.toString() ?? normalizedQuery;
      final inferredSubservices =
          (matchedContext?['subservices'] as List<Map<String, dynamic>>?) ??
              const <Map<String, dynamic>>[];
      final matchedSubserviceId =
          matchedContext?['matchedSubserviceId']?.toString();

      if (kDebugMode) {
        debugPrint(
            'SearchPage: Mapped query "$normalizedQuery" to main service "$serviceName" (ID: $serviceId)');
      }

      setState(() {
        _currentMainCategory = serviceName;
        _currentMainCategoryId = serviceId;
        _isMainService = true;
        _selectedTrade = serviceName;
        _selectedSubservice = matchedSubserviceId;
        _currentSubservices = inferredSubservices;
      });

      // Load sub-services for this main service
      if (serviceId.isNotEmpty) {
        await _loadSubservicesForMainService(serviceId);
      }
    } else {
      // No main service match found - perform generic search
      if (kDebugMode)
        debugPrint(
            'SearchPage: No main service match for "$normalizedQuery", performing generic search');

      setState(() {
        _resetSearchContext();
      });
    }

    // Perform the artisan search
    _startSearch();
  }

  /// Load subservices for a specific main service
  Future<void> _loadSubservicesForMainService(String categoryId) async {
    if (categoryId.isEmpty) return;

    // Check cache first
    if (_subcategoryCache.containsKey(categoryId)) {
      if (mounted) {
        setState(() {
          _currentSubservices = _subcategoryCache[categoryId] ?? [];
        });
      }
      return;
    }

    if (_mainServiceSubservices.containsKey(categoryId)) {
      final knownSubservices = _mainServiceSubservices[categoryId] ?? [];
      _subcategoryCache[categoryId] = knownSubservices;
      if (mounted) {
        setState(() {
          _currentSubservices = knownSubservices;
        });
      }
      return;
    }

    try {
      final uri = Uri.parse(
          '$API_BASE_URL/api/job-subcategories?categoryId=$categoryId&limit=50');
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        List<dynamic>? items;

        if (body is Map && body['data'] is List) {
          items = body['data'] as List<dynamic>;
        } else if (body is List) {
          items = body;
        }

        if (items != null && items.isNotEmpty) {
          final subservices = items
              .map((e) {
                if (e is! Map) return null;
                final m = Map<String, dynamic>.from(e.cast<String, dynamic>());
                return {
                  'id': m['_id'] ?? m['id'],
                  'name': m['name'] ?? 'Service',
                  'slug': m['slug'] ?? '',
                  'categoryId': categoryId,
                };
              })
              .whereType<Map<String, dynamic>>()
              .toList();

          // Cache the result
          _subcategoryCache[categoryId] = subservices;
          _mainServiceSubservices[categoryId] = subservices;

          if (mounted) {
            setState(() {
              _currentSubservices = subservices;
            });
          }
        } else {
          _subcategoryCache[categoryId] = [];
          if (mounted) {
            setState(() {
              _currentSubservices = [];
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading subservices: $e');
      _subcategoryCache[categoryId] = [];
    }
  }

  /// Handle search input with debounce
  void _handleSearchInput(String query) {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;

      // Store the query to avoid reprocessing the same query
      if (query == _lastSearchedQuery) return;
      _lastSearchedQuery = query;

      _processSearchQuery(query);
    });
  }

  Future<void> _startSearch() async {
    setState(() {
      _hasSearched = true;
      _isLoading = true;
      _page = 1;
      _hasMore = true;
      _artisans.clear();
      _errorMessage = null;
    });

    await _fetchArtisans(reset: true);
  }

  Future<void> _fetchArtisans({bool reset = false}) async {
    if (!_hasMore && !reset) return;
    if (reset) {
      _page = 1;
      _hasMore = true;
    }
    if (!_hasSearched) return;

    if (reset) {
      if (mounted) {
        setState(() {
          _isLoading = true;
          _isLoadingMore = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoadingMore = true;
        });
      }
    }

    try {
      final q = _model.textController!.text.trim();

      // Determine search parameters based on whether it's a main service search
      String? tradeParam;
      String? subserviceParam;

      if (_isMainService && _currentMainCategory != null) {
        // If it's a main service search, use the main service as trade
        tradeParam = _currentMainCategory;
        subserviceParam = _selectedSubservice;
      } else {
        // For random searches, use the raw query
        tradeParam = q.isNotEmpty ? q : null;
        subserviceParam = _selectedSubservice;
      }

      if (kDebugMode) {
        debugPrint(
            'SearchPage._fetchArtisans -> q="$q" tradeParam=$tradeParam subservice=$subserviceParam isMainService=$_isMainService page=$_page limit=$_limit');
      }

      final results = await ArtistService.fetchArtisans(
        page: _page,
        limit: _limit,
        q: !_isMainService && q.isNotEmpty ? q : null,
        trade: tradeParam,
        categoryId: _isMainService ? _currentMainCategoryId : null,
        subCategoryId: subserviceParam,
      );

      if (!mounted) return;

      if (results.isNotEmpty) {
        setState(() {
          final merged = _mergeUniqueArtisans(
            reset ? <Map<String, dynamic>>[] : _artisans,
            results,
            query: q,
          );
          _artisans
            ..clear()
            ..addAll(merged);
          _hasMore = results.length == _limit;
          if (_hasMore) _page++;
        });

        // Batch load services for all artisans
        _batchLoadServices();
      } else {
        setState(() => _hasMore = false);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error fetching artisans: $e');
      if (mounted) {
        setState(() {
          _hasMore = false;
          _errorMessage =
              'Failed to load artisans. Please check your connection.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _batchLoadServices() async {
    // Get all artisan IDs that aren't in cache
    final artisanIds = _artisans
        .map((a) => a['_id']?.toString() ?? a['id']?.toString())
        .where((id) =>
            id != null && id.isNotEmpty && !_serviceCache.containsKey(id))
        .cast<String>()
        .toList();

    if (artisanIds.isEmpty) return;

    // Process in batches to avoid overwhelming the server
    const batchSize = 5;
    for (var i = 0; i < artisanIds.length; i += batchSize) {
      final batch = artisanIds.skip(i).take(batchSize).toList();
      await Future.wait(batch.map((id) => _fetchArtisanServicesForCard(id)));
    }
  }

  Future<void> _fetchMore() async {
    if (_isLoadingMore || !_hasMore) return;
    await _fetchArtisans(reset: false);
  }

  /// Check if URL is valid
  bool _isValidImageUrl(String url) {
    if (url.isEmpty) return false;

    // Fix protocol-relative URLs
    if (url.startsWith('//')) {
      url = 'https:$url';
    }

    try {
      final uri = Uri.parse(url);
      return uri.hasScheme &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Fetch artisan's configured services from API - FIXED VERSION
  Future<List<String>> _fetchArtisanServicesForCard(String? artisanId) async {
    if (artisanId == null || artisanId.isEmpty) return <String>[];

    // Check cache first
    if (_serviceCache.containsKey(artisanId)) {
      if (kDebugMode)
        debugPrint(
            'SearchPage: Returning cached services for artisanId=$artisanId');
      return _serviceCache[artisanId] ?? <String>[];
    }

    try {
      final rawServices = await ArtistService.fetchArtisanServices(artisanId);
      final flattenedServices =
          MyServiceService.flattenArtisanServices(rawServices);
      final uniqueServices = flattenedServices
          .map(_serviceLabelFromMap)
          .where((label) => label.isNotEmpty)
          .toSet()
          .toList();

      _serviceCache[artisanId] = uniqueServices;
      if (kDebugMode) {
        debugPrint(
          'SearchPage: Found ${uniqueServices.length} normalized services for artisanId=$artisanId: $uniqueServices',
        );
      }
      return uniqueServices;
    } catch (e) {
      if (kDebugMode) debugPrint('Error fetching artisan services: $e');
    }

    // Cache empty result to avoid repeated failed requests
    _serviceCache[artisanId] = <String>[];
    return <String>[];
  }

  String _serviceLabelFromMap(Map<String, dynamic> item) {
    final directName = item['subCategoryName'] ??
        item['categoryName'] ??
        item['name'] ??
        item['serviceName'] ??
        item['title'] ??
        item['service'] ??
        item['service_type'] ??
        item['category'];

    if (directName != null && directName.toString().trim().isNotEmpty) {
      return directName.toString().trim();
    }

    final nestedFields = [
      'subCategoryId',
      'subCategory',
      'subcategory',
      'categoryId',
      'category',
    ];
    for (final field in nestedFields) {
      if (item[field] is Map) {
        final nested = Map<String, dynamic>.from(
          (item[field] as Map).cast<String, dynamic>(),
        );
        final nestedName = nested['name'] ??
            nested['title'] ??
            nested['label'] ??
            nested['service'];
        if (nestedName != null && nestedName.toString().trim().isNotEmpty) {
          return nestedName.toString().trim();
        }
      }
    }

    return '';
  }

  // ENHANCED Filter Chip Widget
  Widget _buildEnhancedFilterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Responsive calculations
    final bool isSmallScreen = screenWidth < 360;
    final bool isMediumScreen = screenWidth < 420;

    // Adaptive padding based on screen size
    final horizontalPadding =
        isSmallScreen ? 14.0 : (isMediumScreen ? 16.0 : 20.0);
    final verticalPadding =
        isSmallScreen ? 8.0 : (isMediumScreen ? 10.0 : 12.0);

    // Adaptive font size
    final fontSize = isSmallScreen ? 13.0 : (isMediumScreen ? 14.0 : 15.0);

    // Adaptive border radius
    final borderRadius = BorderRadius.circular(isSmallScreen ? 16 : 20);

    // Adaptive colors based on theme
    final backgroundColor = selected ? _primaryColor : Colors.transparent;

    final borderColor = selected
        ? _primaryColor
        : (isDark ? const Color(0xFF4B5563) : _borderColor);

    final textColor = selected
        ? Colors.white
        : (isDark ? const Color(0xFFD1D5DB) : _textSecondary);

    final shadowColor = selected
        ? _primaryColor.withAlpha(((isDark ? 0.3 : 0.15) * 255).round())
        : Colors.transparent;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(
          right: isSmallScreen ? 8.0 : (isMediumScreen ? 10.0 : 12.0),
          bottom: screenHeight < 700 ? 4.0 : 0,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: verticalPadding,
        ),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: borderRadius,
          border: Border.all(
            color: borderColor,
            width: selected ? 1.5 : 1.0,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: shadowColor,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            label,
            key: ValueKey('$label-$selected'),
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: textColor,
              letterSpacing: selected ? -0.1 : -0.2,
              height: 1.2,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  /// Build the tabs section based on current search context
  Widget _buildTabsSection(bool isDark, double horizontalPadding,
      double filterChipHeight, bool isSmallScreen) {
    final typedQuery = _model.textController?.text.trim() ?? '';

    if (_isMainService && _currentMainCategory != null) {
      // Show main service and its subservices
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Main service chip (always visible)
          Padding(
            padding: EdgeInsets.only(
              bottom: 12,
              left: horizontalPadding,
              right: horizontalPadding,
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildEnhancedFilterChip(
                    label: _currentMainCategory!,
                    selected: true,
                    onTap: () {
                      setState(() {
                        _selectedSubservice = null;
                      });
                      _startSearch();
                    },
                    isDark: isDark,
                  ),
                ],
              ),
            ),
          ),

          // Subservices (if available)
          if (_currentSubservices.isNotEmpty)
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(
                    left: horizontalPadding,
                    right: horizontalPadding,
                    bottom: 8,
                  ),
                  child: Text(
                    'Sub-services',
                    style: TextStyle(
                      fontSize: isSmallScreen ? 12 : 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xFFD1D5DB) : _textSecondary,
                    ),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      _currentSubservices.length,
                      (index) {
                        final subservice = _currentSubservices[index];
                        final subserviceName = subservice['name'] ?? 'Service';
                        final subserviceId = subservice['id'] ?? '';
                        final selected = _selectedSubservice == subserviceId;

                        return _buildEnhancedFilterChip(
                          label: subserviceName,
                          selected: selected,
                          onTap: () {
                            setState(() {
                              _selectedSubservice =
                                  selected ? null : subserviceId;
                            });
                            _startSearch();
                          },
                          isDark: isDark,
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
        ],
      );
    } else {
      final hasActiveQuery = typedQuery.isNotEmpty;

      // Show search-context chip for free-text mode, otherwise popular services
      return (!hasActiveQuery && _popularServices.isEmpty)
          ? const SizedBox.shrink()
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(
                    left: horizontalPadding,
                    right: horizontalPadding,
                    bottom: 8,
                  ),
                  child: Text(
                    hasActiveQuery ? 'Search Filter' : 'Popular Services',
                    style: TextStyle(
                      fontSize: isSmallScreen ? 12 : 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xFFD1D5DB) : _textSecondary,
                    ),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: hasActiveQuery
                        ? [
                            _buildEnhancedFilterChip(
                              label: typedQuery,
                              selected: true,
                              onTap: () {},
                              isDark: isDark,
                            ),
                          ]
                        : List.generate(
                            _popularServices.length,
                            (index) {
                              final service = _popularServices[index];
                              final serviceName = service['name'] ?? 'Service';
                              final selected = _selectedTrade == serviceName;

                              return _buildEnhancedFilterChip(
                                label: serviceName,
                                selected: selected,
                                onTap: () {
                                  if (!selected) {
                                    setState(() {
                                      _selectedTrade = serviceName;
                                      _model.textController?.text = serviceName;
                                    });
                                    _processSearchQuery(serviceName);
                                  } else {
                                    setState(() {
                                      _resetSearchContext(
                                          clearQuery: true,
                                          clearLastQuery: true);
                                    });
                                    _startSearch();
                                  }
                                },
                                isDark: isDark,
                              );
                            },
                          ),
                  ),
                ),
              ],
            );
    }
  }

  Widget _buildArtisanCard(BuildContext context, Map<String, dynamic> artisan) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    // Adaptive colors for dark/light mode
    final Color surfaceColor = isDark ? const Color(0xFF1F2937) : Colors.white;
    final Color cardBorderColor =
        isDark ? const Color(0xFF374151) : _borderColor;
    final Color textPrimaryColor = isDark ? Colors.white : _textPrimary;
    final Color textSecondaryColor =
        isDark ? const Color(0xFF9CA3AF) : _textSecondary;

    // Trade badge background color - using primary color with opacity
    final Color tradeBadgeColor = isDark
        ? _primaryColor.withAlpha((0.2 * 255).round())
        : _primaryColor.withAlpha((0.1 * 255).round());
    final Color tradeTextColor =
        isDark ? _primaryColor.lighten(0.2) : _primaryColor.darken(0.1);

    String _extractName(Map<String, dynamic> src) {
      try {
        final top = src['name'];
        if (top != null && top.toString().trim().isNotEmpty)
          return top.toString().trim();

        // Fixed: Removed duplicate entry
        final authKeys = {
          'artisanAuthDetails',
          'artisanAuthdDetails',
          'artisanAuthdetails'
        }.toList();
        for (final k in authKeys) {
          final a = src[k];
          if (a is Map &&
              a['name'] != null &&
              a['name'].toString().trim().isNotEmpty)
            return a['name'].toString().trim();
        }

        final possibleKeys = ['user', 'userId', 'owner', 'artisan'];
        for (final k in possibleKeys) {
          final p = src[k];
          if (p is Map &&
              p['name'] != null &&
              p['name'].toString().trim().isNotEmpty)
            return p['name'].toString().trim();
        }
      } catch (_) {}
      return 'Artisan';
    }

    String _extractImageUrl(Map<String, dynamic> src) {
      try {
        for (final k in [
          'profileImage',
          'profile_image',
          'profileImageUrl',
          'profileImageURL',
          'avatar',
          'image'
        ]) {
          final v = src[k];
          if (v is String && v.isNotEmpty) return v;
          if (v is Map) {
            final u = v['url'] ?? v['secure_url'] ?? v['uri'] ?? v['value'];
            if (u is String && u.isNotEmpty) return u;
          }
        }

        final nestedKeys = [
          'user',
          'userId',
          'artisan',
          'owner',
          'artisanUser',
          'artisanProfile',
          'artisanAuthDetails',
          'artisanAuthdDetails',
          'artisanAuthdetails'
        ];
        for (final nk in nestedKeys) {
          final node = src[nk];
          if (node is Map) {
            final maybe = _extractImageUrl(Map<String, dynamic>.from(node));
            if (maybe.isNotEmpty) return maybe;
          }
          if (node is List) {
            for (final el in node) {
              if (el is Map) {
                final maybe = _extractImageUrl(Map<String, dynamic>.from(el));
                if (maybe.isNotEmpty) return maybe;
              }
            }
          }
        }

        if (src.containsKey('artisanProfile') && src['artisanProfile'] is Map) {
          final maybe = _extractImageUrl(
              Map<String, dynamic>.from(src['artisanProfile']));
          if (maybe.isNotEmpty) return maybe;
        }
      } catch (_) {}
      return '';
    }

    final name = _extractName(artisan);

    var imageUrl = _extractImageUrl(artisan);
    if (imageUrl.startsWith('//')) imageUrl = 'https:$imageUrl';
    imageUrl = imageUrl.trim();

    // Extract location
    String location = '';
    try {
      if (artisan['serviceArea'] is Map) {
        location = artisan['serviceArea']['address']?.toString() ?? '';
      }
    } catch (_) {}
    if (location.isEmpty)
      location = artisan['location'] ?? artisan['city'] ?? '';

    // Extract rating and review count
    final rating = (artisan['rating'] is num)
        ? (artisan['rating'] as num).toDouble()
        : (artisan['averageRating'] ?? artisan['average_rating'] ?? 0)
            .toDouble();
    final reviewCount = artisan['reviewsCount'] ??
        artisan['reviewCount'] ??
        artisan['review_count'] ??
        0;

    // Extract artisan ID to fetch their services
    String? artisanId;
    try {
      artisanId =
          (artisan['_id'] ?? artisan['id'] ?? artisan['artisanId'])?.toString();
    } catch (_) {}

    return _buildArtisanCardWithServices(
      context: context,
      artisan: artisan,
      imageUrl: imageUrl,
      artisanId: artisanId,
      isDark: isDark,
      surfaceColor: surfaceColor,
      cardBorderColor: cardBorderColor,
      textPrimaryColor: textPrimaryColor,
      textSecondaryColor: textSecondaryColor,
      tradeBadgeColor: tradeBadgeColor,
      tradeTextColor: tradeTextColor,
      name: name,
      location: location,
      rating: rating,
      reviewCount: reviewCount,
    );
  }

  /// Helper method to build artisan card with fetched services
  Widget _buildArtisanCardWithServices({
    required BuildContext context,
    required Map<String, dynamic> artisan,
    required String imageUrl,
    required String? artisanId,
    required bool isDark,
    required Color surfaceColor,
    required Color cardBorderColor,
    required Color textPrimaryColor,
    required Color textSecondaryColor,
    required Color tradeBadgeColor,
    required Color tradeTextColor,
    required String name,
    required String location,
    required double rating,
    required int reviewCount,
  }) {
    String _getInitials(String s) {
      final parts = s
          .trim()
          .split(RegExp(r'\s+'))
          .where((part) => part.isNotEmpty)
          .toList();
      if (parts.isEmpty) return 'A';
      if (parts.first.isEmpty) return 'A';
      if (parts.length == 1) return parts.first.characters.first.toUpperCase();
      return (parts[0].characters.first + parts[1].characters.first)
          .toUpperCase();
    }

    return FutureBuilder<List<String>>(
      future: _fetchArtisanServicesForCard(artisanId),
      builder: (context, snapshot) {
        if (kDebugMode) {
          debugPrint(
              'FutureBuilder for artisan $artisanId - state: ${snapshot.connectionState}, hasData: ${snapshot.hasData}, data: ${snapshot.data}');
        }

        List<String> services = <String>[];
        if (snapshot.hasData) {
          services = snapshot.data ?? <String>[];
        }

        return Container(
          margin: const EdgeInsets.only(
            bottom: 16,
            left: 4,
            right: 4,
          ),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cardBorderColor, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: _primaryColor.withAlpha((0.1 * 255).round()),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _primaryColor.withAlpha((0.2 * 255).round()),
                        width: 1,
                      ),
                    ),
                    child: Builder(builder: (context) {
                      final hasValidUrl = _isValidImageUrl(imageUrl);
                      if (hasValidUrl) {
                        return ClipOval(
                          child: CachedNetworkImage(
                            imageUrl: imageUrl,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            imageBuilder: (context, imageProvider) => Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                image: DecorationImage(
                                  image: imageProvider,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            placeholder: (context, url) => Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation(_primaryColor),
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) => Center(
                              child: Text(
                                _getInitials(name),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: _primaryColor,
                                ),
                              ),
                            ),
                          ),
                        );
                      }

                      return Center(
                        child: Text(
                          _getInitials(name),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: _primaryColor,
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(width: 16),

                  // Name and rating
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: textPrimaryColor,
                            letterSpacing: -0.3,
                            height: 1.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        // Service badge - show only 1 service
                        if (services.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: tradeBadgeColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _primaryColor
                                    .withAlpha((0.2 * 255).round()),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              services.first,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: tradeTextColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          )
                        else
                          Text(
                            'No service yet',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: textSecondaryColor,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.star_rounded,
                              size: 16,
                              color: const Color(0xFFF59E0B),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              rating.toStringAsFixed(1),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: textPrimaryColor,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '($reviewCount reviews)',
                              style: TextStyle(
                                fontSize: 13,
                                color: textSecondaryColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Book Button
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    child: ElevatedButton(
                      onPressed: () {
                        try {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ArtisanDetailPageWidget(artisan: artisan),
                            ),
                          );
                        } catch (_) {}
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryColor,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          horizontal:
                              MediaQuery.of(context).size.width < 360 ? 16 : 20,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      child: const Text('Book'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Location only - services now shown in badge above
              if (location.isNotEmpty)
                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 16,
                      color: textSecondaryColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        location,
                        style: TextStyle(
                          fontSize: 14,
                          color: textSecondaryColor,
                          height: 1.4,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSkeletonCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final placeholder = isDark
        ? Colors.white.withAlpha((0.05 * 255).round())
        : Colors.black.withAlpha((0.05 * 255).round());
    final placeholderAlt = isDark
        ? Colors.white.withAlpha((0.08 * 255).round())
        : Colors.black.withAlpha((0.08 * 255).round());
    final borderColor = isDark ? const Color(0xFF374151) : _borderColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: placeholder,
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 120,
                      height: 16,
                      decoration: BoxDecoration(
                        color: placeholderAlt,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 80,
                      height: 12,
                      decoration: BoxDecoration(
                        color: placeholder,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 60,
                height: 36,
                decoration: BoxDecoration(
                  color: placeholder,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: 150,
            height: 14,
            decoration: BoxDecoration(
              color: placeholderAlt,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: List.generate(
                3,
                (_) => Container(
                      width: 60,
                      height: 24,
                      decoration: BoxDecoration(
                        color: placeholder,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    )),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ffTheme = FlutterFlowTheme.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mq = MediaQuery.of(context);
    final screenWidth = mq.size.width;
    final screenHeight = mq.size.height;

    // Responsive calculations
    final bool isSmallScreen = screenWidth < 360;
    final bool isMediumScreen = screenWidth < 420;

    // Responsive padding
    final horizontalPadding =
        isSmallScreen ? 16.0 : (isMediumScreen ? 20.0 : 24.0);

    final filterChipHeight =
        screenHeight < 700 ? 42.0 : (isSmallScreen ? 46.0 : 52.0);

    final emptyIconSize =
        screenHeight < 600 ? 40.0 : (screenHeight < 700 ? 48.0 : 56.0);

    final emptyTitleSpacing = screenHeight < 600 ? 12.0 : 16.0;

    final emptySubSpacing = screenHeight < 600 ? 6.0 : 8.0;

    return Scaffold(
      key: scaffoldKey,
      backgroundColor: ffTheme.primaryBackground,
      appBar: AppBar(
        backgroundColor: ffTheme.primaryBackground,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_rounded,
            color: ffTheme.primaryText,
            size: 24,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Search',
          style: TextStyle(
            fontSize: isSmallScreen ? 18 : 20,
            fontWeight: FontWeight.w500,
            color: ffTheme.primaryText,
            letterSpacing: -0.5,
          ),
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search Bar
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: isSmallScreen ? 12 : 16,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? colorScheme.surfaceContainerHighest
                      : ffTheme.secondaryBackground,
                  borderRadius: BorderRadius.circular(isSmallScreen ? 10 : 12),
                  boxShadow: isDark
                      ? null
                      : [
                          BoxShadow(
                            color: Colors.black.withAlpha((0.02 * 255).round()),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                ),
                child: TextFormField(
                  controller: _model.textController,
                  focusNode: _model.textFieldFocusNode,
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  onChanged: _handleSearchInput,
                  textInputAction: TextInputAction.search,
                  onFieldSubmitted: (value) => _processSearchQuery(value),
                  style: TextStyle(
                    fontSize: isSmallScreen ? 14 : 15,
                    color: ffTheme.primaryText,
                    height: 1.4,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search artisans or services...',
                    hintStyle: TextStyle(
                      color: isDark
                          ? const Color(0xFF9CA3AF)
                          : ffTheme.secondaryText,
                      fontSize: isSmallScreen ? 14 : 15,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: isSmallScreen ? 16 : 20,
                      vertical: isSmallScreen ? 16 : 18,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: isDark
                          ? const Color(0xFF9CA3AF)
                          : ffTheme.secondaryText,
                      size: isSmallScreen ? 18 : 20,
                    ),
                    suffixIcon: _model.textController!.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(
                              Icons.clear_rounded,
                              size: isSmallScreen ? 16 : 18,
                              color: isDark
                                  ? const Color(0xFF9CA3AF)
                                  : ffTheme.secondaryText,
                            ),
                            onPressed: () {
                              setState(() {
                                _resetSearchContext(
                                    clearQuery: true, clearLastQuery: true);
                              });
                              _startSearch();
                            },
                          )
                        : null,
                  ),
                ),
              ),
            ),

            // Dynamic Tabs Section
            _buildTabsSection(
                isDark, horizontalPadding, filterChipHeight, isSmallScreen),

            // Divider with responsive height
            Container(
              height: 1,
              margin: EdgeInsets.symmetric(
                  horizontal: horizontalPadding, vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isDark ? const Color(0xFF374151) : _borderColor,
                    width: 1,
                  ),
                ),
              ),
            ),

            // Results Section
            Expanded(
              child: _hasSearched
                  ? _isLoading
                      ? ListView.builder(
                          padding: EdgeInsets.all(horizontalPadding),
                          itemCount: 3,
                          itemBuilder: (context, index) => _buildSkeletonCard(),
                        )
                      : _errorMessage != null
                          ? Center(
                              child: Padding(
                                padding: EdgeInsets.all(horizontalPadding),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.error_outline_rounded,
                                      size: emptyIconSize,
                                      color: isDark
                                          ? const Color(0xFF6B7280)
                                          : _textSecondary,
                                    ),
                                    SizedBox(height: emptyTitleSpacing),
                                    Text(
                                      _errorMessage!,
                                      style: TextStyle(
                                        fontSize: isSmallScreen ? 14 : 16,
                                        color: isDark
                                            ? Colors.white
                                            : _textPrimary,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    SizedBox(height: emptySubSpacing * 2),
                                    ElevatedButton(
                                      onPressed: _startSearch,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _primaryColor,
                                        foregroundColor: Colors.white,
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 24,
                                          vertical: 12,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                      ),
                                      child: const Text('Retry'),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : _artisans.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(horizontalPadding),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.search_off_rounded,
                                          size: emptyIconSize,
                                          color: isDark
                                              ? const Color(0xFF6B7280)
                                              : _textSecondary,
                                        ),
                                        SizedBox(height: emptyTitleSpacing),
                                        Text(
                                          _activeSearchTerm().isEmpty
                                              ? 'No artisans available'
                                              : 'No artisans found',
                                          style: TextStyle(
                                            fontSize: isSmallScreen ? 16 : 18,
                                            fontWeight: FontWeight.w500,
                                            color: isDark
                                                ? Colors.white
                                                : _textPrimary,
                                          ),
                                        ),
                                        SizedBox(height: emptySubSpacing),
                                        Text(
                                          _activeSearchTerm().isEmpty
                                              ? 'Try browsing another service category.'
                                              : 'No results for "${_activeSearchTerm()}". Try a different keyword or filter.',
                                          style: TextStyle(
                                            fontSize: isSmallScreen ? 13 : 14,
                                            color: isDark
                                                ? const Color(0xFF9CA3AF)
                                                : _textSecondary,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                        SizedBox(height: emptySubSpacing * 2),
                                        if (_activeSearchTerm().isNotEmpty)
                                          OutlinedButton(
                                            onPressed: () {
                                              setState(() {
                                                _resetSearchContext(
                                                    clearQuery: true,
                                                    clearLastQuery: true);
                                              });
                                              _startSearch();
                                            },
                                            style: OutlinedButton.styleFrom(
                                              side: BorderSide(
                                                color: isDark
                                                    ? const Color(0xFF4B5563)
                                                    : _borderColor,
                                              ),
                                              foregroundColor: isDark
                                                  ? Colors.white
                                                  : _textPrimary,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 18,
                                                vertical: 12,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                            ),
                                            child: const Text('Clear search'),
                                          ),
                                      ],
                                    ),
                                  ),
                                )
                              : RefreshIndicator(
                                  onRefresh: () async {
                                    await _startSearch();
                                  },
                                  color: _primaryColor,
                                  child: ListView.builder(
                                    controller: _scrollController,
                                    padding: EdgeInsets.all(horizontalPadding),
                                    itemCount: _artisans.length +
                                        (_isLoadingMore ? 1 : 0),
                                    itemBuilder: (context, index) {
                                      if (index < _artisans.length) {
                                        return _buildArtisanCard(
                                            context, _artisans[index]);
                                      } else {
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 24),
                                          child: Center(
                                            child: SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor:
                                                    AlwaysStoppedAnimation(
                                                        _primaryColor),
                                              ),
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                )
                  : Center(
                      child: Padding(
                        padding: EdgeInsets.all(horizontalPadding),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.search_rounded,
                              size: emptyIconSize,
                              color: isDark
                                  ? const Color(0xFF6B7280)
                                  : _textSecondary,
                            ),
                            SizedBox(height: emptyTitleSpacing),
                            Text(
                              'Find Artisans',
                              style: TextStyle(
                                fontSize: isSmallScreen ? 18 : 20,
                                fontWeight: FontWeight.w500,
                                color: isDark ? Colors.white : _textPrimary,
                                letterSpacing: -0.5,
                              ),
                            ),
                            SizedBox(height: emptySubSpacing),
                            Text(
                              'Search for skilled professionals',
                              style: TextStyle(
                                fontSize: isSmallScreen ? 13 : 14,
                                color: isDark
                                    ? const Color(0xFF9CA3AF)
                                    : _textSecondary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: emptySubSpacing / 2),
                            Text(
                              'Use filters or type a keyword',
                              style: TextStyle(
                                fontSize: isSmallScreen ? 12 : 13,
                                color: isDark
                                    ? const Color(0xFF9CA3AF)
                                    : _textSecondary,
                              ),
                              textAlign: TextAlign.center,
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
  }
}

// Extension methods for color manipulation
extension ColorExtension on Color {
  Color darken([double amount = .1]) {
    assert(amount >= 0 && amount <= 1);

    final hsl = HSLColor.fromColor(this);
    final hslDark = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));

    return hslDark.toColor();
  }

  Color lighten([double amount = .1]) {
    assert(amount >= 0 && amount <= 1);

    final hsl = HSLColor.fromColor(this);
    final hslLight =
        hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0));

    return hslLight.toColor();
  }
}
