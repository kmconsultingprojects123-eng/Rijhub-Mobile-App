import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../google_maps_config.dart';
import 'edit_profile_user_model.dart';
import '../../services/user_service.dart';
import '../../services/token_storage.dart';
import '../../utils/awesome_dialogs.dart';
import '../../utils/error_messages.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/foundation.dart';
export 'edit_profile_user_model.dart';

/// Create a page where users can edit and update their profile including
/// profile and cover photos
class EditProfileUserWidget extends StatefulWidget {
  const EditProfileUserWidget({super.key});

  static String routeName = 'editProfileUser';
  static String routePath = '/editProfileUser';

  @override
  State<EditProfileUserWidget> createState() => _EditProfileUserWidgetState();
}

class _EditProfileUserWidgetState extends State<EditProfileUserWidget> {
  late EditProfileUserModel _model;
  final scaffoldKey = GlobalKey<ScaffoldState>();

  String? _profileImagePath;
  Uint8List? _profileImageBytes;
  String? _profileImageFilename;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();

  final _formKey = GlobalKey<FormState>();
  bool _hasChanged = false;
  Map<String, String> _initialFields = {};
  bool _loadedInitial = false;
  String? _successMessage;
  Timer? _successTimer;
  bool _isSaving = false;

  // LGA/state helpers and geocoding
  Map<String, List<String>> _statesLgas = {};
  List<String> _statesList = [];
  List<String> _lgasForSelectedState = [];
  String? _selectedState;
  String? _selectedLga;
  double? _serviceLat;
  double? _serviceLon;
  bool _isGeocoding = false;
  Timer? _locationDebounce;

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => EditProfileUserModel());

    // Populate initial values from backend
    () async {
      try {
        final profile = await UserService.getProfile();
        if (profile != null && mounted) {
          setState(() {
            _nameController.text = (profile['name'] ?? profile['fullName'] ?? '')?.toString() ?? '';
            _emailController.text = (profile['email'] ?? '')?.toString() ?? '';
            _phoneController.text = (profile['phone'] ?? '')?.toString() ?? '';
            final img = profile['profileImage'];
            if (img is Map && img['url'] != null) {
              _profileImagePath = img['url'].toString();
            }
            // record initial values so we can detect changes
            _initialFields = {
              'name': _nameController.text,
              'email': _emailController.text,
              'phone': _phoneController.text,
              'location': _locationController.text,
              'profileImage': _profileImagePath ?? '',
            };
            _loadedInitial = true;
          });
        }

        // Prefer canonical cached location to populate the location input and coordinates
        try {
          final loc = await UserService.getCanonicalLocation();
          if (loc != null && mounted) {
            final addr = loc['address'] as String?;
            final lat = loc['latitude'] as double?;
            final lon = loc['longitude'] as double?;
            if (addr != null && addr.isNotEmpty && _locationController.text.isEmpty) {
              setState(() { _locationController.text = addr; });
            }
            if (lat != null && lon != null && (_serviceLat == null || _serviceLon == null)) {
              setState(() { _serviceLat = lat; _serviceLon = lon; });
            }
          }
        } catch (_) {}
      } catch (e) {
        if (kDebugMode) debugPrint('EditProfile.init -> failed to load profile: $e');
      }
    }();

    // load states/lgas json for LGA auto-fill
    _loadStatesLgas();

    // listen for changes to enable Save button
    _nameController.addListener(_onFieldChanged);
    _emailController.addListener(_onFieldChanged);
    _phoneController.addListener(_onFieldChanged);
    _locationController.addListener(_onFieldChanged);
  }

  Future<void> _loadStatesLgas() async {
    try {
      final s = await rootBundle.loadString('assets/jsons/nigeria_states_lgas.json');
      final decoded = jsonDecode(s) as Map<String, dynamic>;
      final map = <String, List<String>>{};
      for (final e in decoded.entries) {
        final key = e.key.toString();
        final v = e.value;
        if (v is List) map[key] = List<String>.from(v.map((i) => i.toString()));
      }
      if (mounted) setState(() { _statesLgas = map; _statesList = map.keys.toList()..sort(); });
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to load states/lgas json: $e');
    }
  }

  Future<void> _geocodeAddress(String address) async {
    if (address.trim().isEmpty) return;
    setState(() { _isGeocoding = true; _serviceLat = null; _serviceLon = null; });
    try {
      final key = GOOGLE_MAPS_API_KEY;
      if (key.isEmpty) return;
      final q = Uri.encodeComponent(address);
      final url = Uri.parse('https://maps.googleapis.com/maps/api/geocode/json?address=$q&key=$key');
      final resp = await http.get(url).timeout(const Duration(seconds: 12));
      if (resp.statusCode == 200 && resp.body.isNotEmpty) {
        final body = jsonDecode(resp.body);
        if (body is Map && body['results'] is List && (body['results'] as List).isNotEmpty) {
          final res = (body['results'] as List).first;
          if (res is Map && res['geometry'] is Map && res['geometry']['location'] is Map) {
            final loc = res['geometry']['location'];
            final lat = loc['lat'];
            final lon = loc['lng'];
            if (lat is num && lon is num) {
              if (mounted) setState(() { _serviceLat = lat.toDouble(); _serviceLon = lon.toDouble(); });
            }
          }
        }
      } else {
        if (mounted && kDebugMode) debugPrint('Geocode failed (${resp.statusCode}): ${resp.body}');
      }
    } catch (e) {
      if (mounted && kDebugMode) debugPrint('Geocode error: $e');
    } finally {
      if (mounted) setState(() => _isGeocoding = false);
    }
  }

  void _onLocationChanged(String value) {
    _locationDebounce?.cancel();
    _locationDebounce = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      final input = value.trim();
      if (input.isEmpty) return;

      // Try exact LGA match first
      String? matchedState;
      String? matchedLga;
      for (final entry in _statesLgas.entries) {
        for (final l in entry.value) {
          if (l.toLowerCase() == input.toLowerCase()) { matchedState = entry.key; matchedLga = l; break; }
        }
        if (matchedLga != null) break;
      }
      // fallback: contains
      if (matchedLga == null) {
        for (final entry in _statesLgas.entries) {
          for (final l in entry.value) {
            if (l.toLowerCase().contains(input.toLowerCase())) { matchedState = entry.key; matchedLga = l; break; }
          }
          if (matchedLga != null) break;
        }
      }

      if (matchedLga != null && matchedState != null) {
        if (mounted) {
          setState(() {
            _selectedState = matchedState;
            _lgasForSelectedState = _statesLgas[matchedState] ?? [];
            _selectedLga = matchedLga;
            final addr = '${matchedLga}, ${matchedState}, Nigeria';
            _locationController.text = addr;
          });
          await _geocodeAddress('${matchedLga}, ${matchedState}, Nigeria');
        }
      } else {
        if (input.length > 3) await _geocodeAddress(input);
      }
    });
  }

  @override
  void dispose() {
    _locationDebounce?.cancel();
    _model.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _locationController.dispose();
    _successTimer?.cancel();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.image);
      if (res == null) return;
      final picked = res.files.single;
      // On web, use bytes; on native use path when available
      if (kIsWeb) {
        final bytes = picked.bytes;
        if (bytes == null) return;
        setState(() {
          _profileImageBytes = bytes;
          _profileImagePath = null;
          _profileImageFilename = picked.name;
          _hasChanged = true;
        });
      } else {
        final path = picked.path;
        if (path == null) return;
        try {
          // read as bytes so we always send multipart via bytes path (more reliable across platforms)
          final file = File(path);
          final bytes = await file.readAsBytes();
          setState(() {
            _profileImageBytes = bytes;
            _profileImagePath = null; // clear path to avoid confusion; bytes will be used
            _profileImageFilename = picked.name;
            if ((_initialFields['profileImage'] ?? '') != (_profileImageFilename ?? '')) _hasChanged = true;
          });
        } catch (e) {
          // fallback: keep the path if reading bytes fails (content:// URIs may fail)
          setState(() {
            _profileImagePath = path;
            _profileImageBytes = null;
            _profileImageFilename = picked.name;
            if ((_initialFields['profileImage'] ?? '') != (_profileImagePath ?? '')) _hasChanged = true;
          });
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Image pick error: $e');
    }
  }

  Future<void> _saveProfile() async {
    // validate form
    if (!_formKey.currentState!.validate()) return;
    if (!_hasChanged) return; // nothing to save

    setState(() => _isSaving = true);

    // gather fields
    final fields = <String, String>{
      'name': _nameController.text.trim(),
      'email': _emailController.text.trim(),
      'phone': _phoneController.text.trim(),
      'location': _locationController.text.trim(),
    };
    // include coordinates if available
    try {
      if (_serviceLat != null && _serviceLon != null) {
        fields['latitude'] = _serviceLat!.toString();
        fields['longitude'] = _serviceLon!.toString();
      }
    } catch (_) {}

    try {
      // pass image bytes for web or local path for native
      await UserService.updateProfile(fields,
          imagePath: (_profileImagePath ?? '').startsWith('http') ? null : _profileImagePath,
          imageBytes: _profileImageBytes,
          imageFilename: _profileImageFilename,
          // Force updating the user document so profileImage is updated on the
          // user record (ProfileWidget reads /api/users/me). This ensures
          // artisans who update their image also see it in the general profile view.
          forceUserPath: true);

      // fetch the fresh profile from server and persist small fields for quick UI updates
      Map<String, dynamic>? updatedProfile;
      try {
        updatedProfile = await UserService.getProfile();
        if (updatedProfile != null) {
          // persist quick fields so other UI can show them immediately
          final name = (updatedProfile['name'] ?? updatedProfile['fullName'] ?? '')?.toString();
          final email = (updatedProfile['email'] ?? '')?.toString();
          final phone = (updatedProfile['phone'] ?? '')?.toString();
          try { await TokenStorage.saveRecentRegistration(name: name, email: email, phone: phone); } catch (_) {}
          // Persist canonical location into TokenStorage so ProfileWidget.getCanonicalLocation
          // can return the updated address even if the server stored it under artisan/serviceArea.
          try {
            String? addr;
            double? lat;
            double? lon;
            // Prefer server-provided serviceArea/location in the updated profile
            if (updatedProfile['serviceArea'] is Map) {
              final sa = Map<String, dynamic>.from(updatedProfile['serviceArea']);
              addr = sa['address']?.toString() ?? addr;
              final coords = sa['coordinates'] ?? sa['center'] ?? sa['location'];
              if (coords is List && coords.length >= 2) {
                lon = (coords[0] is num) ? coords[0].toDouble() : double.tryParse(coords[0].toString());
                lat = (coords[1] is num) ? coords[1].toDouble() : double.tryParse(coords[1].toString());
              }
              if (sa['lat'] != null && sa['lon'] != null) {
                lat = (sa['lat'] is num) ? sa['lat'].toDouble() : double.tryParse(sa['lat'].toString());
                lon = (sa['lon'] is num) ? sa['lon'].toDouble() : double.tryParse(sa['lon'].toString());
              }
            }
            if (addr == null && (fields['location']?.isNotEmpty == true)) addr = fields['location'];
            if (lat == null && _serviceLat != null) lat = _serviceLat;
            if (lon == null && _serviceLon != null) lon = _serviceLon;
            if (addr != null || lat != null || lon != null) {
              try { await TokenStorage.saveLocation(address: addr, latitude: lat, longitude: lon); } catch (_) {}
            }
          } catch (_) {}
          // persist role and kyc flag if available so UI can update quickly
          try {
            final role = (updatedProfile['role'] ?? updatedProfile['type'] ?? updatedProfile['accountType'])?.toString();
            if (role != null && role.isNotEmpty) await TokenStorage.saveRole(role);
          } catch (_) {}
          try {
            final k = updatedProfile['kycVerified'] ?? updatedProfile['isVerified'] ?? updatedProfile['kyc']?['verified'];
            if (k != null) {
              final kBool = (k is bool) ? k : (k.toString().toLowerCase() == 'true' || k.toString() == '1');
              await TokenStorage.saveKycVerified(kBool);
            }
          } catch (_) {}

          // Update in-memory app state so other pages immediately reflect changes (including location)
          try {
            AppStateNotifier.instance.setProfile(Map<String, dynamic>.from(updatedProfile));
          } catch (_) {}
        }
      } catch (_) {
        // ignore profile fetch failure here
      }

      // Show success message
      setState(() {
        _successMessage = 'Profile updated successfully';
        _isSaving = false;
      });
      _successTimer?.cancel();
      _successTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _successMessage = null);
      });

      // reset initial fields and _hasChanged
      _initialFields = {
        'name': _nameController.text,
        'email': _emailController.text,
        'phone': _phoneController.text,
        'location': _locationController.text,
        'profileImage': _profileImagePath ?? '',
      };
      setState(() => _hasChanged = false);

      // Allow user to see feedback briefly, then pop returning the updated profile
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) {
        // Ensure AppStateNotifier is refreshed as fallback
        try { await AppStateNotifier.instance.refreshProfile(); } catch (_) {}
        Navigator.of(context).pop(updatedProfile);
      }

    } catch (e) {
      setState(() => _isSaving = false);
      await showAppErrorDialog(context, title: 'Update failed', desc: ErrorMessages.humanize(e));
    }
  }

  void _onFieldChanged() {
    // Only run change detection after initial data is loaded
    if (!_loadedInitial) return;

    String normalizeName(String s) => s.trim();
    String normalizeEmail(String s) => s.trim().toLowerCase();
    String normalizePhone(String s) => s.replaceAll(RegExp(r'\D'), '');
    String normalizeLocation(String s) => s.trim();

    final nameNow = normalizeName(_nameController.text);
    final emailNow = normalizeEmail(_emailController.text);
    final phoneNow = normalizePhone(_phoneController.text);
    final locNow = normalizeLocation(_locationController.text);

    final nameThen = normalizeName(_initialFields['name'] ?? '');
    final emailThen = normalizeEmail(_initialFields['email'] ?? '');
    final phoneThen = normalizePhone(_initialFields['phone'] ?? '');
    final locThen = normalizeLocation(_initialFields['location'] ?? '');

    // image comparison: if bytes selected -> changed; else compare paths/urls
    final imgThen = _initialFields['profileImage'] ?? '';
    String imgNow;
    if (_profileImageBytes != null) {
      imgNow = '<<bytes:${_profileImageFilename ?? 'file'}>>';
    } else {
      imgNow = _profileImagePath ?? '';
    }

    final changed = nameNow != nameThen || emailNow != emailThen || phoneNow != phoneThen || locNow != locThen || imgNow != imgThen;
    if (changed != _hasChanged) setState(() => _hasChanged = changed);
  }

  void _clearImage() {
    setState(() {
      _profileImageBytes = null;
      _profileImagePath = null;
      _profileImageFilename = null;
      _hasChanged = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: () { FocusScope.of(context).unfocus(); },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: isDark ? Colors.black : Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              // Header with back button and save
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: theme.colorScheme.onSurface.withOpacity(0.1),
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.chevron_left_rounded,
                        color: colorScheme.onSurface.withOpacity(0.8),
                        size: 28,
                      ),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    Text(
                      'Edit Profile',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                        fontSize: 18,
                      ),
                    ),
                    SizedBox(
                      width: 100,
                      child: _isSaving
                          ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                          : ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _hasChanged
                              ? colorScheme.primary
                              : colorScheme.onSurface.withOpacity(0.1),
                          foregroundColor: _hasChanged
                              ? colorScheme.onPrimary
                              : colorScheme.onSurface.withOpacity(0.3),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          elevation: 0,
                        ),
                        onPressed: _hasChanged ? _saveProfile : null,
                        child: Text(
                          'Save',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Success Message
              if (_successMessage != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  // Use a green success color for the alert background
                  color: Colors.green.withOpacity(0.12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 18,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _successMessage!,
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.close,
                          size: 18,
                          color: Colors.green.withOpacity(0.8),
                        ),
                        onPressed: () {
                          _successTimer?.cancel();
                          setState(() => _successMessage = null);
                        },
                      ),
                    ],
                  ),
                ),

              // Form Content
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(height: 40.0),

                          // Profile Image Section
                          Stack(
                            children: [
                              GestureDetector(
                                onTap: _pickImage,
                                child: Container(
                                  width: 120,
                                  height: 120,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: colorScheme.surface,
                                    border: Border.all(
                                      color: colorScheme.onSurface.withOpacity(0.1),
                                      width: 2,
                                    ),
                                  ),
                                  child: ClipOval(
                                    child: _profileImageBytes != null
                                        ? Image.memory(
                                      _profileImageBytes!,
                                      fit: BoxFit.cover,
                                    )
                                        : (_profileImagePath != null &&
                                        _profileImagePath!.isNotEmpty)
                                        ? (_profileImagePath!.startsWith('http')
                                        ? Image.network(
                                      _profileImagePath!,
                                      fit: BoxFit.cover,
                                    )
                                        : Image.file(
                                      File(_profileImagePath!),
                                      fit: BoxFit.cover,
                                    ))
                                        : Icon(
                                      Icons.person_outline,
                                      size: 48,
                                      color: colorScheme.onSurface
                                          .withOpacity(0.3),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: colorScheme.primary,
                                    border: Border.all(
                                      color: isDark
                                          ? Colors.black
                                          : Colors.white,
                                      width: 3,
                                    ),
                                  ),
                                  child: IconButton(
                                    icon: Icon(
                                      Icons.camera_alt_outlined,
                                      size: 18,
                                      color: colorScheme.onPrimary,
                                    ),
                                    onPressed: _pickImage,
                                    padding: EdgeInsets.zero,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _clearImage,
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                            ),
                            child: Text(
                              'Remove photo',
                              style: TextStyle(
                                color: theme.colorScheme.error,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),

                          const SizedBox(height: 48.0),

                          // Form Fields
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'FULL NAME',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.6),
                                  letterSpacing: 1.0,
                                ),
                              ),
                              const SizedBox(height: 8.0),
                              TextFormField(
                                controller: _nameController,
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface,
                                  fontSize: 16,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'John Doe',
                                  hintStyle: TextStyle(
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.3),
                                  ),
                                  filled: true,
                                  fillColor: isDark
                                      ? Colors.grey[900]
                                      : Colors.grey[50],
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12.0),
                                    borderSide: BorderSide.none,
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12.0),
                                    borderSide: BorderSide(
                                      color: colorScheme.primary,
                                      width: 1.5,
                                    ),
                                  ),
                                  errorBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12.0),
                                    borderSide: BorderSide(
                                      color: theme.colorScheme.error,
                                      width: 1.0,
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16.0,
                                    vertical: 16.0,
                                  ),
                                ),
                                keyboardType: TextInputType.name,
                                validator: (v) => (v == null || v.trim().isEmpty)
                                    ? 'Please enter your name'
                                    : null,
                              ),
                            ],
                          ),

                          const SizedBox(height: 20.0),

                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'EMAIL',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.6),
                                  letterSpacing: 1.0,
                                ),
                              ),
                              const SizedBox(height: 8.0),
                              TextFormField(
                                controller: _emailController,
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface,
                                  fontSize: 16,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'your@email.com',
                                  hintStyle: TextStyle(
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.3),
                                  ),
                                  filled: true,
                                  fillColor: isDark
                                      ? Colors.grey[900]
                                      : Colors.grey[50],
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12.0),
                                    borderSide: BorderSide.none,
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12.0),
                                    borderSide: BorderSide(
                                      color: colorScheme.primary,
                                      width: 1.5,
                                    ),
                                  ),
                                  errorBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12.0),
                                    borderSide: BorderSide(
                                      color: theme.colorScheme.error,
                                      width: 1.0,
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16.0,
                                    vertical: 16.0,
                                  ),
                                ),
                                keyboardType: TextInputType.emailAddress,
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return 'Please enter your email';
                                  }
                                  final re = RegExp(
                                      r"^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}");
                                  return re.hasMatch(v.trim())
                                      ? null
                                      : 'Please enter a valid email';
                                },
                              ),
                            ],
                          ),

                          const SizedBox(height: 20.0),

                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'PHONE NUMBER',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.6),
                                  letterSpacing: 1.0,
                                ),
                              ),
                              const SizedBox(height: 8.0),
                              TextFormField(
                                controller: _phoneController,
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface,
                                  fontSize: 16,
                                ),
                                decoration: InputDecoration(
                                  hintText: '+1234567890',
                                  hintStyle: TextStyle(
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.3),
                                  ),
                                  filled: true,
                                  fillColor: isDark
                                      ? Colors.grey[900]
                                      : Colors.grey[50],
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12.0),
                                    borderSide: BorderSide.none,
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12.0),
                                    borderSide: BorderSide(
                                      color: colorScheme.primary,
                                      width: 1.5,
                                    ),
                                  ),
                                  errorBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12.0),
                                    borderSide: BorderSide(
                                      color: theme.colorScheme.error,
                                      width: 1.0,
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16.0,
                                    vertical: 16.0,
                                  ),
                                ),
                                keyboardType: TextInputType.phone,
                                validator: (v) =>
                                (v == null || v.trim().isEmpty)
                                    ? 'Please enter your phone'
                                    : null,
                              ),
                            ],
                          ),

                          const SizedBox(height: 20.0),

                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'LOCATION / ADDRESS',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.6),
                                  letterSpacing: 1.0,
                                ),
                              ),
                              const SizedBox(height: 8.0),
                              TextFormField(
                                controller: _locationController,
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface,
                                  fontSize: 16,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Type your LGA (e.g. Bwari) or full address',
                                  hintStyle: TextStyle(
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.3),
                                  ),
                                  filled: true,
                                  fillColor: isDark
                                      ? Colors.grey[900]
                                      : Colors.grey[50],
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12.0),
                                    borderSide: BorderSide.none,
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12.0),
                                    borderSide: BorderSide(
                                      color: colorScheme.primary,
                                      width: 1.5,
                                    ),
                                  ),
                                  errorBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12.0),
                                    borderSide: BorderSide(
                                      color: theme.colorScheme.error,
                                      width: 1.0,
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16.0,
                                    vertical: 16.0,
                                  ),
                                ),
                                keyboardType: TextInputType.streetAddress,
                                onChanged: _onLocationChanged,
                                onFieldSubmitted: (v) async => await _geocodeAddress(v.trim()),
                              ),
                              const SizedBox(height: 8.0),
                              if (_selectedLga != null) Padding(
                                padding: const EdgeInsets.only(bottom: 6.0),
                                child: Text('LGA: ${_selectedLga!}', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                              ),
                              // Coordinates (latitude/longitude) are intentionally hidden
                              // from the UI. The widget still computes and stores
                              // `_serviceLat` and `_serviceLon` (used when saving the profile),
                              // but we do not render them anywhere in the form.
                              if (_isGeocoding) const Padding(padding: EdgeInsets.only(top:8), child: LinearProgressIndicator()),
                            ],
                          ),

                          const SizedBox(height: 60.0),
                        ],
                      ),
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

