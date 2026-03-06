import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';
import 'all_servicepage_model.dart';
import '../../services/job_service.dart';
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../search_page/search_page_widget.dart' as sp;
export 'all_servicepage_model.dart';

class AllServicepageWidget extends StatefulWidget {
  const AllServicepageWidget({super.key});

  static String routeName = 'allServicepage';
  static String routePath = '/allServicepage';

  @override
  State<AllServicepageWidget> createState() => _AllServicepageWidgetState();
}

class _AllServicepageWidgetState extends State<AllServicepageWidget> with RouteAware {
  late AllServicepageModel _model;
  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => AllServicepageModel());

    _model.textController ??= TextEditingController();
    _model.textFieldFocusNode ??= FocusNode();
    _fetchJobCategories();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    try {
      routeObserver.subscribe(this, ModalRoute.of(context)!);
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    try { routeObserver.unsubscribe(this); } catch (_) {}
    try { _scrollController.removeListener(_onScroll); _scrollController.dispose(); } catch (_) {}
    _model.dispose();
    super.dispose();
  }

  // Called when this route is pushed back onto the navigator (e.g. user
  // returns to this page). We'll refresh categories so the UI stays fresh.
  @override
  void didPopNext() {
    // Background refresh but show a small loader if empty
    _fetchJobCategories(forceRefresh: true);
  }

  // Dynamic service list loaded from the server's Job Category endpoint
  // _allServices keeps the full, unfiltered list. _services is the currently
  // visible (possibly filtered) list shown in the grid.
  List<ServiceItem> _allServices = [];
  List<ServiceItem> _services = [];
  bool _loadingServices = true;
  String? _servicesError;
  String _searchQuery = '';
  Timer? _searchDebounce;
  static const String _cacheKey = 'job_categories_cache_v1';
  // Pagination state
  final ScrollController _scrollController = ScrollController();
  int _currentPage = 1;
  static const int _pageSize = 18; // number of items per page
  bool _hasMore = true;
  bool _loadingMore = false;

  // Map known category names/slugs to colors and icons (keeps parity with Home page)
  static const Map<String, Color> _categoryColorMap = {
    'carpentry': Color(0xFFFF6B35),
    'catering': Color(0xFF00C9A7),
    'cleaning': Color(0xFF4CD964),
    'electric': Color(0xFF5E5CE6),
    'gardening': Color(0xFF32D74B),
    'maintenance': Color(0xFF64D2FF),
    'mechanic': Color(0xFFFF375F),
    'tailor': Color(0xFFBF5AF2),
    'painting': Color(0xFF805AD5),
    'beauty': Color(0xFFD69E2E),
    'moving': Color(0xFF4FD1C5),
    'it': Color(0xFFA20025),
  };

  // Known icon map (fall back to a generic work icon)
  static const Map<String, IconData> _categoryIconMap = {
    'carpentry': FFIcons.kcapentry,
    'catering': FFIcons.kcatering,
    'cleaning': FFIcons.kcleaning,
    'electric': FFIcons.kelectrictian,
    'gardening': FFIcons.kgardener,
    'maintenance': FFIcons.kmaintainace,
    'mechanic': FFIcons.kmechanic,
    'tailor': FFIcons.ktailor,
  };

  /// Fetch job categories. If [append] is true, load the next page and append.
  /// If [forceRefresh] is true (typically on pull-to-refresh) start at page 1
  /// and replace existing items.
  Future<void> _fetchJobCategories({bool forceRefresh = false, bool append = false}) async {
    _servicesError = null;

    // If forcing refresh, reset pagination state
    if (forceRefresh && !append) {
      _currentPage = 1;
      _hasMore = true;
    }

    // Show cached items if present (only on initial non-forced load)
    if (!forceRefresh && !append) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_cacheKey);
        if (raw != null && raw.isNotEmpty) {
          final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
          final fromCache = decoded.cast<Map<String, dynamic>>();
          final items = fromCache.map((c) => _mapCategoryToServiceItem(c)).toList();
          // Populate both master and visible lists from cache
          if (mounted) setState(() { _allServices = items; _services = List<ServiceItem>.from(items); _loadingServices = false; });
        }
      } catch (_) {
        // ignore cache read errors and continue to network fetch
      }
    } else {
      // If not showing cached items (forced refresh or append), update loading flags
      if (append) {
        if (mounted) setState(() { _loadingMore = true; });
      } else {
        if (mounted) setState(() { _loadingServices = true; });
      }
    }

    // Determine page to fetch
    final int pageToFetch = append ? (_currentPage + 1) : _currentPage;

    try {
      final cats = await JobService.getJobCategories(page: pageToFetch, limit: _pageSize);
      if (!mounted) return;

      // Map API results to items
      final newItems = cats.map((c) => _mapCategoryToServiceItem(c)).toList();

      // Keep master list in sync. If appending, append to _allServices,
      // otherwise replace it.
      if (append) {
        _allServices = List<ServiceItem>.from(_allServices)..addAll(newItems);
      } else {
        _allServices = newItems;
      }

      // Apply current search filter to determine visible _services
      _applySearchFilter();

      if (append) {
        // When appending we already updated _allServices above; just update
        // loading flags. Visible _services were updated by _applySearchFilter.
        if (mounted) setState(() {
          _loadingMore = false;
          _servicesError = null;
        });
        _currentPage = pageToFetch;
      } else {
        // Replace
        if (mounted) setState(() {
          _loadingServices = false;
          _servicesError = null;
        });
        _currentPage = pageToFetch;
      }

      // Update hasMore: if we received fewer than pageSize, no more pages
      if (newItems.length < _pageSize) {
        _hasMore = false;
      } else {
        _hasMore = true;
      }

      // Persist the full list to cache
      try {
        final prefs = await SharedPreferences.getInstance();
        // store the current (possibly appended) list as raw API-like maps when possible.
        // We try to persist by re-encoding the displayed ServiceItem list in a compact form.
        final rawToStore = _allServices.map((s) => {
          'name': s.title,
          'slug': s.searchQuery,
          'description': s.description,
        }).toList();
        await prefs.setString(_cacheKey, jsonEncode(rawToStore));
      } catch (_) {}
    } catch (e) {
      if (!mounted) return;
      if (_services.isEmpty) {
        setState(() {
          _servicesError = e.toString();
          _loadingServices = false;
          _loadingMore = false;
        });
      } else {
        // background refresh / pagination failed; keep current items and hide loadingMore
        setState(() { _loadingServices = false; _loadingMore = false; });
      }
    }
  }

  ServiceItem _mapCategoryToServiceItem(Map<String, dynamic> c) {
    final name = (c['name'] ?? c['title'] ?? '').toString();
    final slug = (c['slug'] ?? '').toString().toLowerCase();
    final desc = (c['description'] ?? '').toString();

    Color color = const Color(0xFFA20025); // fallback
    for (final key in _categoryColorMap.keys) {
      if (slug.contains(key) || name.toLowerCase().contains(key)) {
        color = _categoryColorMap[key]!;
        break;
      }
    }

    // Pick an icon dynamically from the name/slug using keyword heuristics.
    // Falls back to category-specific icon map, then to a general work icon.
    IconData icon = _pickIconForName(name, slug) ?? Icons.work_outline;

    return ServiceItem(
      title: name.isNotEmpty ? name : (slug.isNotEmpty ? slug : 'Service'),
      icon: icon,
      color: color,
      searchQuery: name.isNotEmpty ? name : slug,
      description: desc.isNotEmpty ? desc : 'Professional service',
    );
  }

  /// Choose an IconData that best matches [name] or [slug] using simple
  /// keyword heuristics. Returns null when no match found.
  IconData? _pickIconForName(String name, String slug) {
    final s = (name + " " + slug).toLowerCase();

    // explicit keyword -> icon map (material icons + project FFIcons where available)
    final Map<String, IconData> map = {
      'carpenter': FFIcons.kcapentry, 'carpentry': FFIcons.kcapentry, 'wood': FFIcons.kcapentry,
      'cater': FFIcons.kcatering, 'catering': FFIcons.kcatering, 'chef': Icons.restaurant,
      'clean': FFIcons.kcleaning, 'cleaning': FFIcons.kcleaning, 'maid': Icons.cleaning_services,
      'plumb': Icons.plumbing, 'plumber': Icons.plumbing, 'pipe': Icons.plumbing,
      'electric': FFIcons.kelectrictian, 'electrician': FFIcons.kelectrictian, 'wiring': Icons.electrical_services,
      'garden': FFIcons.kgardener, 'gardening': FFIcons.kgardener, 'lawn': Icons.grass,
      'maintain': FFIcons.kmaintainace, 'maintenance': FFIcons.kmaintainace, 'repair': Icons.build,
      'mechanic': FFIcons.kmechanic, 'car': Icons.car_repair, 'auto': Icons.car_repair,
      'tailor': FFIcons.ktailor, 'sew': FFIcons.ktailor, 'tailoring': FFIcons.ktailor,
      'paint': Icons.format_paint, 'painter': Icons.format_paint, 'painting': Icons.format_paint,
      'beauty': Icons.spa, 'hair': Icons.content_cut, 'salon': Icons.content_cut,
      'moving': Icons.local_shipping, 'movers': Icons.local_shipping, 'delivery': Icons.delivery_dining,
      'it': Icons.computer, 'tech': Icons.computer, 'computer': Icons.computer,
      'tutor': Icons.school, 'teaching': Icons.school, 'education': Icons.school,
      'photo': Icons.camera_alt, 'photography': Icons.camera_alt, 'photographer': Icons.camera_alt,
      'laundry': Icons.local_laundry_service, 'wash': Icons.local_laundry_service,
      'pest': Icons.bug_report, 'pestcontrol': Icons.bug_report,
      'security': Icons.security, 'lock': Icons.lock,
      'massage': Icons.spa, 'spa': Icons.spa,
      'plumbing': Icons.plumbing, 'roof': Icons.home_repair_service, 'cycle': Icons.pedal_bike,
    };

    for (final key in map.keys) {
      if (s.contains(key)) return map[key];
    }

    // Fallback: try to find any meaningful single-word noun and map generically
    final words = s.split(RegExp(r'[^a-z0-9]+')).where((w) => w.length > 3).toList();
    for (final w in words) {
      if (w.contains('car') || w.contains('auto')) return Icons.car_repair;
      if (w.contains('clean')) return Icons.cleaning_services;
      if (w.contains('cook') || w.contains('food') || w.contains('chef')) return Icons.restaurant;
      if (w.contains('tech') || w.contains('it') || w.contains('computer')) return Icons.computer;
      if (w.contains('paint')) return Icons.format_paint;
      if (w.contains('repair') || w.contains('fix')) return Icons.build;
      if (w.contains('photo') || w.contains('camera')) return Icons.camera_alt;
      if (w.contains('move') || w.contains('mover')) return Icons.local_shipping;
      if (w.contains('tal') || w.contains('sew')) return FFIcons.ktailor;
    }

    return null;
  }

  void _handleServiceTap(String query) {
    final q = query.trim();
    if (q.isEmpty) return;
    // Direct navigation: push the Search page with the initial query.
    // This is deterministic and avoids fallbacks that cause inconsistent UX.
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => sp.SearchPageWidget(initialQuery: q)),
    );
  }

  Widget _buildServiceCard(ServiceItem service, BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _handleServiceTap(service.searchQuery),
        splashColor: service.color.withOpacity(0.08),
        highlightColor: Colors.transparent,
        child: Container(
          height: 125, // Fixed height to prevent overflow
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
              width: 1.5,
            ),
            color: isDark ? Colors.grey.shade900.withOpacity(0.5) : Colors.white,
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisSize: MainAxisSize.min, // Use min to prevent overflow
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Icon container - fixed size
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.cardColor,
                  ),
                  child: Center(
                    child: Icon(
                      service.icon,
                      // Use the app's main color for icons to maintain brand consistency
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // Service title with fixed constraints
                Flexible(
                  child: Container(
                    height: 30, // Fixed height for text
                    alignment: Alignment.center,
                    child: Text(
                      service.title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                        fontSize: 11, // Smaller font for better fit
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),

                const SizedBox(height: 4),

                // Available badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: theme.dividerColor.withOpacity(0.08)),
                  ),
                  child: Text(
                    'Available',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                      fontSize: 8, // Smaller badge font
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSkeletonCard(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 125, // Same fixed height
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
            width: 1.5,
          ),
          color: isDark ? Colors.grey.shade900.withOpacity(0.5) : Colors.white,
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Skeleton icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                ),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.0,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Skeleton text
              Container(
                height: 30,
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),

              const SizedBox(height: 4),

              // Skeleton badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: theme.dividerColor.withOpacity(0.08)),
                ),
                child: Text(
                  'Available',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || _loadingServices) return;
    if (!_scrollController.hasClients) return;
    final threshold = 300.0; // px from bottom to trigger
    final maxScroll = _scrollController.position.maxScrollExtent;
    final current = _scrollController.position.pixels;
    if (maxScroll - current <= threshold) {
      // load next page
      _fetchJobCategories(append: true);
    }
  }

  /// Applies the current text search stored in [_searchQuery] against the
  /// master list [_allServices] and updates [_services] shown in the UI.
  void _applySearchFilter() {
    if (_searchQuery.isEmpty) {
      setState(() => _services = List<ServiceItem>.from(_allServices));
      return;
    }

    final q = _searchQuery.toLowerCase();
    final filtered = _allServices.where((s) => s.title.toLowerCase().contains(q)).toList();
    setState(() => _services = filtered);
  }

  /// Debounced search handler called from the TextFormField.
  void _onSearchChanged(String val) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _searchQuery = val.trim();
      _applySearchFilter();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: isDark ? Colors.black : Colors.white,
        appBar: AppBar(
          backgroundColor: isDark ? Colors.black : Colors.white,
          automaticallyImplyLeading: false,
          title: Container(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.chevron_left_rounded,
                        color: colorScheme.onSurface.withOpacity(0.85),
                        size: 28,
                      ),
                      onPressed: () => context.safePop(),
                      splashRadius: 20,
                    ),
                    Text(
                      'All Services',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(width: 48), // Balance for centering
                  ],
                ),

                // Search area
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[900] : Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colorScheme.onSurface.withOpacity(0.1),
                      width: 1,
                    ),
                  ),
                  child: TextFormField(
                    controller: _model.textController,
                    focusNode: _model.textFieldFocusNode,
                    autofocus: false,
                    style: theme.textTheme.bodyMedium,
                    decoration: InputDecoration(
                      hintText: 'Search for services...',
                      hintStyle: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.5),
                      ),
                      filled: true,
                      fillColor: isDark ? Colors.grey[900] : Colors.grey[50],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                        borderSide: BorderSide(
                          color: const Color(0xFFA20025),
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: colorScheme.onSurface.withOpacity(0.5),
                        size: 20,
                      ),
                      suffixIcon: _model.textController!.text.isNotEmpty
                          ? IconButton(
                        icon: Icon(
                          Icons.clear_rounded,
                          size: 18,
                          color: colorScheme.onSurface.withOpacity(0.5),
                        ),
                        onPressed: () {
                          _model.textController?.clear();
                          setState(() {});
                          // clear the search filter as well
                          _onSearchChanged('');
                        },
                        splashRadius: 16,
                      )
                          : null,
                    ),
                    onChanged: (val) {
                      // keep suffix icon state in sync
                      setState(() {});
                      // filter services on the page as user types
                      _onSearchChanged(val);
                    },
                    onFieldSubmitted: (val) {
                      if (val.trim().isNotEmpty) {
                        _handleServiceTap(val);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          toolbarHeight: 140, // Fixed height for the app bar
        ),
        body: SafeArea(
          top: false, // Since we're using AppBar, we don't need SafeArea at top
          child: RefreshIndicator(
            onRefresh: () async => _fetchJobCategories(forceRefresh: true),
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                // Header content
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Discover Professional Services',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface.withOpacity(0.8),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Connect with skilled artisans and service providers for all your needs',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Services grid - Use mainAxisExtent instead of aspectRatio
                if (_loadingServices && _services.isEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        mainAxisExtent: 125, // Fixed height for all cards
                      ),
                      delegate: SliverChildBuilderDelegate(
                            (context, index) => _buildSkeletonCard(context),
                        childCount: 6,
                      ),
                    ),
                  )
                else if (_servicesError != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: colorScheme.error.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: colorScheme.error.withOpacity(0.12)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Could not load services', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                                const SizedBox(height: 8),
                                Text(_servicesError ?? 'An unknown error occurred', style: theme.textTheme.bodySmall),
                                const SizedBox(height: 12),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: _fetchJobCategories,
                                    child: const Text('Retry'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (_services.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
                        child: Center(
                          child: Text(
                            _searchQuery.isNotEmpty
                                ? 'No services match your search.'
                                : 'No services available yet. Check back later.',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          mainAxisExtent: 125, // Fixed height for all cards
                        ),
                        delegate: SliverChildBuilderDelegate(
                              (context, index) => _buildServiceCard(
                            _services[index],
                            context,
                          ),
                          childCount: _services.length,
                        ),
                      ),
                    ),

                // Show loading indicator at bottom when loading more pages
                if (_loadingMore)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.2)
                        ),
                      ),
                    ),
                  ),

                // Coming soon section
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: colorScheme.primary.withOpacity(0.1),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: colorScheme.primary,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.add_business_outlined,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'More Services Coming Soon',
                                      style: theme.textTheme.bodyLarge?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'We\'re constantly adding new categories to serve you better',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurface.withOpacity(0.6),
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Helper class for service data
class ServiceItem {
  final String title;
  final IconData icon;
  final Color color;
  final String searchQuery;
  final String description;

  ServiceItem({
    required this.title,
    required this.icon,
    required this.color,
    required this.searchQuery,
    required this.description,
  });
}