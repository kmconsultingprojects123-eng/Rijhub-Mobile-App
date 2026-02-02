import '/flutter_flow/flutter_flow_util.dart';
import 'search_page_model.dart';
export 'search_page_model.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';
import '../artisan_detail_page/artisan_detail_page_widget.dart';
import '../../services/artist_service.dart';

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

  // Minimalist color scheme
  final Color _primaryColor = const Color(0xFFA20025);
  final Color _surfaceColor = const Color(0xFFF9FAFB);
  final Color _textPrimary = const Color(0xFF111827);
  final Color _textSecondary = const Color(0xFF6B7280);
  final Color _borderColor = const Color(0xFFE5E7EB);

  // Popular items
  final List<String> _popularTrades = ['All', 'Electrician', 'Plumber', 'Carpenter', 'Painter', 'Cleaner'];

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

    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _model.textController!.text = widget.initialQuery!;
        _startSearch();
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
    for (final t in _debounceTimers.values) {
      try {
        t?.cancel();
      } catch (_) {}
    }
    _debounceTimers.clear();
    _scrollController.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _startSearch() async {
    setState(() {
      _hasSearched = true;
      _isLoading = true;
      _page = 1;
      _hasMore = true;
      _artisans.clear();
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
      final tradeParam = (_selectedTrade != null && _selectedTrade!.isNotEmpty && _selectedTrade != 'All') ? _selectedTrade : null;
      if (kDebugMode) {
        try {
          debugPrint('SearchPage._fetchArtisans -> q="$q" tradeParam=$tradeParam page=$_page limit=$_limit');
        } catch (_) {}
      }

      final results = await ArtistService.fetchArtisans(
        page: _page,
        limit: _limit,
        q: q.isNotEmpty ? q : null,
        trade: tradeParam,
      );

      if (!mounted) return;

      if (results.isNotEmpty) {
        setState(() {
          _artisans.addAll(results);
          _hasMore = results.length == _limit;
          if (_hasMore) _page++;
        });
      } else {
        setState(() => _hasMore = false);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error fetching artisans: $e');
      if (mounted) setState(() => _hasMore = false);
      return;
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _fetchMore() async {
    if (_isLoadingMore || !_hasMore) return;
    await _fetchArtisans(reset: false);
  }

  final Map<String, Timer?> _debounceTimers = {};

  void _debounce(String key, Duration duration, VoidCallback action) {
    _debounceTimers[key]?.cancel();
    _debounceTimers[key] = Timer(duration, action);
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
    // final bool isLargeScreen = screenWidth >= 420; // isLargeScreen not needed

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
          bottom: screenHeight < 700 ? 4.0 : 0, // Extra bottom margin on very short screens
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
            key: ValueKey('$label-$selected'), // Force animation on selection change
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

        final authKeys = ['artisanAuthDetails', 'artisanAuthdDetails', 'artisanAuthdDetails', 'artisanAuthdetails'];
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

    final name = _extractName(artisan);

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

    var imageUrl = _extractImageUrl(artisan);
    if (imageUrl.startsWith('//')) imageUrl = 'https:$imageUrl';
    imageUrl = imageUrl.trim();

    final trades = (artisan['trade'] is List)
        ? List<String>.from(artisan['trade'])
        : (artisan['trades'] is List ? List<String>.from(artisan['trades']) : <String>[]);

    String location = '';
    try {
      if (artisan['serviceArea'] is Map) {
        location = artisan['serviceArea']['address']?.toString() ?? '';
      }
    } catch (_) {}
    if (location.isEmpty) location = artisan['location'] ?? artisan['city'] ?? '';

    final rating = (artisan['rating'] is num) ? (artisan['rating'] as num).toDouble() :
    (artisan['averageRating'] ?? artisan['average_rating'] ?? 0).toDouble();
    final reviewCount = artisan['reviewsCount'] ?? artisan['reviewCount'] ?? artisan['review_count'] ?? 0;

    String _initials(String s) {
      final parts = s.trim().split(RegExp(r'\s+'));
      if (parts.isEmpty) return 'A';
      if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
      return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
    }

    return Container(
      margin: EdgeInsets.only(
        bottom: 16,
        left: 4,
        right: 4,
      ),
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorderColor, width: 1),
        // boxShadow removed per request — UI card should be flat
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
                  final hasValidUrl = imageUrl.isNotEmpty && (Uri.tryParse(imageUrl)?.hasScheme ?? false);
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
                            _initials(name),
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
                      _initials(name),
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

              // View Button - ENHANCED with primary color
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
                  child: const Text('View'),
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

          // Trades - ENHANCED with primary color badges
          if (trades.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: trades.take(3).map((trade) {
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
                    trade,
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
    // final bool isLargeScreen = screenWidth >= 420; // isLargeScreen not needed

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
                      });
                    },
                    onChanged: (_) => _debounce(
                      '_searchDebounce',
                      const Duration(milliseconds: 600),
                      _startSearch,
                    ),
                    textInputAction: TextInputAction.search,
                    onFieldSubmitted: (_) => _startSearch(),
                    style: TextStyle(
                      fontSize: isSmallScreen ? 14 : 15,
                      color: isDark ? Colors.white : _textPrimary,
                      height: 1.4,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search artisans...',
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
                          setState(() {});
                          _startSearch();
                        },
                      )
                          : null,
                    ),
                  ),
                ),
              ),

              // Trade Filters - ENHANCED container
              Container(
                height: filterChipHeight,
                margin: EdgeInsets.only(
                  bottom: screenHeight < 700 ? 12 : 16,
                ),
                child: ListView.builder(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  scrollDirection: Axis.horizontal,
                  itemCount: _popularTrades.length,
                  itemBuilder: (context, index) {
                    final trade = _popularTrades[index];
                    final selected = _selectedTrade == trade ||
                        (trade == 'All' && _selectedTrade == null);
                    return _buildEnhancedFilterChip(
                      label: trade,
                      selected: selected,
                      onTap: () {
                        if (!mounted) return;
                        setState(() {
                          _selectedTrade = trade == 'All' ? null : trade;
                          _model.textController?.text = trade == 'All' ? '' : trade;
                        });
                        _startSearch();
                      },
                      isDark: isDark,
                    );
                  },
                ),
              ),

              // Divider with responsive height
              Container(
                height: 1,
                margin: EdgeInsets.symmetric(horizontal: horizontalPadding),
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
                    ? (_isLoading && _artisans.isEmpty)
                    ? ListView.builder(
                  padding: EdgeInsets.all(horizontalPadding),
                  itemCount: 3,
                  itemBuilder: (context, index) => _buildSkeletonCard(),
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
                    : ListView.builder(
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