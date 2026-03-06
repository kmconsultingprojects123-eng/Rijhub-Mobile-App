import 'package:flutter/material.dart';
import 'dart:convert';
import '../../services/my_service_service.dart';
import '../../services/token_storage.dart';
import 'package:flutter/foundation.dart';

class MyServicePageWidget extends StatefulWidget {
  final String? artisanId; // added optional artisanId to allow viewing another artisan's services

  const MyServicePageWidget({Key? key, this.artisanId}) : super(key: key);

  static String routeName = 'myServicePage';
  static String routePath = '/my-service';

  @override
  State<MyServicePageWidget> createState() => _MyServicePageWidgetState();
}

class _MyServicePageWidgetState extends State<MyServicePageWidget> {
  final MyServiceService _svc = MyServiceService();
  bool _loading = true;
  bool _submitting = false;
  List<Map<String, dynamic>> _services = [];

  // Category data (main service -> subservices)
  List<Map<String, dynamic>> _categories = [];

  // Form fields
  String? _selectedMainId;
  String? _selectedSubId;
  final TextEditingController _priceCtrl = TextEditingController();
  String? _editingId;

  // Cache for subcategories to avoid repeated fetches
  final Map<String, List<Map<String, dynamic>>> _subcategoriesCache = {};

  @override
  void initState() {
    super.initState();
    _loadAll();
    // Initialize token-derived behavior (no UI banner required here)
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      // If an artisanId was passed to this page, fetch that artisan's public services
      if (widget.artisanId != null && widget.artisanId!.isNotEmpty) {
        try {
          final resp = await _svc.fetchArtisanServices(widget.artisanId!);
          if (resp.ok) {
            // Normalize using helper
            _services = MyServiceService.flattenArtisanServices(resp.data);
            if (kDebugMode) debugPrint('MyServicePage: fetched ${_services.length} artisan services for ${widget.artisanId}');
          } else {
            _services = [];
            if (kDebugMode) debugPrint('MyServicePage: fetchArtisanServices not ok: ${resp.message}');
          }
        } catch (e) {
          _services = [];
          if (kDebugMode) debugPrint('MyServicePage: fetchArtisanServices exception: $e');
        }
      } else if (MyServiceService.endpointsEnabled) {
        // Ensure we have an auth token before calling artisan-only endpoints
        final token = await TokenStorage.getToken();
        if (token == null || token.isEmpty) {
          debugPrint('MyServicePage: no auth token available; cannot fetch artisan services');
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(content: const Text('Please sign in to view your services'), behavior: SnackBarBehavior.floating),
          );
          if (mounted) setState(() => _loading = false);
          return;
        }
        final resp = await _svc.fetchMyServices(context: context);
        if (kDebugMode) debugPrint('MyServicePage: fetchMyServices ok=${resp.ok} status=${resp.statusCode} raw=${resp.raw}');
        if (resp.ok) {
          _services = MyServiceService.flattenArtisanServices(resp.data);
          if (kDebugMode) debugPrint('MyServicePage: flattened services count=${_services.length}');
         }
       } else {
         // Local-only mode: keep existing _services as-is (persisted in memory during session)
         _services = _services; // no-op but explicit
       }
     } catch (e) {
       // ignore
       if (kDebugMode) debugPrint('MyServicePage: _loadAll exception: $e');
     }

    try {
      final catResp = await _svc.fetchCategories(context: context);
      if (kDebugMode) debugPrint('MyServicePage: fetchCategories ok=${catResp.ok} status=${catResp.statusCode} raw=${catResp.raw}');
      if (catResp.ok) {
        final cdata = catResp.data;
        if (cdata is List) {
          _categories = List<Map<String, dynamic>>.from(cdata.map((e) => e is Map ? Map<String, dynamic>.from(e) : {'id': null, 'name': e.toString()}));
        } else if (cdata is Map && cdata['data'] is List) {
          _categories = List<Map<String, dynamic>>.from(cdata['data']);
        }
        if (kDebugMode) debugPrint('MyServicePage: categories loaded count=${_categories.length}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('MyServicePage: fetchCategories exception: $e');
    }

    if (mounted) setState(() => _loading = false);
  }

  // Helper to get display name for a category id
  String? _categoryName(String? id) {
    if (id == null) return null;
    try {
      final found = _categories.firstWhere((c) => (c['id']?.toString() ?? c['_id']?.toString()) == id);
      return (found['name'] ?? found['title'])?.toString();
    } catch (_) {}
    return null;
  }

  String? _subcategoryName(String? mainId, String? subId) {
    if (subId == null) return null;
    final subs = _getSubcategoriesFor(mainId);
    try {
      final found = subs.firstWhere((s) => (s['id']?.toString() ?? s['_id']?.toString()) == subId);
      return (found['name'] ?? found['title'])?.toString();
    } catch (_) {}
    return null;
  }

  // Choose an icon for a service name using keyword matching. Fallback to build icon.
  IconData _iconForName(String name) {
    final s = name.toLowerCase();
    if (s.contains('plumb')) return Icons.plumbing;
    if (s.contains('elect')) return Icons.electrical_services;
    if (s.contains('paint') || s.contains('painter')) return Icons.brush;
    if (s.contains('carp') || s.contains('wood') || s.contains('join')) return Icons.construction;
    if (s.contains('clean')) return Icons.cleaning_services;
    if (s.contains('install') || s.contains('setup')) return Icons.settings;
    if (s.contains('move') || s.contains('mover') || s.contains('transport')) return Icons.local_shipping;
    if (s.contains('beaut') || s.contains('spa') || s.contains('salon')) return Icons.spa;
    if (s.contains('it') || s.contains('computer') || s.contains('tech')) return Icons.computer;
    if (s.contains('lock') || s.contains('security')) return Icons.lock;
    if (s.contains('tile') || s.contains('floor') || s.contains('tiled')) return Icons.grid_on;
    if (s.contains('garden') || s.contains('lawn')) return Icons.grass;
    if (s.contains('electronic') || s.contains('appliance')) return Icons.power;
    return Icons.build_rounded;
  }

  // Create a leading widget for an item (category/subcategory or service) using emoji if provided or icon mapping.
  Widget _leadingForItem(Map<String, dynamic>? item, ColorScheme colorScheme) {
    if (item != null) {
      final iconField = (item['icon'] ?? item['emoji'])?.toString();
      if (iconField != null && iconField.isNotEmpty && iconField.runes.length <= 3) {
        // Likely an emoji or short symbol
        return Center(child: Text(iconField, style: TextStyle(fontSize: 20)));
      }
      final name = (item['name'] ?? item['title'] ?? item['label'])?.toString() ?? '';
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: colorScheme.primary.withAlpha((0.1 * 255).toInt()),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(_iconForName(name), color: colorScheme.primary, size: 20),
      );
    }
    // fallback
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: colorScheme.primary.withAlpha((0.1 * 255).toInt()),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(Icons.build_rounded, color: colorScheme.primary, size: 20),
    );
  }

  List<Map<String, dynamic>> _getSubcategoriesFor(String? mainId) {
    if (mainId == null) return [];

    // Check cache first
    if (_subcategoriesCache.containsKey(mainId)) {
      return _subcategoriesCache[mainId]!;
    }

    // Try to get from categories
    try {
      final found = _categories.firstWhere((c) => (c['id']?.toString() ?? c['_id']?.toString()) == mainId);
      final subs = found['subcategories'] ?? found['children'] ?? found['items'];
      if (subs is List) {
        final result = List<Map<String, dynamic>>.from(subs.map((e) => e is Map ? Map<String, dynamic>.from(e) : {'id': e.toString(), 'name': e.toString()}));
        _subcategoriesCache[mainId] = result;
        return result;
      }
    } catch (_) {}

    return [];
  }

  Future<void> _fetchSubcategoriesIfNeeded(String mainId) async {
    if (_subcategoriesCache.containsKey(mainId) && _subcategoriesCache[mainId]!.isNotEmpty) {
      return;
    }

    try {
      final resp = await _svc.fetchSubcategories(context: context, categoryId: mainId);

      if (!resp.ok) {
        // Ensure we don't repeatedly try when server responds but not OK
        _subcategoriesCache[mainId] = [];
        if (mounted) setState(() {});
        return;
      }

      // Try to extract a List from different possible response shapes
      List<dynamic>? rawList;

      final dynamic data = resp.data;

      if (data is List) {
        rawList = data;
      } else if (data is String) {
        // Sometimes the service returns a JSON string
        try {
          final parsed = jsonDecode(data);
          if (parsed is List) rawList = parsed;
          if (parsed is Map && parsed['data'] is List) rawList = List<dynamic>.from(parsed['data']);
        } catch (_) {
          // ignore parse error
        }
      } else if (data is Map) {
        // Common envelope keys
        if (data['data'] is List) {
          rawList = List<dynamic>.from(data['data']);
        } else if (data['items'] is List) {
          rawList = List<dynamic>.from(data['items']);
        } else if (data['results'] is List) {
          rawList = List<dynamic>.from(data['results']);
        }
      }

      // As a last resort, check for a `body` or `payload` string that contains JSON
      if (rawList == null) {
        try {
          final possible = resp.data?.toString();
          if (possible != null && possible.isNotEmpty) {
            final parsed = jsonDecode(possible);
            if (parsed is List) rawList = parsed;
            if (parsed is Map && parsed['data'] is List) rawList = List<dynamic>.from(parsed['data']);
          }
        } catch (_) {}
      }

      if (rawList != null) {
        final fetched = List<Map<String, dynamic>>.from(rawList.map((e) => e is Map ? Map<String, dynamic>.from(e) : {'id': e.toString(), 'name': e.toString()}));
        _subcategoriesCache[mainId] = fetched;
        debugPrint('MyServicePage: fetched ${fetched.length} subcategories for $mainId');
        if (mounted) setState(() {});
      } else {
        // No subcategories found; cache empty list to avoid repeated fetches
        _subcategoriesCache[mainId] = [];
        if (mounted) setState(() {});
      }
    } catch (e, st) {
      debugPrint('MyServicePage: error fetching subcategories for $mainId: $e\n$st');
      _subcategoriesCache[mainId] = [];
      if (mounted) setState(() {});
    }
  }

  Future<void> _pickMainService() async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (context, setStateModal) {
            final filtered = _categories.where((c) {
              final name = (c['name'] ?? c['title'] ?? '').toString().toLowerCase();
              return query.isEmpty || name.contains(query.toLowerCase());
            }).toList();

            return Container(
              height: MediaQuery.of(ctx).size.height * 0.7,
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(top: 12, bottom: 12),
                      decoration: BoxDecoration(
                        color: colorScheme.onSurface.withAlpha((0.3 * 255).toInt()),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.category_outlined, size: 20, color: colorScheme.primary),
                        const SizedBox(width: 12),
                        Text(
                          'Select Main Service',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),

                  // Search field
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      decoration: InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded, color: colorScheme.onSurface.withAlpha((0.5 * 255).toInt())),
                        hintText: 'Search main services',
                        hintStyle: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface.withAlpha((0.3 * 255).toInt())),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: colorScheme.onSurface.withAlpha((0.1 * 255).toInt())),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: colorScheme.onSurface.withAlpha((0.1 * 255).toInt())),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: colorScheme.primary, width: 2),
                        ),
                        filled: true,
                        fillColor: isDark ? Colors.grey[850] : Colors.grey[50],
                      ),
                      onChanged: (v) => setStateModal(() => query = v),
                      autofocus: true,
                    ),
                  ),

                  // List
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off_rounded,
                            size: 48,
                            color: colorScheme.onSurface.withAlpha((0.3 * 255).toInt()),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No services found',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurface.withAlpha((0.6 * 255).toInt()),
                            ),
                          ),
                        ],
                      ),
                    )
                        : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: colorScheme.onSurface.withAlpha((0.1 * 255).toInt()),
                      ),
                      itemBuilder: (context, i) {
                        final c = filtered[i];
                        final id = (c['id'] ?? c['_id'])?.toString();
                        final name = (c['name'] ?? c['title'])?.toString() ?? '';
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                          leading: _leadingForItem(c, colorScheme),
                          title: Text(
                            name,
                            style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                          ),
                          onTap: () => Navigator.of(ctx).pop({'id': id ?? '', 'name': name}),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (result != null && result['id'] != null) {
      setState(() {
        _selectedMainId = result['id'];
        _selectedSubId = null;
      });

      // Pre-fetch subcategories in background
      _fetchSubcategoriesIfNeeded(result['id']!);
    }
  }

  Future<void> _pickSubService() async {
    if (_selectedMainId == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: const Text('Please select a main service first'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    // Show loading state while fetching
    if (!_subcategoriesCache.containsKey(_selectedMainId) || _subcategoriesCache[_selectedMainId]!.isEmpty) {
      await _fetchSubcategoriesIfNeeded(_selectedMainId!);
    }

    final subsList = _getSubcategoriesFor(_selectedMainId);

    if (subsList.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: const Text('No sub services available for this category'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (context, setStateModal) {
            final filtered = subsList.where((c) {
              final name = (c['name'] ?? c['title'] ?? '').toString().toLowerCase();
              return query.isEmpty || name.contains(query.toLowerCase());
            }).toList();

            return Container(
              height: MediaQuery.of(ctx).size.height * 0.6,
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(top: 12, bottom: 12),
                      decoration: BoxDecoration(
                        color: colorScheme.onSurface.withAlpha((0.3 * 255).toInt()),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Header with main service name
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.list_alt_outlined, size: 20, color: colorScheme.primary),
                            const SizedBox(width: 12),
                            Text(
                              'Select Sub Service',
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.only(left: 32),
                          child: Text(
                            'for ${_categoryName(_selectedMainId)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurface.withAlpha((0.6 * 255).toInt()),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Search field
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      decoration: InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded, color: colorScheme.onSurface.withAlpha((0.5 * 255).toInt())),
                        hintText: 'Search sub services',
                        hintStyle: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface.withAlpha((0.3 * 255).toInt())),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: colorScheme.onSurface.withAlpha((0.1 * 255).toInt())),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: colorScheme.onSurface.withAlpha((0.1 * 255).toInt())),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: colorScheme.primary, width: 2),
                        ),
                        filled: true,
                        fillColor: isDark ? Colors.grey[850] : Colors.grey[50],
                      ),
                      onChanged: (v) => setStateModal(() => query = v),
                      autofocus: true,
                    ),
                  ),

                  // List
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off_rounded,
                            size: 48,
                            color: colorScheme.onSurface.withAlpha((0.3 * 255).toInt()),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No sub services found',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurface.withAlpha((0.6 * 255).toInt()),
                            ),
                          ),
                        ],
                      ),
                    )
                        : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: colorScheme.onSurface.withAlpha((0.1 * 255).toInt()),
                      ),
                      itemBuilder: (context, i) {
                        final c = filtered[i];
                        final id = (c['id'] ?? c['_id'])?.toString();
                        final name = (c['name'] ?? c['title'])?.toString() ?? '';
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                          leading: _leadingForItem(c, colorScheme),
                          title: Text(
                            name,
                            style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                          ),
                          onTap: () => Navigator.of(ctx).pop({'id': id ?? '', 'name': name}),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (result != null && result['id'] != null) {
      setState(() {
        _selectedSubId = result['id'];
      });
    }
  }

  Future<void> _submit() async {
    if (_selectedMainId == null || _selectedSubId == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: const Text('Please pick a main and sub service'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    final priceText = _priceCtrl.text.trim();
    if (priceText.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: const Text('Please provide a price'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    double? price = double.tryParse(priceText.replaceAll(',', ''));
    if (price == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: const Text('Invalid price'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      // Ensure user is authenticated before attempting server-side create/update
      final token = await TokenStorage.getToken();
      if (MyServiceService.endpointsEnabled && (token == null || token.isEmpty)) {
        debugPrint('MyServicePage: cannot create/update service - missing auth token');
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: const Text('You must be signed in to create services. Please sign in and try again.'), behavior: SnackBarBehavior.floating, backgroundColor: Theme.of(context).colorScheme.error),
        );
        if (mounted) setState(() => _submitting = false);
        return;
      }
      // Server expects: { categoryId, services: [{ subCategoryId, price, currency?, notes? }, ...] }
      final body = {
        'categoryId': _selectedMainId,
        'services': [
          {
            'subCategoryId': _selectedSubId,
            'price': price,
            'currency': 'NGN',
          }
        ],
      };

      if (!MyServiceService.endpointsEnabled) {
        // Local-only: create/update in-memory list
        if (_editingId != null) {
          final idx = _services.indexWhere((s) => (s['id'] ?? s['_id'] ?? s['serviceId'])?.toString() == _editingId);
          if (idx != -1) {
            _services[idx] = {
              ..._services[idx],
              'categoryId': _selectedMainId,
              'subCategoryId': _selectedSubId,
              'price': price,
              'categoryName': _categoryName(_selectedMainId) ?? _services[idx]['categoryName'],
              'subCategoryName': _subcategoryName(_selectedMainId, _selectedSubId) ?? _services[idx]['subCategoryName'],
            };
          }
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(content: const Text('Service updated (local mode)'), behavior: SnackBarBehavior.floating),
          );
        } else {
          final newService = {
            'id': DateTime.now().millisecondsSinceEpoch.toString(),
            'categoryId': _selectedMainId,
            'subCategoryId': _selectedSubId,
            'price': price,
            'categoryName': _categoryName(_selectedMainId),
            'subCategoryName': _subcategoryName(_selectedMainId, _selectedSubId),
          };
          _services.insert(0, newService);
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(content: const Text('Service created (local mode)'), behavior: SnackBarBehavior.floating),
          );
        }

        // Reset and update UI
        _editingId = null;
        _priceCtrl.clear();
        _selectedMainId = null;
        _selectedSubId = null;
        if (mounted) setState(() {});
      } else {
        // Use POST (create or update by category) to create/update artisan offerings per API docs.
        final res = await _svc.createService(body, context: context);

        if (kDebugMode) debugPrint('MyServicePage: createService response ok=${res.ok} status=${res.statusCode} raw=${res.raw}');

        if (res.ok) {
          // Refresh the artisan services from server to get canonical data (some APIs don't return the created entry)
          try {
            final refreshResp = await _svc.fetchMyServices(context: context);
            if (kDebugMode) debugPrint('MyServicePage: fetchMyServices after create ok=${refreshResp.ok} status=${refreshResp.statusCode} raw=${refreshResp.raw}');
            if (refreshResp.ok) {
              _services = MyServiceService.flattenArtisanServices(refreshResp.data);
              if (mounted) setState(() {});
            } else {
              // fallback to generic reload which also refreshes categories
              await _loadAll();
            }
          } catch (e) {
            if (kDebugMode) debugPrint('MyServicePage: refresh after create failed: $e');
            await _loadAll();
          }

           ScaffoldMessenger.maybeOf(context)?.showSnackBar(
             SnackBar(
               content: Text(_editingId != null ? 'Service updated successfully' : 'Service created successfully'),
               behavior: SnackBarBehavior.floating,
               shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
             ),
           );
           // Reset form
           _editingId = null;
           _priceCtrl.clear();
           _selectedMainId = null;
           _selectedSubId = null;
          } else {
          // Show server-friendly message if available to help debugging
          final msg = res.message;
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text(msg),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
          // Optionally log full raw body for debugging in console
          if (kDebugMode) debugPrint('MyServicePage: create/update failed raw=${res.raw}');
        }
      }
    } catch (e) {
      // ignore
      if (kDebugMode) debugPrint('MyServicePage: _submit exception: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _startEdit(Map<String, dynamic> service) async {
    setState(() {
      _editingId = (service['id'] ?? service['_id'] ?? service['serviceId'])?.toString();
      _selectedMainId = (service['categoryId'] ?? service['mainCategory'] ?? service['category'])?.toString();
      _selectedSubId = (service['subCategoryId'] ?? service['subCategory'] ?? service['sub'])?.toString();
      _priceCtrl.text = (service['price'] ?? service['amount'] ?? '').toString();
    });

    // Pre-fetch subcategories if needed
    if (_selectedMainId != null) {
      _fetchSubcategoriesIfNeeded(_selectedMainId!);
    }

    // Scroll to form
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: const Text('Editing service - Update the details below'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _confirmDelete(Map<String, dynamic> service) async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final id = (service['id'] ?? service['_id']).toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          'Delete service?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
        ),
        content: Text(
          'This will permanently delete this service. This action cannot be undone.',
          style: TextStyle(color: colorScheme.onSurface.withAlpha((0.7 * 255).toInt())),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      if (!MyServiceService.endpointsEnabled) {
        // Local-only delete
        _services.removeWhere((s) => (s['id'] ?? s['_id'])?.toString() == id);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: const Text('Service deleted (local mode)'), behavior: SnackBarBehavior.floating));
        if (mounted) setState(() {});
        return;
      }

      // Ensure token is present for artisan-only delete
      final token = await TokenStorage.getToken();
      if (token == null || token.isEmpty) {
        debugPrint('MyServicePage: cannot delete service - missing auth token');
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: const Text('You must be signed in to delete services. Please sign in and try again.'), behavior: SnackBarBehavior.floating, backgroundColor: colorScheme.error),
        );
        return;
      }

      // If we have an artisanServiceId and an inner serviceEntryId or subCategoryId,
      // prefer to update the ArtisanService document (PUT) to remove the single sub-service.
      final artisanServiceId = service['artisanServiceId']?.toString() ?? (id.contains('_') ? id.split('_').first : null);
      final serviceEntryId = service['serviceEntryId']?.toString();
      final subCategoryId = service['subCategoryId']?.toString();

      if (artisanServiceId != null && artisanServiceId.isNotEmpty && (serviceEntryId != null || subCategoryId != null)) {
        // Fetch the full artisan services to construct an updated services array
        final allResp = await _svc.fetchMyServices(context: context);
        if (!allResp.ok) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(allResp.message), behavior: SnackBarBehavior.floating, backgroundColor: colorScheme.error));
          return;
        }

        // Locate the matching ArtisanService document from the response (support multiple shapes)
        dynamic foundDoc;
        try {
          final data = allResp.data;
          List<dynamic> list = [];
          if (data is List) list = data;
          else if (data is Map && data['data'] is List) list = List<dynamic>.from(data['data']);

          for (final d in list) {
            if (d is Map) {
              final docId = (d['_id'] ?? d['id'])?.toString();
              if (docId == artisanServiceId) {
                foundDoc = d;
                break;
              }
            }
          }
        } catch (e) {
          debugPrint('MyServicePage: error locating artisan service doc: $e');
        }

        if (foundDoc == null) {
          // fallback: attempt direct delete of artisanServiceId
          final resp = await _svc.deleteService(artisanServiceId, context: context);
          if (resp.ok) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Service deleted successfully'), behavior: SnackBarBehavior.floating));
            await _loadAll();
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(resp.message), behavior: SnackBarBehavior.floating, backgroundColor: colorScheme.error));
          return;
        }

        // Build new services array excluding the targeted sub-entry
        List<dynamic> existingServices = [];
        try {
          final s = foundDoc['services'];
          if (s is List) existingServices = List<dynamic>.from(s);
        } catch (_) {}

        final List<Map<String, dynamic>> updatedServices = [];
        for (final es in existingServices) {
          if (es is Map) {
            final entryId = (es['_id'] ?? es['id'])?.toString();
            // extract subCategoryId from various shapes
            String? esSubId;
            try {
              final raw = es['subCategoryId'] ?? es['subCategory'] ?? es['sub'];
              if (raw is Map) esSubId = (raw['_id'] ?? raw['id'])?.toString();
              else esSubId = raw?.toString();
            } catch (_) {}

            // Keep entries that do NOT match the deletion target
            if ((serviceEntryId != null && entryId == serviceEntryId) || (subCategoryId != null && esSubId == subCategoryId)) {
              // skip this entry (delete)
              continue;
            }

            // Normalize to the expected body shape: { subCategoryId, price, currency?, notes? }
            final normSubId = esSubId ?? (es['subCategoryId']?.toString() ?? es['subCategory']?.toString() ?? es['sub']?.toString());
            final price = es['price'] ?? es['amount'];
            final currency = es['currency'] ?? 'NGN';
            if (normSubId != null && normSubId.isNotEmpty) {
              updatedServices.add({'subCategoryId': normSubId, 'price': price, 'currency': currency});
            }
          }
        }

        if (updatedServices.isEmpty) {
          // No more services under this ArtisanService — delete the whole document
          final resp = await _svc.deleteService(artisanServiceId, context: context);
          if (resp.ok) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Service deleted successfully'), behavior: SnackBarBehavior.floating));
            await _loadAll();
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(resp.message), behavior: SnackBarBehavior.floating, backgroundColor: colorScheme.error));
          return;
        }

        // Prepare update body
        final categoryRaw = foundDoc['categoryId'] ?? foundDoc['mainCategory'] ?? foundDoc['category'];
        String? categoryId;
        if (categoryRaw is Map) categoryId = (categoryRaw['_id'] ?? categoryRaw['id'])?.toString();
        else categoryId = categoryRaw?.toString();

        final body = {'categoryId': categoryId, 'services': updatedServices};
        final updResp = await _svc.updateService(artisanServiceId, body, context: context);
        if (updResp.ok) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Service deleted successfully'), behavior: SnackBarBehavior.floating));
          await _loadAll();
          return;
        }

        // If update failed, surface error
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(updResp.message), behavior: SnackBarBehavior.floating, backgroundColor: colorScheme.error));
        debugPrint('MyServicePage: update delete failed: ${updResp.raw}');
        return;
      }

      // Fallback: call deleteService with the provided id (may be artisanService id)
      // Ensure we never pass a composite id to delete endpoint; prefer first segment if composite
      final fallbackId = (id.contains('_') ? id.split('_').first : id);
      final resp = await _svc.deleteService(fallbackId, context: context);
      if (resp.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Service deleted successfully'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        await _loadAll();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(resp.message), behavior: SnackBarBehavior.floating, backgroundColor: colorScheme.error));
        debugPrint('MyServicePage: delete failed: ${resp.raw}');
      }
    } catch (e, st) {
      debugPrint('MyServicePage: _confirmDelete exception: $e\\n$st');
    }
  }

  String _formatPrice(dynamic price) {
    if (price == null) return '';
    try {
      final num value = double.tryParse(price.toString()) ?? 0;
      return '₦ ${value.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}';
    } catch (_) {
      return '₦ $price';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final onSurfaceAlpha10 = colorScheme.onSurface.withAlpha((0.1 * 255).toInt());
    final onSurfaceAlpha30 = colorScheme.onSurface.withAlpha((0.3 * 255).toInt());
    final onSurfaceAlpha60 = colorScheme.onSurface.withAlpha((0.6 * 255).toInt());

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      appBar: AppBar(
        title: Text(
          'My Services',
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w500, fontSize: 18),
        ),
        backgroundColor: isDark ? Colors.black : Colors.white,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24.0, 0.0, 24.0, MediaQuery.of(context).padding.bottom + 24.0),
          child: _loading
              ? Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colorScheme.primary,
            ),
          )
              : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),

              // Add/Edit Service Card
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: onSurfaceAlpha10, width: 1),
                  color: isDark ? Colors.grey[900] : Colors.white,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withAlpha((0.1 * 255).toInt()),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              _editingId != null ? Icons.edit_outlined : Icons.add_circle_outline,
                              color: colorScheme.primary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _editingId != null ? 'Edit Service' : 'Add New Service',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Main category dropdown - Improved with tap indicator
                      InkWell(
                        onTap: _pickMainService,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: onSurfaceAlpha10),
                            color: isDark ? Colors.grey[850] : Colors.grey[50],
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Main service',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: onSurfaceAlpha60,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _categoryName(_selectedMainId) ?? 'Select main service',
                                      style: theme.textTheme.bodyLarge?.copyWith(
                                        color: _selectedMainId != null ? colorScheme.onSurface : onSurfaceAlpha30,
                                        fontWeight: _selectedMainId != null ? FontWeight.w500 : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.arrow_drop_down_rounded,
                                color: colorScheme.primary,
                                size: 24,
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Sub category dropdown - Improved with tap indicator
                      InkWell(
                        onTap: _pickSubService,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: onSurfaceAlpha10),
                            color: isDark ? Colors.grey[850] : Colors.grey[50],
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Sub service',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: onSurfaceAlpha60,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _subcategoryName(_selectedMainId, _selectedSubId) ??
                                          (_selectedMainId != null ? 'Select sub service' : 'Select main service first'),
                                      style: theme.textTheme.bodyLarge?.copyWith(
                                        color: _selectedSubId != null ? colorScheme.onSurface : onSurfaceAlpha30,
                                        fontWeight: _selectedSubId != null ? FontWeight.w500 : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.arrow_drop_down_rounded,
                                color: _selectedMainId != null ? colorScheme.primary : onSurfaceAlpha30,
                                size: 24,
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Price field
                      TextFormField(
                        controller: _priceCtrl,
                        keyboardType: TextInputType.numberWithOptions(decimal: true),
                        style: theme.textTheme.bodyLarge,
                        decoration: InputDecoration(
                          labelText: 'Price',
                          prefixText: '₦ ',
                          prefixStyle: theme.textTheme.bodyLarge?.copyWith(color: onSurfaceAlpha60),
                          labelStyle: theme.textTheme.bodyMedium?.copyWith(color: onSurfaceAlpha60),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: onSurfaceAlpha30),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: onSurfaceAlpha10),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: colorScheme.primary, width: 2),
                          ),
                          filled: true,
                          fillColor: isDark ? Colors.grey[850] : Colors.grey[50],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Action buttons
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _submitting ? null : _submit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colorScheme.primary,
                                foregroundColor: colorScheme.onPrimary,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                              child: _submitting
                                  ? SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(colorScheme.onPrimary),
                                ),
                              )
                                  : Text(
                                _editingId != null ? 'Update Service' : 'Create Service',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: colorScheme.onPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          if (_editingId != null) ...[
                            const SizedBox(width: 12),
                            OutlinedButton(
                              onPressed: () {
                                setState(() {
                                  _editingId = null;
                                  _priceCtrl.clear();
                                  _selectedMainId = null;
                                  _selectedSubId = null;
                                });
                              },
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                side: BorderSide(color: onSurfaceAlpha30),
                              ),
                              child: Text(
                                'Cancel',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: onSurfaceAlpha60,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Services List Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Your Services',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withAlpha((0.1 * 255).toInt()),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_services.length} total',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Services List
              Expanded(
                child: _services.isEmpty
                    ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.build_outlined,
                        size: 64,
                        color: onSurfaceAlpha30,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No services yet',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: onSurfaceAlpha60,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Add your first service above',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: onSurfaceAlpha30,
                        ),
                      ),
                    ],
                  ),
                )
                    : RefreshIndicator(
                  onRefresh: _loadAll,
                  color: colorScheme.primary,
                  child: ListView.separated(
                    itemCount: _services.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: onSurfaceAlpha10,
                      indent: 16,
                      endIndent: 16,
                    ),
                    itemBuilder: (context, i) {
                      final s = _services[i];
                      // Prefer the explicit subCategory name (artisan configured), then category, then any title/name fields.
                      String? rawTitle;
                      if (s['subCategoryName'] != null && s['subCategoryName'].toString().trim().isNotEmpty) rawTitle = s['subCategoryName'].toString().trim();
                      if ((rawTitle == null || rawTitle.isEmpty) && (s['categoryName'] != null && s['categoryName'].toString().trim().isNotEmpty)) rawTitle = s['categoryName'].toString().trim();
                      if ((rawTitle == null || rawTitle.isEmpty) && (s['title'] != null && s['title'].toString().trim().isNotEmpty)) rawTitle = s['title'].toString().trim();
                      if ((rawTitle == null || rawTitle.isEmpty) && (s['name'] != null && s['name'].toString().trim().isNotEmpty)) rawTitle = s['name'].toString().trim();
                      final title = (rawTitle ?? '${s['categoryName'] ?? ''} ${s['subCategoryName'] ?? ''}'.trim()).toString().trim();
                      final price = _formatPrice(s['price'] ?? s['amount'] ?? '');

                      return Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: _leadingForItem(
                            {
                              'name': s['categoryName'] ?? s['name'] ?? s['title'],
                              'icon': s['icon'] ?? s['emoji'],
                            },
                            colorScheme,
                          ),
                          title: Text(
                            title.isNotEmpty ? title : 'Service',
                            style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            price,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          trailing: Container(
                            decoration: BoxDecoration(
                              color: onSurfaceAlpha10,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  onPressed: () => _startEdit(s),
                                  icon: Icon(Icons.edit_outlined, size: 20),
                                  color: colorScheme.primary,
                                  splashRadius: 20,
                                  tooltip: 'Edit',
                                ),
                                IconButton(
                                  onPressed: () => _confirmDelete(s),
                                  icon: Icon(Icons.delete_outline_rounded, size: 20),
                                  color: colorScheme.error,
                                  splashRadius: 20,
                                  tooltip: 'Delete',
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
          ),
        ),
      ),
    );
  }
}
