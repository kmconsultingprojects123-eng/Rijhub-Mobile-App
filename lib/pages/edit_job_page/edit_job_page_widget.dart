import '/flutter_flow/flutter_flow_drop_down.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/form_field_controller.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:intl/intl.dart';
import 'dart:async';
import '../../services/job_service.dart';
import '../../services/location_service.dart';
import '../../utils/error_messages.dart';
import '../../utils/navigation_utils.dart';
import '/main.dart';

class EditJobPageWidget extends StatelessWidget {
  final Map<String, dynamic> job;
  const EditJobPageWidget({Key? key, required this.job}) : super(key: key);

  static const routeName = 'EditJobPage';
  static const routePath = '/editJobPage';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Removed top AppBar so the in-body compact header is used instead.
      backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
      body: Center(
        child: EditJobForm(
          job: job,
          onUpdated: () {
            Navigator.of(context).pop(true);
          },
        ),
      ),
    );
  }
}

/// Reusable form widget for editing a job. Can be embedded in a page or a bottom sheet.
class EditJobForm extends StatefulWidget {
  final Map<String, dynamic> job;
  final VoidCallback? onUpdated;
  // When embedded in a bottom sheet, hide internal header and action buttons
  final bool embedded;
  const EditJobForm({Key? key, required this.job, this.onUpdated, this.embedded = false}) : super(key: key);

  @override
  State<EditJobForm> createState() => EditJobFormState();
}

class EditJobFormState extends State<EditJobForm> {
  final _formKey = GlobalKey<FormState>();
  bool _submitting = false;
  // Expose current submitting state so parent (sheet) can disable the Save button.
  bool get isSubmitting => _submitting;
  String? _formErrorMessage;

  late TextEditingController _titleController;
  late TextEditingController _companyController;
  late TextEditingController _locationController;
  late TextEditingController _budgetController;
  late TextEditingController _descriptionController;
  late TextEditingController _skillsController;

  final TextEditingController _latController = TextEditingController();
  final TextEditingController _lonController = TextEditingController();

  FormFieldController<String>? _categoryDropController;
  List<Map<String, dynamic>> _categories = [];
  List<String> _categoryNames = [];
  String? _selectedCategoryId;

  FormFieldController<String>? _experienceController;
  String? _experienceValue;

  DateTime? _selectedDeadline;
  Timer? _locDebounce;

  @override
  void initState() {
    super.initState();
    final j = widget.job;
    _titleController = TextEditingController(text: (j['title'] ?? '').toString());
    _companyController = TextEditingController(text: (j['company'] ?? '').toString());
    _locationController = TextEditingController(text: (j['location'] ?? j['address'] ?? '').toString());
    // Normalize budget input: strip any currency symbols (dollar/naira) and commas so the field holds a plain number
    final rawBudget = j['budget']?.toString() ?? '';
    final cleanedBudget = rawBudget.replaceAll(RegExp(r'[^0-9.]'), '');
    _budgetController = TextEditingController(text: cleanedBudget);
    _descriptionController = TextEditingController(text: (j['description'] ?? '').toString());
    _skillsController = TextEditingController(text: (j['trade'] is List) ? (j['trade'] as List).join(', ') : (j['trade'] ?? '').toString());

    // coords
    try {
      final coords = j['coordinates'];
      if (coords is List && coords.length >= 2) {
        // stored as [lon, lat]
        _lonController.text = coords[0].toString();
        _latController.text = coords[1].toString();
      }
    } catch (_) {}

    // schedule
    try {
      final sched = j['schedule'] ?? j['deadline'];
      if (sched != null) {
        final dt = DateTime.tryParse(sched.toString());
        if (dt != null) _selectedDeadline = dt;
      }
    } catch (_) {}

    // category id if present
    _selectedCategoryId = (j['categoryId'] ?? j['category'] ?? j['category_id'])?.toString();

    // employment/experience
    _experienceValue = j['type']?.toString() ?? j['experience']?.toString();

    // Load categories
    () async {
      try {
        final cats = await JobService.getJobCategories();
        if (mounted) setState(() {
          _categories = cats;
          _categoryNames = cats.map((c) => (c['name'] ?? '').toString()).where((n) => n.isNotEmpty).toList();
          if (_selectedCategoryId != null) {
            final found = cats.firstWhere((c) => (c['_id']?.toString() ?? c['id']?.toString()) == _selectedCategoryId, orElse: () => {});
            if (found.isNotEmpty) {
              _categoryDropController = FormFieldController<String>(found['name']?.toString());
            } else {
              _categoryDropController ??= FormFieldController<String>(null);
            }
          } else {
            _categoryDropController ??= FormFieldController<String>(null);
          }
        });
      } catch (_) {
        if (mounted) setState(() => _categoryNames = []);
      }
    }();

    // Auto-geocode when user types a location (debounced)
    _locationController.addListener(() {
      if (_locDebounce?.isActive ?? false) _locDebounce!.cancel();
      _locDebounce = Timer(Duration(milliseconds: 800), () async {
        final place = _locationController.text.trim();
        if (place.isEmpty) return;
        try {
          final res = await LocationService.geocodePlace(place);
          if (res != null && mounted) {
            setState(() {
              _latController.text = res['lat']?.toString() ?? '';
              _lonController.text = res['lon']?.toString() ?? '';
            });
          }
        } catch (_) {}
      });
    });
  }

  @override
  void dispose() {
    _locDebounce?.cancel();
    _titleController.dispose();
    _companyController.dispose();
    _locationController.dispose();
    _budgetController.dispose();
    _descriptionController.dispose();
    _skillsController.dispose();
    _latController.dispose();
    _lonController.dispose();
    super.dispose();
  }

  // Exposed submit method so parent (e.g. bottom sheet) can trigger update.
  Future<void> submit() async {
    if ((_titleController.text).trim().isEmpty) {
      setState(() => _formErrorMessage = 'Please enter a job title');
      return;
    }
    setState(() { _formErrorMessage = null; _submitting = true; });
    try {
      if (_latController.text.trim().isEmpty || _lonController.text.trim().isEmpty) {
        final place = _locationController.text.trim();
        if (place.isNotEmpty) {
          try {
            final res = await LocationService.geocodePlace(place);
            if (res != null) {
              _latController.text = res['lat'].toString();
              _lonController.text = res['lon'].toString();
            }
          } catch (_) {}
        }
      }

      final trades = _skillsController.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      final coords = <double>[]; final lat = double.tryParse(_latController.text); final lon = double.tryParse(_lonController.text);
      if (lat != null && lon != null) { coords.add(lon); coords.add(lat); }

      final Map<String, dynamic> payload = {
        'title': _titleController.text.trim(),
        'company': _companyController.text.trim(),
        'description': _descriptionController.text.trim(),
        'trade': trades.isNotEmpty ? trades : null,
        'location': _locationController.text.trim(),
        'coordinates': coords.isNotEmpty ? coords : null,
        'budget': double.tryParse(_budgetController.text.replaceAll(RegExp(r'[^0-9.]'), '')),
        'schedule': _selectedDeadline?.toIso8601String(),
        'categoryId': _selectedCategoryId,
        'experienceLevel': _experienceValue,
      };
      payload.removeWhere((k, v) => v == null || (v is String && v.trim().isEmpty));

      final id = (widget.job['_id'] ?? widget.job['id'] ?? widget.job['jobId'])?.toString() ?? '';
      if (id.isEmpty) throw Exception('Job id not available');
      if (kDebugMode) debugPrint(id);
      await JobService.updateJob(id, payload);
      if (!mounted) return;
      // Stop submitting and show success to the user
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Job updated successfully'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      // Close the sheet/page: prefer the provided callback to let the caller control closing.
      if (widget.onUpdated != null) {
        widget.onUpdated!.call();
      } else {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ErrorMessages.humanize(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = MediaQuery.of(context).size.width > 900 ? 48.0 : (MediaQuery.of(context).size.width > 600 ? 32.0 : 16.0);
    // Intercept device back to route explicitly to JobPostPage using PopScope for predictive-back compatibility
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (!didPop) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            try {
              NavigationUtils.safePushReplacement(context, NavBarPage(initialPage: 'JobPostPage'));
            } catch (_) {}
          });
        }
      },
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width > 1100 ? 1000.0 : (MediaQuery.of(context).size.width > 800 ? 800.0 : MediaQuery.of(context).size.width),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // compact header for edit form (back link + title) - hidden when embedded inside bottom sheet
                if (!widget.embedded)
                  Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(0.0, 4.0, 0.0, 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () {
                              // Close the sheet/page — keep behavior minimal and consistent with other pages
                              try { Navigator.of(context).maybePop(); } catch (_) {}
                            },
                            icon: Icon(Icons.arrow_back_ios, size: 16, color: FlutterFlowTheme.of(context).primary),
                            label: Text('Back', style: FlutterFlowTheme.of(context).bodyMedium.override(color: FlutterFlowTheme.of(context).primary)),
                            style: TextButton.styleFrom(padding: EdgeInsets.symmetric(horizontal: 0.0, vertical: 2.0), visualDensity: VisualDensity.compact),
                          ),
                        ),
                        Text('Edit Job Posting', style: FlutterFlowTheme.of(context).headlineSmall.override(font: GoogleFonts.interTight(fontWeight: FontWeight.w700), fontSize: 20)),
                        SizedBox(height: 6),
                      ],
                    ),
                  ),
                // location + resolved hint
                _buildTextField(_locationController, 'Location (City, State)', Icons.location_on, hint: 'e.g. Ikeja, Lagos'),
                SizedBox(height: 8),
                if (_latController.text.isNotEmpty && _lonController.text.isNotEmpty)
                  Row(children: [Icon(Icons.check_circle, size: 14, color: FlutterFlowTheme.of(context).success), SizedBox(width: 8), Text('Location resolved (${_latController.text}, ${_lonController.text})', style: FlutterFlowTheme.of(context).bodySmall)])
                else
                  Row(children: [Icon(Icons.info_outline, size: 14, color: FlutterFlowTheme.of(context).secondaryText), SizedBox(width: 8), Text('Location will be automatically resolved to coordinates', style: FlutterFlowTheme.of(context).bodySmall.copyWith(color: FlutterFlowTheme.of(context).secondaryText))]),
                SizedBox(height: 12),

                // category (full width)
                FlutterFlowDropDown<String>(
                  controller: _categoryDropController ??= FormFieldController<String>(null),
                  options: _categoryNames.isNotEmpty ? _categoryNames : ['General'],
                  isSearchable: true,
                  maxHeight: 220,
                  onChanged: (val) {
                    if (val == null) return;
                    // Only update controller when value actually changes to avoid reentrant listener calls
                    if (_categoryDropController?.value != val) _categoryDropController?.value = val;
                    setState(() {
                      final found = _categories.firstWhere((c) => (c['name'] ?? '') == val, orElse: () => <String, dynamic>{});
                      _selectedCategoryId = (found['_id']?.toString() ?? found['id']?.toString());
                    });
                  },
                  hintText: 'Job category',
                  width: double.infinity,
                  height: 48,
                  textStyle: FlutterFlowTheme.of(context).bodyMedium,
                  elevation: 0.0,
                  borderColor: FlutterFlowTheme.of(context).alternate,
                  borderWidth: 1.0,
                  borderRadius: 12.0,
                  margin: EdgeInsetsDirectional.fromSTEB(12.0, 0.0, 12.0, 0.0),
                  hidesUnderline: true,
                ),
                SizedBox(height: 12),

                // budget (Naira) + experience
                Row(children: [Expanded(child: _buildCurrencyField(_budgetController, 'Budget')), SizedBox(width: 12), Expanded(child: _buildExperienceDropdown())]),
                SizedBox(height: 12),

                // description
                TextFormField(controller: _descriptionController, maxLines: 5, decoration: InputDecoration(prefixIcon: Icon(Icons.article_outlined), hintText: 'Job description', filled: true, fillColor: FlutterFlowTheme.of(context).primaryBackground, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0), borderSide: BorderSide(color: FlutterFlowTheme.of(context).alternate)))),
                SizedBox(height: 12),

                // skills
                TextFormField(controller: _skillsController, decoration: InputDecoration(prefixIcon: Icon(Icons.build_outlined), hintText: 'Skills (comma separated)', filled: true, fillColor: FlutterFlowTheme.of(context).primaryBackground, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0), borderSide: BorderSide(color: FlutterFlowTheme.of(context).alternate)))),
                SizedBox(height: 12),

                // deadline
                InkWell(onTap: () async { final now = DateTime.now(); final picked = await showDatePicker(context: context, initialDate: _selectedDeadline ?? now, firstDate: now, lastDate: DateTime(now.year + 5)); if (picked != null) setState(() => _selectedDeadline = picked); }, child: Container(height: 48, decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: FlutterFlowTheme.of(context).secondaryBackground, border: Border.all(color: FlutterFlowTheme.of(context).alternate)), child: Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(_selectedDeadline != null ? DateFormat.yMMMd().format(_selectedDeadline!) : 'Select deadline', style: FlutterFlowTheme.of(context).bodyMedium), Icon(Icons.calendar_today, size: 18, color: FlutterFlowTheme.of(context).secondaryText)])))),
                SizedBox(height: 12),

                // form-level error
                if (_formErrorMessage != null) Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text(_formErrorMessage!, style: TextStyle(color: Colors.red))),

                // actions - hide internal action buttons when embedded; parent sheet will provide Cancel/Save
                if (!widget.embedded)
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton(onPressed: _submitting ? null : () { Navigator.of(context).maybePop(false); }, child: Text('Cancel')),
                    SizedBox(width: 12),
                    ElevatedButton(onPressed: _submitting ? null : submit, style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(horizontal: 18, vertical: 12), backgroundColor: FlutterFlowTheme.of(context).primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: Text(_submitting ? 'Updating...' : 'Update Job', style: FlutterFlowTheme.of(context).titleMedium.override(color: FlutterFlowTheme.of(context).onPrimary))),
                  ])
              ], // <-- ADDED: closes the Column children
            ), // <-- ADDED: closes the Form child
          ), // <-- ADDED: closes the SingleChildScrollView
        ), // <-- ADDED: closes the ConstrainedBox
      ), // <-- ADDED: closes the PopScope child
    ); // <-- ADDED: closes the return statement and build method
  } // <-- This closes the build method

  Widget _buildTextField(TextEditingController ctrl, String label, IconData icon, {String? hint, TextInputType? keyboard}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboard,
      decoration: InputDecoration(
        prefixIcon: Icon(icon),
        hintText: hint ?? label,
        labelText: label,
        filled: true,
        fillColor: FlutterFlowTheme.of(context).secondaryBackground,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0), borderSide: BorderSide(color: FlutterFlowTheme.of(context).alternate)),
      ),
    );
  }

  // Currency input tailored for Naira (₦). UI-only: shows ₦ prefix and uses numeric keyboard.
  Widget _buildCurrencyField(TextEditingController ctrl, String label) {
    return TextFormField(
      controller: ctrl,
      keyboardType: TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        prefixText: '₦ ',
        prefixStyle: TextStyle(fontWeight: FontWeight.w700, color: FlutterFlowTheme.of(context).primary),
        hintText: 'e.g. 50000',
        labelText: label,
        filled: true,
        fillColor: FlutterFlowTheme.of(context).secondaryBackground,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0), borderSide: BorderSide(color: FlutterFlowTheme.of(context).alternate)),
      ),
    );
  }

  // Ensure experience dropdown updates controller immediately when changed
  Widget _buildExperienceDropdown() {
    _experienceController ??= FormFieldController<String>(_experienceValue);
    return FlutterFlowDropDown<String>(
      controller: _experienceController,
      options: ['entry','mid','senior'],
      onChanged: (val) {
        if (val == null) return;
        if (_experienceController?.value != val) _experienceController?.value = val;
        setState(() => _experienceValue = val);
      },
      hintText: 'Experience level',
      width: double.infinity,
      height: 48,
      textStyle: FlutterFlowTheme.of(context).bodyMedium,
      elevation: 0.0,
      borderColor: FlutterFlowTheme.of(context).alternate,
      borderWidth: 1.0,
      borderRadius: 12.0,
      margin: EdgeInsetsDirectional.fromSTEB(12.0, 0.0, 12.0, 0.0),
      hidesUnderline: true,
    );
  }
}
