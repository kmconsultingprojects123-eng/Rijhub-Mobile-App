import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:convert';
import '../../api_config.dart';
import '../../services/kyc_service.dart';
import '/state/app_state_notifier.dart';
import '/services/token_storage.dart';
import 'package:flutter/services.dart';
import '../../utils/error_messages.dart';
import 'package:flutter/foundation.dart';
import '../../services/job_service.dart';
import '../../services/api_client.dart';
import '../../services/location_service.dart';
import 'package:flutter/widgets.dart';

class ArtisanKycPageWidget extends StatefulWidget {
  const ArtisanKycPageWidget({super.key});

  static String routeName = 'ArtisanKycPageWidget';
  static String routePath = '/artisanKycPage';

  @override
  State<ArtisanKycPageWidget> createState() => _ArtisanKycPageWidgetState();
}

class _ArtisanKycPageWidgetState extends State<ArtisanKycPageWidget> {
  final _formKey = GlobalKey<FormState>();
  int _currentStep = 0;

  // Step 1 fields
  final TextEditingController _businessNameCtrl = TextEditingController();
  final TextEditingController _countryCtrl = TextEditingController(text: 'Nigeria');
  final TextEditingController _stateCtrl = TextEditingController();
  final TextEditingController _lgaCtrl = TextEditingController();
  String _idType = 'national_id';
  // NOTE: service category is now a dropdown backed by JobService
  final TextEditingController _serviceCategoryCtrl = TextEditingController(); // kept as fallback
  List<Map<String, dynamic>> _categories = [];
  String? _selectedCategoryId;
  final TextEditingController _yearsExperienceCtrl = TextEditingController();

  // Files
  File? _profileImage;
  File? _idFront;
  File? _idBack;

  bool _isSubmitting = false;
  String? _error;
  String? _successMessage;
  Map<String, String> _fieldErrors = {};

  final List<String> _stepTitles = [
    'Business Details',
    'Document Upload',
    'Review & Submit'
  ];

  // States and LGAs for dropdowns
  List<String> _states = [];
  List<String> _lgas = [];
  bool _loadingStates = false;
  bool _loadingLgas = false;

  @override
  void initState() {
    super.initState();
    _fetchCategories();
    _fetchStates();
  }

  @override
  void dispose() {
    _businessNameCtrl.dispose();
    _countryCtrl.dispose();
    _stateCtrl.dispose();
    _lgaCtrl.dispose();
    _serviceCategoryCtrl.dispose();
    _yearsExperienceCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchCategories() async {
    try {
      final cats = await JobService.getJobCategories();
      if (!mounted) return;
      setState(() {
        _categories = cats;
      });
    } catch (e) {
      // ignore - categories are optional, fallback to free-text
      if (kDebugMode) debugPrint('Failed to fetch job categories: $e');
    }
  }

  Future<void> _pickFile(Function(File) onPicked) async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (res != null && res.files.isNotEmpty) {
        final pf = res.files.first;
        if (pf.path != null) {
          // Client-side validation: size and extension
          const int maxBytes = 5 * 1024 * 1024; // 5MB
          final name = pf.name.toLowerCase();
          final ext = name.contains('.') ? name.split('.').last : '';
          const allowed = ['jpg', 'jpeg', 'png'];

          if (pf.size > maxBytes) {
            setState(() {
              _error = 'File too large. Maximum allowed size is 5MB.';
            });
            return;
          }

          if (!allowed.contains(ext)) {
            setState(() {
              _error = 'Unsupported file type. Allowed: JPG, PNG.';
            });
            return;
          }

          onPicked(File(pf.path!));
          setState(() {
            _error = null;
          });
        }
      }
    } catch (e) {
      setState(() => _error = ErrorMessages.humanize(e, context: 'file_select'));
    }
  }

  Future<void> _fetchStates() async {
    try {
      setState(() { _loadingStates = true; });

      // Prefer client-side LocationService which is now restricted to Abuja FCT.
      final states = await LocationService.fetchNigeriaStates();
      if (mounted) setState(() { _states = states; });

    } catch (e) {
      if (kDebugMode) debugPrint('Failed to load states via LocationService: $e');

      // fallback to existing API call if needed
      try {
        final resp = await ApiClient.get('$API_BASE_URL/api/locations/nigeria/states', headers: {'Content-Type': 'application/json'});
        if (resp['status'] is int && resp['status'] >= 200 && resp['status'] < 300) {
          final body = resp['json'] ?? (resp['body']?.isNotEmpty == true ? jsonDecode(resp['body'] as String) : null);
          List<dynamic>? list;
          if (body is Map && body['data'] is List) list = body['data'] as List<dynamic>;
          else if (body is List) list = body as List<dynamic>;
          else if (body is Map && body['states'] is List) list = body['states'] as List<dynamic>;

          if (list != null) {
            final names = list.map((e) => e is String ? e : (e is Map && e['name'] != null ? e['name'].toString() : e.toString())).toList().cast<String>();
            if (mounted) setState(() { _states = names; });
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Failed to load states: $e');
      }
    } finally {
      if (mounted) setState(() { _loadingStates = false; });
    }
  }

  Future<void> _fetchLgasForState(String state) async {
    try {
      setState(() { _loadingLgas = true; _lgas = []; _lgaCtrl.text = ''; });

      // If the requested state isn't allowed, return empty list.
      final lgas = await LocationService.fetchNigeriaLgas(state);
      if (mounted) setState(() { _lgas = lgas; });

      // if LocationService returned nothing, fall back to API
      if (lgas.isEmpty) {
        final uri = '$API_BASE_URL/api/locations/nigeria/lgas?state=${Uri.encodeQueryComponent(state)}';
        final resp = await ApiClient.get(uri, headers: {'Content-Type': 'application/json'});
        if (resp['status'] is int && resp['status'] >= 200 && resp['status'] < 300) {
          final body = resp['json'] ?? (resp['body']?.isNotEmpty == true ? jsonDecode(resp['body'] as String) : null);
          List<dynamic>? list;
          if (body is Map && body['data'] is List) list = body['data'] as List<dynamic>;
          else if (body is List) list = body as List<dynamic>;
          else if (body is Map && body['lgas'] is List) list = body['lgas'] as List<dynamic>;

          if (list != null) {
            final names = list.map((e) => e is String ? e : (e is Map && e['name'] != null ? e['name'].toString() : e.toString())).toList().cast<String>();
            if (mounted) setState(() { _lgas = names; });
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to load lgas for $state: $e');
    } finally {
      if (mounted) setState(() { _loadingLgas = false; });
    }
  }

  Widget _buildStepIndicator() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
            children: List.generate(3, (index) {
              final isActive = index == _currentStep;
              final isCompleted = index < _currentStep;

              return Column(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive || isCompleted
                          ? theme.colorScheme.primary
                          : theme.colorScheme.surface,
                      border: Border.all(
                        color: isActive
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface.withOpacity(0.1),
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: isCompleted
                          ? Icon(
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
                  Text(
                    _stepTitles[index],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                      color: isActive || isCompleted
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildStepContent() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: _getCurrentStepWidget(),
      ),
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
    final isDark = theme.brightness == Brightness.dark;
    final Color primaryColor = const Color(0xFFA20025);

    return SingleChildScrollView(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 40),

            // Header
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Business Information',
                  style: theme.textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w300,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tell us about your business to get verified',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),

            // Business Name Field
            Text(
              'BUSINESS NAME',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface.withOpacity(0.6),
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _businessNameCtrl,
              decoration: InputDecoration(
                hintText: 'Enter your business name',
                hintStyle: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(0.3),
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
                    color: primaryColor,
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
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 16,
              ),
              textInputAction: TextInputAction.next,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Business name is required';
                }
                return null;
              },
            ),
            if (_fieldErrors['businessName'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  _fieldErrors['businessName']!,
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: 20),

            // Country Field (fixed to Nigeria)
            Text(
              'COUNTRY',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface.withOpacity(0.6),
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _countryCtrl,
              readOnly: true,
              enabled: false,
              decoration: InputDecoration(
                hintText: 'Enter your country',
                hintStyle: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(0.3),
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
                    color: primaryColor,
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
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 16,
              ),
              textInputAction: TextInputAction.next,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Country is required';
                }
                return null;
              },
            ),
            if (_fieldErrors['country'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  _fieldErrors['country']!,
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: 20),

            // State Field (dropdown populated from API)
            Text(
              'STATE',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface.withOpacity(0.6),
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[900] : Colors.grey[50],
                borderRadius: BorderRadius.circular(12.0),
              ),
              child: _loadingStates
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12.0),
                      child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.0))),
                    )
                  : DropdownButtonFormField<String>(
                       value: _stateCtrl.text.isNotEmpty ? _stateCtrl.text : null,
                       hint: Text('Select state'),
                       decoration: InputDecoration(
                         contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                         border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0), borderSide: BorderSide.none),
                         focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0), borderSide: BorderSide(color: primaryColor, width: 1.5)),
                       ),
                       isExpanded: true,
                       items: _states.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                       onChanged: (value) {
                         final v = value ?? '';
                         setState(() {
                           _stateCtrl.text = v;
                           _lgaCtrl.text = '';
                           _lgas = [];
                         });
                         if (v.isNotEmpty) _fetchLgasForState(v);
                       },
                       validator: (value) {
                         if (value == null || value.trim().isEmpty) return 'State is required';
                         return null;
                       },
                     ),
            ),
            if (_fieldErrors['state'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  _fieldErrors['state']!,
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: 20),

            // LGA Field (dependent on selected state)
            Text(
              'LOCAL GOVERNMENT AREA',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface.withOpacity(0.6),
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[900] : Colors.grey[50],
                borderRadius: BorderRadius.circular(12.0),
              ),
              child: _loadingLgas
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12.0),
                      child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.0))),
                    )
                  : DropdownButtonFormField<String>(
                       value: _lgaCtrl.text.isNotEmpty ? _lgaCtrl.text : null,
                       hint: Text('Select LGA'),
                       decoration: InputDecoration(
                         contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                         border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0), borderSide: BorderSide.none),
                         focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0), borderSide: BorderSide(color: primaryColor, width: 1.5)),
                       ),
                       isExpanded: true,
                       items: _lgas.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                       onChanged: (value) {
                         final v = value ?? '';
                         setState(() { _lgaCtrl.text = v; });
                       },
                       validator: (value) {
                         if (value == null || value.trim().isEmpty) return 'LGA is required';
                         return null;
                       },
                     ),
            ),
            if (_fieldErrors['lga'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  _fieldErrors['lga']!,
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: 20),

            // ID Type Field (Styled as dropdown)
            Text(
              'ID TYPE',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface.withOpacity(0.6),
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[900] : Colors.grey[50],
                borderRadius: BorderRadius.circular(12.0),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _idType,
                  isExpanded: true,
                  icon: Icon(
                    Icons.arrow_drop_down,
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 16,
                  ),
                  dropdownColor: isDark ? Colors.grey[900] : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  items: const [
                    DropdownMenuItem(
                      value: 'national_id',
                      child: Text('National ID Card'),
                    ),
                    DropdownMenuItem(
                      value: 'driver_license',
                      child: Text('Driver License'),
                    ),
                    DropdownMenuItem(
                      value: 'passport',
                      child: Text('International Passport'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => _idType = value ?? _idType);
                  },
                ),
              ),
            ),
            if (_fieldErrors['IdType'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  _fieldErrors['IdType']!,
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: 20),

            // Service Category Field
            Text(
              'SERVICE CATEGORY',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface.withOpacity(0.6),
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),
            // Dropdown populated from job categories; fallback to free-text if categories unavailable
            if (_categories.isNotEmpty)
              Container(
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[900] : Colors.grey[50],
                  borderRadius: BorderRadius.circular(12.0),
                ),
                child: DropdownButtonFormField<String>(
                   value: _selectedCategoryId,
                   hint: Text('Select service category'),
                   decoration: InputDecoration(
                     contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                     border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0), borderSide: BorderSide.none),
                     focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0), borderSide: BorderSide(color: primaryColor, width: 1.5)),
                   ),
                  isExpanded: true,
                  items: _categories.map((c) {
                    final id = (c['_id'] ?? c['id'] ?? '').toString();
                    final name = (c['name'] ?? c['title'] ?? '').toString();
                    return DropdownMenuItem(value: id, child: Text(name));
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedCategoryId = value;
                      // keep fallback text controller in sync for review fallback
                      final sel = _categories.firstWhere((c) => ((c['_id'] ?? c['id'])?.toString() ?? '') == value, orElse: () => <String,dynamic>{});
                      final name = (sel['name'] ?? '').toString();
                      _serviceCategoryCtrl.text = name;
                    });
                  },
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Please select a service category';
                    return null;
                  },
                ),
              )
            else
              // fallback to free-text if categories couldn't be loaded
              TextFormField(
                controller: _serviceCategoryCtrl,
                decoration: InputDecoration(
                  hintText: 'e.g., Plumbing, Electrical, Carpentry',
                  hintStyle: TextStyle(
                    color: theme.colorScheme.onSurface.withOpacity(0.3),
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
                      color: primaryColor,
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
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontSize: 16,
                ),
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Service category is required';
                  }
                  return null;
                },
              ),
            if (_fieldErrors['serviceCategory'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  _fieldErrors['serviceCategory']!,
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: 20),

            // Years of Experience Field
            Text(
              'YEARS OF EXPERIENCE',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface.withOpacity(0.6),
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _yearsExperienceCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                hintText: 'Number of years',
                hintStyle: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(0.3),
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
                    color: primaryColor,
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
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 16,
              ),
              textInputAction: TextInputAction.done,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Years of experience is required';
                }
                final n = int.tryParse(value);
                if (n == null || n < 0) return 'Enter a valid number';
                return null;
              },
            ),
            if (_fieldErrors['yearsExperience'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  _fieldErrors['yearsExperience']!,
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildStep2() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color primaryColor = const Color(0xFFA20025);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),

          // Header
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Document Upload',
                style: theme.textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w300,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Upload clear images of your documents',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                  fontWeight: FontWeight.w300,
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),

          // Profile Photo Upload
          Text(
            'PROFILE PHOTO',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface.withOpacity(0.6),
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 8),
          _buildFileUploadField(
            title: 'Upload a clear professional photo',
            file: _profileImage,
            onPick: () => _pickFile((f) => setState(() => _profileImage = f)),
            fieldKey: 'profileImage',
          ),
          if (_fieldErrors['profileImage'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                _fieldErrors['profileImage']!,
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ),
          const SizedBox(height: 24),

          // ID Front Upload
          Text(
            'ID CARD (FRONT)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface.withOpacity(0.6),
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 8),
          _buildFileUploadField(
            title: 'Front side of your ID card',
            file: _idFront,
            onPick: () => _pickFile((f) => setState(() => _idFront = f)),
            fieldKey: 'IdUploadFront',
          ),
          if (_fieldErrors['IdUploadFront'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                _fieldErrors['IdUploadFront']!,
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ),
          const SizedBox(height: 24),

          // ID Back Upload
          Text(
            'ID CARD (BACK)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface.withOpacity(0.6),
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 8),
          _buildFileUploadField(
            title: 'Back side of your ID card',
            file: _idBack,
            onPick: () => _pickFile((f) => setState(() => _idBack = f)),
            fieldKey: 'IdUploadBack',
          ),
          if (_fieldErrors['IdUploadBack'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                _fieldErrors['IdUploadBack']!,
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ),
          const SizedBox(height: 32),

          // Requirements Note
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: primaryColor.withAlpha((0.05 * 255).toInt()),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: primaryColor,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Upload Requirements',
                      style: TextStyle(
                        color: primaryColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildRequirementItem('• Clear, high-quality images'),
                _buildRequirementItem('• Maximum file size: 5MB each'),
                _buildRequirementItem('• Supported formats: JPG, PNG'),
                _buildRequirementItem('• All documents must be valid'),
              ],
            ),
          ),
          const SizedBox(height: 60),
        ],
      ),
    );
  }

  Widget _buildFileUploadField({
    required String title,
    required File? file,
    required VoidCallback onPick,
    required String? fieldKey,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color primaryColor = const Color(0xFFA20025);

    return GestureDetector(
      onTap: onPick,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[900] : Colors.grey[50],
          borderRadius: BorderRadius.circular(12.0),
          border: file != null
              ? Border.all(
            color: primaryColor,
            width: 1.5,
          )
              : null,
        ),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.cloud_upload_outlined,
                  color: primaryColor,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file != null
                            ? 'Change file'
                            : 'Click to upload',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withOpacity(0.5),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                if (file != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: primaryColor.withAlpha((0.1 * 255).toInt()),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: primaryColor,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Uploaded',
                          style: TextStyle(
                            color: primaryColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (file != null) ...[
              const SizedBox(height: 16),
              Container(
                height: 120,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  image: DecorationImage(
                    image: FileImage(file),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                file.path.split('/').last,
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRequirementItem(String text) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: TextStyle(
          color: theme.colorScheme.onSurface.withOpacity(0.7),
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildStep3() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color primaryColor = const Color(0xFFA20025);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),

          // Header
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Review & Submit',
                style: theme.textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w300,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Please review all information before submitting',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                  fontWeight: FontWeight.w300,
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),

          // Summary Card
          Container(
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[900] : Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Business Details
                _buildReviewSection(
                  title: 'Business Details',
                  items: [
                    _buildReviewItem('Business Name', _businessNameCtrl.text),
                    _buildReviewItem('Service Category', _serviceCategoryCtrl.text.isNotEmpty
                        ? _serviceCategoryCtrl.text
                        : (_selectedCategoryId != null && _selectedCategoryId!.isNotEmpty
                            ? (_categories.firstWhere((c) => (c['_id'] ?? c['id'])?.toString() == _selectedCategoryId, orElse: () => {})['name']?.toString() ?? '')
                            : '')),
                    _buildReviewItem('Years of Experience', '${_yearsExperienceCtrl.text} years'),
                  ],
                ),
                const SizedBox(height: 24),

                // Location
                _buildReviewSection(
                  title: 'Location',
                  items: [
                    _buildReviewItem('Country', _countryCtrl.text),
                    _buildReviewItem('State', _stateCtrl.text),
                    _buildReviewItem('LGA', _lgaCtrl.text),
                  ],
                ),
                const SizedBox(height: 24),

                // Documents
                _buildReviewSection(
                  title: 'Documents',
                  items: [
                    _buildReviewItem('ID Type', _idType.replaceAll('_', ' ').toUpperCase()),
                    _buildReviewItem('Profile Photo', _profileImage != null ? '✓ Uploaded' : '✗ Not uploaded'),
                    _buildReviewItem('ID Front', _idFront != null ? '✓ Uploaded' : '✗ Not uploaded'),
                    _buildReviewItem('ID Back', _idBack != null ? '✓ Uploaded' : '✗ Not uploaded'),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Terms Note
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: primaryColor.withAlpha((0.05 * 255).toInt()),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.security_outlined,
                  color: primaryColor,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'By submitting this form, you confirm that all information provided is accurate and complete.',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 60),
        ],
      ),
    );
  }

  Widget _buildReviewSection({
    required String title,
    required List<Widget> items,
  }) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface.withOpacity(0.8),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),
        ...items,
      ],
    );
  }

  Widget _buildReviewItem(String label, String value) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _validateCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _formKey.currentState?.validate() ?? false;
      case 1:
        return _profileImage != null && _idFront != null && _idBack != null;
      case 2:
        return true;
      default:
        return false;
    }
  }

  Future<void> _nextStep() async {
    setState(() {
      _error = null;
      _fieldErrors = {};
    });

    if (!_validateCurrentStep()) {
      setState(() {
        _error = _currentStep == 1
            ? 'Please upload all required documents'
            : 'Please fill in all required fields';
      });
      return;
    }

    if (_currentStep < 2) {
      setState(() {
        _currentStep++;
      });
    } else {
      await _submitKYC();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
        _error = null;
      });
    }
  }

    // Removed the widget-local parseFieldErrors function so the file will use
    // the shared `parseFieldErrors(http.Response)` defined in
    // `lib/services/kyc_service.dart`. This ensures server validation responses
    // are parsed consistently and field error keys are mapped (snake/camel).

    Future<void> _submitKYC() async {
    setState(() {
      _isSubmitting = true;
      _error = null;
      _successMessage = null;
      _fieldErrors = {};
    });

    try {
      final fields = <String, String>{
        'businessName': _businessNameCtrl.text.trim(),
        'country': _countryCtrl.text.trim(),
        'state': _stateCtrl.text.trim(),
        'lga': _lgaCtrl.text.trim(),
        'IdType': _idType,
        // Prefer sending category id (if selected), otherwise fallback to free-text name
        'serviceCategory': (_selectedCategoryId != null && _selectedCategoryId!.isNotEmpty) ? _selectedCategoryId! : _serviceCategoryCtrl.text.trim(),
        'yearsExperience': _yearsExperienceCtrl.text.trim(),
      };

      final files = <String, List<File>>{};
      if (_profileImage != null) files['profileImage'] = [_profileImage!];
      if (_idFront != null) files['IdUploadFront'] = [_idFront!];
      if (_idBack != null) files['IdUploadBack'] = [_idBack!];

      // Client-side validation: ensure required text fields and files are present
      final clientErrors = <String, String>{};
      if (fields['businessName'] == null || fields['businessName']!.isEmpty) clientErrors['businessName'] = 'Business name is required';
      if (fields['country'] == null || fields['country']!.isEmpty) clientErrors['country'] = 'Country is required';
      if (fields['state'] == null || fields['state']!.isEmpty) clientErrors['state'] = 'State is required';
      if (fields['lga'] == null || fields['lga']!.isEmpty) clientErrors['lga'] = 'LGA is required';
      if (fields['IdType'] == null || fields['IdType']!.isEmpty) clientErrors['IdType'] = 'ID type is required';
      if (fields['serviceCategory'] == null || fields['serviceCategory']!.isEmpty) clientErrors['serviceCategory'] = 'Service category is required';
      if (fields['yearsExperience'] == null || fields['yearsExperience']!.isEmpty) clientErrors['yearsExperience'] = 'Years of experience is required';

      if (!files.containsKey('profileImage') || files['profileImage']!.isEmpty) clientErrors['profileImage'] = 'Profile image is required';
      if (!files.containsKey('IdUploadFront') || files['IdUploadFront']!.isEmpty) clientErrors['IdUploadFront'] = 'ID front image is required';
      if (!files.containsKey('IdUploadBack') || files['IdUploadBack']!.isEmpty) clientErrors['IdUploadBack'] = 'ID back image is required';

      if (clientErrors.isNotEmpty) {
        setState(() {
          _fieldErrors = clientErrors;
          _isSubmitting = false;
          _error = 'Please fix the highlighted fields.';
        });
        return;
      }

      final token = AppStateNotifier.instance.token;
      if (token == null || token.isEmpty) {
        setState(() {
          _isSubmitting = false;
          _error = 'You must be signed in to submit KYC. Please login and try again.';
        });
        return;
      }
      // Validate yearsExperience is numeric and non-negative
      final y = int.tryParse(fields['yearsExperience'] ?? '');
      if (y == null || y < 0) {
        setState(() {
          _isSubmitting = false;
          _fieldErrors = {'yearsExperience': 'Enter a valid non-negative number'};
          _error = 'Please correct the highlighted fields.';
        });
        return;
      }
      // Use the enhanced submit which will try direct signed uploads and
      // sensible JSON fallbacks when the server rejects multipart.
      final resp = await KycService.submitKycEnhanced(fields, files, token: token);

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        setState(() {
          _successMessage = 'KYC submitted successfully! Your application is under review.';
        });

        try {
          // Save a 'pending' status so the app knows the submission is awaiting admin review
          await TokenStorage.saveKycStatus('pending');
          // Keep kycVerified false until admin approves
          await TokenStorage.saveKycVerified(false);
         } catch (_) {}

        // Navigate back after delay
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            Navigator.pop(context);
          }
        });
      } else {
        // Try to parse structured field errors first
        final parsed = parseFieldErrors(resp);

        if (parsed.isNotEmpty) {
          setState(() {
            _fieldErrors = parsed;
            _error = 'Please fix the highlighted fields.';
          });
        } else {
          if (kDebugMode) {
            debugPrint('KYC submit non-2xx body: ${resp.body}');
          }
          setState(() {
            _error = 'Failed to submit KYC. Please try again later.';
          });
        }
      }
    } catch (e, st) {
      // Handle the user-friendly exception separately so the UI shows a
      // concise message while developer details are logged in debug builds.
      if (e is UserFriendlyException) {
        if (kDebugMode && e.developerMessage != null) {
          debugPrint('KYC submit developer message: ${e.developerMessage}');
        }
        setState(() {
          _error = e.userMessage;
        });
      } else {
        if (kDebugMode) debugPrint('Unexpected error in KYC submit: $e\n$st');
        setState(() {
          _error = 'An unexpected error occurred. Please try again.';
        });
      }
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
   }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color primaryColor = const Color(0xFFA20025);

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        backgroundColor: isDark ? Colors.black : Colors.white,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header with back button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded),
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                      onPressed: () => Navigator.pop(context),
                      iconSize: 32,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Complete KYC',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
              ),

              // Step indicator
              _buildStepIndicator(),

              // Step content
              Expanded(
                child: _buildStepContent(),
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
                  children: [
                    // Error/Success messages
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

                    if (_successMessage != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.green.withOpacity(0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _successMessage!,
                                style: const TextStyle(
                                  color: Colors.green,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Buttons
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
                            onPressed: _isSubmitting ? null : _nextStep,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: _isSubmitting
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
                              _currentStep == 2 ? 'SUBMIT' : 'CONTINUE',
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
        ),
      ),
    );
  }
}
