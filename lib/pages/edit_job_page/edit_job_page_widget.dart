import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:go_router/go_router.dart';
import '../../services/job_service.dart';
import '../../services/location_service.dart';
import '../../utils/app_notification.dart';
import '../../utils/error_messages.dart';
import '../../services/my_service_service.dart';
import '../../utils/job_events.dart';

class EditJobPageWidget extends StatefulWidget {
  final Map<String, dynamic> job;

  const EditJobPageWidget({
    Key? key,
    required this.job
  }) : super(key: key);

  static String routeName = 'EditJobPage';
  static String routePath = '/editJobPage';

  @override
  State<EditJobPageWidget> createState() => _EditJobPageWidgetState();
}

class _EditJobPageWidgetState extends State<EditJobPageWidget> {
  // Minimalist color scheme (matches CreateJobPage1)
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
  bool _loading = true;

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
  List<String> _selectedSubserviceIds = [];
  List<String> _selectedSubserviceNames = [];
  final TextEditingController _serviceSearchController = TextEditingController();
  bool _loadingSubservices = false;

  final scaffoldKey = GlobalKey<ScaffoldState>();
  final _formKey = GlobalKey<FormState>();

  // Form controllers
  late TextEditingController _titleController;
  late TextEditingController _companyController;
  late TextEditingController _locationController;
  late TextEditingController _budgetController;
  late TextEditingController _descriptionController;
  late TextEditingController _skillsController;

  // Coordinates
  double? _jobLat;
  double? _jobLon;
  bool _isGeocoding = false;

  // Focus nodes
  final FocusNode _titleFocusNode = FocusNode();
  final FocusNode _companyFocusNode = FocusNode();
  final FocusNode _locationFocusNode = FocusNode();
  final FocusNode _budgetFocusNode = FocusNode();
  final FocusNode _descriptionFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Initialize controllers with job data
    _initializeControllers();
    // Attempt to fetch a fresh copy of the job if the provided job seems partial
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeFetchFullJob());
  }

  void _initializeControllers() {
    final job = widget.job;

    // Basic fields
    _titleController = TextEditingController(
        text: (job['title'] ?? job['jobTitle'] ?? '').toString()
    );

    // Accept several common keys used across the app/api for company and location.
    String extractString(dynamic v) {
      if (v == null) return '';
      if (v is String) return v;
      if (v is Map) return (v['name'] ?? v['title'] ?? v['label'] ?? v['address'] ?? '').toString();
      return v.toString();
    }

    _companyController = TextEditingController(
      text: extractString(job['company'] ?? job['employer'] ?? job['companyName'] ?? job['company_name'] ?? job['employerName'] ?? job['employer_name'])
    );

    _locationController = TextEditingController(
      text: extractString(job['location'] ?? job['address'] ?? job['venue'] ?? job['place'] ?? job['city'] ?? job['state'] ?? '')
    );

    // Budget - strip non-numeric characters
    final rawBudget = job['budget']?.toString() ?? job['price']?.toString() ?? '';
    _budgetController = TextEditingController(
        text: _stripNumericDot(rawBudget)
    );

    _descriptionController = TextEditingController(
        text: (job['description'] ?? job['details'] ?? '').toString()
    );

    // Skills/trade (fallback)
    _skillsController = TextEditingController(
        text: (job['trade'] is List)
            ? (job['trade'] as List).map((e)=>e?.toString()?.trim() ?? '').where((s)=>s.isNotEmpty).join(', ')
            : (job['trade'] ?? '').toString()
    );

    // Parse coordinates
    try {
      final coords = job['coordinates'];
      if (coords is List && coords.length >= 2) {
        // Stored as [lon, lat]
        _jobLon = (coords[0] is num) ? coords[0].toDouble() : double.tryParse(coords[0].toString());
        _jobLat = (coords[1] is num) ? coords[1].toDouble() : double.tryParse(coords[1].toString());
      } else if (job['geo'] is Map) {
        final geo = job['geo'];
        _jobLat = (geo['lat'] is num) ? geo['lat'].toDouble() : double.tryParse(geo['lat']?.toString() ?? '');
        _jobLon = (geo['lon'] is num) ? geo['lon'].toDouble() : double.tryParse(geo['lon']?.toString() ?? '');
      }
    } catch (_) {}

    // Parse deadline
    try {
      final sched = job['schedule'] ?? job['deadline'] ?? job['dueDate'];
      if (sched != null) {
        final dt = DateTime.tryParse(sched.toString());
        if (dt != null) _selectedDeadline = dt;
      }
    } catch (_) {}

    // Parse category
    _selectedCategoryId = (job['categoryId'] ?? job['category'] ?? job['category_id'])?.toString();

    // Parse experience level and normalize to UI labels (Entry/Mid/Senior).
    // Accept tokens like: 'entry', 'mid', 'senior' or mixed values from different APIs.
    try {
      final rawExpObj = job['experienceLevel'] ?? job['type'] ?? job['experience'] ?? job['experience_level'];
      String? rawExp = rawExpObj is String ? rawExpObj : (rawExpObj?.toString());
      if (rawExp != null && rawExp.trim().isNotEmpty) {
        final low = rawExp.toLowerCase();
        if (low.contains('entry')) _selectedExperienceLevel = 'Entry';
        else if (low.contains('mid')) _selectedExperienceLevel = 'Mid';
        else if (low.contains('senior')) _selectedExperienceLevel = 'Senior';
        else {
          if (low == 'e' || low == 'entry_level' || low == '1') _selectedExperienceLevel = 'Entry';
          else if (low == 'm' || low == 'mid_level' || low == '2') _selectedExperienceLevel = 'Mid';
          else if (low == 's' || low == 'senior_level' || low == '3') _selectedExperienceLevel = 'Senior';
        }
      }
    } catch (_) {}

    // Parse subservice selections (accept ids list, objects list, or names)
    try {
      final dynamic sidsRaw = job['subCategoryIds'] ?? job['sub_category_ids'] ?? job['subCategories'] ?? job['serviceIds'] ?? job['services'];
      if (sidsRaw is List) {
        final ids = <String>[];
        final names = <String>[];
        for (final e in sidsRaw) {
          if (e == null) continue;
          if (e is String || e is num) {
            ids.add(e.toString());
          } else if (e is Map) {
            final id = (e['_id'] ?? e['id'])?.toString();
            final name = (e['name'] ?? e['title'] ?? e['label'])?.toString();
            if (id != null && id.isNotEmpty) ids.add(id);
            if (name != null && name.isNotEmpty) names.add(name);
          }
        }
        if (ids.isNotEmpty) _selectedSubserviceIds = ids;
        if (names.isNotEmpty) _selectedSubserviceNames = names;
      } else if (sidsRaw is String || sidsRaw is num) {
        final s = sidsRaw.toString(); if (s.isNotEmpty) _selectedSubserviceIds = [s];
      }

      final dynamic snames = job['subCategoryNames'] ?? job['sub_category_names'] ?? job['serviceNames'];
      if ((snames is List) && snames.isNotEmpty) {
        _selectedSubserviceNames = snames.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
      }
    } catch (_) {}
    // If we still have no selected subservice names but the job has a `trade` array (names),
    // use those to prefill the UI chips so users see the previously selected services.
    try {
      if ((_selectedSubserviceNames.isEmpty || _selectedSubserviceNames.every((n) => n.trim().isEmpty)) && job['trade'] is List) {
        final fromTrade = (job['trade'] as List).map((e) => e?.toString() ?? '').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        if (fromTrade.isNotEmpty) {
          if (mounted) setState(() { _selectedSubserviceNames = fromTrade; });
        }
      }
    } catch (_) {}

    setState(() { _loading = false; });

    // Debug: log what we extracted for the Edit Job page
    try {
      // ignore: avoid_print
      print('DEBUG EditJobPage: prefill -> title=${_titleController.text}, company=${_companyController.text}, location=${_locationController.text}, subserviceIds=${_selectedSubserviceIds}, subserviceNames=${_selectedSubserviceNames}, experience=${_selectedExperienceLevel}');
    } catch (_) {}
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

        // If we already have selected subservice IDs but no names (coming from the job payload),
        // try to map ids -> names from the fetched list so the selector shows prefilled chips.
        if (_selectedSubserviceNames.isEmpty && _selectedSubserviceIds.isNotEmpty && _subservices.isNotEmpty) {
          final mappedNames = <String>[];
          for (final id in _selectedSubserviceIds) {
            final found = _subservices.firstWhere(
              (s) => ((s['_id'] ?? s['id'])?.toString() ?? '') == id,
              orElse: () => {},
            );
            if (found.isNotEmpty) {
              final name = (found['name'] ?? found['title'] ?? '').toString();
              if (name.isNotEmpty) mappedNames.add(name);
            }
          }
          if (mounted && mappedNames.isNotEmpty) {
            setState(() { _selectedSubserviceNames = mappedNames; });
          }
        }
      }
    } catch (_) {
      // Ignore errors
    } finally {
      if (mounted) setState(() { _loadingSubservices = false; });
    }
  }

  Future<void> _geocodeLocation(String place) async {
    if (place.trim().isEmpty) return;
    if (mounted) setState(() { _isGeocoding = true; });
    try {
      final result = await LocationService.geocodePlace(place);
      if (result != null && mounted) {
        setState(() {
          final rlat = result['lat'];
          final rlon = result['lon'];
          _jobLat = (rlat is num) ? rlat.toDouble() : double.tryParse(rlat?.toString() ?? '');
          _jobLon = (rlon is num) ? rlon.toDouble() : double.tryParse(rlon?.toString() ?? '');
        });
      }
    } catch (_) {
      // Ignore geocode errors
    } finally {
      if (mounted) setState(() => _isGeocoding = false);
    }
  }

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

  Future<void> _updateJob() async {
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

      // Parse skills - prefer selected sub-services
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
          setState(() { _formErrorMessage = msg; });
          AppNotification.showError(context, msg);
        }
        setState(() { _submitting = false; });
        return;
      }

      // Parse budget
      final budgetString = _budgetController.text.replaceAll(RegExp(r'[^0-9.]'), '');
      final budget = double.tryParse(budgetString);

      // Map UI labels to backend tokens
      final Map<String, String> _experienceMap = {
        'Entry': 'entry',
        'Mid': 'mid',
        'Senior': 'senior',
      };

      final experienceToken = _selectedExperienceLevel != null
          ? _experienceMap[_selectedExperienceLevel!]
          : null;

      if (_selectedExperienceLevel != null && experienceToken == null) {
        final allowed = _experienceMap.keys.join(', ');
        final friendly = 'Please select a valid experience level. Allowed: $allowed';
        if (mounted) {
          setState(() { _formErrorMessage = friendly; });
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
        'subCategoryId': _selectedSubserviceIds.isNotEmpty ? _selectedSubserviceIds.first : null,
        'subCategoryIds': _selectedSubserviceIds.isNotEmpty ? _selectedSubserviceIds : null,
        'experienceLevel': experienceToken,
      };

      // Remove null or empty values
      payload.removeWhere((key, value) =>
      value == null ||
          (value is String && value.trim().isEmpty) ||
          (value is List && value.isEmpty));

      final jobId = (widget.job['_id'] ?? widget.job['id'] ?? widget.job['jobId'])?.toString();
      if (jobId == null || jobId.isEmpty) {
        throw Exception('Job ID not found');
      }

      // Debug: print payload just before calling update, to help diagnose why fields are empty or not sent
      try {
        // ignore: avoid_print
        print('DEBUG EditJobPage: submit payload -> $payload');
      } catch (_) {}

      try {
        final resp = await JobService.updateJob(jobId, payload);
        // ignore: avoid_print
        print('DEBUG EditJobPage: update response -> $resp');
        if (mounted) {
          AppNotification.showSuccess(context, 'Job updated successfully');
          try {
            final updatedMap = resp is Map<String, dynamic> ? resp : Map<String, dynamic>.from(resp);
            JobEvents.emitJobUpdated(updatedMap);
            context.pop(updatedMap);
          } catch (_) {
            try { JobEvents.emitJobUpdated(resp as Map<String,dynamic>); context.pop(resp); } catch (_) { context.pop(true); }
          }
        }
      } catch (e, st) {
        // ignore: avoid_print
        print('DEBUG EditJobPage: update failed -> $e');
        // ignore: avoid_print
        print(st);
        if (mounted) {
          final msg = ErrorMessages.humanize(e);
          setState(() { _formErrorMessage = msg; });
          AppNotification.showError(context, msg);
        }
      }
    } catch (e) {
      if (mounted) {
        final msg = ErrorMessages.humanize(e);
        setState(() { _formErrorMessage = msg; });
        AppNotification.showError(context, msg);
      }
    } finally {
      if (mounted) {
        setState(() { _submitting = false; });
      }
    }
  }

  // If the page was opened with only a shallow job object (maybe only id),
  // try to fetch the full job from the API and apply it to controllers so
  // the UI is prefilled for editing.
  Future<void> _maybeFetchFullJob() async {
    try {
      final id = (widget.job['_id'] ?? widget.job['id'] ?? widget.job['jobId'])?.toString() ?? '';
      if (id.isEmpty) return;
      // Always attempt to fetch the full job from the server to ensure we have
      // canonical values for company, location, services and experience.
      // ignore: avoid_print
      print('DEBUG EditJobPage: attempting to fetch full job for id=$id');
      final fetched = await JobService.getJob(id);
      // ignore: avoid_print
      print('DEBUG EditJobPage: fetched job -> $fetched');
      if (fetched.isNotEmpty) {
        // apply to controllers without recreating them
        _applyJobToControllers(fetched);
      }
    } catch (e) {
      // ignore fetch errors — keep existing values
      // ignore: avoid_print
      print('DEBUG EditJobPage: could not fetch full job -> $e');
    }
  }

  void _applyJobToControllers(Map<String, dynamic> job) {
    try {
      // Basic fields
      if (_titleController == null) return; // safety
    } catch (_) {}

    setState(() {
      _titleController.text = (job['title'] ?? job['jobTitle'] ?? '').toString();
      _companyController.text = _extractString(job['company'] ?? job['employer'] ?? job['companyName'] ?? job['company_name'] ?? job['employerName'] ?? '');
      _locationController.text = _extractString(job['location'] ?? job['address'] ?? job['venue'] ?? job['place'] ?? job['city'] ?? job['state'] ?? '');
      _budgetController.text = _stripNumericDot((job['budget'] ?? job['price'] ?? '').toString());
      _descriptionController.text = (job['description'] ?? job['details'] ?? '').toString();
      _skillsController.text = (job['trade'] is List) ? (job['trade'] as List).join(', ') : (job['trade'] ?? '').toString();

      // coordinates
      try {
        final coords = job['coordinates'];
        if (coords is List && coords.length >= 2) {
          _jobLon = (coords[0] is num) ? coords[0].toDouble() : double.tryParse(coords[0].toString());
          _jobLat = (coords[1] is num) ? coords[1].toDouble() : double.tryParse(coords[1].toString());
        }
      } catch (_) {}

      // experience
      try {
        final rawExpObj = job['experienceLevel'] ?? job['type'] ?? job['experience'] ?? job['experience_level'];
        String? rawExp = rawExpObj is String ? rawExpObj : (rawExpObj?.toString());
        if (rawExp != null && rawExp.trim().isNotEmpty) {
          final low = rawExp.toLowerCase();
          if (low.contains('entry')) _selectedExperienceLevel = 'Entry';
          else if (low.contains('mid')) _selectedExperienceLevel = 'Mid';
          else if (low.contains('senior')) _selectedExperienceLevel = 'Senior';
        }
      } catch (_) {}

      // subservices
      try {
        final dynamic sidsRaw = job['subCategoryIds'] ?? job['sub_category_ids'] ?? job['subCategories'] ?? job['serviceIds'] ?? job['services'];
        if (sidsRaw is List) {
          final ids = <String>[];
          final names = <String>[];
          for (final e in sidsRaw) {
            if (e == null) continue;
            if (e is String || e is num) ids.add(e.toString());
            else if (e is Map) {
              final id = (e['_id'] ?? e['id'])?.toString();
              final name = (e['name'] ?? e['title'] ?? e['label'])?.toString();
              if (id != null && id.isNotEmpty) ids.add(id);
              if (name != null && name.isNotEmpty) names.add(name);
            }
          }
          if (ids.isNotEmpty) _selectedSubserviceIds = ids;
          if (names.isNotEmpty) _selectedSubserviceNames = names;
        } else if (sidsRaw is String || sidsRaw is num) {
          final s = sidsRaw.toString(); if (s.isNotEmpty) _selectedSubserviceIds = [s];
        }

        final dynamic snames = job['subCategoryNames'] ?? job['sub_category_names'] ?? job['serviceNames'];
        if ((snames is List) && snames.isNotEmpty) _selectedSubserviceNames = snames.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
      } catch (_) {}
      // If we still have no selected subservice names but the job has a `trade` array (names),
      // use those to prefill the UI chips so users see the previously selected services.
      try {
        if ((_selectedSubserviceNames.isEmpty || _selectedSubserviceNames.every((n) => n.trim().isEmpty)) && job['trade'] is List) {
          final fromTrade = (job['trade'] as List).map((e) => e?.toString() ?? '').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
          if (fromTrade.isNotEmpty) {
            if (mounted) setState(() { _selectedSubserviceNames = fromTrade; });
          }
        }
      } catch (_) {}
    });
    try {
      // ignore: avoid_print
      print('DEBUG EditJobPage: controllers after apply -> title=${_titleController.text}, company=${_companyController.text}, location=${_locationController.text}, services=${_selectedSubserviceNames}, experience=${_selectedExperienceLevel}');
    } catch (_) {}
  }

  String _extractString(dynamic v) {
    if (v == null) return '';
    if (v is String) return v;
    if (v is Map) return (v['name'] ?? v['title'] ?? v['label'] ?? v['address'] ?? '').toString();
    return v.toString();
  }


  // Helper colors (theme-aware) - matches CreateJobPage1
  Color _getPrimaryColor(BuildContext context) => _primaryColor;
  Color _getTextPrimary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? Colors.white : _textPrimary;
  Color _getTextSecondary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? _textSecondaryDark : _textSecondary;
  Color _getBorderColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? const Color(0xFF374151) : _borderColor;
  Color _getSurfaceColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0B1220) : Colors.white;

  // Theme helpers for EditJobFormState (local copy)
  Color _formPrimaryColor(BuildContext context) => const Color(0xFFA20025);
  Color _formTextPrimary(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? Colors.white : const Color(0xFF111827);
  Color _formTextSecondary(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
  Color _formBorderColor(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? const Color(0xFF374151) : const Color(0xFFE5E7EB);
  Color _formSurfaceColor(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0B1220) : Colors.white;

  // Helper to strip non-numeric characters (except dot)
  String _stripNumericDot(String s) {
    if (s.isEmpty) return '';
    final allowed = '0123456789.';
    return s.split('').where((c) => allowed.contains(c)).join();
  }

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

          // Use AnimatedBuilder to react to focus changes on the provided FocusNode
          AnimatedBuilder(
            animation: focusNode,
            builder: (context, _) {
              final isFocused = focusNode.hasFocus;

              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isFocused ? _getPrimaryColor(context) : borderColor, width: isFocused ? 1.5 : 1),
                  color: fillColor,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: TextFormField(
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
                    // Remove the inner border so the surrounding container provides the visual chrome
                    border: InputBorder.none,
                    // Keep the field visually compact since the container handles padding
                    isDense: true,
                    // Preserve prefix/suffix support if callers add them later
                  ),
                  validator: required ? validator : null,
                ),
              );
            },
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
          Text('Required Service', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: textPrimary)),
          const SizedBox(height: 8),
          InkWell(
            onTap: _openServiceSelector,
            child: Container(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: borderColor, width: 1), color: surface),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: _selectedSubserviceNames.isEmpty
                        ? Text('Select services', style: TextStyle(color: textSecondary))
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
                                          if (_selectedSubserviceIds.length > removeIndex) {
                                            _selectedSubserviceIds.removeAt(removeIndex);
                                          }
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
          const SizedBox(height: 8),
          TextFormField(
            controller: _skillsController,
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.build_outlined),
              hintText: 'Skills (comma separated)',
              filled: true,
              fillColor: _getSurfaceColor(context),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
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
    // load subservices if not present
    if (_selectedCategoryId != null) {
      await _fetchSubservices(categoryId: _selectedCategoryId);
    } else if (_subservices.isEmpty) {
      await _fetchSubservices();
    }

    final List<String> localSelectedIds = List<String>.from(_selectedSubserviceIds);
    final List<String> localSelectedNames = List<String>.from(_selectedSubserviceNames);
    List<Map<String, dynamic>> localFiltered = List<Map<String, dynamic>>.from(_subservices);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setBottomState) {
            void _localSearch(String v) {
              final q = v.trim().toLowerCase();
              if (q.isEmpty) {
                localFiltered = List<Map<String, dynamic>>.from(_subservices);
              } else {
                localFiltered = _subservices.where((s) {
                  final n = (s['name'] ?? s['title'] ?? '').toString().toLowerCase();
                  return n.contains(q);
                }).toList();
              }
              setBottomState(() {});
            }

            void _toggleItem(Map<String, dynamic> s) {
              final id = (s['_id'] ?? s['id'])?.toString();
              final name = (s['name'] ?? s['title'])?.toString() ?? '';
              if (id == null) return;
              final idx = localSelectedIds.indexOf(id);
              if (idx >= 0) {
                localSelectedIds.removeAt(idx);
                if (localSelectedNames.length > idx) localSelectedNames.removeAt(idx);
              } else {
                localSelectedIds.add(id);
                localSelectedNames.add(name);
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
                            setState(() {
                              _selectedSubserviceIds = List<String>.from(localSelectedIds);
                              _selectedSubserviceNames = List<String>.from(localSelectedNames);
                            });
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
                        controller: TextEditingController(),
                        decoration: InputDecoration(hintText: 'Search services', prefixIcon: Icon(Icons.search)),
                        onChanged: _localSearch,
                      ),
                    ),
                    Expanded(
                      child: localFiltered.isEmpty
                          ? Center(child: Text('No services found'))
                          : ListView.separated(
                              itemCount: localFiltered.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, i) {
                                final s = localFiltered[i];
                                final id = (s['_id'] ?? s['id'])?.toString();
                                final name = (s['name'] ?? s['title'])?.toString() ?? '';
                                final checked = id != null && localSelectedIds.contains(id);
                                return CheckboxListTile(
                                  value: checked,
                                  onChanged: (_) => _toggleItem(s),
                                  title: Text(name),
                                  controlAffinity: ListTileControlAffinity.trailing,
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
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
            _buildFormField(
              label: 'Location',
              controller: _locationController,
              focusNode: _locationFocusNode,
              validator: (value) => _validateRequired(value, 'location'),
              hintText: 'City, State or full address',
            ),
            // Coordinates are captured but hidden from UI (same as create page)
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
    _serviceSearchController.dispose();
    _titleController.dispose();
    _companyController.dispose();
    _locationController.dispose();
    _budgetController.dispose();
    _descriptionController.dispose();
    _skillsController.dispose();
    _titleFocusNode.dispose();
    _companyFocusNode.dispose();
    _locationFocusNode.dispose();
    _budgetFocusNode.dispose();
    _descriptionFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
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
            'Edit Job',
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

                        // Next/Update button
                        ElevatedButton(
                          onPressed: _currentStep < _totalSteps - 1
                              ? _nextStep
                              : _submitting ? null : _updateJob,
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
                              : const Text('Update Job'),
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
