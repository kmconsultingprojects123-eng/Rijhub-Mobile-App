import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'create_job_page1_model.dart';
import 'package:go_router/go_router.dart';
import '../../services/user_service.dart';
import '../../services/job_service.dart';
import '../../services/location_service.dart';
import '../../utils/app_notification.dart';
import '../../utils/error_messages.dart';
import '../../services/navigation_service.dart';
import '../../services/my_service_service.dart';
// ...existing code... (removed rootBundle/json import)
export 'create_job_page1_model.dart';

class CreateJobPage1Widget extends StatefulWidget {
  const CreateJobPage1Widget({super.key});

  static String routeName = 'CreateJobPage1';
  static String routePath = '/createJobPage1';

  @override
  State<CreateJobPage1Widget> createState() => _CreateJobPage1WidgetState();
}

class _CreateJobPage1WidgetState extends State<CreateJobPage1Widget> {
  late CreateJobPage1Model _model;

    // Minimalist color scheme
    final Color _primaryColor = const Color(0xFFA20025);
    final Color _textPrimary = const Color(0xFF111827);
    final Color _textSecondary = const Color(0xFF6B7280);
    final Color _textSecondaryDark = const Color(0xFF9CA3AF);
    final Color _borderColor = const Color(0xFFE5E7EB);

  // Form state
  final ScrollController _scrollController = ScrollController();
  int _currentStep = 0;
  final int _totalSteps = 4;
  DateTime? _selectedDeadline;
  String? _formErrorMessage;
  bool _submitting = false;
  bool _checkingAuth = true;

    // Job categories
    List<Map<String, dynamic>> _categories = [];
    List<String> _categoryNames = [];
    String? _selectedCategoryId;

    // Experience levels (UI choices limited to backend-supported values)
    final List<String> _experienceLevels = [
      'Entry',
      'Mid',
      'Senior',
    ];
    String? _selectedExperienceLevel;

    // Sub-services (job subcategories) and search
    List<Map<String, dynamic>> _subservices = [];
    List<Map<String, dynamic>> _filteredSubservices = [];
    // Support multiple selected sub-services
    List<String> _selectedSubserviceIds = [];
    List<String> _selectedSubserviceNames = [];
    final TextEditingController _serviceSearchController = TextEditingController();
    bool _loadingSubservices = false;

    // (location uses free-text input; lat/lon auto-filled on blur)

  final scaffoldKey = GlobalKey<ScaffoldState>();
  final _formKey = GlobalKey<FormState>();

  // Form controllers
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _companyController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _budgetController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _skillsController = TextEditingController();
   // Note: latitude/longitude are displayed as plain text below the Location input.
  double? _jobLat;
  double? _jobLon;
  bool _isGeocoding = false;

  // Focus nodes
  final FocusNode _titleFocusNode = FocusNode();
  final FocusNode _companyFocusNode = FocusNode();
  final FocusNode _locationFocusNode = FocusNode();
  final FocusNode _budgetFocusNode = FocusNode();
  final FocusNode _descriptionFocusNode = FocusNode();
  // _skillsFocusNode was removed after converting skills to sub-service selector

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => CreateJobPage1Model());

    // Initialize any FlutterFlow-specific controllers
    _model.textController1 ??= TextEditingController();
    _model.textFieldFocusNode1 ??= FocusNode();

    // Check authentication
    _checkAuthentication();

    // Fetch job categories
    _fetchCategories();

    // Prefill location from user's profile
    _prefillLocation();

    // Fetch all sub-services (will optionally be filtered by category later)
    _fetchSubservices();

    // Setup geocoding on location blur
    _locationFocusNode.addListener(() {
      if (!_locationFocusNode.hasFocus) {
        final place = _locationController.text.trim();
        if (place.isNotEmpty) {
          _geocodeLocation(place);
        }
      }
    });
  }

  Future<void> _checkAuthentication() async {
    try {
      await AppStateNotifier.instance.refreshAuth();
      if (!AppStateNotifier.instance.loggedIn) {
        if (!mounted) return;
        try {
          GoRouter.of(context).go('/splash');
        } catch (_) {
          try {
            await NavigationService.instance.go(context, '/splash');
          } catch (_) {
            if (appNavigatorKey.currentState != null) {
              appNavigatorKey.currentState!.pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const SplashScreenPage2Widget()),
                    (Route<dynamic> route) => false,
              );
            }
          }
        }
        return;
      }
    } catch (_) {
      if (mounted) {
        try {
          await NavigationService.instance.go(context, '/splash');
        } catch (_) {
          if (appNavigatorKey.currentState != null) {
            appNavigatorKey.currentState!.pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const SplashScreenPage2Widget()),
                  (Route<dynamic> route) => false,
            );
          }
        }
      }
    } finally {
      if (mounted) {
        setState(() => _checkingAuth = false);
      }
    }
  }

  Future<void> _fetchCategories() async {
    try {
      final categories = await JobService.getJobCategories();
      if (mounted) {
        setState(() {
          _categories = categories;
          _categoryNames = categories
              .map((c) => (c['name'] ?? '').toString())
              .where((n) => n.isNotEmpty)
              .toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchSubservices({String? categoryId}) async {
    if (!mounted) return;
    setState(() { _loadingSubservices = true; });
    try {
      final svc = MyServiceService();
      final resp = await svc.fetchSubcategories(context: context, categoryId: categoryId);
      List<Map<String, dynamic>> list = [];
      if (resp.ok && resp.data != null) {
        final data = resp.data;
        if (data is List) {
          list = data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        } else if (data is Map && data['data'] is List) {
          list = List<Map<String, dynamic>>.from(data['data'].map((e) => Map<String, dynamic>.from(e)));
        } else if (data is Map && data['items'] is List) {
          list = List<Map<String, dynamic>>.from(data['items'].map((e) => Map<String, dynamic>.from(e)));
        } else if (data is Map) {
          list = [Map<String, dynamic>.from(data)];
        }
      }

      if (mounted) {
        setState(() {
          _subservices = list;
          _filteredSubservices = List<Map<String, dynamic>>.from(list);
        });
        try {
          debugPrint('Fetched ${list.length} subservices for selector');
          if (list.isNotEmpty) {
            final sample = list.take(3).map((e) => ((e['_id'] ?? e['id'])?.toString() ?? 'no-id') + ':' + ((e['name'] ?? e['title'] ?? e['label'])?.toString() ?? 'no-name')).join(', ');
            debugPrint('Sample subservices: $sample');
          }
        } catch (_) {}
      }
    } catch (e) {
      // ignore errors but keep UI responsive
    } finally {
      if (mounted) setState(() { _loadingSubservices = false; });
    }
  }

  Future<void> _prefillLocation() async {
    try {
      final loc = await UserService.getCanonicalLocation();
      final addr = loc['address'] as String?;
      final lat = loc['latitude'] as double?;
      final lon = loc['longitude'] as double?;
      if (addr != null && addr.isNotEmpty && _locationController.text.isEmpty) _locationController.text = addr;
      if (lat != null && lon != null && (_jobLat == null || _jobLon == null)) {
        _jobLat = lat;
        _jobLon = lon;
      }
    } catch (_) {}
  }

  Future<void> _geocodeLocation(String place) async {
    if (place.trim().isEmpty) return;
    if (mounted) setState(() { _isGeocoding = true; _jobLat = null; _jobLon = null; });
    try {
      final result = await LocationService.geocodePlace(place);
      if (result != null && mounted) {
        setState(() {
          // Expect result to have 'lat' and 'lon' doubles
          final rlat = result['lat'];
          final rlon = result['lon'];
          _jobLat = (rlat is num) ? rlat.toDouble() : double.tryParse(rlat?.toString() ?? '');
          _jobLon = (rlon is num) ? rlon.toDouble() : double.tryParse(rlon?.toString() ?? '');
        });
      }
    } catch (_) {
      // ignore geocode errors
    } finally {
      if (mounted) setState(() => _isGeocoding = false);
    }
  }

    // ...existing code... (removed LGA helpers; geocoding triggered on location blur)

  void _nextStep() {
    if (_currentStep < _totalSteps - 1) {
      setState(() => _currentStep += 1);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToTop());
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep -= 1);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToTop());
    }
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  String? _validateRequired(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter $fieldName';
    }
    return null;
  }

  Future<void> _submitJob() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _formErrorMessage = null;
      _submitting = true;
    });

    try {
      // Ensure coordinates are available
      if (_jobLat == null || _jobLon == null) {
        final place = _locationController.text.trim();
        if (place.isNotEmpty) {
          await _geocodeLocation(place);
        }
      }

      // Coordinates (use geocoded doubles)
      final List<double> coordinates = [];
      if (_jobLat != null && _jobLon != null) {
        coordinates.add(_jobLon!);
        coordinates.add(_jobLat!);
      }

      // Parse skills - prefer the selected sub-services (multiple) if present, otherwise fall back to legacy text input
      List<String> skills = [];
      if (_selectedSubserviceIds.isNotEmpty) {
        skills = List<String>.from(_selectedSubserviceNames);
      } else {
        skills = _skillsController.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }

       // Require at least one skill/sub-service selection
       if (skills.isEmpty) {
         final msg = 'Please select a required service or enter required skills.';
         if (mounted) {
           setState(() => _formErrorMessage = msg);
           AppNotification.showError(context, msg);
         }
         setState(() => _submitting = false);
         return;
       }

       // Parse budget
       final budgetString = _budgetController.text.replaceAll(RegExp(r'[^0-9.]'), '');
       final budget = double.tryParse(budgetString);

       // Map the UI labels to the backend tokens. Backend supports only
       // 'entry', 'mid', and 'senior'. Ensure we only send one of these.
       final Map<String, String> _experienceMap = {
         'Entry': 'entry',
         'Mid': 'mid',
         'Senior': 'senior',
       };

       final experienceToken = _selectedExperienceLevel != null ? _experienceMap[_selectedExperienceLevel!] : null;
       if (_selectedExperienceLevel != null && experienceToken == null) {
         // Give a clear user-facing error listing allowed choices and stop submission
         final allowed = _experienceMap.keys.join(', ');
         final friendly = 'Please select a valid experience level. Allowed: $allowed';
         if (mounted) {
           setState(() => _formErrorMessage = friendly);
           AppNotification.showError(context, friendly);
         }
         return;
       }

       final payload = {
         'title': _titleController.text.trim(),
         'company': _companyController.text.trim(),
         'description': _descriptionController.text.trim(),
         'trade': skills.isNotEmpty ? skills : null,
         'location': _locationController.text.trim(),
         'coordinates': coordinates.isNotEmpty ? coordinates : null,
         'budget': budget,
         'schedule': _selectedDeadline?.toIso8601String(),
         'categoryId': _selectedCategoryId,
        // Include first selected id for backward compatibility and a list of ids
         'subCategoryId': _selectedSubserviceIds.isNotEmpty ? _selectedSubserviceIds.first : null,
         'subCategoryIds': _selectedSubserviceIds.isNotEmpty ? _selectedSubserviceIds : null,
         'experienceLevel': experienceToken,
       };

      // Remove null or empty values
      payload.removeWhere((key, value) =>
      value == null ||
          (value is String && value.trim().isEmpty) ||
          (value is List && value.isEmpty));

      await JobService.createJob(payload);

      if (mounted) {
        AppNotification.showSuccess(context, 'Job created successfully');
        // After creating a job, return to the previous page with a truthy result
        // so the caller can refresh its list if needed (e.g. jobPostPage).
        // Use pop(true) instead of navigating to a new route or using context.go().
        try {
          // Prefer go_router's context.pop when available
          context.pop(true);
        } catch (_) {
          // Fallback to Navigator if pop extension isn't available
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      if (mounted) {
        final msg = ErrorMessages.humanize(e);
        // Show the human-friendly message directly (no duplicate prefix)
        setState(() => _formErrorMessage = msg);
        AppNotification.showError(context, msg);
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  // Helper colors (theme-aware)
  Color _getPrimaryColor(BuildContext context) => _primaryColor;
  Color _getTextPrimary(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? Colors.white : _textPrimary;
  Color _getTextSecondary(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? _textSecondaryDark : _textSecondary;
  Color _getBorderColor(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? const Color(0xFF374151) : _borderColor;
  Color _getSurfaceColor(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0B1220) : Colors.white;

  Widget _buildStepIndicator() {
    return Column(
      children: [
        SizedBox(
          height: 4,
          child: LayoutBuilder(builder: (context, constraints) {
            final totalWidth = constraints.maxWidth;
            return Row(
              children: List.generate(_totalSteps, (index) {
                final width = (totalWidth - (_totalSteps - 1) * 4) / _totalSteps;
                return Container(
                  width: width,
                  height: 4,
                  margin: EdgeInsets.only(right: index == _totalSteps - 1 ? 0 : 4),
                  decoration: BoxDecoration(
                    color: index <= _currentStep ? _getPrimaryColor(context) : _getBorderColor(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                );
              }),
            );
          }),
        ),
        const SizedBox(height: 12),
        Text(
          'Step ${_currentStep + 1} of $_totalSteps',
          style: TextStyle(
            fontSize: 12,
            color: _getTextSecondary(context),
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _buildFormField({
    required String label,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String? Function(String?) validator,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    String hintText = '',
    bool required = true,
  }) {
    return Builder(builder: (context) {
      final textPrimary = _getTextPrimary(context);
      final textSecondary = _getTextSecondary(context);
      final borderColor = _getBorderColor(context);
      final fillColor = _getSurfaceColor(context);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: textPrimary,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            focusNode: focusNode,
            keyboardType: keyboardType,
            maxLines: maxLines,
            style: TextStyle(
              fontSize: 15,
              color: textPrimary,
            ),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(
                fontSize: 15,
                color: textSecondary,
              ),
              filled: true,
              fillColor: fillColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor, width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _getPrimaryColor(context), width: 1.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.red, width: 1),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
            validator: required ? validator : null,
          ),
          const SizedBox(height: 20),
        ],
      );
    });
  }

  Widget _buildServiceSelector() {
    return Builder(builder: (context) {
      final textPrimary = _getTextPrimary(context);
      final textSecondary = _getTextSecondary(context);
      final borderColor = _getBorderColor(context);
      final surface = _getSurfaceColor(context);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Required Service',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: textPrimary,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => _openServiceSelector(),
            child: Container(
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: 1),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: (_selectedSubserviceNames.isEmpty)
                        ? Text(
                            'Select services',
                            style: TextStyle(fontSize: 15, color: textSecondary),
                          )
                        : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: _selectedSubserviceNames.map((name) {
                                return Padding(
                                   padding: const EdgeInsets.only(right: 8.0),
                                   child: Chip(
                                     label: Text(name, style: TextStyle(color: textPrimary)),
                                     backgroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.white12 : Colors.grey[200],
                                     onDeleted: () {
                                       setState(() {
                                         final removeIndex = _selectedSubserviceNames.indexOf(name);
                                         if (removeIndex >= 0) {
                                           _selectedSubserviceNames.removeAt(removeIndex);
                                           if (_selectedSubserviceIds.length > removeIndex) _selectedSubserviceIds.removeAt(removeIndex);
                                         }
                                       });
                                     },
                                   ),
                                 );
                              }).toList(),
                            ),
                          ),
                  ),
                  Icon(Icons.keyboard_arrow_down_rounded, color: textSecondary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      );
    });
  }

  void _onServiceSearchChanged(String value) {
    final q = value.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() { _filteredSubservices = List<Map<String, dynamic>>.from(_subservices); });
      return;
    }
    setState(() {
      _filteredSubservices = _subservices.where((s) {
        final n = (s['name'] ?? s['title'] ?? s['label'] ?? '').toString().toLowerCase();
        return n.contains(q);
      }).toList();
    });
  }

      Future<void> _openServiceSelector() async {
     // If there is a selected category, try to fetch subservices for it to narrow the list
     if (_selectedCategoryId != null) {
       await _fetchSubservices(categoryId: _selectedCategoryId);
     } else if (_subservices.isEmpty) {
       await _fetchSubservices();
     }

     _serviceSearchController.text = '';
     _onServiceSearchChanged('');

     // Local copies for multi-select that persist across bottom-sheet rebuilds
     final List<String> localSelectedIds = List<String>.from(_selectedSubserviceIds);
     final List<String> localSelectedNames = List<String>.from(_selectedSubserviceNames);
    // Local filtered list used by the bottom-sheet so search updates are responsive
    List<Map<String, dynamic>> localFiltered = List<Map<String, dynamic>>.from(_subservices);

    // Debug: log how many subservices are available when opening selector
    try {
      debugPrint('Opening service selector: ${_subservices.length} total subservices, ${localSelectedIds.length} preselected');
    } catch (_) {}

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setBottomState) {

          // Local search helper for the bottom-sheet
          void _localSearch(String v) {
            final q = v.trim().toLowerCase();
            if (q.isEmpty) {
              localFiltered = List<Map<String, dynamic>>.from(_subservices);
            } else {
              localFiltered = _subservices.where((s) {
                final n = (s['name'] ?? s['title'] ?? s['label'] ?? '').toString().toLowerCase();
                return n.contains(q);
              }).toList();
            }
            setBottomState(() {});
          }

          void _toggleItem(Map<String, dynamic> s) {
             final id = (s['_id'] ?? s['id'])?.toString();
             final name = (s['name'] ?? s['title'] ?? s['label'])?.toString() ?? '';
             if (id == null) return;
             final idx = localSelectedIds.indexOf(id);
             if (idx >= 0) {
               localSelectedIds.removeAt(idx);
               if (localSelectedNames.length > idx) localSelectedNames.removeAt(idx);
               try { debugPrint('Deselected subservice: $id'); } catch (_) {}
              } else {
                localSelectedIds.add(id);
                localSelectedNames.add(name);
                try { debugPrint('Selected subservice: $id ($name)'); } catch (_) {}
              }
              setBottomState(() {});
           }

          return Padding(
            padding: MediaQuery.of(ctx).viewInsets,
            child: Container(
              height: MediaQuery.of(ctx).size.height * 0.7,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Select services', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      TextButton(
                        onPressed: () {
                          // Commit selection to parent state
                          setState(() {
                            _selectedSubserviceIds = List<String>.from(localSelectedIds);
                            _selectedSubserviceNames = List<String>.from(localSelectedNames);
                          });
                          try { debugPrint('Committed ${_selectedSubserviceIds.length} selected subservices'); } catch (_) {}
                           Navigator.of(ctx).pop();
                         },
                         child: Text('Done'),
                       ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: _serviceSearchController,
                      decoration: InputDecoration(
                        hintText: 'Search services',
                        prefixIcon: Icon(Icons.search, color: _getTextSecondary(context)),
                        filled: true,
                        fillColor: _getSurfaceColor(context),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _getBorderColor(context))),
                      ),
                      onChanged: (v) {
                        _localSearch(v);
                      },
                    ),
                  ),
                  Expanded(
                    child: _loadingSubservices
                        ? Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(_getPrimaryColor(context))))
                        : localFiltered.isEmpty
                            ? Center(child: Text('No services found', style: TextStyle(color: _getTextSecondary(context))))
                            : ListView.separated(
                                itemCount: localFiltered.length,
                                separatorBuilder: (_, __) => Divider(height: 1),
                                itemBuilder: (context, i) {
                                  final s = localFiltered[i];
                                   final id = (s['_id'] ?? s['id'])?.toString();
                                   final name = (s['name'] ?? s['title'] ?? s['label'])?.toString() ?? '';
                                   final checked = id != null && localSelectedIds.contains(id);
                                   return CheckboxListTile(
                                     key: id != null ? ValueKey('subsvc_$id') : null,
                                     value: checked,
                                     onChanged: (_) { _toggleItem(s); },
                                     title: Text(name),
                                     subtitle: s['description'] != null ? Text(s['description'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis) : null,
                                     controlAffinity: ListTileControlAffinity.trailing,
                                   );
                                },
                               ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
   }

  Widget _buildDropdown({
    required String label,
    required List<String> options,
    required String? value,
    required void Function(String?) onChanged,
    String hintText = 'Select',
  }) {
    return Builder(builder: (context) {
      final textPrimary = _getTextPrimary(context);
      final textSecondary = _getTextSecondary(context);
      final borderColor = _getBorderColor(context);
      final surface = _getSurfaceColor(context);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: textPrimary,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: value,
                  hint: Text(
                    hintText,
                    style: TextStyle(
                      fontSize: 15,
                      color: textSecondary,
                    ),
                  ),
                  isExpanded: true,
                  items: options.map((option) {
                    return DropdownMenuItem<String>(
                      value: option,
                      child: Text(
                        option,
                        style: TextStyle(
                          fontSize: 15,
                          color: textPrimary,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: onChanged,
                  style: TextStyle(
                    fontSize: 15,
                    color: textPrimary,
                  ),
                  icon: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: textSecondary,
                    size: 20,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  elevation: 2,
                  dropdownColor: surface,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      );
    });
  }

  Widget _buildDatePicker() {
    return Builder(builder: (context) {
      final textPrimary = _getTextPrimary(context);
      final textSecondary = _getTextSecondary(context);
      final borderColor = _getBorderColor(context);
      final surface = _getSurfaceColor(context);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Application Deadline',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: textPrimary,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedDeadline ?? now,
                firstDate: now,
                lastDate: DateTime(now.year + 5),
                builder: (context, child) {
                  final isDark = Theme.of(context).brightness == Brightness.dark;
                  return Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: isDark
                          ? ColorScheme.dark(
                        primary: _getPrimaryColor(context),
                        onPrimary: Colors.white,
                        surface: surface,
                        onSurface: textPrimary,
                      )
                          : ColorScheme.light(
                        primary: _getPrimaryColor(context),
                        onPrimary: Colors.white,
                        surface: surface,
                        onSurface: textPrimary,
                      ),
                      dialogTheme: DialogThemeData(
                        backgroundColor: surface,
                      ),
                    ),
                    child: child!,
                  );
                },
              );
              if (picked != null && mounted) {
                setState(() => _selectedDeadline = picked);
              }
            },
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: _getSurfaceColor(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: 1),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _selectedDeadline != null
                          ? DateFormat('MMM dd, yyyy').format(_selectedDeadline!)
                          : 'Select date',
                      style: TextStyle(
                        fontSize: 15,
                        color: _selectedDeadline != null ? textPrimary : textSecondary,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 18,
                    color: textSecondary,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      );
    });
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return Column(
          children: [
            _buildFormField(
              label: 'Job Title',
              controller: _titleController,
              focusNode: _titleFocusNode,
              validator: (value) => _validateRequired(value, 'job title'),
              hintText: 'e.g. Senior Software Engineer',
            ),
            _buildFormField(
              label: 'Company Name / Owners Name',
              controller: _companyController,
              focusNode: _companyFocusNode,
              validator: (value) => _validateRequired(value, 'company name'),
              hintText: 'Your company name',
            ),
          ],
        );

      case 1:
        return Column(
          children: [
            // Location free-text input (geocodes on blur and fills lat/lon)
            _buildFormField(
              label: 'Location',
              controller: _locationController,
              focusNode: _locationFocusNode,
              validator: (value) => _validateRequired(value, 'location'),
              hintText: 'City, State or full address',
            ),
            // Latitude/Longitude are intentionally hidden from the UI but are
            // still captured by the geocoding logic and submitted in the
            // payload as `coordinates`. Do not remove the _jobLat/_jobLon
            // fields or the geocoding that sets them.
           ],
         );

      case 2:
        return Column(
          children: [
            _buildFormField(
              label: 'Budget',
              controller: _budgetController,
              focusNode: _budgetFocusNode,
              validator: (value) {
                if (value == null || value.trim().isEmpty) return null;
                final n = double.tryParse(value.replaceAll(RegExp(r'[^0-9.]'), ''));
                if (n == null) return 'Please enter a valid number';
                return null;
              },
              keyboardType: TextInputType.number,
              hintText: 'e.g. 25000',
              required: false,
            ),
            _buildFormField(
              label: 'Job Description',
              controller: _descriptionController,
              focusNode: _descriptionFocusNode,
              validator: (value) => _validateRequired(value, 'job description'),
              maxLines: 5,
              hintText: 'Describe the role, responsibilities, and requirements...',
            ),
          ],
        );

      case 3:
        return Column(
          children: [
            // Replace free-text skills with a searchable sub-service selector
            _buildServiceSelector(),
             _buildDropdown(
               label: 'Experience Level',
               options: _experienceLevels,
               value: _selectedExperienceLevel,
               onChanged: (value) {
                 setState(() => _selectedExperienceLevel = value);
               },
               hintText: 'Select experience level',
             ),
             _buildDatePicker(),
           ],
         );

      default:
        return Container();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _model.dispose();
    _serviceSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingAuth) {
      return Scaffold(
        backgroundColor: _getSurfaceColor(context),
        body: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(_getPrimaryColor(context)),
            ),
          ),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = _getSurfaceColor(context);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: backgroundColor,
        appBar: AppBar(
          backgroundColor: backgroundColor,
          elevation: 0,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_rounded,
              color: isDark ? Colors.white : _getTextPrimary(context),
              size: 24,
            ),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: Text(
            'Create Job',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w400,
              color: isDark ? Colors.white : _getTextPrimary(context),
              letterSpacing: -0.5,
            ),
          ),
          centerTitle: false,
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Step indicator
                    _buildStepIndicator(),

                    const SizedBox(height: 32),

                    // Step content
                    _buildStepContent(),

                    // Error message
                    if (_formErrorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Text(
                          _formErrorMessage!,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.red,
                          ),
                        ),
                      ),

                    // Navigation buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Back button
                        if (_currentStep > 0)
                          TextButton(
                            onPressed: _prevStep,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              foregroundColor: _primaryColor,
                              side: BorderSide(color: _primaryColor),
                            ),
                            child: const Text('Back'),
                          )
                        else
                          const SizedBox(width: 100),

                        // Next/Submit button
                        ElevatedButton(
                          onPressed: _currentStep < _totalSteps - 1
                              ? _nextStep
                              : _submitting ? null : _submitJob,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: _currentStep < _totalSteps - 1
                              ? const Text('Continue')
                              : _submitting
                              ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                              : const Text('Publish Job'),
                        ),
                      ],
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

}
