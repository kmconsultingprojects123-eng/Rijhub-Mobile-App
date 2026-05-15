import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

// Switched from native `dojah_kyc_sdk_flutter` to the WebView-based
// `flutter_dojah_kyc` because the native SDK 0.1.7 has a fragment lifecycle
// crash during selfie capture. Re-enable the lines below to flip back once
// Dojah ships a fixed native SDK (>0.1.7).
// import 'package:dojah_kyc_sdk_flutter/dojah_extra_flutter_data.dart';
// import 'package:dojah_kyc_sdk_flutter/dojah_kyc_sdk_flutter.dart';
import 'package:flutter_dojah_kyc/flutter_dojah_kyc.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import '../../dojah_config.dart';
import '../../google_maps_config.dart';
import '../../services/artist_service.dart';
import '../../services/job_service.dart';
import '../../services/kyc_service.dart';
import '../../services/my_service_service.dart';
import '../../services/token_storage.dart';
import '../../services/user_service.dart';
import '../../utils/image_compress.dart';
import '../../state/auth_notifier.dart';
import '../../utils/location_permission.dart';
import 'artisan_onboarding_model.dart';

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

  // Location-search scope: Abuja / Federal Capital Territory only.
  // RijHub currently operates in FCT, so suggestions for addresses
  // outside the territory just add noise. Center is roughly Abuja
  // city centre; radius=60km covers the entire FCT plus a small
  // buffer for edge areas (Mararaba/Kuje/etc.). Combined with
  // `strictbounds=true` this hard-limits Places Autocomplete to
  // results inside the circle.
  static const double _abujaLat = 9.0765;
  static const double _abujaLng = 7.3986;
  static const int _abujaSearchRadiusMeters = 60000;

  // Section expansion state — first section opens by default.
  // Index 0=Trade, 1=Work, 2=Showcase, 3=Identity.
  final List<bool> _expanded = [true, false, false, false];
  // Section completion state (local) — used for stepper checkmarks.
  final List<bool> _completed = [false, false, false, false];

  // Server-reported profile progress (0.0–1.0). Refetched from
  // GET /api/artisans/me on init and after every onboarding step succeeds —
  // same endpoint the artisan dashboard uses, so the two stay in sync.
  double _serverProgress = 0.0;

  // True while the screen is performing its initial fetch of categories +
  // existing artisan data. The form is hidden behind a centered loader
  // during this window so returning users don't see a stale empty form
  // for a beat before their saved data populates.
  bool _hydrating = true;

  final ScrollController _scrollController = ScrollController();
  final List<GlobalKey> _sectionKeys = [
    GlobalKey(),
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

  // Section 3: Showcase Your Work (portfolio + certifications)
  // Each portfolio entry: {title: String, imagePath: String?, imageUrl: String?}
  // - imagePath is set for newly-picked local files (uploaded on save).
  // - imageUrl is set for entries hydrated from the backend.
  final List<Map<String, dynamic>> _portfolioItems = [];
  // Each cert entry: {name: String, fileUrl: String?}
  final List<Map<String, dynamic>> _certifications = [];
  bool _savingShowcase = false;
  // Progress state for the showcase upload (Section 3). Mirrors the
  // legacy ArtisanKycWidget UX: compressing -> uploading, with a
  // percentage and a determinate progress bar so the artisan isn't
  // staring at a spinner during a long multipart upload.
  // null label hides the indicator entirely.
  String? _showcaseProgressLabel;
  double _showcaseProgress = 0.0;
  Timer? _showcaseUploadTickTimer;

  // Section 4: Identity Verification
  String _documentType = 'NIN';

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => ArtisanOnboardingModel());
    _hydrateFromStorage();
    // Categories must load BEFORE hydrating from server, because the
    // hydration maps the artisan's saved trade name back to a category id.
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      await _loadCategories();
      if (!mounted) return;
      await Future.wait([
        _hydrateFromServer(),
        _refreshProfileProgress(),
      ]);
    } finally {
      if (mounted) setState(() => _hydrating = false);
    }
  }

  // ---- Theme helpers ----------------------------------------------------
  // The original light-mode design used soft pink fills (e.g. 0xFFFFF1F4)
  // and a black text palette. These helpers return the equivalent colour
  // for the current brightness so the screen reads cleanly in dark mode.

  /// Soft pink in light mode; subtle dark surface in dark mode. Used as the
  /// fill colour for input fields, dropdowns, and price-row containers.
  Color _inputFillColor(ThemeData theme) {
    return theme.brightness == Brightness.dark
        ? theme.colorScheme.onSurface.withOpacity(0.06)
        : const Color(0xFFFFF1F4);
  }

  /// Subtle border colour that adapts to the brightness.
  Color _subtleBorder(ThemeData theme) {
    return theme.colorScheme.onSurface.withOpacity(0.08);
  }

  @override
  void dispose() {
    for (final row in _selectedServices.values) {
      row.priceCtrl.dispose();
    }
    _scrollController.dispose();
    _searchDebounce?.cancel();
    _showcaseUploadTickTimer?.cancel();
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

  /// Pulls the artisan's saved data from the backend and pre-fills every
  /// section so returning users see what they already entered. Runs after
  /// `_loadCategories` so we can map the saved `trade` name back to a
  /// category id. Sections that come back already filled are marked
  /// completed and collapsed; the first incomplete one is auto-expanded.
  Future<void> _hydrateFromServer() async {
    try {
      final profileFuture = ArtistService.getMyProfile();
      final servicesFuture = MyServiceService().fetchMyServices();
      final kycFuture = TokenStorage.getToken().then((t) {
        if (t != null && t.isNotEmpty) {
          return KycService.getKycStatus(token: t).catchError(
              (_) => <String, dynamic>{});
        }
        return <String, dynamic>{};
      });

      final results = await Future.wait<dynamic>([
        profileFuture,
        servicesFuture,
        kycFuture,
      ]);
      if (!mounted) return;

      final profile = results[0] as Map<String, dynamic>?;
      final servicesResp = results[1];
      final kycStatus = results[2] as Map<String, dynamic>;

      // ---- Section 1: trade category + experience -----------------------
      String? matchedCategoryId;
      if (profile != null) {
        final trade = profile['trade'];
        String? tradeName;
        if (trade is List && trade.isNotEmpty) {
          tradeName = trade.first?.toString();
        } else if (trade is String) {
          tradeName = trade;
        }
        if (tradeName != null && tradeName.trim().isNotEmpty) {
          final lookup = tradeName.trim().toLowerCase();
          final found = _categories.firstWhere(
            (c) =>
                (c['name'] ?? c['title'] ?? '')
                    .toString()
                    .toLowerCase() ==
                lookup,
            orElse: () => {},
          );
          if (found.isNotEmpty) {
            matchedCategoryId = (found['_id'] ?? found['id']).toString();
          }
        }
        // Experience years
        final exp = profile['experience'];
        if (exp != null &&
            (_model.experienceController?.text.trim().isEmpty ?? true)) {
          _model.experienceController?.text = exp.toString();
        }

        // ---- Section 2: location + photo --------------------------------
        final sa = profile['serviceArea'];
        if (sa is Map) {
          final addr = sa['address']?.toString();
          final coords = sa['coordinates'];
          final radius = sa['radius'];
          double? lat;
          double? lng;
          if (coords is List && coords.length >= 2) {
            // serviceArea is stored [lon, lat] per the legacy convention.
            lng = (coords[0] as num?)?.toDouble();
            lat = (coords[1] as num?)?.toDouble();
          }
          if (mounted) {
            setState(() {
              if (lat != null && lng != null) {
                _lat = lat;
                _lng = lng;
              }
              if (addr != null && addr.isNotEmpty) {
                _addressLabel = addr;
                if (_locationSearchCtrl.text.isEmpty) {
                  _locationSearchCtrl.text = addr;
                }
              }
              if (radius is num) _radiusKm = radius.toDouble();
            });
          }
        }

        final img = (profile['profileImage'] ??
                profile['avatar'] ??
                profile['photo'])
            ?.toString();
        if (img != null && img.isNotEmpty) {
          if (mounted) setState(() => _photoUrl = img);
        }

        // ---- Section 3: portfolio + certifications ----------------------
        final port = profile['portfolio'];
        if (port is List && mounted) {
          final hydrated = <Map<String, dynamic>>[];
          for (final p in port) {
            if (p is! Map) continue;
            final title = (p['title'] ?? '').toString();
            String? imageUrl;
            final imgs = p['images'];
            if (imgs is List && imgs.isNotEmpty) {
              final first = imgs.first;
              if (first is String) {
                imageUrl = first;
              } else if (first is Map) {
                imageUrl = (first['url'] ?? first['secure_url'])?.toString();
              }
            }
            hydrated.add({
              'title': title,
              'imagePath': null,
              'imageUrl': imageUrl,
            });
          }
          setState(() {
            _portfolioItems
              ..clear()
              ..addAll(hydrated);
          });
        }

        final certs = profile['certifications'];
        if (certs is List && mounted) {
          final hydrated = <Map<String, dynamic>>[];
          for (final c in certs) {
            if (c is String && c.isNotEmpty) {
              hydrated.add({'name': c, 'fileUrl': null});
            } else if (c is Map) {
              final name = (c['name'] ?? c['title'] ?? '').toString();
              final url = (c['fileUrl'] ?? c['url'])?.toString();
              if (name.isNotEmpty || (url != null && url.isNotEmpty)) {
                hydrated.add({
                  'name': name.isNotEmpty ? name : (url ?? ''),
                  'fileUrl': url,
                });
              }
            }
          }
          setState(() {
            _certifications
              ..clear()
              ..addAll(hydrated);
          });
        }

        // Business name (optional) — pre-fill if the artisan saved one
        // previously. Only set when the field is currently empty so we
        // don't clobber a value the user is mid-typing.
        final bn = profile['businessName']?.toString();
        if (bn != null && bn.isNotEmpty && mounted) {
          if ((_model.businessNameController?.text.trim().isEmpty ??
              true)) {
            _model.businessNameController?.text = bn;
          }
        }

        // Bio (optional) — same pre-fill rule. Backend stores it as
        // top-level `bio` on the artisan document.
        final bioPrev = profile['bio']?.toString();
        if (bioPrev != null && bioPrev.isNotEmpty && mounted) {
          if ((_model.bioController?.text.trim().isEmpty ?? true)) {
            _model.bioController?.text = bioPrev;
          }
        }
      }

      // Subcategories must be loaded before we can populate selected services.
      if (matchedCategoryId != null) {
        if (mounted) setState(() => _selectedCategoryId = matchedCategoryId);
        await _loadSubcategories(matchedCategoryId);
        if (!mounted) return;
      }

      // ---- Section 1: services + prices ---------------------------------
      if (servicesResp != null && servicesResp.ok == true &&
          servicesResp.data != null) {
        final flat = MyServiceService.flattenArtisanServices(servicesResp.data);
        if (mounted && flat.isNotEmpty) {
          setState(() {
            for (final s in flat) {
              final subId =
                  (s['subCategoryId'] ?? s['_id'] ?? s['id'])?.toString();
              if (subId == null || subId.isEmpty) continue;
              final name =
                  (s['subCategoryName'] ?? s['name'] ?? 'Service').toString();
              final priceStr = s['price']?.toString() ?? '';
              _selectedServices[subId]?.priceCtrl.dispose();
              _selectedServices[subId] = _ServiceRow(
                name: name,
                priceCtrl: TextEditingController(text: priceStr),
              );
            }
          });
        }
      }

      // ---- Section 3: KYC status ----------------------------------------
      final kycSt = kycStatus['status']?.toString();
      final kycDone = kycSt == 'approved' ||
          kycSt == 'pending' ||
          kycSt == 'pending_review';

      // ---- Mark sections completed + auto-expand the first incomplete one
      if (!mounted) return;
      setState(() {
        // Section 1: has a category, services, and experience.
        _completed[0] = _selectedCategoryId != null &&
            _selectedServices.isNotEmpty &&
            (_model.experienceController?.text.trim().isNotEmpty ?? false);
        // Section 2: has lat/lng (location is the only hard requirement;
        // photo is encouraged but optional).
        _completed[1] = _lat != null && _lng != null;
        // Section 3 (Showcase Your Work): optional — mark complete if the
        // artisan already has any portfolio item or certification on file.
        // If both are empty, the section stays open so they can either
        // add content or explicitly skip it.
        _completed[2] =
            _portfolioItems.isNotEmpty || _certifications.isNotEmpty;
        // Section 4: KYC submitted (approved or under review).
        _completed[3] = kycDone;

        // Re-derive expansion: collapse what's done, expand the first
        // incomplete section.
        final firstIncomplete = _completed.indexOf(false);
        for (int i = 0; i < _expanded.length; i++) {
          _expanded[i] = i == firstIncomplete;
        }
      });
    } catch (e) {
      if (kDebugMode) debugPrint('hydrateFromServer error: $e');
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
        unawaited(_refreshProfileProgress());
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
      // No `types=` filter on purpose. `types=geocode` excludes
      // establishments (churches, businesses, POIs) — searching for
      // "NKST church Nyanya area c" was returning a generic "Area C
      // Phase IV" road instead of the actual church because the church
      // is classified as an establishment. Omitting the filter matches
      // what the Google Maps app does: addresses + places mixed,
      // ranked by relevance.
      //
      // `location=<lat>,<lng>&radius=<m>&strictbounds=true` hard-limits
      // results to within a 60km radius of Abuja city centre — the
      // service area for RijHub. Without strictbounds, Google returns
      // nearby + globally-popular hits; with it, results outside FCT
      // are filtered out entirely.
      final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/place/autocomplete/json'
          '?input=${Uri.encodeQueryComponent(query)}'
          '&components=country:ng'
          '&location=$_abujaLat,$_abujaLng'
          '&radius=$_abujaSearchRadiusMeters'
          '&strictbounds=true'
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

  /// Last-chance fallback when the user typed an address but never tapped a
  /// suggestion. Hits Google's Geocoding API directly with the raw text and,
  /// if anything resolves, returns the first match's lat/lng/address/radius.
  /// Returns null on any failure — the caller then keeps the raw text as a
  /// free-form address with no coordinates.
  /// Resolve a user-typed address string to coordinates. Used when the
  /// artisan presses Save on the work-profile section without first
  /// tapping a suggestion from the autocomplete dropdown.
  ///
  /// We use the **Places Autocomplete + Place Details** pair (NOT the
  /// Geocoding API). Geocoding is great for "formatted" addresses
  /// (e.g. "1 Infinite Loop, Cupertino") but loose with partial or
  /// hyper-local Nigerian text like "PLOT 100 area c NKST church nyanya"
  /// — it'll return whatever vaguely-matching coordinate comes back
  /// first, which has produced wildly-wrong resolves in testing (e.g.
  /// the above query landing on a Plus Code in Ado, FCT). Autocomplete
  /// is ranked by Google's place index and confidence, so taking the
  /// top prediction here matches what the artisan would have seen as
  /// the first dropdown option.
  ///
  /// Returns null when there's no good match (caller keeps the typed
  /// text as a free-form address with no coordinates — better than
  /// silently substituting the wrong place).
  Future<Map<String, dynamic>?> _geocodeTypedAddress(String text) async {
    try {
      final key = GOOGLE_MAPS_API_KEY;
      if (key.isEmpty) return null;

      // Step 1: Places Autocomplete — ranked by Google's index.
      // No `types=` filter — same reason as `_searchPlaces`: include
      // establishments (churches, businesses, POIs) so "NKST church
      // Nyanya" surfaces the church itself, not the surrounding street.
      // Scoped to Abuja/FCT via location+radius+strictbounds so a
      // save-without-picking on a vague query can't resolve to e.g.
      // Lagos or Kano.
      final autoUrl = Uri.parse(
          'https://maps.googleapis.com/maps/api/place/autocomplete/json'
          '?input=${Uri.encodeQueryComponent(text)}'
          '&components=country:ng'
          '&location=$_abujaLat,$_abujaLng'
          '&radius=$_abujaSearchRadiusMeters'
          '&strictbounds=true'
          '&key=$key');
      final autoResp =
          await http.get(autoUrl).timeout(const Duration(seconds: 10));
      if (autoResp.statusCode != 200 || autoResp.body.isEmpty) {
        if (kDebugMode) {
          debugPrint(
              '[Onboarding] geocodeTypedAddress: autocomplete http=${autoResp.statusCode}');
        }
        return null;
      }
      final autoBody = jsonDecode(autoResp.body);
      if (autoBody is! Map ||
          autoBody['predictions'] is! List ||
          (autoBody['predictions'] as List).isEmpty) {
        if (kDebugMode) {
          debugPrint(
              '[Onboarding] geocodeTypedAddress: no autocomplete predictions for "$text"');
        }
        return null;
      }
      final top = (autoBody['predictions'] as List).first as Map;
      final placeId = top['place_id']?.toString();
      final description = top['description']?.toString() ?? text;
      if (placeId == null || placeId.isEmpty) return null;

      if (kDebugMode) {
        debugPrint(
            '[Onboarding] geocodeTypedAddress: top prediction for "$text" -> "$description" (place_id=$placeId)');
      }

      // Step 2: Place Details — fetch geometry + formatted_address for the
      // top prediction. Same shape the user would have got by tapping it.
      final detailsUrl = Uri.parse(
          'https://maps.googleapis.com/maps/api/place/details/json'
          '?place_id=$placeId'
          '&fields=geometry,formatted_address'
          '&key=$key');
      final detResp =
          await http.get(detailsUrl).timeout(const Duration(seconds: 10));
      if (detResp.statusCode != 200 || detResp.body.isEmpty) return null;
      final detBody = jsonDecode(detResp.body);
      if (detBody is! Map || detBody['result'] is! Map) return null;
      final result = detBody['result'] as Map;
      final geometry = result['geometry'] as Map?;
      final loc = geometry?['location'] as Map?;
      final viewport = geometry?['viewport'] as Map?;
      final lat = (loc?['lat'] as num?)?.toDouble();
      final lng = (loc?['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;
      final address =
          result['formatted_address']?.toString() ?? description;

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
          final diag = _haversineDistance(swLat, swLng, neLat, neLng);
          radiusKm = diag / 2;
          if (radiusKm < 5) radiusKm = 5;
          if (radiusKm > 50) radiusKm = 50;
        }
      }

      if (kDebugMode) {
        debugPrint(
            '[Onboarding] geocodeTypedAddress: resolved "$text" -> "$address" ($lat,$lng) radius=${radiusKm.round()}km');
      }

      try {
        await TokenStorage.saveLocation(
          address: address,
          latitude: lat,
          longitude: lng,
        );
      } catch (_) {}

      return {
        'lat': lat,
        'lng': lng,
        'address': address,
        'radiusKm': radiusKm,
      };
    } catch (e) {
      if (kDebugMode) debugPrint('geocodeTypedAddress error: $e');
      return null;
    }
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
    // Three accepted shapes for "location set":
    //   1. _lat + _lng populated (the user tapped a suggestion or used GPS).
    //   2. Search text typed but no suggestion picked — try Google Geocoding
    //      as a one-shot resolve. If it succeeds, we get coords for free.
    //   3. Geocoding fails too — accept the typed text as a free-form
    //      address with no coordinates rather than block the user.
    if (_lat == null || _lng == null) {
      final typed = _locationSearchCtrl.text.trim();
      if (typed.isEmpty) {
        _toast('Set your service base location');
        return;
      }
      // Try to resolve coordinates from the typed text. If Google returns
      // something we use it; if not we keep the typed string as the address.
      setState(() => _savingProfile = true);
      final resolved = await _geocodeTypedAddress(typed);
      if (resolved != null) {
        final resolvedAddr = (resolved['address'] as String?) ?? typed;
        setState(() {
          _lat = resolved['lat'] as double?;
          _lng = resolved['lng'] as double?;
          _addressLabel = resolvedAddr;
          // Reflect the resolved label back into the search box so the
          // artisan sees exactly what we matched. If it's wrong they can
          // edit and re-save.
          _locationSearchCtrl.text = resolvedAddr;
          final r = resolved['radiusKm'] as double?;
          if (r != null) _radiusKm = r;
        });
        // Non-blocking confirmation. The previous flow silently
        // substituted a (sometimes wildly different) address — that bit
        // us in testing when "PLOT 100 area c NKST church nyanya"
        // resolved to a Plus Code in Ado. Showing the resolved string
        // lets the artisan catch a bad match before continuing.
        if (resolvedAddr.toLowerCase().trim() !=
            typed.toLowerCase().trim()) {
          _toast('Matched to: $resolvedAddr');
        }
      } else {
        setState(() {
          _addressLabel = typed;
        });
      }
    }

    setState(() => _savingProfile = true);
    try {
      final serviceArea = <String, dynamic>{
        'address': _addressLabel ?? _locationSearchCtrl.text.trim(),
        'radius': _radiusKm.round(),
      };
      // Only include coordinates when we actually have them — sending
      // [null, null] would corrupt the geo index on the backend.
      if (_lat != null && _lng != null) {
        serviceArea['coordinates'] = [_lng, _lat];
      }
      final payload = <String, dynamic>{
        'serviceArea': serviceArea,
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
        unawaited(_refreshProfileProgress());
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

  // ---- Section 3: Showcase Your Work (portfolio + certifications) -------

  /// Pick one or more images from the gallery and append them to the
  /// portfolio. Matches the legacy onboarding flow which only collected
  /// images — no title. (The data model still carries an optional `title`
  /// for backwards compatibility with anything previously saved by the
  /// old flow.) `pickMultiImage` lets the artisan multi-select in the
  /// system picker, so they can drop several work samples in one go.
  Future<void> _addPortfolioItem() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickMultiImage(
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (picked.isEmpty || !mounted) return;
      setState(() {
        for (final file in picked) {
          _portfolioItems.add({
            'title': '',
            'imagePath': file.path,
            'imageUrl': null,
          });
        }
      });
    } catch (e) {
      if (kDebugMode) debugPrint('addPortfolioItem error: $e');
      _toast('Could not add the images. Please try again.');
    }
  }

  /// Opens a small inline dialog to capture a certification name.
  Future<void> _addCertification() async {
    final ctrl = TextEditingController();
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final inputFill = _inputFillColor(theme);
    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: theme.cardColor,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: Text('Add certification',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: onSurface)),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            style: TextStyle(color: onSurface),
            decoration: InputDecoration(
              hintText: 'e.g. NABTEB Plumbing Cert',
              hintStyle: TextStyle(color: onSurface.withOpacity(0.5)),
              filled: true,
              fillColor: inputFill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 14),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel',
                  style: TextStyle(
                      color: onSurface.withOpacity(0.65),
                      fontWeight: FontWeight.w600)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              onPressed: () {
                if (ctrl.text.trim().isEmpty) return;
                Navigator.of(ctx).pop(true);
              },
              child: const Text('Add',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        );
      },
    );
    // Read the value before scheduling dispose, then defer dispose to the
    // next frame so the AlertDialog's exit animation can finish without the
    // TextField rebuilding against an already-disposed controller (which
    // crashes with `A TextEditingController was used after being disposed`).
    final entered = ctrl.text.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
    if (added == true && entered.isNotEmpty && mounted) {
      setState(() {
        _certifications.add({
          'name': entered,
          'fileUrl': null,
        });
      });
    }
  }

  /// Persists portfolio + certifications to the artisan profile via
  /// PUT /api/artisans/me. New local images are uploaded as multipart files
  /// (`portfolioImage<n>`); existing items already-uploaded URLs are sent in
  /// the JSON `portfolio` array. Certifications go up as plain string names.
  Future<void> _saveShowcase() async {
    setState(() {
      _savingShowcase = true;
      _showcaseProgress = 0.0;
      _showcaseProgressLabel = null;
    });
    try {
      // Build the multipart map for newly-picked local images so the
      // server can stream them to Cloudinary alongside the JSON payload.
      final localPaths = <String>[];
      final preExistingUrls = <String>[];
      final titles = <String>[];
      for (final it in _portfolioItems) {
        final title = (it['title'] ?? '').toString();
        titles.add(title);
        final path = it['imagePath']?.toString();
        final url = it['imageUrl']?.toString();
        if (path != null && path.isNotEmpty) {
          localPaths.add(path);
          preExistingUrls.add(''); // placeholder — filled by upload
        } else if (url != null && url.isNotEmpty) {
          localPaths.add('');
          preExistingUrls.add(url);
        }
      }

      // Compress new images before uploading (smaller payload + faster
      // upload + Cloudinary doesn't reject huge originals). Matches the
      // legacy KYC widget's progress UX: the bar fills 0% -> 40% over
      // compression, then jumps to 50% and ticks slowly toward 90% during
      // upload (the http package can't surface real upload progress, so
      // a timer-based estimate is the honest best we can do here).
      final pendingIndices = <int>[];
      for (var i = 0; i < localPaths.length; i++) {
        if (localPaths[i].isNotEmpty) pendingIndices.add(i);
      }

      if (pendingIndices.isNotEmpty) {
        setState(() {
          _showcaseProgressLabel = pendingIndices.length == 1
              ? 'Compressing image...'
              : 'Compressing 0 of ${pendingIndices.length}...';
          _showcaseProgress = 0.0;
        });
        try {
          final paths = pendingIndices.map((i) => localPaths[i]).toList();
          final compressed = await ImageCompressUtil.compressAll(
            paths,
            onProgress: (done, total) {
              if (!mounted) return;
              setState(() {
                _showcaseProgressLabel =
                    'Compressing $done of $total...';
                // First 40% of the bar is compression progress.
                _showcaseProgress = (done / total) * 0.4;
              });
            },
          );
          // Swap compressed paths back into localPaths so the multipart
          // upload sends the smaller files.
          for (var i = 0; i < pendingIndices.length; i++) {
            localPaths[pendingIndices[i]] = compressed[i];
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('Showcase compress failed (uploading originals): $e');
          }
        }
      }

      Map<String, List<String>>? fileMap;
      if (localPaths.any((p) => p.isNotEmpty)) {
        fileMap = <String, List<String>>{};
        for (var i = 0; i < localPaths.length; i++) {
          if (localPaths[i].isNotEmpty) {
            fileMap['portfolioImage${i + 1}'] = [localPaths[i]];
          }
        }
      }

      // Pre-existing items go in the JSON payload as-is. New items will
      // be filled in by the server's multipart handler — we still include
      // the titles array so the server can pair titles with the uploaded
      // images by index.
      final portfolioJson = <Map<String, dynamic>>[];
      for (var i = 0; i < _portfolioItems.length; i++) {
        final url = preExistingUrls[i];
        portfolioJson.add({
          'title': titles[i],
          'images': url.isNotEmpty ? [url] : <String>[],
          'beforeAfter': false,
        });
      }

      final certNames = _certifications
          .map((c) => (c['name'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toList();

      final businessName =
          _model.businessNameController?.text.trim() ?? '';
      final bio = _model.bioController?.text.trim() ?? '';

      final payload = <String, dynamic>{
        'portfolio': portfolioJson,
        'certifications': certNames,
        // Business name is optional — only sent when filled, so the
        // server doesn't overwrite a previously-saved value with empty.
        if (businessName.isNotEmpty) 'businessName': businessName,
        // Bio mirrors the legacy ArtisanCompleteProfileWidget's
        // 'bio' field on PUT /api/artisans/me. Same omit-if-empty
        // rule so a returning artisan doesn't accidentally wipe a
        // previously-saved bio by leaving the field blank.
        if (bio.isNotEmpty) 'bio': bio,
      };

      // Kick off the simulated upload tick. We jump to 50% (compression
      // is done, multipart request is about to fly), then tick toward
      // 90% over ~12 seconds so the bar keeps moving for slow networks
      // without ever reaching 100% before the server actually responds.
      if (fileMap != null && fileMap.isNotEmpty) {
        setState(() {
          _showcaseProgressLabel = fileMap!.length == 1
              ? 'Uploading work sample...'
              : 'Uploading work samples...';
          _showcaseProgress = 0.5;
        });
        _showcaseUploadTickTimer?.cancel();
        _showcaseUploadTickTimer = Timer.periodic(
          const Duration(milliseconds: 300),
          (_) {
            if (!mounted) return;
            if (_showcaseProgress >= 0.9) return;
            setState(() {
              _showcaseProgress =
                  math.min(0.9, _showcaseProgress + 0.01);
            });
          },
        );
      }

      final res = await ArtistService.updateMyProfile(
        payload,
        fileMap: fileMap,
      );
      _showcaseUploadTickTimer?.cancel();
      _showcaseUploadTickTimer = null;
      if (mounted) {
        setState(() {
          _showcaseProgress = 1.0;
          _showcaseProgressLabel = 'Finalising...';
        });
      }
      if (!mounted) return;
      if (res != null) {
        // If the server returned a finalised portfolio (with uploaded URLs),
        // mirror it into local state so subsequent re-saves don't re-upload.
        try {
          if (res['portfolio'] is List) {
            final returned = (res['portfolio'] as List)
                .whereType<Map>()
                .toList();
            _portfolioItems
              ..clear()
              ..addAll(returned.map((p) {
                final imgs = (p['images'] is List)
                    ? (p['images'] as List).map((e) => e.toString()).toList()
                    : <String>[];
                return {
                  'title': p['title']?.toString() ?? '',
                  'imagePath': null,
                  'imageUrl': imgs.isNotEmpty ? imgs.first : null,
                };
              }));
          }
        } catch (_) {}
        setState(() {
          _completed[2] = true;
          _expanded[2] = false;
          if (!_completed[3]) _expanded[3] = true;
        });
        _advanceTo(3);
        _toast('Showcase saved');
        unawaited(_refreshProfileProgress());
      } else {
        _toast('Could not save showcase. Please try again.');
      }
    } catch (e) {
      _toast('Could not save showcase. Please try again.');
      if (kDebugMode) debugPrint('saveShowcase error: $e');
    } finally {
      _showcaseUploadTickTimer?.cancel();
      _showcaseUploadTickTimer = null;
      if (mounted) {
        setState(() {
          _savingShowcase = false;
          _showcaseProgress = 0.0;
          _showcaseProgressLabel = null;
        });
      }
    }
  }

  void _skipShowcase() {
    setState(() {
      _completed[2] = true;
      _expanded[2] = false;
      if (!_completed[3]) _expanded[3] = true;
    });
    _advanceTo(3);
  }

  // ---- Section 4: KYC ----------------------------------------------------

  /// Pre-flight camera + microphone permission check before launching the
  /// Dojah WebView. Returns true when both permissions are granted and the
  /// SDK is safe to open; false otherwise (with appropriate user feedback
  /// already shown).
  ///
  /// On iOS, the Dojah WebView's `getUserMedia` call requires camera
  /// permission to be granted at the OS level before the page loads —
  /// otherwise the SDK silently bails to iOS Settings. Asking up-front means
  /// either the native iOS prompt fires (first run) or we show a clear
  /// dialog explaining why Settings is being opened (subsequent runs after
  /// a deny). Mic is included because Dojah's liveness step uses voice
  /// prompts on some flows.
  Future<bool> _ensureKycPermissions() async {
    // Camera is non-negotiable for selfie + liveness.
    final cam = await _requestPermission(
      Permission.camera,
      friendlyName: 'camera',
      explanation:
          "RijHub needs camera access to capture your selfie for identity verification. Please enable it in Settings to continue.",
    );
    if (!cam) return false;

    // Mic is best-effort — some Dojah widget configs use voice prompts for
    // liveness, so we ask, but a denial here shouldn't block the flow.
    try {
      final micStatus = await Permission.microphone.status;
      if (micStatus.isDenied) {
        await Permission.microphone.request();
      }
    } catch (_) {
      // Some platforms (web/desktop) don't expose mic; ignore.
    }
    return true;
  }

  /// Check + request a single permission, surfacing the right UI for each
  /// terminal state. Returns true iff the permission is `granted` (or
  /// `limited`, which iOS treats as a soft-yes).
  Future<bool> _requestPermission(
    Permission permission, {
    required String friendlyName,
    required String explanation,
  }) async {
    var status = await permission.status;
    if (status.isGranted || status.isLimited) return true;

    if (status.isDenied) {
      status = await permission.request();
      if (status.isGranted || status.isLimited) return true;
    }

    if (!mounted) return false;

    // permanentlyDenied (Android) / restricted (iOS managed devices) /
    // denied-after-prompt — the OS won't show its own prompt anymore, so
    // we explain the situation and offer to open Settings ourselves. This
    // replaces the SDK's silent Settings-open with something the artisan
    // can actually understand.
    final goToSettings = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          title: Text('${friendlyName[0].toUpperCase()}${friendlyName.substring(1)} access needed'),
          content: Text(
            explanation,
            style: theme.textTheme.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Not now'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Open settings'),
            ),
          ],
        );
      },
    );

    if (goToSettings == true) {
      try {
        await openAppSettings();
      } catch (_) {}
    }
    return false;
  }

  Future<void> _startVerification() async {
    final nin = _model.ninController?.text.trim() ?? '';
    if (nin.length != 11 || int.tryParse(nin) == null) {
      _toast('Enter a valid 11-digit NIN');
      return;
    }
    if (DOJAH_WIDGET_ID.isEmpty) {
      _toast('Identity verification is not configured. Please try again later.');
      if (kDebugMode) {
        debugPrint('startVerification: DOJAH_WIDGET_ID is empty');
      }
      return;
    }

    // Pre-flight camera/mic permission. The Dojah WebView calls
    // `getUserMedia` for the selfie + liveness step; on iOS that requires
    // OS-level camera permission to already be granted. If it isn't, the
    // SDK opens iOS Settings without explanation — which is exactly what
    // the artisan was seeing. By requesting up-front we either get the
    // native prompt (first run) or show our own dialog when permission
    // was previously denied, instead of yanking the user to Settings.
    final permsOk = await _ensureKycPermissions();
    if (!permsOk) return;

    // Pre-fill what we can so the user skips redundant entry inside the
    // Dojah widget. The widget handles the NIN entry, liveness, and selfie
    // match itself; first/last name come from the auth profile.
    final profile = AuthNotifier.instance.profile;
    String firstName = '';
    String lastName = '';
    final fullName = profile?['name']?.toString() ?? '';
    if (fullName.isNotEmpty) {
      final parts = fullName.split(' ');
      firstName = parts.first;
      if (parts.length > 1) lastName = parts.sublist(1).join(' ');
    }
    final email = profile?['email']?.toString();
    final userId = (profile?['_id'] ?? profile?['id'])?.toString();

    // Ask the backend to start a Dojah session and hand us a canonical
    // referenceId (see `dojah-pending-resolution-mobile.md`). This both
    // seeds a `pending` KYC record on our side and gives us the reference
    // the SDK must pass back to Dojah, ensuring the same id flows through
    // SDK -> Dojah -> verify-reference for the lookup.
    //
    // If start-session fails we abort here rather than fall back to a
    // client-generated id: the backend wouldn't have a `pending` record
    // for verify-reference to update, so the artisan would land on the
    // dashboard with no path to a final status.
    final token = await TokenStorage.getToken() ?? '';
    if (token.isEmpty) {
      _toast('You need to sign in again before verifying your identity.');
      return;
    }
    String? referenceId;
    try {
      referenceId = await KycService.startDojahSession(token: token);
    } catch (e) {
      if (kDebugMode) debugPrint('[Onboarding] startDojahSession threw: $e');
    }
    if (referenceId == null || referenceId.isEmpty) {
      if (kDebugMode) {
        debugPrint(
            '[Onboarding] startDojahSession failed — aborting KYC launch');
      }
      _toast(
          "Couldn't start identity verification. Please check your connection and try again.");
      return;
    }
    if (kDebugMode) {
      debugPrint(
          '[Onboarding] startDojahSession -> using server referenceId=$referenceId');
    }

    // Persist the referenceId so the dashboard's pending-retry loop can
    // replay verify-reference if the artisan lands there with a
    // still-pending KYC. Cleared in `_startVerification`'s post-handling
    // once the status flips to approved/rejected.
    try {
      await TokenStorage.saveKycReferenceId(referenceId);
    } catch (_) {}

    // Launch the Dojah WebView KYC widget. The widget runs the configured
    // verification flow (NIN entry / liveness / selfie match) inside a
    // WebView and reports back via callbacks. `open()` returns once the
    // user dismisses the WebView (whether by completing, closing, or
    // erroring), at which point `wasSuccess` / `capturedReference` /
    // `errorMsg` reflect the final state.
    String? capturedReference;
    String? errorMsg;
    bool wasSuccess = false;

    try {
      final dojah = DojahKYC(
        appId: DOJAH_APP_ID,
        publicKey: DOJAH_PUBLIC_KEY,
        type: 'custom',
        referenceId: referenceId,
        config: {
          'widget_id': DOJAH_WIDGET_ID,
        },
        userData: {
          if (firstName.isNotEmpty) 'first_name': firstName,
          if (lastName.isNotEmpty) 'last_name': lastName,
          if (email != null && email.isNotEmpty) 'email': email,
        },
        // Pre-fill NIN so the user skips re-typing it inside the widget.
        govData: {'nin': nin},
        metaData: {
          if (userId != null) 'rijhub_user_id': userId,
          'rijhub_local_ref': referenceId,
        },
      );

      await dojah.open(
        context,
        onSuccess: (result) {
          if (kDebugMode) debugPrint('DojahKYC.onSuccess: $result');
          wasSuccess = true;
          // Result shape varies — try to find a Dojah reference on it,
          // otherwise fall back to our local reference (which Dojah ties
          // to the verification on its side via `referenceId:` above).
          String? ref;
          if (result is Map) {
            ref = (result['referenceId'] ??
                    result['reference_id'] ??
                    result['data']?['referenceId'] ??
                    result['data']?['reference_id'])
                ?.toString();
          } else if (result is String && result.isNotEmpty) {
            ref = result;
          }
          capturedReference = ref ?? referenceId;
          // The Dojah hosted page doesn't close itself after the success
          // screen — it just calls this handler and goes blank. Pop the
          // WebView so the user returns to the onboarding screen and the
          // continuation below (verify-reference, status mapping) runs
          // immediately instead of waiting for a manual back-out.
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        },
        onClose: (close) {
          if (kDebugMode) debugPrint('DojahKYC.onClose: $close');
          // User-initiated close already pops the route, so don't double-pop.
        },
        onError: (err) {
          if (kDebugMode) debugPrint('DojahKYC.onError: $err');
          errorMsg = err?.toString();
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        },
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('DojahKYC.open failed: $e\n$st');
      }
      _toast('Could not start identity verification. Please try again.');
      return;
    }

    if (!mounted) return;

    if (errorMsg != null) {
      _toast(errorMsg!);
      return;
    }
    if (!wasSuccess || capturedReference == null || capturedReference!.isEmpty) {
      // User closed the widget without completing the flow.
      return;
    }
    final referenceForBackend = capturedReference!;

    // Show a non-dismissable overlay while we round-trip to the backend so
    // the user gets immediate feedback after Dojah closes (the API call can
    // take a couple of seconds; without this they see a stale onboarding
    // screen and assume nothing's happening).
    _showVerifyingKycOverlay();

    // Send the reference to the backend for authoritative verification.
    Map<String, dynamic> result = {};
    try {
      final token = await TokenStorage.getToken() ?? '';
      result = await KycService.verifyDojahReference(
        referenceId: referenceForBackend,
        token: token,
      );
    } on UserFriendlyException catch (e) {
      if (kDebugMode) {
        debugPrint('verifyDojahReference: ${e.developerMessage ?? e.userMessage}');
      }
      _dismissVerifyingKycOverlay();
      _toast(e.userMessage);
      return;
    } catch (e) {
      if (kDebugMode) debugPrint('verifyDojahReference unexpected: $e');
      // Treat as pending so the section doesn't stay open forever; the
      // dashboard's KYC status pill will catch up via /api/kyc/status.
      result = {'status': 'pending_review'};
    }

    // While the loader dialog is still up, fetch the authoritative KYC
    // status from the backend and persist it to TokenStorage. The dashboard
    // reads `TokenStorage.getKycStatus()` synchronously in its `initState`
    // (`_initKycStatus`), so by the time we navigate it already knows KYC
    // is verified — no stale "Almost there" Continue Setup card flash.
    // While the loader dialog is still up, hydrate the authoritative KYC
    // state from the backend and persist it to TokenStorage. The dashboard
    // reads from TokenStorage in its `initState`, so by the time we
    // navigate it already knows the outcome — no stale "Almost there"
    // Continue Setup card flash, and rejected submissions land with a
    // backend-supplied reason ready to show.
    //
    // Source-of-truth priority (per the backend's `dojah-kyc-status-updates`
    // doc):
    //   1) `/api/users/me` -> `data.kycDetails`  — most reliable; the doc
    //      explicitly added this field so the frontend has a single read
    //      that always reflects the current verification state.
    //   2) `/api/kyc/status` (`data.status`) — fallback. We've observed this
    //      endpoint occasionally returning 404 "No KYC record" right after
    //      a fresh submission while `/api/users/me` correctly reports
    //      `kycDetails.status = "pending"`. That's the bug that previously
    //      forced users to refresh the dashboard to see the "Verification
    //      pending" card.
    //   3) `result['status']` from verify-reference — last-resort tentative
    //      value used when both server reads fail (network/timeout).
    final tentativeStatus = result['status']?.toString() ?? '';
    String? resolvedStatus;
    String? resolvedReason;

    try {
      final profile = await UserService.getProfile();
      final details = profile == null ? null : profile['kycDetails'];
      if (details is Map) {
        final s = details['status']?.toString();
        final r = details['failureReason']?.toString();
        if (s != null && s.isNotEmpty && s.toLowerCase() != 'not_submitted') {
          resolvedStatus = s;
        }
        if (r != null && r.isNotEmpty && r.toLowerCase() != 'null') {
          resolvedReason = r;
        }
        if (kDebugMode) {
          debugPrint(
              '[Onboarding] post-verify profile.kycDetails -> status=$resolvedStatus reason=$resolvedReason');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('post-verify getProfile failed: $e');
    }

    // Fallback 2: /api/kyc/status (only if profile didn't yield a status).
    if (resolvedStatus == null) {
      try {
        final token = await TokenStorage.getToken() ?? '';
        if (token.isNotEmpty) {
          final fresh = await KycService.getKycStatus(token: token);
          final freshStatus = fresh['status']?.toString();
          final freshReason = fresh['failureReason']?.toString();
          if (freshStatus != null && freshStatus.isNotEmpty) {
            resolvedStatus = freshStatus;
            if (freshReason != null && freshReason.isNotEmpty) {
              resolvedReason ??= freshReason;
            }
            if (kDebugMode) {
              debugPrint(
                  '[Onboarding] post-verify /api/kyc/status -> status=$resolvedStatus reason=$resolvedReason');
            }
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('post-verify getKycStatus failed: $e');
      }
    }

    // Fallback 3: verify-reference's tentative status (network/timeout case).
    resolvedStatus ??= tentativeStatus.isNotEmpty ? tentativeStatus : null;
    resolvedReason ??= result['failureReason']?.toString();

    // Persist whatever we resolved so the dashboard reads it on mount.
    if (resolvedStatus != null && resolvedStatus.isNotEmpty) {
      try {
        await TokenStorage.saveKycStatus(resolvedStatus);
      } catch (_) {}
      // Update local result so the post-loader UI branching below uses the
      // freshest server-confirmed value.
      result['status'] = resolvedStatus;
      if (resolvedReason != null && resolvedReason.isNotEmpty) {
        result['failureReason'] = resolvedReason;
      }

      // Persist (or clear) the failure reason in lockstep with the status.
      // Non-rejection statuses pass null which wipes any stale reason left
      // over from a prior failed attempt.
      try {
        final sl = resolvedStatus.toLowerCase();
        if (sl == 'rejected' || sl == 'failed') {
          await TokenStorage.saveKycFailureReason(resolvedReason);
        } else {
          await TokenStorage.saveKycFailureReason(null);
        }
      } catch (_) {}

      // Reference id lifecycle: keep it while the KYC is still `pending`
      // so the dashboard's retry loop can keep polling; wipe it the moment
      // we hit a terminal state (approved/rejected/failed) so we don't
      // pointlessly re-verify a finalised record.
      try {
        final sl = resolvedStatus.toLowerCase();
        final isPending = sl == 'pending' || sl == 'pending_review';
        if (!isPending) await TokenStorage.saveKycReferenceId(null);
      } catch (_) {}

      // Push the fresh profile (with new kycDetails) into the global
      // AppStateNotifier so the dashboard — whose State persists inside
      // NavBarPage across navigations and therefore won't re-run
      // initState on return — picks up the change via its
      // notifyListeners() subscription. Without this, the artisan lands
      // on a stale dashboard and has to pull-to-refresh.
      try {
        unawaited(AppStateNotifier.instance.refreshProfile());
      } catch (_) {}
    }

    _dismissVerifyingKycOverlay();
    if (!mounted) return;

    final status = result['status']?.toString();
    if (status == 'approved' ||
        status == 'pending' ||
        status == 'pending_review') {
      setState(() {
        _completed[3] = true;
        _expanded[3] = false;
      });
      _toast(status == 'approved'
          ? 'Identity verified'
          : 'Verification submitted — we\'ll let you know once it\'s approved');
      unawaited(_refreshProfileProgress());
      // KYC is the last hard gate — push the artisan to the dashboard
      // even if Showcase Your Work was skipped. They can come back to add
      // showcase items from the dashboard's Continue Setup prompt later.
      Future.delayed(const Duration(milliseconds: 700), () {
        if (!mounted) return;
        _exitToDashboard();
      });
    } else if (status == 'rejected' || status == 'failed') {
      _toast(
          (result['failureReason'] ?? 'Verification didn\'t match — try again')
              .toString());
    }
  }

  /// Tracks whether the verifying-KYC overlay is currently shown so
  /// `_dismissVerifyingKycOverlay` can avoid popping the wrong route.
  bool _kycOverlayOpen = false;

  void _showVerifyingKycOverlay() {
    if (!mounted || _kycOverlayOpen) return;
    _kycOverlayOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: theme.cardColor,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.8, color: primaryColor),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Verifying your identity…',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'This usually takes a few seconds.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: theme.colorScheme.onSurface.withOpacity(0.65),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _dismissVerifyingKycOverlay() {
    if (!_kycOverlayOpen) return;
    _kycOverlayOpen = false;
    if (!mounted) return;
    try {
      Navigator.of(context, rootNavigator: true).pop();
    } catch (_) {}
  }

  void _skipVerification() {
    setState(() {
      _completed[3] = true;
      _expanded[3] = false;
    });
    _toast('You can verify later from your profile');
    unawaited(_refreshProfileProgress());
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
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final scaffoldBg = isDark
        ? theme.scaffoldBackgroundColor
        : Colors.white;
    final appBarFg = colorScheme.onSurface;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldLeave = await _confirmExit();
        if (shouldLeave && mounted) _exitToDashboard();
      },
      child: Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        backgroundColor: scaffoldBg,
        elevation: 0,
        foregroundColor: appBarFg,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            final shouldLeave = await _confirmExit();
            if (shouldLeave && mounted) _exitToDashboard();
          },
        ),
        title: Text(
          'Get Set Up',
          style: TextStyle(fontWeight: FontWeight.w700, color: appBarFg),
        ),
      ),
      body: _hydrating
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: primaryColor,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Loading your saved progress…',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface.withOpacity(0.65),
                    ),
                  ),
                ],
              ),
            )
          : ListView(
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
              icon: Icons.collections_outlined,
              iconBg: const Color(0xFFFCE4EC),
              title: 'Showcase Your Work',
              subtitle: 'Optional — but verified portfolios get more jobs',
              child: _buildShowcaseSection(theme),
            ),
          ),
          const SizedBox(height: 16),
          KeyedSubtree(
            key: _sectionKeys[3],
            child: _buildSectionCard(
              index: 3,
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

    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: theme.cardColor,
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
                  color: primaryColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.bolt_rounded,
                    color: primaryColor, size: 30),
              ),
              const SizedBox(height: 16),
              Text(
                'Almost there — finish setting up',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: onSurface,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Most artisans complete this in under 3 minutes. Until you finish, your profile won't appear in client searches and you can't receive bookings.",
                style: TextStyle(
                  fontSize: 13.5,
                  color: onSurface.withOpacity(0.65),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
              _DialogBenefit(
                color: primaryColor,
                icon: Icons.search_rounded,
                text: 'Get found by clients in your area',
                onSurface: onSurface,
              ),
              const SizedBox(height: 10),
              _DialogBenefit(
                color: primaryColor,
                icon: Icons.event_available_rounded,
                text: 'Start receiving booking requests',
                onSurface: onSurface,
              ),
              const SizedBox(height: 10),
              _DialogBenefit(
                color: primaryColor,
                icon: Icons.timer_outlined,
                text: 'Takes about 3 minutes',
                onSurface: onSurface,
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
                  child: Text(
                    'Exit anyway',
                    style: TextStyle(
                      color: onSurface.withOpacity(0.65),
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
    final onSurface = theme.colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Profile Completion',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: onSurface,
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
            backgroundColor: primaryColor.withOpacity(0.15),
            valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Complete these 4 steps to start receiving booking requests from customers in your area.',
          style: TextStyle(
              fontSize: 13,
              color: onSurface.withOpacity(0.65),
              height: 1.4),
        ),
      ],
    );
  }

  /// Sequential gate: a section can only be expanded if its prerequisite
  /// is complete. The optional Showcase section (index 2) is always
  /// expandable, and KYC (index 3) skips over Showcase to depend on Work
  /// (index 1) so an artisan who didn't fill out Showcase can still verify.
  bool _canExpand(int index) {
    switch (index) {
      case 0:
        return true; // Trade is always the first available step
      case 1:
        return _completed[0]; // Work needs Trade done
      case 2:
        return true; // Showcase is optional, always available
      case 3:
        return _completed[1]; // KYC needs Work done (skips over Showcase)
      default:
        return true;
    }
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
    final canExpand = _canExpand(index);
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return Opacity(
      opacity: canExpand ? 1.0 : 0.55,
      child: Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: onSurface.withOpacity(0.08)),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              if (!canExpand) {
                _toast('Complete the previous step first');
                return;
              }
              setState(() => _expanded[index] = !expanded);
            },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.12),
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
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: onSurface,
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
                          style: TextStyle(
                            fontSize: 12,
                            color: onSurface.withOpacity(0.65),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: onSurface.withOpacity(0.65),
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
      ),
    );
  }

  // ---- Section 1 UI ------------------------------------------------------

  Widget _buildTradeSection(ThemeData theme) {
    final onSurface = theme.colorScheme.onSurface;
    final inputFill = _inputFillColor(theme);
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
                  Text('Trade Category',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: onSurface)),
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
                            color: inputFill,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: _selectedCategoryId,
                              hint: Text('Select',
                                  style: TextStyle(
                                      color:
                                          onSurface.withOpacity(0.5))),
                              dropdownColor: theme.cardColor,
                              style: TextStyle(
                                  fontSize: 15, color: onSurface),
                              iconEnabledColor:
                                  onSurface.withOpacity(0.6),
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
                  Text('Years',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: onSurface)),
                  const SizedBox(height: 6),
                  Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: inputFill,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: TextField(
                      controller: _model.experienceController,
                      focusNode: _model.experienceFocus,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 2,
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: '0',
                        hintStyle:
                            TextStyle(color: onSurface.withOpacity(0.4)),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 14),
                      ),
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: onSurface),
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
              fontSize: 11.5, color: onSurface.withOpacity(0.5)),
        ),
        const SizedBox(height: 16),
        Text('Services Offered',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: onSurface)),
        const SizedBox(height: 8),
        _buildServicesChips(theme),
        if (_selectedServices.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: inputFill,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: onSurface,
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
                    theme, e.value.name, e.value.priceCtrl)),
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

  Widget _buildServicesChips(ThemeData theme) {
    final onSurface = theme.colorScheme.onSurface;
    final mutedTextStyle = TextStyle(
        fontSize: 12, color: onSurface.withOpacity(0.6));
    if (_selectedCategoryId == null) {
      return Text(
        'Pick a category to see services you can offer.',
        style: mutedTextStyle,
      );
    }
    if (_loadingSubs) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    if (_subcategories.isEmpty) {
      return Text(
        'No services found for this category yet.',
        style: mutedTextStyle,
      );
    }
    final unselectedChipBg = theme.cardColor;
    final selectedChipBg = primaryColor.withOpacity(0.12);
    final unselectedBorder = onSurface.withOpacity(0.15);
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
                color: selected ? selectedChipBg : unselectedChipBg,
                borderRadius: BorderRadius.circular(40),
                border: Border.all(
                    color: selected ? primaryColor : unselectedBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 13,
                      color: selected ? primaryColor : onSurface,
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
              color: unselectedBorder,
              style: BorderStyle.solid,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add,
                  size: 14, color: onSurface.withOpacity(0.6)),
              const SizedBox(width: 4),
              Text('Add Service',
                  style: TextStyle(
                      fontSize: 13,
                      color: onSurface.withOpacity(0.6))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPriceRow(
      ThemeData theme, String name, TextEditingController ctrl) {
    final onSurface = theme.colorScheme.onSurface;
    final borderSide = BorderSide(color: onSurface.withOpacity(0.15));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: TextStyle(fontSize: 14, color: onSurface),
            ),
          ),
          SizedBox(
            width: 110,
            child: TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.right,
              style: TextStyle(color: onSurface),
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                filled: true,
                fillColor: theme.cardColor,
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: 8, right: 4),
                  child: Text('₦',
                      style: TextStyle(
                          fontSize: 14,
                          color: onSurface.withOpacity(0.65),
                          fontWeight: FontWeight.w600)),
                ),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 0, minHeight: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: borderSide,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: borderSide,
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
    final onSurface = theme.colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Text('Service Base Location',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: onSurface)),
        const SizedBox(height: 6),
        _buildLocationSearch(theme),
        const SizedBox(height: 18),
        Text('Professional Profile Photo',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: onSurface)),
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
                  Text(
                    'A clear, professional photo helps build trust with potential clients.',
                    style: TextStyle(
                        fontSize: 12,
                        color: onSurface.withOpacity(0.65)),
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
  Widget _buildLocationSearch(ThemeData theme) {
    final hasSelected = _lat != null && _lng != null;
    final onSurface = theme.colorScheme.onSurface;
    final isDark = theme.brightness == Brightness.dark;
    final inputFill = _inputFillColor(theme);
    // Soft green for the success card — adapt to dark.
    final successBg = isDark
        ? Colors.green.withOpacity(0.15)
        : const Color(0xFFE8F5E9);
    final successBorder = isDark
        ? Colors.green.withOpacity(0.3)
        : const Color(0xFFC8E6C9);
    final successPrimary =
        isDark ? Colors.green.shade300 : Colors.green.shade700;
    final successSecondary =
        isDark ? Colors.green.shade200 : Colors.green.shade900;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search field
        Container(
          decoration: BoxDecoration(
            color: inputFill,
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: _locationSearchCtrl,
            focusNode: _locationSearchFocus,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            style: TextStyle(color: onSurface),
            decoration: InputDecoration(
              hintText: 'Search address (e.g. Lekki Phase 1, Lagos)',
              hintStyle: TextStyle(
                  fontSize: 13.5, color: onSurface.withOpacity(0.5)),
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
                          icon: Icon(Icons.close,
                              color: onSurface.withOpacity(0.5),
                              size: 18),
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
              Text('Detecting your location…',
                  style: TextStyle(
                      fontSize: 12,
                      color: onSurface.withOpacity(0.65))),
            ],
          ),
        ],

        // Suggestions dropdown
        if (_placeSuggestions.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _subtleBorder(theme)),
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
                                    style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                        color: onSurface),
                                  ),
                                  if (secondary.isNotEmpty)
                                    Text(
                                      secondary,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: onSurface
                                              .withOpacity(0.65)),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (i < _placeSuggestions.length - 1)
                      Divider(
                          height: 1, color: onSurface.withOpacity(0.06)),
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
              color: successBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: successBorder),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle,
                    color: successPrimary, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _addressLabel ?? '',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: onSurface),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Service area: ~${_radiusKm.round()} km radius (auto)',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: successSecondary,
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

  // ---- Section 3 UI: Showcase Your Work ---------------------------------

  Widget _buildShowcaseSection(ThemeData theme) {
    final onSurface = theme.colorScheme.onSurface;
    final inputFill = _inputFillColor(theme);
    final softTextColor = onSurface.withOpacity(0.65);
    final emptyBoxBorder = _subtleBorder(theme);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: inputFill,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.tips_and_updates_outlined,
                  size: 18, color: primaryColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Add a few past jobs and any certifications you have. It's optional, but artisans with portfolios get booked more often.",
                  style: TextStyle(
                    fontSize: 12,
                    color: onSurface.withOpacity(0.75),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // ----- Business name (optional) -----
        Text('Business name',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: onSurface)),
        const SizedBox(height: 6),
        TextField(
          controller: _model.businessNameController,
          focusNode: _model.businessNameFocus,
          textInputAction: TextInputAction.next,
          style: TextStyle(color: onSurface),
          decoration: InputDecoration(
            hintText: 'e.g. Smart Hands Plumbing',
            hintStyle: TextStyle(color: onSurface.withOpacity(0.5)),
            filled: true,
            fillColor: inputFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 14),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Optional — leave blank if you don\'t have one.',
          style: TextStyle(fontSize: 11.5, color: softTextColor),
        ),
        const SizedBox(height: 18),

        // ----- Bio (optional) -----
        // Free-form intro shown on the artisan's public profile. Mirrors
        // the legacy ArtisanCompleteProfileWidget's "Bio / About You"
        // field; the backend stores it as a top-level `bio` string on
        // PUT /api/artisans/me.
        Text('Bio',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: onSurface)),
        const SizedBox(height: 6),
        TextField(
          controller: _model.bioController,
          focusNode: _model.bioFocus,
          minLines: 3,
          maxLines: 4,
          maxLength: 500,
          textInputAction: TextInputAction.newline,
          textCapitalization: TextCapitalization.sentences,
          style: TextStyle(color: onSurface),
          decoration: InputDecoration(
            hintText:
                'A short intro about you and the work you do. Clients see this on your profile.',
            hintStyle: TextStyle(color: onSurface.withOpacity(0.5)),
            filled: true,
            fillColor: inputFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 14),
            counterStyle:
                TextStyle(fontSize: 11, color: softTextColor),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Optional — leave blank if you prefer.',
          style: TextStyle(fontSize: 11.5, color: softTextColor),
        ),
        const SizedBox(height: 18),

        // ----- Portfolio -----
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Portfolio',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: onSurface)),
            Text(
              '${_portfolioItems.length} item${_portfolioItems.length == 1 ? '' : 's'}',
              style: TextStyle(fontSize: 12, color: softTextColor),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_portfolioItems.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: emptyBoxBorder),
            ),
            child: Text(
              'No work samples yet. Tap "Add work sample" to add one.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: softTextColor),
            ),
          )
        else
          // Thumbnail grid — no title row; the image speaks for itself.
          // Each tile has a small ✕ overlay to remove it.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(_portfolioItems.length, (i) {
              final item = _portfolioItems[i];
              final imagePath = item['imagePath']?.toString();
              final imageUrl = item['imageUrl']?.toString();
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 92,
                      height: 92,
                      color: inputFill,
                      child: imagePath != null && imagePath.isNotEmpty
                          ? Image.file(File(imagePath), fit: BoxFit.cover)
                          : (imageUrl != null && imageUrl.isNotEmpty)
                              ? Image.network(imageUrl, fit: BoxFit.cover)
                              : Icon(Icons.image_outlined,
                                  color: primaryColor),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          setState(() => _portfolioItems.removeAt(i));
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.55),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close,
                              size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
        const SizedBox(height: 6),
        // Once at least one image is in the list, the button reads
        // "Add more" so it doesn't repeat the section's call-to-action.
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: primaryColor,
            side: BorderSide(color: primaryColor.withOpacity(0.6)),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
          onPressed: _addPortfolioItem,
          icon: const Icon(Icons.add, size: 18),
          label: Text(
            _portfolioItems.isEmpty ? 'Add work sample' : 'Add more',
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),

        const SizedBox(height: 22),

        // ----- Certifications -----
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Certifications',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: onSurface)),
            Text(
              '${_certifications.length} item${_certifications.length == 1 ? '' : 's'}',
              style: TextStyle(fontSize: 12, color: softTextColor),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_certifications.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(_certifications.length, (i) {
              final name = (_certifications[i]['name'] ?? '').toString();
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: inputFill,
                  borderRadius: BorderRadius.circular(40),
                  border: Border.all(color: primaryColor.withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                          fontSize: 13,
                          color: primaryColor,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () {
                        setState(() => _certifications.removeAt(i));
                      },
                      borderRadius: BorderRadius.circular(40),
                      child: Icon(Icons.close,
                          size: 14, color: primaryColor),
                    ),
                  ],
                ),
              );
            }),
          ),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: primaryColor,
            side: BorderSide(color: primaryColor.withOpacity(0.6)),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
          onPressed: _addCertification,
          icon: const Icon(Icons.add, size: 18),
          label: Text(
            _certifications.isEmpty ? 'Add certification' : 'Add more',
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),

        const SizedBox(height: 18),

        // ----- Upload progress (visible only while saving + we have a label) -----
        // Matches the legacy ArtisanKycWidget UX: shows compression then upload
        // phases with a percentage + determinate bar, so the artisan sees the
        // upload is progressing on slow networks rather than staring at a
        // featureless spinner.
        if (_showcaseProgressLabel != null) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _showcaseProgressLabel!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withOpacity(0.75),
                        ),
                      ),
                    ),
                    Text(
                      '${(_showcaseProgress * 100).toInt()}%',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: primaryColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _showcaseProgress,
                    minHeight: 6,
                    backgroundColor:
                        theme.colorScheme.onSurface.withOpacity(0.08),
                    valueColor: AlwaysStoppedAnimation(primaryColor),
                  ),
                ),
              ],
            ),
          ),
        ],

        // ----- Save / Skip -----
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
            onPressed: _savingShowcase ||
                    (_portfolioItems.isEmpty && _certifications.isEmpty)
                ? null
                : _saveShowcase,
            child: _savingShowcase
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
        const SizedBox(height: 4),
        Center(
          child: TextButton(
            onPressed: _skipShowcase,
            child: Text(
              'Skip for now',
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

  // ---- Section 4 UI: Identity Verification ------------------------------

  Widget _buildKycSection(ThemeData theme) {
    final onSurface = theme.colorScheme.onSurface;
    final isDark = theme.brightness == Brightness.dark;
    final infoBg = isDark
        ? Colors.green.withOpacity(0.15)
        : const Color(0xFFE8F5E9);
    final infoBorder = isDark
        ? Colors.green.withOpacity(0.3)
        : const Color(0xFFC8E6C9);
    final infoIconColor =
        isDark ? Colors.green.shade300 : const Color(0xFF2E7D32);
    final infoTextColor =
        isDark ? Colors.green.shade200 : Colors.green.shade900;
    final inputBorder = BorderSide(color: onSurface.withOpacity(0.15));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: infoBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: infoBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: infoIconColor, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Verification usually takes less than 24 hours. Verified artisans get 3x more bookings.',
                  style: TextStyle(
                    fontSize: 12,
                    color: infoTextColor,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text('Document Type',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: onSurface)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: onSurface.withOpacity(0.15)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _documentType,
              dropdownColor: theme.cardColor,
              style: TextStyle(fontSize: 15, color: onSurface),
              iconEnabledColor: onSurface.withOpacity(0.6),
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
        Text('ID Number',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: onSurface)),
        const SizedBox(height: 6),
        TextField(
          controller: _model.ninController,
          focusNode: _model.ninFocus,
          keyboardType: TextInputType.number,
          maxLength: 11,
          style: TextStyle(color: onSurface),
          decoration: InputDecoration(
            counterText: '',
            hintText: 'Enter ID Number',
            hintStyle: TextStyle(color: onSurface.withOpacity(0.5)),
            filled: true,
            fillColor: theme.cardColor,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: inputBorder,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: inputBorder,
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
  // Optional theme-aware text colour. When null we fall back to the
  // ambient onSurface, which keeps the row readable in both light and
  // dark modes.
  final Color? onSurface;

  const _DialogBenefit({
    required this.icon,
    required this.text,
    required this.color,
    this.onSurface,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = onSurface ?? Theme.of(context).colorScheme.onSurface;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13.5,
              color: textColor,
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
