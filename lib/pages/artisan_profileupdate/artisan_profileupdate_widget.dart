import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle, MissingPluginException;
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'dart:math' as math;
import '../../mapbox_config.dart';
import '../../utils/error_messages.dart';
import '../../services/user_service.dart';
import '../../services/token_storage.dart';
import '../../services/artist_service.dart';
import '../../services/job_service.dart';
import 'artisan_profileupdate_model.dart';
export 'artisan_profileupdate_model.dart';

class ArtisanProfileupdateWidget extends StatefulWidget {
  const ArtisanProfileupdateWidget({super.key});

  static String routeName = 'artisanProfileupdate';
  static String routePath = '/artisanProfileupdate';

  @override
  State<ArtisanProfileupdateWidget> createState() =>
      _ArtisanProfileupdateWidgetState();
}

class _ArtisanProfileupdateWidgetState
    extends State<ArtisanProfileupdateWidget> {
  late ArtisanProfileupdateModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();
  final _formKey = GlobalKey<FormState>();
    bool _isSaving = false;
    bool _hasArtisanProfile = false;
    // Accumulate step values here so data travels from step to step until final submit
    final Map<String, dynamic> _formData = {};
    // Keep only remote portfolio metadata (no local file uploads handled here)
    List<Map<String, dynamic>> _remotePortfolioItems = [];
  // Local state for LGA/state lists and geocoding
  Map<String, List<String>> _statesLgas = {};
  List<String> _statesList = [];
  List<String> _lgasForSelectedState = [];
  String? _selectedState;
  String? _selectedLga;
  double? _serviceLat;
  double? _serviceLon;
  bool _isGeocoding = false;
  // Multi-step state (now 3 steps: professional, pricing, portfolio)
  int _currentStep = 0;
  List<String> _stepTitles = const ['Professional Details', 'Pricing & Availability', 'Portfolio'];
  String? _error;

  // Convenience getter for last step index
  int get _lastStepIndex => _stepTitles.length - 1;
  bool get _atLastStep => _currentStep == _lastStepIndex;

  // Availability structured entries
  List<String> _availabilityList = [];
  String _selectedDay = 'Monday';
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

    // Local picked images for portfolio (simple file picker)
    List<String> _localPortfolioImagePaths = [];
    // Job categories for service dropdown
    List<Map<String, dynamic>> _jobCategories = [];
    String? _selectedCategoryId;
    String? _selectedCategoryName; // cached name for saving when categories not present
    // Track whether file picker is available on this platform
    bool _filePickerAvailable = true;

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => ArtisanProfileupdateModel());

    // Only initialize controllers that the API accepts for update
    _model.fullNameController ??= TextEditingController();
    _model.fullNameFocusNode ??= FocusNode();

    _model.emailController ??= TextEditingController();
    _model.emailFocusNode ??= FocusNode();

    _model.phoneController ??= TextEditingController();
    _model.phoneFocusNode ??= FocusNode();

    _model.passwordController ??= TextEditingController();
    _model.passwordFocusNode ??= FocusNode();

    // Initialize artisan-specific controllers
    _model.tradeController ??= TextEditingController();
    _model.tradeFocusNode ??= FocusNode();

    _model.experienceController ??= TextEditingController();
    _model.experienceFocusNode ??= FocusNode();

    _model.certificationsController ??= TextEditingController();
    _model.certificationsFocusNode ??= FocusNode();

    _model.bioController ??= TextEditingController();
    _model.bioFocusNode ??= FocusNode();

    _model.pricingPerHourController ??= TextEditingController();
    _model.pricingPerHourFocusNode ??= FocusNode();

    _model.pricingPerJobController ??= TextEditingController();
    _model.pricingPerJobFocusNode ??= FocusNode();

    _model.availabilityController ??= TextEditingController();
    _model.availabilityFocusNode ??= FocusNode();

    _model.serviceAreaAddressController ??= TextEditingController();
    _model.serviceAreaAddressFocusNode ??= FocusNode();

    _model.serviceAreaRadiusController ??= TextEditingController();
    _model.serviceAreaRadiusFocusNode ??= FocusNode();

    // Attempt to prefill from backend profile after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadProfileData();
      _loadStatesLgas();
      _fetchJobCategories();
    });
  }

  // Helper to display a friendly error to the user and set the _error state
  void _showUserError(dynamic error, {String? fallback}) {
    final msg = ErrorMessages.humanize(error ?? fallback ?? 'Something went wrong. Please try again.');
    if (mounted) {
      setState(() => _error = msg);
      try {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      } catch (_) {
        // ignore any scaffold messenger errors during build
      }
    }
  }

  // Availability helpers (moved here so analyzer finds them before use)
  String _formatAvailabilityEntry(String day, TimeOfDay start, TimeOfDay end) {
    String fmt(TimeOfDay t) => t.hour.toString().padLeft(2,'0') + ':' + t.minute.toString().padLeft(2,'0');
    return '$day ${fmt(start)}-${fmt(end)}';
  }

  Future<void> _pickTimeRange() async {
    final s = await showTimePicker(context: context, initialTime: _startTime ?? const TimeOfDay(hour:9,minute:0));
    if (s == null) return;
    final e = await showTimePicker(context: context, initialTime: _endTime ?? const TimeOfDay(hour:17,minute:0));
    if (e == null) return;
    setState(() { _startTime = s; _endTime = e; });
  }

  void _addAvailability() {
    if (_startTime == null || _endTime == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please pick a start and end time')));
      return;
    }
    final entry = _formatAvailabilityEntry(_selectedDay, _startTime!, _endTime!);
    if (!_availabilityList.contains(entry)) {
      setState(() {
        _availabilityList.add(entry);
        _model.availabilityController?.text = _availabilityList.join(',');
      });
    }
  }

  void _removeAvailability(String entry) {
    setState(() {
      _availabilityList.remove(entry);
      _model.availabilityController?.text = _availabilityList.join(',');
    });
  }

  Future<void> _loadStatesLgas() async {
    try {
      final s = await rootBundle.loadString('assets/jsons/nigeria_states_lgas.json');
      final decoded = jsonDecode(s) as Map<String, dynamic>;
      final map = <String, List<String>>{};
      for (final e in decoded.entries) {
        final key = e.key.toString();
        final v = e.value;
        if (v is List) {
          map[key] = List<String>.from(v.map((i) => i.toString()));
        }
      }
      setState(() {
        _statesLgas = map;
        _statesList = map.keys.toList()..sort();
      });
      // If profile already filled serviceArea address was loaded earlier, try to pre-select matching state/LGA
      if ((_model.serviceAreaAddressController?.text ?? '').isNotEmpty) {
        final addr = _model.serviceAreaAddressController!.text.toLowerCase();
        String? foundState;
        String? foundLga;
        for (final entry in map.entries) {
          final stateKey = entry.key.toLowerCase();
          if (addr.contains(stateKey) || stateKey.contains(addr)) {
            foundState = entry.key;
            break;
          }
        }
        if (foundState == null) {
          // try fuzzy match by checking any state name contained in address
          for (final k in map.keys) {
            if (addr.contains(k.toLowerCase())) { foundState = k; break; }
          }
        }
        if (foundState != null) {
          final lg = map[foundState] ?? [];
          for (final l in lg) {
            if (addr.contains(l.toLowerCase())) { foundLga = l; break; }
          }
        }
        if (mounted) setState(() { _selectedState = foundState; _lgasForSelectedState = _statesLgas[foundState] ?? []; _selectedLga = foundLga; });
      }
    } catch (e) {
      if (mounted && kDebugMode) debugPrint('Failed to load states/lgas json: $e');
      // Show a friendly message but keep app usable
      _showUserError('Could not load location data. Some address helpers may be unavailable.');
    }
  }

  Future<void> _geocodeAddress(String address) async {
    if (address.trim().isEmpty) return;
    setState(() { _isGeocoding = true; _serviceLat = null; _serviceLon = null; });
    try {
      final q = Uri.encodeComponent(address);
      final url = Uri.parse('https://api.mapbox.com/geocoding/v5/mapbox.places/$q.json?limit=1&access_token=$MAPBOX_ACCESS_TOKEN');
      final resp = await http.get(url).timeout(const Duration(seconds: 12));
      if (resp.statusCode == 200 && resp.body.isNotEmpty) {
        final body = jsonDecode(resp.body);
        if (body is Map && body['features'] is List && (body['features'] as List).isNotEmpty) {
          final feat = (body['features'] as List).first;
          if (feat is Map && feat['center'] is List) {
            final center = List.from(feat['center']);
            if (center.length >= 2) {
              final lon = (center[0] is num) ? center[0].toDouble() : double.tryParse(center[0].toString());
              final lat = (center[1] is num) ? center[1].toDouble() : double.tryParse(center[1].toString());
              setState(() { _serviceLat = lat; _serviceLon = lon; });
            }
          }
        }
      } else {
        if (mounted && kDebugMode) debugPrint('Geocode failed (${resp.statusCode}): ${resp.body}');
        // Present a short, friendly message to the user
        _showUserError('Could not look up the address. Please check it and try again.');
      }
    } catch (e) {
      if (mounted && kDebugMode) debugPrint('Geocode error: $e');
      _showUserError('Location lookup failed. Please check your connection and try again.');
    } finally {
      if (mounted) setState(() => _isGeocoding = false);
    }
  }

  // Load profile data from backend and prefill fields
  Future<void> _loadProfileData() async {
    try {
      // Prefer explicit artisan profile check so we can change UI between create/edit
      Map<String, dynamic>? profile = await ArtistService.getMyProfile();
      _hasArtisanProfile = profile != null;
      if (profile == null) profile = await UserService.getProfile();
      if (profile == null) return;

      final p = profile;
      setState(() {
        // profile image
        try {
          final img = p['profileImage'];
          if (img is Map && img['url'] != null) {
            _formData['profileImage'] = img['url'].toString();
          } else if (p['profileImage'] is String && p['profileImage'].toString().startsWith('http')) {
            _formData['profileImage'] = p['profileImage'] as String;
          }
        } catch (_) {}

        // identity fields
        if ((_model.fullNameController?.text ?? '').isEmpty) _model.fullNameController?.text = (p['name'] ?? p['fullName'] ?? p['username'] ?? '').toString();
        if ((_model.emailController?.text ?? '').isEmpty) _model.emailController?.text = (p['email'] ?? '').toString();
        if ((_model.phoneController?.text ?? '').isEmpty) _model.phoneController?.text = (p['phone'] ?? p['telephone'] ?? '').toString();

        // trades/service prefill and category matching
        try {
          if ((_model.tradeController?.text ?? '').isEmpty) {
            if (p['trade'] is List) _model.tradeController?.text = (p['trade'] as List).map((e) => e.toString()).join(',');
            else if (p['trade'] is String) _model.tradeController?.text = p['trade'];
          }

          final preText = (_model.tradeController?.text ?? '').trim();
          if (preText.isNotEmpty && _jobCategories.isNotEmpty) {
            final first = preText.split(',').map((s) => s.trim()).firstWhere((s) => s.isNotEmpty, orElse: () => '');
            if (first.isNotEmpty) {
              final match = _jobCategories.firstWhere((c) {
                final name = (c['name'] ?? c['title'] ?? '').toString().toLowerCase();
                return name == first.toLowerCase();
              }, orElse: () => {});
              if (match is Map && ((match['_id'] ?? match['id'] ?? '')?.toString() ?? '').isNotEmpty) {
                _selectedCategoryId = (match['_id'] ?? match['id']).toString();
                _selectedCategoryName = (match['name'] ?? match['title']).toString();
                _model.tradeController?.text = _selectedCategoryName ?? '';
              }
            }
          }
        } catch (e) {
          if (mounted && kDebugMode) debugPrint('artisan prefill error: $e');
        }

        // other simple prefills
        try {
          if ((_model.experienceController?.text ?? '').isEmpty) _model.experienceController?.text = (p['experience'] ?? '').toString();
          if ((_model.certificationsController?.text ?? '').isEmpty) _model.certificationsController?.text = (p['certifications'] is List ? (p['certifications'] as List).map((e)=>e.toString()).join(',') : (p['certifications'] ?? '').toString());
          if ((_model.bioController?.text ?? '').isEmpty) _model.bioController?.text = (p['bio'] ?? '').toString();
          if ((_model.pricingPerHourController?.text ?? '').isEmpty) _model.pricingPerHourController?.text = (p['pricing']?['perHour'] ?? '').toString();
          if ((_model.pricingPerJobController?.text ?? '').isEmpty) _model.pricingPerJobController?.text = (p['pricing']?['perJob'] ?? '').toString();
          if ((_model.availabilityController?.text ?? '').isEmpty && p['availability'] is List) _model.availabilityController?.text = (p['availability'] as List).map((e)=>e.toString()).join(',');
          if ((_model.serviceAreaAddressController?.text ?? '').isEmpty) _model.serviceAreaAddressController?.text = (p['serviceArea']?['address'] ?? '').toString();
          if ((_model.serviceAreaRadiusController?.text ?? '').isEmpty) _model.serviceAreaRadiusController?.text = (p['serviceArea']?['radius'] ?? '').toString();
        } catch (e) {
          if (mounted && kDebugMode) debugPrint('artisan prefill error: $e');
        }
      });

      try {
        final sa = p['serviceArea'];
        if (sa is Map) {
          final lat = sa['lat'] ?? sa['latitude'] ?? sa['center']?['lat'];
          final lon = sa['lon'] ?? sa['longitude'] ?? sa['center']?['lon'];
          if (lat != null && lon != null) {
            _serviceLat = (lat is num) ? lat.toDouble() : double.tryParse(lat.toString());
            _serviceLon = (lon is num) ? lon.toDouble() : double.tryParse(lon.toString());
          }
        }
      } catch (_) {}

      // Load remote portfolio items if any
      try {
        final rawPortfolio = p['portfolio'];
        if (rawPortfolio is List && rawPortfolio.isNotEmpty) {
          final items = <Map<String,dynamic>>[];
          for (final it in rawPortfolio) {
            if (it is Map) {
              final title = it['title']?.toString();
              final desc = it['description']?.toString();
              final images = <Map<String,String>>[];
              if (it['images'] is List) {
                for (final im in (it['images'] as List)) {
                  if (im is Map) {
                    final url = (im['url'] ?? im['src'] ?? '').toString();
                    final pid = (im['public_id'] ?? im['publicId'] ?? '').toString();
                    if (url.isNotEmpty) images.add({'url': url, 'public_id': pid});
                  } else if (im is String) {
                    images.add({'url': im, 'public_id': ''});
                  }
                }
              }
              items.add({'title': title, 'description': desc, 'images': images});
            }
          }
          _remotePortfolioItems = items;
        }
      } catch (e) {
        if (mounted && kDebugMode) debugPrint('Failed to parse portfolio: $e');
      }
    } catch (e) {
      if (mounted && kDebugMode) debugPrint('Prefill profile failed: $e');
    }
  }

  // Remove local file/photo pickers & compression: simplified flow will only handle JSON payloads.

  // Remove local portfolio helper functions and compression routines.

  // Remove local portfolio removal; keep remote image removal helper.
  void _removeRemoteImage(int itemIndex, int imageIndex) {
    setState(() {
      if (itemIndex >= 0 && itemIndex < _remotePortfolioItems.length) {
        final imgs = (_remotePortfolioItems[itemIndex]['images'] is List)
            ? List<Map<String, dynamic>>.from(_remotePortfolioItems[itemIndex]['images'])
            : <Map<String,dynamic>>[];
        if (imageIndex >= 0 && imageIndex < imgs.length) {
          imgs.removeAt(imageIndex);
          _remotePortfolioItems[itemIndex]['images'] = imgs;
        }
        // If an item has no images and no title/description, consider removing the item entirely
        final title = _remotePortfolioItems[itemIndex]['title'];
        final desc = _remotePortfolioItems[itemIndex]['description'];
        final remaining = (_remotePortfolioItems[itemIndex]['images'] is List) ? (_remotePortfolioItems[itemIndex]['images'] as List).length : 0;
        if ((title == null || title.toString().trim().isEmpty) && (desc == null || desc.toString().trim().isEmpty) && remaining == 0) {
          _remotePortfolioItems.removeAt(itemIndex);
        }
      }
    });
  }

  // Save profile: collects fields and calls UserService.updateProfile
  Future<void> _saveProfile() async {
     setState(() {
       _isSaving = true;
       _error = null;
     });

     try {
       // Build artisan payload from accumulated _formData (primary source), merge missing controller values
       final payload = Map<String, dynamic>.from(_formData);
      // Prepare holder for server response; declared early so multipart branch can assign to it.
      Map<String, dynamic>? updated;
       // Top-level identity fields (controllers override only if set on controllers)
       if ((_model.fullNameController?.text ?? '').isNotEmpty) payload['name'] = _model.fullNameController!.text.trim();
       if ((_model.emailController?.text ?? '').isNotEmpty) payload['email'] = _model.emailController!.text.trim();
       if ((_model.phoneController?.text ?? '').isNotEmpty) payload['phone'] = _model.phoneController!.text.trim();
       if ((_model.passwordController?.text ?? '').isNotEmpty) payload['password'] = _model.passwordController!.text.trim();

       // Ensure artisan-specific fields are present (fall back to controllers if needed)
       // Handle trade: prefer selected category id/name mapping when available
       if (payload['trade'] == null || (payload['trade'] is List && (payload['trade'] as List).isEmpty)) {
         if (_selectedCategoryId != null && _selectedCategoryId!.isNotEmpty) {
           // send the selected category name as the trade array so backend remains compatible
           final name = _selectedCategoryName ?? _jobCategories.firstWhere((c) => (c['_id'] ?? c['id'])?.toString() == _selectedCategoryId, orElse: () => {})['name']?.toString() ?? '';
           if (name.isNotEmpty) payload['trade'] = [name];
         } else if ((_model.tradeController?.text ?? '').isNotEmpty) {
           payload['trade'] = _model.tradeController!.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
         }
       }
       if (payload['experience'] == null) {
         if ((_model.experienceController?.text ?? '').isNotEmpty) {
           final v = num.tryParse(_model.experienceController!.text.trim());
           if (v != null) payload['experience'] = v;
         }
       }
       if (payload['certifications'] == null || (payload['certifications'] is List && (payload['certifications'] as List).isEmpty)) {
         if ((_model.certificationsController?.text ?? '').isNotEmpty) {
           payload['certifications'] = _model.certificationsController!.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
         }
       }
       if (payload['bio'] == null || (payload['bio'] is String && (payload['bio'] as String).isEmpty)) {
         if ((_model.bioController?.text ?? '').isNotEmpty) payload['bio'] = _model.bioController!.text.trim();
       }

       // Pricing
       if (payload['pricing'] == null) payload['pricing'] = {};
       final phFromData = payload['pricing']?['perHour'];
       final pjFromData = payload['pricing']?['perJob'];
       final perHour = phFromData ?? num.tryParse((_model.pricingPerHourController?.text ?? '').trim());
       final perJob = pjFromData ?? num.tryParse((_model.pricingPerJobController?.text ?? '').trim());
       if (perHour != null) payload['pricing']['perHour'] = perHour;
       if (perJob != null) payload['pricing']['perJob'] = perJob;

       // Availability
       // Availability: ensure we always send an array of strings when available.
       // Priority: existing payload -> in-memory _availabilityList -> availabilityController text
       List<String> availability = [];
       try {
         if (payload['availability'] is List) {
           availability = List<String>.from((payload['availability'] as List).map((e) => e.toString()).where((s) => s.isNotEmpty));
         }
       } catch (_) {}

       if (availability.isEmpty) {
         if (_availabilityList.isNotEmpty) {
           availability = List<String>.from(_availabilityList);
         } else if ((_model.availabilityController?.text ?? '').isNotEmpty) {
           availability = (_model.availabilityController!.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList());
         }
       }

       if (availability.isNotEmpty) payload['availability'] = availability;

       // Service area
       if (payload['serviceArea'] == null) payload['serviceArea'] = {};
       if ((payload['serviceArea']?['address'] ?? '').toString().isEmpty && (_model.serviceAreaAddressController?.text ?? '').isNotEmpty) payload['serviceArea']['address'] = _model.serviceAreaAddressController!.text.trim();
       if ((payload['serviceArea']?['radius'] ?? '').toString().isEmpty) {
         final r = num.tryParse((_model.serviceAreaRadiusController?.text ?? '').trim());
         if (r != null) payload['serviceArea']['radius'] = r;
       }
       if (payload['serviceArea']?['coordinates'] == null && _serviceLon != null && _serviceLat != null) {
         payload['serviceArea']['coordinates'] = [_serviceLon, _serviceLat];
       }

      // Validate minimal required fields (name, email, phone still required)
      // Per API docs: artisan profile requires trade and experience. Identity fields
      // (name/email/phone) are managed by the auth/user profile and are optional
      // here. Do not enforce them for create/update so partial updates are allowed.

      // Stricter validation for create flow: ensure trade and experience present and numeric
      if (!_hasArtisanProfile) {
        if (payload['trade'] == null || (payload['trade'] is List && (payload['trade'] as List).isEmpty)) {
          throw Exception('Please provide at least one trade (e.g., Plumber)');
        }
        final expText = (_model.experienceController?.text ?? '').trim();
        if (expText.isEmpty) throw Exception('Experience (years) is required');
        final expNum = num.tryParse(expText);
        if (expNum == null) throw Exception('Experience must be a number (years)');
        payload['experience'] = expNum;
      }

      // Pricing validation: if user entered pricing ensure numeric
      final perHourText = (_model.pricingPerHourController?.text ?? '').trim();
      final perJobText = (_model.pricingPerJobController?.text ?? '').trim();
      if (perHourText.isNotEmpty && num.tryParse(perHourText) == null) throw Exception('Per hour pricing must be a number');
      if (perJobText.isNotEmpty && num.tryParse(perJobText) == null) throw Exception('Per job pricing must be a number');

      // Attach remote portfolio metadata (reflect deletions or changed titles) so server can persist
      if (_remotePortfolioItems.isNotEmpty) {
        // Convert remote items to the JSON shape expected by the API: title, description, images:list<string>, beforeAfter:bool
        payload['portfolio'] = _remotePortfolioItems.map((it) {
          final images = <String>[];
          if (it['images'] is List) {
            for (final im in it['images']) {
              if (im is Map) {
                final url = im['url']?.toString() ?? '';
                if (url.isNotEmpty) images.add(url);
              } else if (im is String) {
                if (im.isNotEmpty) images.add(im);
              }
            }
          }
          return {
            'title': it['title']?.toString(),
            'description': it['description']?.toString(),
            'images': images,
            'beforeAfter': (it['beforeAfter'] is bool) ? it['beforeAfter'] : false,
          };
        }).toList();
      }

      // If the user selected local images in this session, instead of attempting
      // to call backend signing endpoints (which may not exist), encode files
      // as base64 data URIs and include them directly in the JSON payload as
      // an additional portfolio item. This avoids multipart/signature flows
      // and keeps the request JSON-only as required by the server.
      if (_localPortfolioImagePaths.isNotEmpty) {
        final localPaths = List<String>.from(_localPortfolioImagePaths);
        // Build numbered field names: portfolioImage1, portfolioImage2, ...
        final fileMap = <String, List<String>>{};
        for (var i = 0; i < localPaths.length; i++) {
          fileMap['portfolioImage${i + 1}'] = [localPaths[i]];
        }
        bool sent = false;
        try {
          if (kDebugMode) debugPrint('Attempting multipart profile update with fileMap keys=${fileMap.keys.toList()}');
          if (_hasArtisanProfile) {
            updated = await ArtistService.updateMyProfile(payload, fileMap: fileMap);
          } else {
            updated = await ArtistService.createMyProfile(payload, fileMap: fileMap);
          }
          sent = updated != null;
        } catch (e) {
          if (kDebugMode) debugPrint('Multipart profile update failed: $e');
          sent = false;
        }

        if (!sent) {
          // Fallback: upload via attachments/direct Cloudinary and include returned URLs in payload
          try {
            if (kDebugMode) debugPrint('Falling back to attachments/direct upload for ${localPaths.length} files...');
            final uploaded = await ArtistService.uploadFilesToAttachments(localPaths);
            if (kDebugMode) debugPrint('Profile update: uploaded results -> $uploaded');
            final uploadedUrls = <String>[];
            for (final u in uploaded) {
              final url = (u['url'] ?? '').toString();
              if (url.isNotEmpty) uploadedUrls.add(url);
            }
            if (uploadedUrls.isNotEmpty) {
              payload['portfolio'] = (payload['portfolio'] is List) ? List.from(payload['portfolio']) : [];
              payload['portfolio'].add({
                'title': 'Mobile Uploads',
                'description': null,
                'images': uploadedUrls,
                'beforeAfter': false,
              });
            }
          } catch (e) {
            if (kDebugMode) debugPrint('Profile update: uploadFilesToAttachments failed: $e');
          }
        }
      }

       // Remove any transient local file reference from payload — we always send JSON with URLs
       payload.remove('localPortfolioFiles');

      // If multipart/fallback already returned a response (updated != null),
      // skip the JSON-only request. Otherwise send the JSON payload now.
      if (updated == null) {
        if (_hasArtisanProfile) {
          updated = await ArtistService.updateMyProfile(payload);
        } else {
          updated = await ArtistService.createMyProfile(payload);
        }
      } else {
        if (kDebugMode) debugPrint('Skip JSON create/update because multipart path already returned a response');
      }

      if (updated == null) throw Exception(!_hasArtisanProfile ? 'Profile creation failed' : 'Profile update failed');

      try {
        if (updated['role'] != null) await TokenStorage.saveRole(updated['role'].toString());
      } catch (_) {}

      if (mounted) {
        final msg = !_hasArtisanProfile ? 'Profile created successfully' : 'Profile updated successfully';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(msg)),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
        // If we just created the profile, mark that we now have one so future saves will update
        if (!_hasArtisanProfile) setState(() => _hasArtisanProfile = true);
        Navigator.of(context).maybePop(true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = ErrorMessages.humanize(e));
    } finally {
      if (mounted) setState(() {
        _isSaving = false;
      });
    }
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  Widget _buildStepIndicator() {
     final theme = Theme.of(context);
     final Color primaryColor = const Color(0xFFA20025);

     return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.onSurface.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // Step titles
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(_stepTitles.length, (index) {
              final isActive = index == _currentStep;
              final isCompleted = index < _currentStep;

              // Make each step column flexible so titles don't overflow the row.
              return Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isActive || isCompleted
                            ? primaryColor
                            : theme.colorScheme.surface,
                        border: Border.all(
                          color: isActive
                              ? primaryColor
                              : theme.colorScheme.onSurface.withOpacity(0.1),
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: isCompleted
                            ? const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 20,
                              )
                            : Text(
                                (index + 1).toString(),
                                style: TextStyle(
                                  color: isActive
                                      ? Colors.white
                                      : theme.colorScheme.onSurface.withOpacity(0.5),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 96),
                      child: Text(
                        _stepTitles[index],
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                          color: isActive || isCompleted
                              ? primaryColor
                              : theme.colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildStepContent() {
    // Return the active step directly inside a keyed container. Avoid using
    // AnimatedSwitcher here because its layout transition can cause semantics
    // and layout assertions when the child subtree is complex (forms, inputs,
    // scrolling). The outer layout provides horizontal padding already.
    return Container(
      key: ValueKey<int>(_currentStep),
      child: _getCurrentStepWidget(),
    );
  }

  Widget _getCurrentStepWidget() {
    switch (_currentStep) {
      case 0:
        return _buildStep1();
      case 1:
        return _buildStep2();
      case 2:
        return _buildStep3();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildStep1() {
    final theme = Theme.of(context);
    final Color primaryColor = const Color(0xFFA20025);

    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Text(
            'Professional Details',
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            'Tell us about your trade and experience',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.6)),
          ),
          const SizedBox(height: 24),

          // Service (select from known job categories when available; fallback to free-text)
          Text('SERVICE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: theme.colorScheme.onSurface.withOpacity(0.6))),
          const SizedBox(height: 8),
          if (_jobCategories.isNotEmpty) ...[
            DropdownButtonFormField<String>(
              value: _selectedCategoryId,
              isExpanded: true,
              isDense: true,
              iconSize: 20,
              items: _jobCategories.map((c) {
                final id = (c['_id'] ?? c['id'] ?? '').toString();
                final name = (c['name'] ?? c['title'] ?? '').toString();
                return DropdownMenuItem(
                  value: id,
                  child: Text(name, overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: (v) {
                final sel = _jobCategories.firstWhere((c) {
                  final id = (c['_id'] ?? c['id'] ?? '').toString();
                  return id == (v ?? '');
                }, orElse: () => {});
                setState(() {
                  _selectedCategoryId = (sel['_id'] ?? sel['id']).toString();
                  _selectedCategoryName = (sel['name'] ?? sel['title']).toString();
                  // keep controller text in sync for review/fallback
                  _model.tradeController?.text = _selectedCategoryName ?? '';
                });
              },
              decoration: InputDecoration(
                hintText: 'Select your service',
                filled: true,
                fillColor: theme.brightness == Brightness.dark ? Colors.grey[900] : Colors.grey[50],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: primaryColor, width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              validator: (v) {
                if ((v == null || v.trim().isEmpty) && (_model.tradeController?.text?.trim().isEmpty ?? true)) return 'Please select your service';
                return null;
              },
            ),
          ] else ...[
            TextFormField(
              controller: _model.tradeController,
              focusNode: _model.tradeFocusNode,
              decoration: InputDecoration(
                hintText: 'e.g. plumber, electrician',
                filled: true,
                fillColor: theme.brightness == Brightness.dark ? Colors.grey[900] : Colors.grey[50],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: primaryColor, width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              textInputAction: TextInputAction.next,
              cursorColor: primaryColor,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'At least one service is required' : null,
            ),
          ],

          const SizedBox(height: 16),

          // Experience
          Text('EXPERIENCE (years)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: theme.colorScheme.onSurface.withOpacity(0.6))),
          const SizedBox(height: 8),
          TextFormField(
            controller: _model.experienceController,
            focusNode: _model.experienceFocusNode,
            decoration: InputDecoration(
              hintText: 'e.g. 3',
              filled: true,
              fillColor: theme.brightness == Brightness.dark ? Colors.grey[900] : Colors.grey[50],
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: primaryColor, width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            keyboardType: TextInputType.number,
            cursorColor: primaryColor,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Experience is required';
              if (num.tryParse(v.trim()) == null) return 'Enter a valid number';
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Certifications
          Text('CERTIFICATIONS (comma separated)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: theme.colorScheme.onSurface.withOpacity(0.6))),
          const SizedBox(height: 8),
          TextFormField(
            controller: _model.certificationsController,
            focusNode: _model.certificationsFocusNode,
            decoration: InputDecoration(hintText: 'e.g. NCCER, OSHA', filled: true, fillColor: theme.brightness == Brightness.dark ? Colors.grey[900] : Colors.grey[50], border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: primaryColor, width: 1.5)), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
            cursorColor: primaryColor,
          ),
          const SizedBox(height: 16),

          // Bio
          Text('BIO', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: theme.colorScheme.onSurface.withOpacity(0.6))),
          const SizedBox(height: 8),
          TextFormField(
            controller: _model.bioController,
            focusNode: _model.bioFocusNode,
            maxLines: 4,
            decoration: InputDecoration(hintText: 'Short description of your services', filled: true, fillColor: theme.brightness == Brightness.dark ? Colors.grey[900] : Colors.grey[50], border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: primaryColor, width: 1.5)), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
            cursorColor: primaryColor,
          ),
          const SizedBox(height: 24),
        ],
      );
  }

  Widget _buildStep2() {
    final theme = Theme.of(context);
    final Color primaryColor = const Color(0xFFA20025);

    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Text('Pricing & Availability', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Text(
            'Set your pricing structure and availability',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.6)),
          ),
          const SizedBox(height: 24),

          // Pricing per hour
          Text('PRICING - PER HOUR', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: theme.colorScheme.onSurface.withOpacity(0.6))),
          const SizedBox(height: 8),
          TextFormField(
            controller: _model.pricingPerHourController,
            focusNode: _model.pricingPerHourFocusNode,
            decoration: InputDecoration(hintText: 'Amount', filled: true, fillColor: theme.brightness == Brightness.dark ? Colors.grey[900] : Colors.grey[50], border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: primaryColor, width: 1.5)), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            cursorColor: primaryColor,
          ),
          const SizedBox(height: 16),

          // Pricing per job
          Text('PRICING - PER JOB', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: theme.colorScheme.onSurface.withOpacity(0.6))),
          const SizedBox(height: 8),
          TextFormField(
            controller: _model.pricingPerJobController,
            focusNode: _model.pricingPerJobFocusNode,
            decoration: InputDecoration(hintText: 'Amount', filled: true, fillColor: theme.brightness == Brightness.dark ? Colors.grey[900] : Colors.grey[50], border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: primaryColor, width: 1.5)), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            cursorColor: primaryColor,
          ),
          const SizedBox(height: 16),

          // Availability
          Text('AVAILABILITY (choose day & time)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: theme.colorScheme.onSurface.withOpacity(0.6))),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedDay,
                  isExpanded: true,
                  isDense: true,
                  iconSize: 20,
                  items: ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday']
                      .map((d) => DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedDay = v ?? _selectedDay),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: theme.brightness==Brightness.dark?Colors.grey[900]:Colors.grey[50],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                fit: FlexFit.loose,
                child: OutlinedButton(
                  onPressed: _pickTimeRange,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(_startTime == null || _endTime == null ? 'Pick time' : '${_startTime!.format(context)} - ${_endTime!.format(context)}', overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                fit: FlexFit.loose,
                child: ElevatedButton(
                  onPressed: _addAvailability,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: const Text('Add'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // show chips
          if (_availabilityList.isNotEmpty) Wrap(
            spacing: 8,
            children: _availabilityList.map((a) => Chip(
              label: Text(a),
              onDeleted: () => _removeAvailability(a),
            )).toList(),
          ),
          const SizedBox(height: 8),
           // Service area
          Text('SERVICE AREA - State & LGA', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: theme.colorScheme.onSurface.withOpacity(0.6))),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedState,
                  isExpanded: true,
                  isDense: true,
                  iconSize: 20,
                  items: _statesList.map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) {
                    setState(() {
                      _selectedState = v;
                      _lgasForSelectedState = v != null ? (_statesLgas[v] ?? []) : [];
                      _selectedLga = null;
                      // clear auto-filled address until LGA is chosen
                      _model.serviceAreaAddressController?.text = '';
                      _serviceLat = null; _serviceLon = null;
                    });
                  },
                  decoration: InputDecoration(hintText: 'Select state', filled: true, fillColor: theme.brightness==Brightness.dark?Colors.grey[900]:Colors.grey[50], border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedLga,
                  isExpanded: true,
                  isDense: true,
                  items: _lgasForSelectedState.map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (_lgasForSelectedState.isEmpty) ? null : (v) async {
                    setState(() {
                      _selectedLga = v;
                    });
                    if (v != null && _selectedState != null) {
                      final addr = '$v, ${_selectedState!}, Nigeria';
                      _model.serviceAreaAddressController?.text = addr;
                      await _geocodeAddress(addr);
                    }
                  },
                  disabledHint: const Text('Choose state first'),
                  decoration: InputDecoration(hintText: 'LGA', filled: true, fillColor: theme.brightness==Brightness.dark?Colors.grey[900]:Colors.grey[50], border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('SERVICE AREA - ADDRESS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: theme.colorScheme.onSurface.withOpacity(0.6))),
          const SizedBox(height: 8),
          TextFormField(controller: _model.serviceAreaAddressController, focusNode: _model.serviceAreaAddressFocusNode, decoration: InputDecoration(hintText: 'Address (auto-filled from LGA)', filled: true, fillColor: theme.brightness == Brightness.dark ? Colors.grey[900] : Colors.grey[50], border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: primaryColor, width: 1.5)), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)), cursorColor: primaryColor),
          const SizedBox(height: 8),
          // Keep coordinates in the widget tree but hide them from the UI so they remain available
          // programmatically (e.g., for form submission or geocoding) without showing to users.
          Offstage(
            offstage: true,
            child: Column(
              children: [
                // These Text widgets are intentionally offstage. Do not remove if you rely on
                // widget-based value extraction elsewhere; keeping them preserves state.
                Text('Longitude: ${_serviceLon?.toStringAsFixed(6) ?? "-"}'),
                const SizedBox(height: 4),
                Text('Latitude: ${_serviceLat?.toStringAsFixed(6) ?? "-"}'),
              ],
            ),
          ),
          if (_isGeocoding) const Padding(padding: EdgeInsets.only(top:8), child: LinearProgressIndicator()),
          const SizedBox(height: 12),
          Text('SERVICE AREA - RADIUS (km)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: theme.colorScheme.onSurface.withOpacity(0.6))),
          const SizedBox(height: 8),
          TextFormField(controller: _model.serviceAreaRadiusController, focusNode: _model.serviceAreaRadiusFocusNode, decoration: InputDecoration(hintText: 'Radius in km', filled: true, fillColor: theme.brightness == Brightness.dark ? Colors.grey[900] : Colors.grey[50], border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: primaryColor, width: 1.5)), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)), keyboardType: TextInputType.number, cursorColor: primaryColor),
          const SizedBox(height: 24),
        ],
      );
  }

  // Step 3: Portfolio - simplified to only show remote items or an empty state
  Widget _buildStep3() {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text('Portfolio', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Text('A portfolio helps customers see your past work.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.6))),
        const SizedBox(height: 16),

        if (_remotePortfolioItems.isNotEmpty) ...[
          const Text('Existing portfolio'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < _remotePortfolioItems.length; i++)
              for (var j = 0; j < ((_remotePortfolioItems[i]['images'] is List) ? (_remotePortfolioItems[i]['images'] as List).length : 0); j++)
                Builder(builder: (context) {
                  final img = (_remotePortfolioItems[i]['images'] as List)[j];
                  final url = (img is Map) ? (img['url']?.toString() ?? '') : img?.toString() ?? '';
                  return Stack(
                    children: [
                      ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(url, width: 96, height: 96, fit: BoxFit.cover, errorBuilder: (c,_,__) => Container(width:96,height:96,color:Colors.grey))),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: InkWell(
                          onTap: () => _removeRemoteImage(i, j),
                          child: Container(
                            decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), shape: BoxShape.circle),
                            padding: const EdgeInsets.all(4),
                            child: const Icon(Icons.close, size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  );
                }),
          ]),
          const SizedBox(height: 16),
        ] else ...[
          // Removed the large "No portfolio yet" card as requested. Keep minimal spacing instead.
          const SizedBox(height: 8),
        ],

        // Local image picker UI
        if (_localPortfolioImagePaths.isNotEmpty) ...[
          const Text('Selected images'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < _localPortfolioImagePaths.length; i++)
              Stack(
                children: [
                  ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(_localPortfolioImagePaths[i]), width: 96, height: 96, fit: BoxFit.cover, errorBuilder: (c,_,__) => Container(width:96,height:96,color:Colors.grey))),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: InkWell(
                      onTap: () => _removeLocalImage(i),
                      child: Container(
                        decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), shape: BoxShape.circle),
                        padding: const EdgeInsets.all(4),
                        child: const Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
          ]),
          const SizedBox(height: 12),
        ],

         // Picker button
         Row(
           children: [
             Expanded(
               child: OutlinedButton.icon(
                onPressed: _filePickerAvailable ? _pickPortfolioImages : null,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(_filePickerAvailable ? 'Pick images' : 'Picker unavailable'),
               ),
             ),
           ],
         ),
        if (!_filePickerAvailable)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text('File picker is not available on this platform. Restart the app after installing native plugins.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.6))),
          ),
         const SizedBox(height: 12),
       ],
     );
      }

    bool _validateCurrentStep() {
    // Use Form validators when available, otherwise fall back to step-specific checks
    final formValid = _formKey.currentState?.validate() ?? true;
    if (!formValid) return false;

    switch (_currentStep) {
      case 0:
        // Require trade & numeric experience (these fields live on step 0 in this form)
        final hasTrade = (_model.tradeController?.text.trim().isNotEmpty == true);
        final hasExperience = (_model.experienceController?.text.trim().isNotEmpty == true) && (num.tryParse(_model.experienceController!.text.trim()) != null);
        return hasTrade && hasExperience;
      case 1:
        // Intermediate step: pricing & availability — allow to proceed if fields validated by form
        return true;
      case 2:
        // Portfolio step: optional, always valid
        return true;
      default:
        return false;
    }

    }

    Future<void> _nextStep() async {
    setState(() {
      _error = null;
    });

    // First validate current visible form fields
    if (!_validateCurrentStep()) {
      setState(() {
        _error = 'Please fill in all required fields';
      });
      return;
    }

    // Save current step values into the _formData accumulator so data travels across steps
    if (_currentStep == 0) {
      _formData['trade'] = _model.tradeController?.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      _formData['experience'] = num.tryParse((_model.experienceController?.text ?? '').trim());
      _formData['certifications'] = _model.certificationsController?.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      _formData['bio'] = _model.bioController?.text.trim();
    } else if (_currentStep == 1) {
      // collect pricing & availability & service area into formData before final submit
      final perHour = num.tryParse((_model.pricingPerHourController?.text ?? '').trim());
      final perJob = num.tryParse((_model.pricingPerJobController?.text ?? '').trim());
      if (perHour != null || perJob != null) {
        _formData['pricing'] = {};
        if (perHour != null) _formData['pricing']['perHour'] = perHour;
        if (perJob != null) _formData['pricing']['perJob'] = perJob;
      }
      if ((_model.availabilityController?.text ?? '').isNotEmpty) _formData['availability'] = _model.availabilityController!.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      if ((_model.serviceAreaAddressController?.text ?? '').isNotEmpty || (_model.serviceAreaRadiusController?.text ?? '').isNotEmpty) {
        _formData['serviceArea'] = {};
        if ((_model.serviceAreaAddressController?.text ?? '').isNotEmpty) _formData['serviceArea']['address'] = _model.serviceAreaAddressController!.text.trim();
        final r = num.tryParse((_model.serviceAreaRadiusController?.text ?? '').trim());
        if (r != null) _formData['serviceArea']['radius'] = r;
        if (_serviceLon != null && _serviceLat != null) _formData['serviceArea']['coordinates'] = [_serviceLon, _serviceLat];
      }
    }

    if (_currentStep < _lastStepIndex) {
      setState(() {
        _currentStep++;
        // restore controllers from _formData when entering the next step (keeps UI consistent)
        if (_currentStep == 1) {
          // step 1 shows pricing/availability/service area — prefill if we have data
          if (_formData['pricing'] is Map) {
            _model.pricingPerHourController?.text = (_formData['pricing']['perHour'] ?? '').toString();
            _model.pricingPerJobController?.text = (_formData['pricing']['perJob'] ?? '').toString();
          }
          if (_formData['availability'] is List) {
            _model.availabilityController?.text = (_formData['availability'] as List).join(',');
          }
          if (_formData['serviceArea'] is Map) {
            _model.serviceAreaAddressController?.text = (_formData['serviceArea']['address'] ?? '').toString();
            _model.serviceAreaRadiusController?.text = (_formData['serviceArea']['radius'] ?? '').toString();
          }
        }
      });
    } else {
      // Final step: merge formData with any remaining controllers (name/email/phone) and submit
      // Save top-level identity fields
      _formData['name'] = _model.fullNameController?.text.trim();
      _formData['email'] = _model.emailController?.text.trim();
      _formData['phone'] = _model.phoneController?.text.trim();
      // include trade/experience if not previously saved
      if (!_formData.containsKey('trade') && (_model.tradeController?.text ?? '').isNotEmpty) {
        _formData['trade'] = _model.tradeController!.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      }
      if (!_formData.containsKey('experience') && (_model.experienceController?.text ?? '').isNotEmpty) {
        _formData['experience'] = num.tryParse(_model.experienceController!.text.trim());
      }

      // Attach portfolio metadata if exists
      if (_remotePortfolioItems.isNotEmpty) _formData['portfolio'] = _remotePortfolioItems;

      // Attach locally picked image metadata so final submit can include references (actual file upload not implemented here)
      if (_localPortfolioImagePaths.isNotEmpty) {
        _formData['localPortfolioFiles'] = _localPortfolioImagePaths.map((p) => {'path': p, 'name': File(p).uri.pathSegments.isNotEmpty ? File(p).uri.pathSegments.last : p}).toList();
      }

      await _saveProfile();
    }
    }

    void _previousStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
        _error = null;
        // restore fields for the step we're returning to
        if (_currentStep == 0) {
          if (_formData['trade'] is List) _model.tradeController?.text = (_formData['trade'] as List).join(',');
          if (_formData['experience'] != null) _model.experienceController?.text = _formData['experience'].toString();
          if (_formData['certifications'] is List) _model.certificationsController?.text = (_formData['certifications'] as List).join(',');
          if (_formData['bio'] != null) _model.bioController?.text = _formData['bio'].toString();
        }
        if (_currentStep == 1) {
          if (_formData['pricing'] is Map) {
            _model.pricingPerHourController?.text = (_formData['pricing']['perHour'] ?? '').toString();
            _model.pricingPerJobController?.text = (_formData['pricing']['perJob'] ?? '').toString();
          }
          if (_formData['availability'] is List) _model.availabilityController?.text = (_formData['availability'] as List).join(',');
          if (_formData['serviceArea'] is Map) {
            _model.serviceAreaAddressController?.text = (_formData['serviceArea']['address'] ?? '').toString();
            _model.serviceAreaRadiusController?.text = (_formData['serviceArea']['radius'] ?? '').toString();
          }
        }
      });
    }
    }

    void _removeLocalImage(int index) {
    if (index >= 0 && index < _localPortfolioImagePaths.length) {
      setState(() => _localPortfolioImagePaths.removeAt(index));
    }
    }

    Future<void> _pickPortfolioImages() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: true);
      if (result == null) return; // user canceled
      final added = <String>[];
      for (final f in result.files) {
        // On some platforms (web) path may be null; skip those in this simplified flow
        if (f.path != null) added.add(f.path!);
      }
      if (added.isEmpty) {
        _showUserError('No selectable file paths available on this platform');
        return;
      }
      setState(() => _localPortfolioImagePaths.addAll(added));
    } on MissingPluginException catch (e) {
      if (mounted && kDebugMode) debugPrint('File pick plugin not implemented: $e');
      _showUserError('File picker is not available on this platform');
      setState(() {
        _filePickerAvailable = false;
      });
    } catch (e) {
      if (mounted && kDebugMode) debugPrint('Image pick error: $e');
      _showUserError(e);
    }
    }

   Future<void> _fetchJobCategories() async {
     try {
       final cats = await JobService.getJobCategories();
       if (!mounted) return;
       setState(() {
         _jobCategories = cats;
       });

       // If profile prefills already include a trade string, try to match it
       final pre = (_model.tradeController?.text ?? '').trim();
       if (pre.isNotEmpty) {
         final first = pre.split(',').map((s) => s.trim()).firstWhere((s) => s.isNotEmpty, orElse: () => '');
         if (first.isNotEmpty) {
           final match = _jobCategories.firstWhere((c) {
             final name = (c['name'] ?? c['title'] ?? '').toString().toLowerCase();
             return name == first.toLowerCase();
           }, orElse: () => {});
           if (match is Map && (match['_id'] ?? match['id'] ?? '').toString().isNotEmpty) {
             setState(() {
               _selectedCategoryId = (match['_id'] ?? match['id']).toString();
               _selectedCategoryName = (match['name'] ?? match['title']).toString();
               _model.tradeController?.text = _selectedCategoryName ?? '';
             });
           }
         }
       }
     } catch (e) {
       if (kDebugMode) debugPrint('Failed to fetch job categories: $e');
     }
   }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color primaryColor = const Color(0xFFA20025);

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: theme.colorScheme.surface,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double horizontalPadding = math.min(48.0, constraints.maxWidth * 0.06);

              return Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 40.0),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left_rounded),
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                          onPressed: () => context.safePop(),
                          iconSize: 32,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _hasArtisanProfile ? 'Edit Profile' : 'Create Artisan Profile',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                            fontSize: 18,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),

                    // Step indicator
                    _buildStepIndicator(),

                    // Step content - make the whole form scrollable to avoid RenderFlex overflow
                    Expanded(
                      child: SingleChildScrollView(
                        child: Form(
                          key: _formKey,
                          child: _buildStepContent(),
                        ),
                      ),
                    ),

                    // Bottom buttons
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: theme.colorScheme.onSurface.withOpacity(0.1),
                            width: 1,
                          ),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_error != null)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.error.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: theme.colorScheme.error.withOpacity(0.2),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    color: theme.colorScheme.error,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _error!,
                                      style: TextStyle(
                                        color: theme.colorScheme.error,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          Row(
                            children: [
                              if (_currentStep > 0)
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _previousStep,
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      side: BorderSide(
                                        color: theme.colorScheme.onSurface.withOpacity(0.2),
                                      ),
                                    ),
                                    child: const Text('Back'),
                                  ),
                                ),

                              if (_currentStep > 0) const SizedBox(width: 12),

                              Expanded(
                                flex: _currentStep == 0 ? 2 : 1,
                                child: ElevatedButton(
                                  onPressed: _isSaving ? null : _nextStep,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: primaryColor,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: _isSaving
                                      ? SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation(
                                              Colors.white,
                                            ),
                                          ),
                                        )
                                      : Text(
                                          _atLastStep
                                              ? (_hasArtisanProfile ? 'SAVE PROFILE' : 'CREATE PROFILE')
                                              : 'CONTINUE',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}











































