import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import '../../google_maps_config.dart';
import '../../services/artist_service.dart';
import '../../services/job_service.dart';
import '../../services/my_service_service.dart';
import '../../services/token_storage.dart';
import '../../state/auth_notifier.dart';
import '../../utils/location_permission.dart';
import 'artisan_onboarding_model.dart';
import 'liveness_check_widget.dart';

export 'artisan_onboarding_model.dart';

class ArtisanOnboardingWidget extends StatefulWidget {
  const ArtisanOnboardingWidget({super.key});

  static String routeName = 'ArtisanOnboarding';
  static String routePath = '/artisanOnboarding';

  @override
  State<ArtisanOnboardingWidget> createState() =>
      _ArtisanOnboardingWidgetState();
}

class _ArtisanOnboardingWidgetState extends State<ArtisanOnboardingWidget> {
  late ArtisanOnboardingModel _model;
  final Color primaryColor = const Color(0xFFA20025);

  // Section expansion state — first section opens by default.
  final List<bool> _expanded = [true, false, false];
  // Section completion state (local) — used for stepper checkmarks.
  final List<bool> _completed = [false, false, false];

  // Server-reported profile progress (0.0–1.0). Refetched from
  // GET /api/artisans/me on init and after every onboarding step succeeds —
  // same endpoint the artisan dashboard uses, so the two stay in sync.
  double _serverProgress = 0.0;

  final ScrollController _scrollController = ScrollController();
  final List<GlobalKey> _sectionKeys = [
    GlobalKey(),
    GlobalKey(),
    GlobalKey(),
  ];

  // Dummy suggested prices until the backend price-suggestions endpoint ships.
  // Keyword match (case-insensitive) sets the BASE price for the service,
  // then a deterministic ±30% spread (seeded by the service name's hash)
  // gives each service a distinct but plausible value — so two "pipe-..."
  // services don't read identically. Falls back to a sensible default
  // when no keyword matches.
  //
  // Iteration order matters: more-specific domain keywords are listed
  // first so they win over the generic action verbs at the bottom
  // (`install`, `repair`, `service`, `fix`).
  static const Map<String, int> _dummyPriceHints = {
    // ----- Plumbing -----
    'water heater': 18000,
    'pipe': 5000,
    'drain': 7500,
    'leak': 6000,
    'toilet': 8000,
    'shower': 6500,
    'bath': 7000,
    'sink': 5000,
    'tap': 4000,
    // ----- Electrical -----
    'inverter': 22000,
    'generator': 12000,
    'wiring': 15000,
    'socket': 6000,
    'switch': 4500,
    'bulb': 3500,
    'light': 5000,
    'electric': 10000,
    // ----- Painting -----
    'exterior': 25000,
    'interior': 20000,
    'ceiling': 12000,
    'wall': 10000,
    'paint': 18000,
    // ----- Carpentry / furniture -----
    'cabinet': 35000,
    'wardrobe': 30000,
    'furniture': 25000,
    'door': 15000,
    'window': 10000,
    'shelf': 8000,
    'wood': 12000,
    // ----- AC / cooling -----
    'air conditioner': 15000,
    'cooler': 10000,
    // ----- Auto / mechanic -----
    'engine': 50000,
    'brake': 25000,
    'tyre': 15000,
    'tire': 15000,
    'battery': 10000,
    // ----- Construction / masonry -----
    'masonry': 20000,
    'tile': 12000,
    'cement': 10000,
    'block': 8000,
    // ----- Cleaning / pest -----
    'fumigation': 15000,
    'pest': 12000,
    'polish': 5000,
    'clean': 7000,
    'mop': 3000,
    // ----- Generic action verbs (fallback when no domain keyword matches) -----
    'install': 12000,
    'replace': 8000,
    'maintain': 5000,
    'repair': 6000,
    'service': 6000,
    'fix': 5500,
  };
  static const int _dummyPriceDefault = 5000;

  int _suggestedPriceFor(String serviceName) {
    final lower = serviceName.toLowerCase();
    int base = _dummyPriceDefault;
    for (final entry in _dummyPriceHints.entries) {
      if (lower.contains(entry.key)) {
        base = entry.value;
        break;
      }
    }
    // Deterministic ±30% spread seeded by the service name so two services
    // sharing a base price still surface as distinct numbers.
    final width = base * 60 ~/ 100; // 60% of base
    final offset = serviceName.hashCode.abs() % (width + 1);
    final variant = (base - width ~/ 2) + offset;
    // Round to the nearest ₦500 for friendlier display.
    return ((variant + 250) ~/ 500) * 500;
  }

  // Section 1: Trade, Services & Prices
  List<Map<String, dynamic>> _categories = [];
  bool _loadingCategories = false;
  String? _selectedCategoryId;
  List<Map<String, dynamic>> _subcategories = [];
  bool _loadingSubs = false;
  // Map<subCategoryId, {name, price (TextEditingController)}>
  final Map<String, _ServiceRow> _selectedServices = {};
  bool _savingTrade = false;

  // Section 2: Work Radius & Profile
  double? _lat;
  double? _lng;
  String? _addressLabel;
  bool _loadingLocation = false;
  // Auto-derived from the picked place's viewport via Haversine.
  // Defaults to 10 km until a place is picked.
  double _radiusKm = 10;
  File? _photoFile;
  String? _photoUrl;
  bool _savingProfile = false;

  // Address autocomplete state.
  final TextEditingController _locationSearchCtrl = TextEditingController();
  final FocusNode _locationSearchFocus = FocusNode();
  Timer? _searchDebounce;
  List<Map<String, dynamic>> _placeSuggestions = [];
  bool _searchingPlaces = false;

  // Section 3: Identity Verification
  String _documentType = 'NIN';

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => ArtisanOnboardingModel());
    _loadCategories();
    _hydrateFromStorage();
  }

  @override
  void dispose() {
    for (final row in _selectedServices.values) {
      row.priceCtrl.dispose();
    }
    _scrollController.dispose();
    _searchDebounce?.cancel();
    _locationSearchCtrl.dispose();
    _locationSearchFocus.dispose();
    _model.dispose();
    super.dispose();
  }

  /// Mark the section at [index] complete, collapse it, expand the next
  /// uncompleted section, and smooth-scroll the next section into view.
  void _advanceTo(int nextIndex) {
    if (nextIndex >= _sectionKeys.length) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _sectionKeys[nextIndex].currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInOut,
        alignment: 0.05,
      );
    });
  }

  Future<void> _hydrateFromStorage() async {
    try {
      final loc = await TokenStorage.getLocation();
      if (loc.isNotEmpty && mounted) {
        setState(() {
          _lat = (loc['latitude'] as num?)?.toDouble();
          _lng = (loc['longitude'] as num?)?.toDouble();
          _addressLabel = loc['address']?.toString();
          if (_addressLabel != null && _addressLabel!.isNotEmpty) {
            _locationSearchCtrl.text = _addressLabel!;
          }
        });
      }
    } catch (_) {}
  }

  double get _completionFraction {
    final localFraction = _completed.where((c) => c).length / _completed.length;
    // Use whichever is higher: server-reported progress (authoritative for
    // returning artisans) or local stepper progress (immediate feedback for
    // a step the user just completed in this session, before the next refetch
    // returns).
    return math.max(localFraction, _serverProgress).clamp(0.0, 1.0);
  }

  int get _completionPercent => (_completionFraction * 100).round();

  /// Refetch the artisan profile and read `profileCompletion` / `profileProgress`
  /// — same fields the artisan dashboard uses. Called on init and after every
  /// onboarding step succeeds so the bar reflects authoritative state.
  Future<void> _refreshProfileProgress() async {
    try {
      final profile = await ArtistService.getMyProfile();
      if (!mounted || profile == null) return;
      final raw =
          profile['profileCompletion'] ?? profile['profileProgress'];
      if (raw == null) return;
      double value;
      if (raw is num) {
        value = raw.toDouble();
      } else {
        value = double.tryParse(raw.toString()) ?? 0.0;
      }
      // Backend may report either 0–1 or 0–100. Normalise to 0–1.
      if (value > 1.0) value = value / 100.0;
      value = value.clamp(0.0, 1.0);
      if (mounted) setState(() => _serverProgress = value);
    } catch (e) {
      if (kDebugMode) debugPrint('refreshProfileProgress error: $e');
    }
  }

  // ---- Section 1: Categories & services ---------------------------------

  Future<void> _loadCategories() async {
    if (mounted) setState(() => _loadingCategories = true);
    try {
      final cats = await JobService.getJobCategories();
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _loadingCategories = false;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('loadCategories error: $e');
      if (mounted) setState(() => _loadingCategories = false);
    }
  }

  Future<void> _loadSubcategories(String categoryId) async {
    if (mounted) {
      setState(() {
        _loadingSubs = true;
        _subcategories = [];
        for (final r in _selectedServices.values) {
          r.priceCtrl.dispose();
        }
        _selectedServices.clear();
      });
    }
    try {
      final resp = await MyServiceService()
          .fetchSubcategories(categoryId: categoryId);
      if (!mounted) return;
      List<Map<String, dynamic>> list = [];
      if (resp.ok && resp.data != null) {
        final data = resp.data;
        if (data is List) {
          list = data
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        } else if (data is Map && data['data'] is List) {
          list = (data['data'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }
      setState(() {
        _subcategories = list;
        _loadingSubs = false;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('loadSubcategories error: $e');
      if (mounted) setState(() => _loadingSubs = false);
    }
  }

  void _toggleService(Map<String, dynamic> sub) {
    final id = (sub['_id'] ?? sub['id'])?.toString();
    if (id == null) return;
    final name = (sub['name'] ?? sub['title'] ?? 'Service').toString();
    setState(() {
      if (_selectedServices.containsKey(id)) {
        _selectedServices[id]?.priceCtrl.dispose();
        _selectedServices.remove(id);
      } else {
        // Dummy suggestions until the backend price-suggestions endpoint ships.
        // Prefer a backend-provided value if it happens to be on the payload,
        // otherwise fall back to keyword-matched dummy prices.
        final fromBackend = sub['medianPrice'] ?? sub['suggestedPrice'];
        final suggested = (fromBackend != null && fromBackend.toString().isNotEmpty)
            ? fromBackend.toString()
            : _suggestedPriceFor(name).toString();
        _selectedServices[id] = _ServiceRow(
          name: name,
          priceCtrl: TextEditingController(text: suggested),
        );
      }
    });
  }

  Future<void> _saveTradeDetails() async {
    if (_selectedCategoryId == null) {
      _toast('Pick a trade category first');
      return;
    }
    if (_selectedServices.isEmpty) {
      _toast('Select at least one service you offer');
      return;
    }
    final expText = _model.experienceController?.text.trim() ?? '';
    final expNum = int.tryParse(expText);
    if (expNum == null || expNum < 0) {
      _toast('Enter your years of experience');
      _model.experienceFocus?.requestFocus();
      return;
    }

    setState(() => _savingTrade = true);
    try {
      // 1. Ensure the artisan profile exists. The /api/artisan-services
      //    endpoint requires an Artisan record to be present, so we upsert
      //    {trade, experience} first via PUT /api/artisans/me, which falls
      //    back to POST /api/artisans when the profile doesn't exist yet.
      final categoryName = _categories
              .firstWhere(
                  (c) =>
                      (c['_id'] ?? c['id']).toString() == _selectedCategoryId,
                  orElse: () => {})['name']
              ?.toString() ??
          '';
      final profilePayload = <String, dynamic>{
        if (categoryName.isNotEmpty) 'trade': [categoryName],
        'experience': expNum,
      };
      final profileRes =
          await ArtistService.updateMyProfile(profilePayload);
      if (!mounted) return;
      if (profileRes == null) {
        _toast('Could not set up your trade profile. Please try again.');
        return;
      }

      // 2. Save services with prices.
      final services = _selectedServices.entries.map((e) {
        final priceText = e.value.priceCtrl.text.trim();
        final price = double.tryParse(priceText) ?? 0;
        return {
          'subCategoryId': e.key,
          'price': price,
          'currency': 'NGN',
        };
      }).toList();

      final body = {
        'categoryId': _selectedCategoryId,
        'services': services,
      };

      final resp =
          await MyServiceService().createService(body, context: context);
      if (!mounted) return;
      if (resp.ok) {
        setState(() {
          _completed[0] = true;
          _expanded[0] = false;
          if (!_completed[1]) _expanded[1] = true;
        });
        _advanceTo(1);
        _toast('Services saved');
      } else {
        _toast(resp.message);
      }
    } catch (e) {
      _toast('Could not save services. Please try again.');
      if (kDebugMode) debugPrint('saveTradeDetails error: $e');
    } finally {
      if (mounted) setState(() => _savingTrade = false);
    }
  }

  // ---- Section 2: Location & profile photo ------------------------------

  Future<void> _useCurrentLocation() async {
    setState(() => _loadingLocation = true);
    try {
      final ok =
          await LocationPermissionService.ensureLocationPermissions(context);
      if (!ok) {
        _toast('Location permission denied');
        setState(() => _loadingLocation = false);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.best),
      );
      String? address;
      try {
        final key = GOOGLE_MAPS_API_KEY;
        if (key.isNotEmpty) {
          final url = Uri.parse(
              'https://maps.googleapis.com/maps/api/geocode/json?latlng=${pos.latitude},${pos.longitude}&key=$key');
          final resp =
              await http.get(url).timeout(const Duration(seconds: 10));
          if (resp.statusCode == 200 && resp.body.isNotEmpty) {
            final body = jsonDecode(resp.body);
            if (body is Map &&
                body['results'] is List &&
                (body['results'] as List).isNotEmpty) {
              final first = (body['results'] as List).first;
              if (first is Map && first['formatted_address'] != null) {
                address = first['formatted_address'].toString();
              }
            }
          }
        }
      } catch (_) {}

      if (!mounted) return;
      final label = address ??
          '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _addressLabel = label;
        _locationSearchCtrl.text = label;
        _placeSuggestions = [];
        // GPS gives a point, not a viewport — default to a sensible radius.
        _radiusKm = 10;
      });
      await TokenStorage.saveLocation(
        address: address,
        latitude: pos.latitude,
        longitude: pos.longitude,
      );
    } catch (e) {
      _toast('Could not detect location');
      if (kDebugMode) debugPrint('useCurrentLocation error: $e');
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  // ---- Address search (Google Places Autocomplete) -----------------------

  /// Debounced; called from the TextField onChanged.
  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    if (query.trim().length < 3) {
      if (mounted) setState(() => _placeSuggestions = []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _searchPlaces(query);
    });
  }

  Future<void> _searchPlaces(String query) async {
    if (!mounted) return;
    setState(() => _searchingPlaces = true);
    try {
      final key = GOOGLE_MAPS_API_KEY;
      if (key.isEmpty) {
        if (mounted) setState(() => _searchingPlaces = false);
        return;
      }
      final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/place/autocomplete/json'
          '?input=${Uri.encodeQueryComponent(query)}'
          '&components=country:ng'
          '&types=geocode'
          '&key=$key');
      final resp = await http.get(url).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        if (body is Map && body['predictions'] is List) {
          final list = (body['predictions'] as List)
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList();
          setState(() {
            _placeSuggestions = list;
            _searchingPlaces = false;
          });
          return;
        }
      }
      setState(() => _searchingPlaces = false);
    } catch (e) {
      if (kDebugMode) debugPrint('searchPlaces error: $e');
      if (mounted) setState(() => _searchingPlaces = false);
    }
  }

  Future<void> _selectPlace(Map<String, dynamic> place) async {
    final placeId = place['place_id']?.toString();
    if (placeId == null) return;
    final description = place['description']?.toString() ?? '';
    setState(() {
      _placeSuggestions = [];
      _locationSearchCtrl.text = description;
      _searchingPlaces = true;
    });
    _locationSearchFocus.unfocus();
    try {
      final key = GOOGLE_MAPS_API_KEY;
      final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/place/details/json'
          '?place_id=$placeId'
          '&fields=geometry,formatted_address'
          '&key=$key');
      final resp = await http.get(url).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        if (body is Map && body['result'] is Map) {
          final result = body['result'] as Map;
          final geometry = result['geometry'] as Map?;
          final location = geometry?['location'] as Map?;
          final viewport = geometry?['viewport'] as Map?;
          final lat = (location?['lat'] as num?)?.toDouble();
          final lng = (location?['lng'] as num?)?.toDouble();
          final address =
              result['formatted_address']?.toString() ?? description;

          if (lat != null && lng != null) {
            // Derive radius from viewport (Haversine across the diagonal).
            double radiusKm = 10.0;
            if (viewport is Map) {
              final ne = viewport['northeast'] as Map?;
              final sw = viewport['southwest'] as Map?;
              final neLat = (ne?['lat'] as num?)?.toDouble();
              final neLng = (ne?['lng'] as num?)?.toDouble();
              final swLat = (sw?['lat'] as num?)?.toDouble();
              final swLng = (sw?['lng'] as num?)?.toDouble();
              if (neLat != null &&
                  neLng != null &&
                  swLat != null &&
                  swLng != null) {
                final diag =
                    _haversineDistance(swLat, swLng, neLat, neLng);
                radiusKm = diag / 2;
                if (radiusKm < 5) radiusKm = 5;
                if (radiusKm > 50) radiusKm = 50;
              }
            }

            await TokenStorage.saveLocation(
              address: address,
              latitude: lat,
              longitude: lng,
            );
            if (!mounted) return;
            setState(() {
              _lat = lat;
              _lng = lng;
              _addressLabel = address;
              _radiusKm = radiusKm;
              _locationSearchCtrl.text = address;
              _searchingPlaces = false;
            });
            return;
          }
        }
      }
      if (mounted) setState(() => _searchingPlaces = false);
    } catch (e) {
      if (kDebugMode) debugPrint('selectPlace error: $e');
      if (mounted) setState(() => _searchingPlaces = false);
    }
  }

  void _clearSelectedAddress() {
    setState(() {
      _lat = null;
      _lng = null;
      _addressLabel = null;
      _radiusKm = 10;
      _locationSearchCtrl.clear();
      _placeSuggestions = [];
    });
    _locationSearchFocus.requestFocus();
  }

  /// Haversine distance in kilometres between two lat/lon points.
  double _haversineDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    double toRad(double deg) => deg * (math.pi / 180.0);
    final dLat = toRad(lat2 - lat1);
    final dLon = toRad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(toRad(lat1)) *
            math.cos(toRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  Future<void> _pickPhoto() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1200,
      );
      if (picked == null) return;
      setState(() => _photoFile = File(picked.path));
    } catch (e) {
      _toast('Could not pick a photo');
    }
  }

  Future<void> _saveWorkProfile() async {
    if (_lat == null || _lng == null) {
      _toast('Set your service base location');
      return;
    }
    setState(() => _savingProfile = true);
    try {
      final payload = <String, dynamic>{
        'serviceArea': {
          'address': _addressLabel ?? '',
          'coordinates': [_lng, _lat],
          'radius': _radiusKm.round(),
        },
      };
      Map<String, List<String>>? fileMap;
      if (_photoFile != null) {
        fileMap = {
          'profileImage': [_photoFile!.path],
        };
      }

      final res = await ArtistService.updateMyProfile(
        payload,
        fileMap: fileMap,
      );
      if (!mounted) return;
      if (res != null) {
        if (res['profileImage'] is String) {
          _photoUrl = res['profileImage'].toString();
        }
        setState(() {
          _completed[1] = true;
          _expanded[1] = false;
          if (!_completed[2]) _expanded[2] = true;
        });
        _advanceTo(2);
        _toast('Profile saved');
      } else {
        _toast('Could not save profile. Please try again.');
      }
    } catch (e) {
      _toast('Could not save profile. Please try again.');
      if (kDebugMode) debugPrint('saveWorkProfile error: $e');
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  // ---- Section 3: KYC ----------------------------------------------------

  Future<void> _startVerification() async {
    final nin = _model.ninController?.text.trim() ?? '';
    if (nin.length != 11 || int.tryParse(nin) == null) {
      _toast('Enter a valid 11-digit NIN');
      return;
    }
    final profile = AuthNotifier.instance.profile;
    String firstName = '';
    String lastName = '';
    final fullName = profile?['name']?.toString() ?? '';
    if (fullName.isNotEmpty) {
      final parts = fullName.split(' ');
      firstName = parts.first;
      if (parts.length > 1) lastName = parts.sublist(1).join(' ');
    }

    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => LivenessCheckWidget(
          nin: nin,
          firstName: firstName,
          lastName: lastName,
        ),
      ),
    );
    if (result == null || !mounted) return;
    final status = result['status']?.toString();
    if (status == 'approved' ||
        status == 'pending' ||
        status == 'pending_review') {
      setState(() {
        _completed[2] = true;
        _expanded[2] = false;
      });
      _toast(status == 'approved'
          ? 'Identity verified'
          : 'Verification submitted — we\'ll let you know once it\'s approved');
      _maybeFinish();
    } else if (status == 'rejected') {
      _toast(
          (result['failureReason'] ?? 'Verification didn\'t match — try again')
              .toString());
    }
  }

  void _skipVerification() {
    setState(() {
      _completed[2] = true;
      _expanded[2] = false;
    });
    _toast('You can verify later from your profile');
    _maybeFinish();
  }

  void _maybeFinish() {
    if (_completed.every((c) => c)) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        try {
          context.go(ArtisanDashboardPageWidget.routePath);
        } catch (_) {
          Navigator.of(context).pushReplacementNamed(
              ArtisanDashboardPageWidget.routePath);
        }
      });
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  // ---- Build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldLeave = await _confirmExit();
        if (shouldLeave && mounted) _exitToDashboard();
      },
      child: Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            final shouldLeave = await _confirmExit();
            if (shouldLeave && mounted) _exitToDashboard();
          },
        ),
        title: const Text(
          'Get Set Up',
          style: TextStyle(fontWeight: FontWeight.w700, color: Colors.black),
        ),
      ),
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _buildProgressHeader(theme),
          const SizedBox(height: 20),
          KeyedSubtree(
            key: _sectionKeys[0],
            child: _buildSectionCard(
              index: 0,
              icon: Icons.handyman_outlined,
              iconBg: const Color(0xFFFCE4EC),
              title: 'Trade, Services & Prices',
              subtitle: 'Tell us what you do best',
              child: _buildTradeSection(theme),
            ),
          ),
          const SizedBox(height: 16),
          KeyedSubtree(
            key: _sectionKeys[1],
            child: _buildSectionCard(
              index: 1,
              icon: Icons.location_on_outlined,
              iconBg: const Color(0xFFFCE4EC),
              title: 'Work Radius & Profile',
              subtitle: 'Set your service area and photo',
              child: _buildWorkProfileSection(theme),
            ),
          ),
          const SizedBox(height: 16),
          KeyedSubtree(
            key: _sectionKeys[2],
            child: _buildSectionCard(
              index: 2,
              icon: Icons.verified_user_outlined,
              iconBg: const Color(0xFFFCE4EC),
              title: 'Identity Verification',
              subtitle: 'Secure your account with KYC',
              child: _buildKycSection(theme),
            ),
          ),
        ],
      ),
      ),
    );
  }

  void _exitToDashboard() {
    try {
      context.go(ArtisanDashboardPageWidget.routePath);
    } catch (_) {
      try {
        Navigator.of(context).pushReplacementNamed(
            ArtisanDashboardPageWidget.routePath);
      } catch (_) {}
    }
  }

  Future<bool> _confirmExit() async {
    // Everything's done — no point asking, just let them out.
    if (_completed.every((c) => c)) return true;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFFCE4EC),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.bolt_rounded,
                    color: primaryColor, size: 30),
              ),
              const SizedBox(height: 16),
              const Text(
                'Almost there — finish setting up',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Most artisans complete this in under 3 minutes. Until you finish, your profile won't appear in client searches and you can't receive bookings.",
                style: TextStyle(
                  fontSize: 13.5,
                  color: Colors.black54,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
              _DialogBenefit(
                color: primaryColor,
                icon: Icons.search_rounded,
                text: 'Get found by clients in your area',
              ),
              const SizedBox(height: 10),
              _DialogBenefit(
                color: primaryColor,
                icon: Icons.event_available_rounded,
                text: 'Start receiving booking requests',
              ),
              const SizedBox(height: 10),
              _DialogBenefit(
                color: primaryColor,
                icon: Icons.timer_outlined,
                text: 'Takes about 3 minutes',
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Continue setup',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text(
                    'Exit anyway',
                    style: TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return result ?? false;
  }

  Widget _buildProgressHeader(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Profile Completion',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            Text(
              '$_completionPercent% Complete',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: primaryColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: _completionFraction,
            minHeight: 6,
            backgroundColor: const Color(0xFFFCE4EC),
            valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Complete these 3 steps to start receiving booking requests from customers in your area.',
          style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.4),
        ),
      ],
    );
  }

  Widget _buildSectionCard({
    required int index,
    required IconData icon,
    required Color iconBg,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    final expanded = _expanded[index];
    final completed = _completed[index];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEFEFEF)),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _expanded[index] = !expanded),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: iconBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: primaryColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                            if (completed) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.check_circle,
                                  color: primaryColor, size: 16),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.black54,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: child,
            ),
        ],
      ),
    );
  }

  // ---- Section 1 UI ------------------------------------------------------

  Widget _buildTradeSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Trade category — takes most of the row.
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Trade Category',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  _loadingCategories
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: LinearProgressIndicator(minHeight: 2),
                        )
                      : Container(
                          height: 48,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF1F4),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: _selectedCategoryId,
                              hint: const Text('Select'),
                              items: _categories.map((c) {
                                final id = (c['_id'] ?? c['id']).toString();
                                final name = (c['name'] ??
                                        c['title'] ??
                                        'Category')
                                    .toString();
                                return DropdownMenuItem(
                                    value: id, child: Text(name));
                              }).toList(),
                              onChanged: (v) {
                                if (v == null) return;
                                setState(() {
                                  _selectedCategoryId = v;
                                });
                                _loadSubcategories(v);
                              },
                            ),
                          ),
                        ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Years of experience — small numeric field beside category.
            SizedBox(
              width: 96,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Years',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1F4),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: TextField(
                      controller: _model.experienceController,
                      focusNode: _model.experienceFocus,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 2,
                      decoration: const InputDecoration(
                        counterText: '',
                        hintText: '0',
                        border: InputBorder.none,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                      ),
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'How many years have you been doing this work?',
          style: TextStyle(
              fontSize: 11.5, color: Colors.black.withOpacity(0.5)),
        ),
        const SizedBox(height: 16),
        const Text('Services Offered',
            style:
                TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        _buildServicesChips(),
        if (_selectedServices.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                    children: [
                      const TextSpan(text: 'Service Pricing '),
                      TextSpan(
                        text: '(Suggestions based on market)',
                        style: TextStyle(
                          color: primaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                ..._selectedServices.entries.map((e) => _buildPriceRow(
                    e.value.name, e.value.priceCtrl)),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            onPressed: _savingTrade ? null : _saveTradeDetails,
            child: _savingTrade
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Text('Save Trade Details',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
      ],
    );
  }

  Widget _buildServicesChips() {
    if (_selectedCategoryId == null) {
      return const Text(
        'Pick a category to see services you can offer.',
        style: TextStyle(fontSize: 12, color: Colors.black54),
      );
    }
    if (_loadingSubs) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    if (_subcategories.isEmpty) {
      return const Text(
        'No services found for this category yet.',
        style: TextStyle(fontSize: 12, color: Colors.black54),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ..._subcategories.map((s) {
          final id = (s['_id'] ?? s['id']).toString();
          final name = (s['name'] ?? s['title'] ?? 'Service').toString();
          final selected = _selectedServices.containsKey(id);
          return InkWell(
            onTap: () => _toggleService(s),
            borderRadius: BorderRadius.circular(40),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFFFFF1F4) : Colors.white,
                borderRadius: BorderRadius.circular(40),
                border: Border.all(
                    color: selected ? primaryColor : const Color(0xFFE0E0E0)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 13,
                      color: selected ? primaryColor : Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.close, size: 14, color: primaryColor),
                  ],
                ],
              ),
            ),
          );
        }),
        // Disabled placeholder "+ Add Service" chip — keeps the design but
        // doesn't add anything since selection is driven by the chips above.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(40),
            border: Border.all(
              color: const Color(0xFFE0E0E0),
              style: BorderStyle.solid,
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 14, color: Colors.black54),
              SizedBox(width: 4),
              Text('Add Service',
                  style: TextStyle(fontSize: 13, color: Colors.black54)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPriceRow(String name, TextEditingController ctrl) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
            ),
          ),
          SizedBox(
            width: 110,
            child: TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                filled: true,
                fillColor: Colors.white,
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(left: 8, right: 4),
                  child: Text('₦',
                      style: TextStyle(
                          fontSize: 14,
                          color: Colors.black54,
                          fontWeight: FontWeight.w600)),
                ),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 0, minHeight: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- Section 2 UI ------------------------------------------------------

  Widget _buildWorkProfileSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        const Text('Service Base Location',
            style:
                TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        _buildLocationSearch(),
        const SizedBox(height: 18),
        const Text('Professional Profile Photo',
            style:
                TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            DottedBox(
              size: 100,
              color: primaryColor,
              child: _photoFile != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(_photoFile!,
                          fit: BoxFit.cover, width: 100, height: 100),
                    )
                  : (_photoUrl != null && _photoUrl!.isNotEmpty)
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(_photoUrl!,
                              fit: BoxFit.cover, width: 100, height: 100),
                        )
                      : Center(
                          child: Icon(Icons.add_a_photo_outlined,
                              color: primaryColor, size: 32),
                        ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'A clear, professional photo helps build trust with potential clients.',
                    style:
                        TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryColor,
                      side: BorderSide(color: primaryColor),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                    ),
                    onPressed: _pickPhoto,
                    child: const Text('Upload Photo',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            onPressed: _savingProfile ? null : _saveWorkProfile,
            child: _savingProfile
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Text('Save & Continue',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
      ],
    );
  }

  /// Search-driven location picker: typeahead address input + GPS shortcut.
  /// On selection, derives `_radiusKm` from the place's viewport via Haversine
  /// (same approach the legacy artisan_profileupdate flow used) so the artisan
  /// never has to set a slider.
  Widget _buildLocationSearch() {
    final hasSelected = _lat != null && _lng != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search field
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFFF1F4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: _locationSearchCtrl,
            focusNode: _locationSearchFocus,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search address (e.g. Lekki Phase 1, Lagos)',
              hintStyle: const TextStyle(
                  fontSize: 13.5, color: Colors.black45),
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
              prefixIcon: Icon(Icons.search, color: primaryColor, size: 20),
              suffixIcon: _searchingPlaces
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: primaryColor),
                      ),
                    )
                  : (_locationSearchCtrl.text.isNotEmpty
                      ? IconButton(
                          tooltip: 'Clear',
                          icon: const Icon(Icons.close,
                              color: Colors.black45, size: 18),
                          onPressed: _clearSelectedAddress,
                        )
                      : IconButton(
                          tooltip: 'Use current location',
                          icon: Icon(Icons.my_location,
                              color: primaryColor, size: 18),
                          onPressed: _loadingLocation
                              ? null
                              : _useCurrentLocation,
                        )),
            ),
          ),
        ),

        // GPS spinner row (only when GPS is detecting and there's no selection yet)
        if (_loadingLocation && !hasSelected) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: primaryColor),
              ),
              const SizedBox(width: 8),
              const Text('Detecting your location…',
                  style: TextStyle(fontSize: 12, color: Colors.black54)),
            ],
          ),
        ],

        // Suggestions dropdown
        if (_placeSuggestions.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFEEEEEE)),
            ),
            child: Column(
              children: List.generate(_placeSuggestions.length, (i) {
                final s = _placeSuggestions[i];
                final main = s['structured_formatting']?['main_text']
                        ?.toString() ??
                    s['description']?.toString() ??
                    '';
                final secondary = s['structured_formatting']
                            ?['secondary_text']
                        ?.toString() ??
                    '';
                return Column(
                  children: [
                    InkWell(
                      onTap: () => _selectPlace(s),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        child: Row(
                          children: [
                            Icon(Icons.location_on_outlined,
                                size: 18, color: primaryColor),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    main,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black87),
                                  ),
                                  if (secondary.isNotEmpty)
                                    Text(
                                      secondary,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.black54),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (i < _placeSuggestions.length - 1)
                      const Divider(height: 1, color: Color(0xFFF0F0F0)),
                  ],
                );
              }),
            ),
          ),
        ],

        // Confirmation card after a place is selected
        if (hasSelected && _placeSuggestions.isEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFC8E6C9)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle,
                    color: Colors.green.shade700, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _addressLabel ?? '',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Service area: ~${_radiusKm.round()} km radius (auto)',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.green.shade900,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // Legacy map-based location card with manual radius slider. Kept commented
  // for rollback per the project's "comment, don't remove" preference.
  // Replaced by the search-driven _buildLocationSearch() above.
  // ignore: unused_element
  // Widget _buildLocationCard() {
  //   final hasLatLng = _lat != null && _lng != null;
  //   return Container(
  //     height: 160,
  //     decoration: BoxDecoration(
  //       color: const Color(0xFFEFEFEF),
  //       borderRadius: BorderRadius.circular(12),
  //     ),
  //     child: Stack(
  //       children: [
  //         if (hasLatLng)
  //           ClipRRect(
  //             borderRadius: BorderRadius.circular(12),
  //             child: AbsorbPointer(
  //               child: gmaps.GoogleMap(
  //                 initialCameraPosition: gmaps.CameraPosition(
  //                   target: gmaps.LatLng(_lat!, _lng!),
  //                   zoom: 14,
  //                 ),
  //                 markers: {
  //                   gmaps.Marker(
  //                     markerId: const gmaps.MarkerId('me'),
  //                     position: gmaps.LatLng(_lat!, _lng!),
  //                   ),
  //                 },
  //                 liteModeEnabled: true,
  //                 zoomControlsEnabled: false,
  //                 mapToolbarEnabled: false,
  //                 myLocationButtonEnabled: false,
  //               ),
  //             ),
  //           )
  //         else
  //           const Center(
  //             child: Text(
  //               'Set your service base location',
  //               style: TextStyle(color: Colors.black54),
  //             ),
  //           ),
  //       ],
  //     ),
  //   );
  // }

  // ---- Section 3 UI ------------------------------------------------------

  Widget _buildKycSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFC8E6C9)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline,
                  color: Color(0xFF2E7D32), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Verification usually takes less than 24 hours. Verified artisans get 3x more bookings.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.green.shade900,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const Text('Document Type',
            style:
                TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE0E0E0)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _documentType,
              items: const [
                DropdownMenuItem(value: 'NIN', child: Text('NIN')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _documentType = v);
              },
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Text('ID Number',
            style:
                TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: _model.ninController,
          focusNode: _model.ninFocus,
          keyboardType: TextInputType.number,
          maxLength: 11,
          decoration: InputDecoration(
            counterText: '',
            hintText: 'Enter ID Number',
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            onPressed: _startVerification,
            child: const Text('Verify Now',
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: _skipVerification,
            child: Text(
              'Skip ID for now',
              style: TextStyle(
                color: primaryColor,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ServiceRow {
  final String name;
  final TextEditingController priceCtrl;
  _ServiceRow({required this.name, required this.priceCtrl});
}

/// Single benefit row used inside the exit-confirmation dialog.
class _DialogBenefit extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _DialogBenefit({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: const Color(0xFFFCE4EC),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13.5,
              color: Colors.black87,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

/// Dotted-border placeholder used for the photo upload tile.
class DottedBox extends StatelessWidget {
  final double size;
  final Color color;
  final Widget child;

  const DottedBox({
    super.key,
    required this.size,
    required this.color,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DottedBorderPainter(color: color),
      child: SizedBox(width: size, height: size, child: child),
    );
  }
}

class _DottedBorderPainter extends CustomPainter {
  final Color color;
  _DottedBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(10),
    );
    final path = Path()..addRRect(rect);

    const dashWidth = 5.0;
    const dashSpace = 4.0;
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double distance = 0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
