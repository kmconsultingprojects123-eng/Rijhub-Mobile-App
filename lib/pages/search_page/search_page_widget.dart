import '/flutter_flow/flutter_flow_util.dart';
import 'search_page_model.dart';
export 'search_page_model.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../artisan_detail_page/artisan_detail_page_widget.dart';
import '../../services/artist_service.dart';
import '../../api_config.dart';

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
  final Color _primaryColor = const Color(0xFFA20025);
  final Color _surfaceColor = const Color(0xFFF9FAFB);
  final Color _textPrimary = const Color(0xFF111827);
  final Color _textSecondary = const Color(0xFF6B7280);
  final Color _borderColor = const Color(0xFFE5E7EB);

  // Service and subcategory management
  List<Map<String, dynamic>> _allMainServices = [];
  List<Map<String, dynamic>> _popularServices = [];
  List<Map<String, dynamic>> _currentSubservices = [];
  String? _currentMainCategory;
  String? _currentMainCategoryId;
  bool _isMainService = false;
  String? _lastSearchedQuery;

  // Cache for service data
  final Map<String, List<Map<String, dynamic>>> _subcategoryCache = {};
  final Map<String, List<String>> _serviceCache = {};

  // Search tracking
  Timer? _searchDebounceTimer;

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
      final uri = Uri.parse('$API_BASE_URL/api/job-categories?limit=100');
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
          final mainServices = items
              .map((e) {
            if (e is! Map) return null;
            final m = Map<String, dynamic>.from(e.cast<String, dynamic>());
            return {
              'id': m['_id'] ?? m['id'],
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
              _updatePopularServices();
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading main services: $e');
    }
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

  /// Intelligently match query to a main service using multiple strategies
  Map<String, dynamic>? _findBestServiceMatch(String query) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return null;

    // Strategy 1: Exact match
    try {
      return _allMainServices.firstWhere(
        (service) => service['name'].toString().toLowerCase() == normalizedQuery,
        orElse: () => <String, dynamic>{},
      );
    } catch (_) {}

    // Strategy 2: Query is contained in service name
    try {
      return _allMainServices.firstWhere(
        (service) => service['name'].toString().toLowerCase().contains(normalizedQuery),
        orElse: () => <String, dynamic>{},
      );
    } catch (_) {}

    // Strategy 3: Service name is contained in query
    try {
      return _allMainServices.firstWhere(
        (service) => normalizedQuery.contains(service['name'].toString().toLowerCase()),
        orElse: () => <String, dynamic>{},
      );
    } catch (_) {}

    // Strategy 4: Fuzzy matching by similarity score
    Map<String, dynamic>? bestMatch;
    double bestScore = 0.0;
    
    for (final service in _allMainServices) {
      final serviceName = service['name'].toString();
      final score = _calculateSimilarity(normalizedQuery, serviceName);
      
      if (score > bestScore) {
        bestScore = score;
        bestMatch = service;
      }
    }

    // Return match only if similarity exceeds threshold (45%)
    return (bestScore >= 0.45) ? bestMatch : null;
  }

  /// Process search query with intelligent Main Service mapping
  Future<void> _processSearchQuery(String query) async {
    if (query.isEmpty) {
      setState(() {
        _currentMainCategory = null;
        _currentMainCategoryId = null;
        _currentSubservices = [];
        _isMainService = false;
        _selectedTrade = null;
        _selectedSubservice = null;
      });
      _startSearch();
      return;
    }

    if (kDebugMode) debugPrint('SearchPage: Processing query: "$query"');

    // Try to find best matching main service
    final matchedService = _findBestServiceMatch(query);

    if (matchedService != null && matchedService.isNotEmpty) {
      // Found a matching main service - map to it
      final serviceId = matchedService['id'];
      final serviceName = matchedService['name'];
      
      if (kDebugMode) {
        debugPrint('SearchPage: Mapped query "$query" to main service "$serviceName" (ID: $serviceId)');
      }

      setState(() {
        _currentMainCategory = serviceName;
        _currentMainCategoryId = serviceId;
        _isMainService = true;
        _selectedTrade = serviceName;
        _selectedSubservice = null;
      });

      // Load sub-services for this main service
      await _loadSubservicesForMainService(serviceId);
    } else {
      // No main service match found - perform generic search
      if (kDebugMode) debugPrint('SearchPage: No main service match for "$query", performing generic search');

      setState(() {
        _currentMainCategory = null;
        _currentMainCategoryId = null;
        _currentSubservices = [];
        _isMainService = false;
        _selectedTrade = null;
        _selectedSubservice = null;
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

    try {
      final uri = Uri.parse('$API_BASE_URL/api/job-subcategories?categoryId=$categoryId&limit=50');
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
        debugPrint('SearchPage._fetchArtisans -> q="$q" tradeParam=$tradeParam subservice=$subserviceParam isMainService=$_isMainService page=$_page limit=$_limit');
      }

      final results = await ArtistService.fetchArtisans(
        page: _page,
        limit: _limit,
        q: !_isMainService && q.isNotEmpty ? q : null,
        trade: tradeParam,
        subCategoryId: subserviceParam,
      );

      if (!mounted) return;

      if (results.isNotEmpty) {
        setState(() {
          _artisans.addAll(results);
          _hasMore = results.length == _limit;
          if (_hasMore) _page++;
        });

        // Extract main category from first artisan's services (if on first page)
        if (reset && results.isNotEmpty) {
          final firstArtisan = results.first;
          if (firstArtisan['services'] is List && (firstArtisan['services'] as List).isNotEmpty) {
            final firstService = (firstArtisan['services'] as List)[0];
            if (firstService is Map<String, dynamic>) {
              final categoryId = firstService['categoryId'];
              String? extractedCategoryId;
              String? extractedCategoryName;

              if (categoryId is Map<String, dynamic>) {
                extractedCategoryId = categoryId['_id']?.toString() ?? categoryId['id']?.toString();
                extractedCategoryName = categoryId['name']?.toString();
              } else if (categoryId is String) {
                extractedCategoryId = categoryId;
              }

              // Update subservices based on the extracted category
              if (extractedCategoryId != null && extractedCategoryId.isNotEmpty) {
                await _loadSubservicesForMainService(extractedCategoryId);
                if (kDebugMode) debugPrint('SearchPage: Updated subservices for category: $extractedCategoryName (id: $extractedCategoryId)');
              }
            }
          }
        }

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
          _errorMessage = 'Failed to load artisans. Please check your connection.';
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
        .where((id) => id != null && id.isNotEmpty && !_serviceCache.containsKey(id))
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
      if (kDebugMode) debugPrint('SearchPage: Returning cached services for artisanId=$artisanId');
      return _serviceCache[artisanId] ?? <String>[];
    }

    try {
      final uri = Uri.parse('$API_BASE_URL/api/artisan-services?artisanId=$artisanId&limit=100');
      if (kDebugMode) debugPrint('SearchPage: Fetching services from: $uri');

      final response = await http.get(uri).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (kDebugMode) debugPrint('SearchPage: Services API response for $artisanId: ${body.toString().substring(0, min(500, body.toString().length))}');

        final List<String> services = [];

        // Handle different response structures
        if (body is Map<String, dynamic>) {
          // Case 1: Response has a 'data' field that's an array
          if (body['data'] is List) {
            final items = body['data'] as List;
            for (var item in items) {
              if (item is Map<String, dynamic>) {
                _extractServiceNames(item, services);
              }
            }
          }
          // Case 2: Response has a 'services' field that's an array
          else if (body['services'] is List) {
            final items = body['services'] as List;
            for (var item in items) {
              if (item is Map<String, dynamic>) {
                _extractServiceNames(item, services);
              }
            }
          }
          // Case 3: Response is a single service object
          else {
            _extractServiceNames(body, services);
          }
        }
        // Case 4: Response is directly an array
        else if (body is List) {
          for (var item in body) {
            if (item is Map<String, dynamic>) {
              _extractServiceNames(item, services);
            }
          }
        }

        // Remove duplicates
        final uniqueServices = services.toSet().toList();

        // Cache the result
        _serviceCache[artisanId] = uniqueServices;
        if (kDebugMode) debugPrint('SearchPage: Found ${uniqueServices.length} services for artisanId=$artisanId: $uniqueServices');

        return uniqueServices;
      } else {
        if (kDebugMode) debugPrint('SearchPage: API returned status ${response.statusCode} for artisanId=$artisanId');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error fetching artisan services: $e');
    }

    // Cache empty result to avoid repeated failed requests
    _serviceCache[artisanId] = <String>[];
    return <String>[];
  }

  /// Helper method to extract service names from various possible structures
  void _extractServiceNames(Map<String, dynamic> item, List<String> services) {
    // Try direct name fields
    final directName = item['name'] ??
        item['serviceName'] ??
        item['title'] ??
        item['service'] ??
        item['service_type'] ??
        item['category'];

    if (directName != null && directName.toString().isNotEmpty) {
      services.add(directName.toString());
      return;
    }

    // Try nested objects
    final nestedFields = ['subCategoryId', 'subCategory', 'subcategory', 'categoryId', 'category'];
    for (final field in nestedFields) {
      if (item[field] is Map) {
        final nested = item[field] as Map<String, dynamic>;
        final nestedName = nested['name'] ??
            nested['title'] ??
            nested['label'] ??
            nested['service'];
        if (nestedName != null && nestedName.toString().isNotEmpty) {
          services.add(nestedName.toString());
          return;
        }
      }
    }

    // Try array fields
    final arrayFields = ['services', 'items', 'list'];
    for (final field in arrayFields) {
      if (item[field] is List) {
        final array = item[field] as List;
        for (var element in array) {
          if (element is Map<String, dynamic>) {
            final elementName = element['name'] ??
                element['title'] ??
                element['service'];
            if (elementName != null && elementName.toString().isNotEmpty) {
              services.add(elementName.toString());
            }
          }
        }
      }
    }
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
    final horizontalPadding = isSmallScreen ? 14.0 : (isMediumScreen ? 16.0 : 20.0);
    final verticalPadding = isSmallScreen ? 8.0 : (isMediumScreen ? 10.0 : 12.0);

    // Adaptive font size
    final fontSize = isSmallScreen ? 13.0 : (isMediumScreen ? 14.0 : 15.0);

    // Adaptive border radius
    final borderRadius = BorderRadius.circular(isSmallScreen ? 16 : 20);

    // Adaptive colors based on theme
    final backgroundColor = selected
        ? _primaryColor
        : Colors.transparent;

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
          boxShadow: selected ? [
            BoxShadow(
              color: shadowColor,
              blurRadius: 8,
              offset: const Offset(0, 2),
              spreadRadius: 0,
            ),
          ] : null,
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
  Widget _buildTabsSection(bool isDark, double horizontalPadding, double filterChipHeight, bool isSmallScreen) {
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
                      // Clear subservice filter but keep main service
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
                              _selectedSubservice = selected ? null : subserviceId;
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
      // Show popular services for random/browsing mode
      return _popularServices.isEmpty
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
              'Popular Services',
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
                _popularServices.length,
                (index) {
                  final service = _popularServices[index];
                  final serviceName = service['name'] ?? 'Service';
                  final selected = _selectedTrade == serviceName;

                  return _buildEnhancedFilterChip(
                    label: serviceName,
                    selected: selected,
                    onTap: () {
                      setState(() {
                        _selectedTrade = selected ? null : serviceName;
                        _model.textController?.text = selected ? '' : serviceName;
                      });

                      if (!selected) {
                        // When tapping a popular service, treat it as a main service search
                        _processSearchQuery(serviceName);
                      } else {
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
    final Color cardBorderColor = isDark ? const Color(0xFF374151) : _borderColor;
    final Color textPrimaryColor = isDark ? Colors.white : _textPrimary;
    final Color textSecondaryColor = isDark ? const Color(0xFF9CA3AF) : _textSecondary;

    // Trade badge background color - using primary color with opacity
    final Color tradeBadgeColor = isDark
        ? _primaryColor.withAlpha((0.2 * 255).round())
        : _primaryColor.withAlpha((0.1 * 255).round());
    final Color tradeTextColor = isDark
        ? _primaryColor.lighten(0.2)
        : _primaryColor.darken(0.1);

    String _extractName(Map<String, dynamic> src) {
      try {
        final top = src['name'];
        if (top != null && top.toString().trim().isNotEmpty) return top.toString().trim();

        // Fixed: Removed duplicate entry
        final authKeys = {'artisanAuthDetails', 'artisanAuthdDetails', 'artisanAuthdetails'}.toList();
        for (final k in authKeys) {
          final a = src[k];
          if (a is Map && a['name'] != null && a['name'].toString().trim().isNotEmpty) return a['name'].toString().trim();
        }

        final possibleKeys = ['user', 'userId', 'owner', 'artisan'];
        for (final k in possibleKeys) {
          final p = src[k];
          if (p is Map && p['name'] != null && p['name'].toString().trim().isNotEmpty) return p['name'].toString().trim();
        }
      } catch (_) {}
      return 'Artisan';
    }

    String _extractImageUrl(Map<String, dynamic> src) {
      try {
        for (final k in ['profileImage', 'profile_image', 'profileImageUrl', 'profileImageURL', 'avatar', 'image']) {
          final v = src[k];
          if (v is String && v.isNotEmpty) return v;
          if (v is Map) {
            final u = v['url'] ?? v['secure_url'] ?? v['uri'] ?? v['value'];
            if (u is String && u.isNotEmpty) return u;
          }
        }

        final nestedKeys = ['user', 'userId', 'artisan', 'owner', 'artisanUser', 'artisanProfile', 'artisanAuthDetails', 'artisanAuthdDetails', 'artisanAuthdetails'];
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
          final maybe = _extractImageUrl(Map<String, dynamic>.from(src['artisanProfile']));
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
    if (location.isEmpty) location = artisan['location'] ?? artisan['city'] ?? '';

    // Extract rating and review count
    final rating = (artisan['rating'] is num) ? (artisan['rating'] as num).toDouble() :
    (artisan['averageRating'] ?? artisan['average_rating'] ?? 0).toDouble();
    final reviewCount = artisan['reviewsCount'] ?? artisan['reviewCount'] ?? artisan['review_count'] ?? 0;

    // Extract artisan ID to fetch their services
    String? artisanId;
    try {
      artisanId = (artisan['_id'] ?? artisan['id'] ?? artisan['artisanId'])?.toString();
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
      final parts = s.trim().split(' ');
      if (parts.isEmpty) return 'A';
      if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
      return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
    }

    return FutureBuilder<List<String>>(
      future: _fetchArtisanServicesForCard(artisanId),
      builder: (context, snapshot) {
        if (kDebugMode) {
          debugPrint('FutureBuilder for artisan $artisanId - state: ${snapshot.connectionState}, hasData: ${snapshot.hasData}, data: ${snapshot.data}');
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
                                  valueColor: AlwaysStoppedAnimation(_primaryColor),
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
                              builder: (_) => ArtisanDetailPageWidget(artisan: artisan),
                            ),
                          );
                        } catch (_) {}
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryColor,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          horizontal: MediaQuery.of(context).size.width < 360 ? 16 : 20,
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

              // Location
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

              // Services - FIXED: Now showing from API
              if (services.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: services.take(3).map((service) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: tradeBadgeColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _primaryColor.withAlpha((0.2 * 255).round()),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        service,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: tradeTextColor,
                          letterSpacing: -0.1,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
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
    final borderColor = isDark
        ? const Color(0xFF374151)
        : _borderColor;

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
            children: List.generate(3, (_) => Container(
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mq = MediaQuery.of(context);
    final screenWidth = mq.size.width;
    final screenHeight = mq.size.height;

    // Responsive calculations
    final bool isSmallScreen = screenWidth < 360;
    final bool isMediumScreen = screenWidth < 420;

    // Responsive padding
    final horizontalPadding = isSmallScreen
        ? 16.0
        : (isMediumScreen ? 20.0 : 24.0);

    final filterChipHeight = screenHeight < 700
        ? 42.0
        : (isSmallScreen ? 46.0 : 52.0);

    final emptyIconSize = screenHeight < 600
        ? 40.0
        : (screenHeight < 700 ? 48.0 : 56.0);

    final emptyTitleSpacing = screenHeight < 600
        ? 12.0
        : 16.0;

    final emptySubSpacing = screenHeight < 600
        ? 6.0
        : 8.0;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: isDark ? Colors.black : Colors.white,
        appBar: AppBar(
          backgroundColor: isDark ? Colors.black : Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_rounded,
              color: isDark ? Colors.white : _textPrimary,
              size: 24,
            ),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: Text(
            'Search',
            style: TextStyle(
              fontSize: isSmallScreen ? 18 : 20,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : _textPrimary,
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
                    color: isDark ? const Color(0xFF1F2937) : _surfaceColor,
                    borderRadius: BorderRadius.circular(isSmallScreen ? 10 : 12),
                    boxShadow: isDark ? null : [
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
                    onTap: () {
                      if (!mounted) return;
                      setState(() {
                        _selectedTrade = null;
                        _selectedSubservice = null;
                      });
                    },
                    onChanged: _handleSearchInput,
                    textInputAction: TextInputAction.search,
                    onFieldSubmitted: (value) => _processSearchQuery(value),
                    style: TextStyle(
                      fontSize: isSmallScreen ? 14 : 15,
                      color: isDark ? Colors.white : _textPrimary,
                      height: 1.4,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search artisans or services...',
                      hintStyle: TextStyle(
                        color: isDark ? const Color(0xFF9CA3AF) : _textSecondary,
                        fontSize: isSmallScreen ? 14 : 15,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: isSmallScreen ? 16 : 20,
                        vertical: isSmallScreen ? 16 : 18,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: isDark ? const Color(0xFF9CA3AF) : _textSecondary,
                        size: isSmallScreen ? 18 : 20,
                      ),
                      suffixIcon: _model.textController!.text.isNotEmpty
                          ? IconButton(
                        icon: Icon(
                          Icons.clear_rounded,
                          size: isSmallScreen ? 16 : 18,
                          color: isDark ? const Color(0xFF9CA3AF) : _textSecondary,
                        ),
                        onPressed: () {
                          _model.textController?.clear();
                          setState(() {
                            _currentMainCategory = null;
                            _currentMainCategoryId = null;
                            _currentSubservices = [];
                            _isMainService = false;
                            _selectedTrade = null;
                            _selectedSubservice = null;
                            _lastSearchedQuery = null;
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
              _buildTabsSection(isDark, horizontalPadding, filterChipHeight, isSmallScreen),

              // Divider with responsive height
              Container(
                height: 1,
                margin: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 8),
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
                          color: isDark ? const Color(0xFF6B7280) : _textSecondary,
                        ),
                        SizedBox(height: emptyTitleSpacing),
                        Text(
                          _errorMessage!,
                          style: TextStyle(
                            fontSize: isSmallScreen ? 14 : 16,
                            color: isDark ? Colors.white : _textPrimary,
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
                              borderRadius: BorderRadius.circular(12),
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
                          color: isDark ? const Color(0xFF6B7280) : _textSecondary,
                        ),
                        SizedBox(height: emptyTitleSpacing),
                        Text(
                          'No artisans found',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 16 : 18,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white : _textPrimary,
                          ),
                        ),
                        SizedBox(height: emptySubSpacing),
                        Text(
                          'Try different keywords or filters',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 13 : 14,
                            color: isDark ? const Color(0xFF9CA3AF) : _textSecondary,
                          ),
                          textAlign: TextAlign.center,
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
                    itemCount: _artisans.length + (_isLoadingMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index < _artisans.length) {
                        return _buildArtisanCard(context, _artisans[index]);
                      } else {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(_primaryColor),
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
                          color: isDark ? const Color(0xFF6B7280) : _textSecondary,
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
                            color: isDark ? const Color(0xFF9CA3AF) : _textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: emptySubSpacing / 2),
                        Text(
                          'Use filters or type a keyword',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 12 : 13,
                            color: isDark ? const Color(0xFF9CA3AF) : _textSecondary,
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
    final hslLight = hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0));

    return hslLight.toColor();
  }
}