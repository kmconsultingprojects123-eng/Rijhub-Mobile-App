import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/location_service.dart';
import '../services/job_service.dart';
import '../services/my_service_service.dart';
import '../utils/error_messages.dart';
import '../utils/job_events.dart';

class EditJobForm extends StatefulWidget {
  final Map<String, dynamic> job;
  final void Function(Map<String, dynamic> updatedJob)? onUpdated;
  final bool embedded;
  const EditJobForm({Key? key, required this.job, this.onUpdated, this.embedded = false}) : super(key: key);

  @override
  State<EditJobForm> createState() => EditJobFormState();
}

class EditJobFormState extends State<EditJobForm> {
  final _formKey = GlobalKey<FormState>();
  bool _submitting = false;
  String? _formErrorMessage;

  late TextEditingController _titleController;
  late TextEditingController _companyController;
  late TextEditingController _locationController;
  late TextEditingController _budgetController;
  late TextEditingController _descriptionController;
  late TextEditingController _skillsController;

  double? _lat;
  double? _lon;
  Timer? _locDebounce;

  List<Map<String, dynamic>> _subservices = [];
  List<String> _selectedSubserviceIds = [];
  List<String> _selectedSubserviceNames = [];
  bool _loadingSubservices = false;

  List<Map<String, dynamic>> _categories = [];
  List<String> _categoryNames = [];
  String? _selectedCategoryId;

  String? _experienceValue;

  DateTime? _selectedDeadline;

  bool get isSubmitting => _submitting;

  // Theme helper methods used in the form widget (map to form-specific colors)
  Color _getPrimaryColor(BuildContext context) => const Color(0xFFA20025);
  Color _getTextPrimary(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? Colors.white : const Color(0xFF111827);
  Color _getTextSecondary(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
  Color _getBorderColor(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? const Color(0xFF374151) : const Color(0xFFE5E7EB);
  Color _getSurfaceColor(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0B1220) : Colors.white;

  @override
  void initState() {
    super.initState();
    final j = widget.job;
    _titleController = TextEditingController(text: (j['title'] ?? '').toString());

    String extractString(dynamic v) {
      if (v == null) return '';
      if (v is String) return v;
      if (v is Map) return (v['name'] ?? v['title'] ?? v['label'] ?? v['address'] ?? '').toString();
      return v.toString();
    }

    _companyController = TextEditingController(
        text: extractString(j['company'] ?? j['employer'] ?? j['companyName'] ?? j['company_name'] ?? j['employerName'] ?? '')
    );

    _locationController = TextEditingController(
        text: extractString(j['location'] ?? j['address'] ?? j['venue'] ?? j['place'] ?? j['city'] ?? j['state'] ?? '')
    );
    _budgetController = TextEditingController(text: _stripNumericDot((j['budget'] ?? j['price'] ?? '').toString()));
    _descriptionController = TextEditingController(text: (j['description'] ?? j['details'] ?? '').toString());
    _skillsController = TextEditingController(text: (j['trade'] is List) ? (j['trade'] as List).map((e) => e.toString().trim()).where((s)=>s.isNotEmpty).join(', ') : (j['trade'] ?? '').toString());

    try {
      final coords = j['coordinates'];
      if (coords is List && coords.length >= 2) {
        _lon = (coords[0] is num) ? coords[0].toDouble() : double.tryParse(coords[0].toString());
        _lat = (coords[1] is num) ? coords[1].toDouble() : double.tryParse(coords[1].toString());
      } else if (j['geo'] is Map) {
        final geo = j['geo'];
        _lat = (geo['lat'] is num) ? geo['lat'].toDouble() : double.tryParse(geo['lat']?.toString() ?? '');
        _lon = (geo['lon'] is num) ? geo['lon'].toDouble() : double.tryParse(geo['lon']?.toString() ?? '');
      }
    } catch (_) {}

    try {
      final sched = j['schedule'] ?? j['deadline'];
      if (sched != null) {
        final dt = DateTime.tryParse(sched.toString());
        if (dt != null) _selectedDeadline = dt;
      }
    } catch (_) {}

    _selectedCategoryId = (j['categoryId'] ?? j['category'] ?? j['category_id'])?.toString();

    try {
      final rawExp = (j['experienceLevel'] ?? j['type'] ?? j['experience'])?.toString();
      if (rawExp != null) {
        final low = rawExp.toLowerCase();
        if (low == 'entry' || low.contains('entry')) _experienceValue = 'Entry';
        else if (low == 'mid' || low.contains('mid')) _experienceValue = 'Mid';
        else if (low == 'senior' || low.contains('senior')) _experienceValue = 'Senior';
        else _experienceValue = rawExp;
      }
    } catch (_) {}

    try {
      final dynamic sidsRaw = j['subCategoryIds'] ?? j['sub_category_ids'] ?? j['subCategories'] ?? j['serviceIds'] ?? j['services'];
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

      final dynamic snames = j['subCategoryNames'] ?? j['sub_category_names'] ?? j['serviceNames'];
      if ((snames is List) && snames.isNotEmpty) {
        _selectedSubserviceNames = snames.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
      }
    } catch (_) {}

    _loadCategories();
    _fetchSubservices();

    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeFetchFullJob());

    try {
      // ignore: avoid_print
      print('DEBUG EditJobForm: prefill -> company=${_companyController.text}, location=${_locationController.text}, subserviceIds=${_selectedSubserviceIds}, subserviceNames=${_selectedSubserviceNames}, experience=${_experienceValue}');
    } catch (_) {}

    _locationController.addListener(() {
      if (_locDebounce?.isActive ?? false) _locDebounce!.cancel();
      _locDebounce = Timer(const Duration(milliseconds: 800), () async {
        final place = _locationController.text.trim();
        if (place.isEmpty) return;
        try {
          final res = await LocationService.geocodePlace(place);
          if (res != null && mounted) {
            setState(() {
              _lat = res['lat'] is num ? (res['lat'] as num).toDouble() : double.tryParse(res['lat']?.toString() ?? '');
              _lon = res['lon'] is num ? (res['lon'] as num).toDouble() : double.tryParse(res['lon']?.toString() ?? '');
            });
          }
        } catch (_) {}
      });
    });
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await JobService.getJobCategories();
      if (mounted) setState(() {
        _categories = cats;
        _categoryNames = cats.map((c) => (c['name'] ?? '').toString()).where((n) => n.isNotEmpty).toList();
      });
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
        if (data is List) list = data.map((e) => Map<String,dynamic>.from(e as Map)).toList();
        else if (data is Map && data['data'] is List) list = List<Map<String,dynamic>>.from(data['data'].map((e)=> Map<String,dynamic>.from(e)));
        else if (data is Map && data['items'] is List) list = List<Map<String,dynamic>>.from(data['items'].map((e)=> Map<String,dynamic>.from(e)));
        else if (data is Map) list = [Map<String,dynamic>.from(data)];
      }
      if (mounted) setState(() { _subservices = list; });
      if (mounted && _selectedSubserviceNames.isEmpty && _selectedSubserviceIds.isNotEmpty && _subservices.isNotEmpty) {
        final mapped = <String>[];
        for (final id in _selectedSubserviceIds) {
          final found = _subservices.firstWhere((s) => ((s['_id'] ?? s['id'])?.toString() ?? '') == id, orElse: () => {});
          if (found.isNotEmpty) {
            final name = (found['name'] ?? found['title'] ?? '').toString();
            if (name.isNotEmpty) mapped.add(name);
          }
        }
        if (mapped.isNotEmpty) setState(() { _selectedSubserviceNames = mapped; });
      }
    } catch (_) {
      // ignore
    } finally { if (mounted) setState(() { _loadingSubservices = false; }); }
  }

  // Try to fetch a fresh full job from the API by id and apply it to controllers.
  Future<void> _maybeFetchFullJob() async {
    try {
      final id = (widget.job['_id'] ?? widget.job['id'] ?? widget.job['jobId'])?.toString() ?? '';
      if (id.isEmpty) return;
      // ignore: avoid_print
      print('DEBUG EditJobForm: fetching full job for id=$id');
      final fetched = await JobService.getJob(id);
      // ignore: avoid_print
      print('DEBUG EditJobForm: fetched job -> $fetched');
      if (fetched.isNotEmpty) _applyJobToControllers(fetched);
    } catch (e) {
      // ignore: avoid_print
      print('DEBUG EditJobForm: failed to fetch full job -> $e');
    }
  }

  void _applyJobToControllers(Map<String, dynamic> j) {
    try {
      setState(() {
        _titleController.text = (j['title'] ?? j['jobTitle'] ?? _titleController.text).toString();
        _companyController.text = _extractString(j['company'] ?? j['employer'] ?? j['companyName'] ?? j['company_name'] ?? j['employerName'] ?? _companyController.text);
        _locationController.text = _extractString(j['location'] ?? j['address'] ?? j['venue'] ?? j['place'] ?? j['city'] ?? j['state'] ?? _locationController.text);
        _budgetController.text = _stripNumericDot((j['budget'] ?? j['price'] ?? _budgetController.text).toString());
        _descriptionController.text = (j['description'] ?? j['details'] ?? _descriptionController.text).toString();
        _skillsController.text = (j['trade'] is List) ? (j['trade'] as List).map((e)=>e?.toString()?.trim() ?? '').where((s)=>s.isNotEmpty).join(', ') : (j['trade'] ?? _skillsController.text).toString();

        try {
          final rawExp = (j['experienceLevel'] ?? j['type'] ?? j['experience'])?.toString();
          if (rawExp != null) {
            final low = rawExp.toLowerCase();
            if (low.contains('entry')) _experienceValue = 'Entry';
            else if (low.contains('mid')) _experienceValue = 'Mid';
            else if (low.contains('senior')) _experienceValue = 'Senior';
            else _experienceValue = rawExp;
          }
        } catch (_) {}

        try {
          final dynamic sidsRaw = j['subCategoryIds'] ?? j['sub_category_ids'] ?? j['subCategories'] ?? j['serviceIds'] ?? j['services'];
          if (sidsRaw is List) {
            final ids = <String>[]; final names = <String>[];
            for (final e in sidsRaw) {
              if (e == null) continue;
              if (e is String || e is num) ids.add(e.toString());
              else if (e is Map) {
                final id = (e['_id'] ?? e['id'])?.toString();
                final name = (e['name'] ?? e['title'])?.toString();
                if (id != null && id.isNotEmpty) ids.add(id);
                if (name != null && name.isNotEmpty) names.add(name);
              }
            }
            if (ids.isNotEmpty) _selectedSubserviceIds = ids;
            if (names.isNotEmpty) _selectedSubserviceNames = names;
          } else if (sidsRaw is String || sidsRaw is num) {
            final s = sidsRaw.toString(); if (s.isNotEmpty) _selectedSubserviceIds = [s];
          }
        } catch (_) {}
        // If no explicit subservice names were provided but the job includes a `trade` list (names),
        // use that to prefill the Required Service selector so chips show up.
        if ((_selectedSubserviceNames.isEmpty || _selectedSubserviceNames.every((n)=>n.trim().isEmpty)) && j['trade'] is List) {
          try {
            final namesFromTrade = (j['trade'] as List).map((e) => e?.toString() ?? '').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
            if (namesFromTrade.isNotEmpty) {
              setState(() { _selectedSubserviceNames = namesFromTrade; });
            }
          } catch (_) {}
        }
      });
      // ignore: avoid_print
      print('DEBUG EditJobForm: controllers applied -> company=${_companyController.text}, location=${_locationController.text}, services=${_selectedSubserviceNames}, experience=${_experienceValue}');
    } catch (_) {}
  }

  String _extractString(dynamic v) {
    if (v == null) return '';
    if (v is String) return v;
    if (v is Map) return (v['name'] ?? v['title'] ?? v['label'] ?? v['address'] ?? '').toString();
    return v.toString();
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
    super.dispose();
  }

  String _stripNumericDot(String s) {
    if (s.isEmpty) return '';
    const allowed = '0123456789.';
    return s.split('').where((c) => allowed.contains(c)).join();
  }

  Future<void> submit() async {
    if (_titleController.text.trim().isEmpty) {
      setState(() { _formErrorMessage = 'Please enter a job title'; });
      return;
    }
    setState(() { _formErrorMessage = null; _submitting = true; });
    try {
      if ((_lat == null || _lon == null) && _locationController.text.trim().isNotEmpty) {
        try {
          final res = await LocationService.geocodePlace(_locationController.text.trim());
          if (res != null) {
            // res is expected to be a Map with 'lat' and 'lon' keys
            final rlat = res['lat'];
            final rlon = res['lon'];
            _lat = (rlat is num) ? rlat.toDouble() : double.tryParse(rlat?.toString() ?? '');
            _lon = (rlon is num) ? rlon.toDouble() : double.tryParse(rlon?.toString() ?? '');
          }
        } catch (_) {}
      }

      final trades = (_selectedSubserviceNames.isNotEmpty) ? List<String>.from(_selectedSubserviceNames) : _skillsController.text.split(',').map((s)=>s.trim()).where((s)=>s.isNotEmpty).toList();
      final coords = <double>[];
      if (_lat != null && _lon != null) { coords.add(_lon!); coords.add(_lat!); }

      String? experienceToken;
      try {
        final val = _experienceValue?.toString();
        if (val != null) {
          final low = val.toLowerCase();
          if (low == 'entry' || low.contains('entry')) experienceToken = 'entry';
          else if (low == 'mid' || low.contains('mid')) experienceToken = 'mid';
          else if (low == 'senior' || low.contains('senior')) experienceToken = 'senior';
          else experienceToken = val;
        }
      } catch (_) {}

      final payload = <String, dynamic>{
        'title': _titleController.text.trim(),
        'company': _companyController.text.trim(),
        'description': _descriptionController.text.trim(),
        'trade': trades.isNotEmpty ? trades : null,
        'location': _locationController.text.trim(),
        'coordinates': coords.isNotEmpty ? coords : null,
        'budget': double.tryParse(_stripNumericDot(_budgetController.text)),
        'schedule': _selectedDeadline?.toIso8601String(),
        'categoryId': _selectedCategoryId,
        'subCategoryIds': _selectedSubserviceIds.isNotEmpty ? _selectedSubserviceIds : null,
        'subCategoryId': _selectedSubserviceIds.isNotEmpty ? _selectedSubserviceIds.first : null,
        'experienceLevel': experienceToken,
      };

      payload.removeWhere((k, v) => v == null || (v is String && v.trim().isEmpty));

      final id = (widget.job['_id'] ?? widget.job['id'] ?? widget.job['jobId'])?.toString() ?? '';
      if (id.isEmpty) throw Exception('Job id not available');

      try {
        // ignore: avoid_print
        print('DEBUG EditJobForm: submit payload -> $payload');
      } catch (_) {}

      try {
        final resp = await JobService.updateJob(id, payload);
        // ignore: avoid_print
        print('DEBUG EditJobForm: update response -> $resp');
        if (!mounted) return;
        setState(() { _submitting = false; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Job updated successfully'), behavior: SnackBarBehavior.floating));

        // Broadcast updated job so other pages (job board / history) can react
        try {
          final updatedMap = resp is Map<String, dynamic> ? resp : Map<String, dynamic>.from(resp);
          JobEvents.emitJobUpdated(updatedMap);
          if (widget.onUpdated != null) {
            widget.onUpdated!(updatedMap);
          } else {
            Navigator.of(context).pop(updatedMap);
          }
        } catch (e) {
          // Fallback: still call the callback or pop with whatever we have
          try { if (widget.onUpdated != null) widget.onUpdated!(resp as Map<String,dynamic>); else Navigator.of(context).pop(resp ?? true); } catch (_) { Navigator.of(context).pop(resp ?? true); }
        }
      } catch (e, st) {
        // ignore: avoid_print
        print('DEBUG EditJobForm: update failed -> $e');
        // ignore: avoid_print
        print(st);
        rethrow;
      }
    } catch (e) {
      setState(() { _submitting = false; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ErrorMessages.humanize(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = MediaQuery.of(context).size.width > 900 ? 48.0 : (MediaQuery.of(context).size.width > 600 ? 32.0 : 16.0);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width > 1100 ? 1000.0 : (MediaQuery.of(context).size.width > 800 ? 800.0 : MediaQuery.of(context).size.width)),
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 16.0),
        child: Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!widget.embedded) Padding(padding: EdgeInsetsDirectional.fromSTEB(0,4,0,8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => Navigator.of(context).maybePop(), icon: Icon(Icons.arrow_back_ios, size: 16), label: Text('Back'))),
              Text('Edit Job Posting', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20)), SizedBox(height: 6),
            ])),

            // Title, Company, Location
            TextFormField(controller: _titleController, decoration: InputDecoration(prefixIcon: Icon(Icons.work_outline), hintText: 'Job title', labelText: 'Job Title', filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))), validator: (v) => (v==null || v.trim().isEmpty) ? 'Please enter a job title' : null),
            SizedBox(height: 12),
            TextFormField(controller: _companyController, decoration: InputDecoration(prefixIcon: Icon(Icons.business), hintText: 'Company name', labelText: 'Company', filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))), validator: (v) => (v==null || v.trim().isEmpty) ? 'Please enter company name' : null),
            SizedBox(height: 12),
            TextFormField(controller: _locationController, decoration: InputDecoration(prefixIcon: Icon(Icons.location_on), hintText: 'e.g. Ikeja, Lagos', labelText: 'Location (City, State)', filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))), ),
            SizedBox(height: 12),

            // Service selector (replaces Category) + Budget + Experience
            Builder(builder: (context) {
              final textPrimary = _getTextPrimary(context);
              final textSecondary = _getTextSecondary(context);
              final borderColor = _getBorderColor(context);
              final surface = _getSurfaceColor(context);

              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Required Service', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: textPrimary)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    if (_selectedCategoryId != null) await _fetchSubservices(categoryId: _selectedCategoryId);
                    else if (_subservices.isEmpty) await _fetchSubservices();

                    final localSelectedIds = List<String>.from(_selectedSubserviceIds);
                    final localSelectedNames = List<String>.from(_selectedSubserviceNames);
                    var localFiltered = List<Map<String, dynamic>>.from(_subservices);

                    await showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
                      builder: (ctx) {
                        return StatefulBuilder(builder: (context, setBottom) {
                          void _localSearch(String v) {
                            final q = v.trim().toLowerCase();
                            if (q.isEmpty) localFiltered = List<Map<String, dynamic>>.from(_subservices);
                            else localFiltered = _subservices.where((s) => ((s['name'] ?? s['title'] ?? '')).toString().toLowerCase().contains(q)).toList();
                            setBottom(() {});
                          }

                          void _toggle(Map<String, dynamic> s) {
                            final id = (s['_id'] ?? s['id'])?.toString();
                            final name = (s['name'] ?? s['title'])?.toString() ?? '';
                            if (id == null) return;
                            final idx = localSelectedIds.indexOf(id);
                            if (idx >= 0) { localSelectedIds.removeAt(idx); if (localSelectedNames.length > idx) localSelectedNames.removeAt(idx); }
                            else { localSelectedIds.add(id); localSelectedNames.add(name); }
                            setBottom(() {});
                          }

                          return Padding(
                            padding: MediaQuery.of(ctx).viewInsets,
                            child: Container(
                              height: MediaQuery.of(ctx).size.height * 0.7,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                  Text('Select services', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                  TextButton(onPressed: () {
                                    setState(() { _selectedSubserviceIds = List<String>.from(localSelectedIds); _selectedSubserviceNames = List<String>.from(localSelectedNames); });
                                    Navigator.of(ctx).pop();
                                  }, child: Text('Done')),
                                ]),
                                const SizedBox(height: 8),
                                Container(margin: const EdgeInsets.only(bottom: 12), child: TextField(decoration: InputDecoration(hintText: 'Search services', prefixIcon: Icon(Icons.search)), onChanged: _localSearch)),
                                Expanded(child: localFiltered.isEmpty ? Center(child: Text('No services found')) : ListView.separated(itemCount: localFiltered.length, separatorBuilder: (_,__) => Divider(height:1), itemBuilder: (c,i) {
                                  final s = localFiltered[i]; final id = (s['_id'] ?? s['id'])?.toString(); final name = (s['name'] ?? s['title'])?.toString() ?? '';
                                  final checked = id != null && localSelectedIds.contains(id);
                                  return CheckboxListTile(value: checked, onChanged: (_) => _toggle(s), title: Text(name), controlAffinity: ListTileControlAffinity.trailing);
                                })),
                              ]),
                            ),
                          );
                        });
                      }
                    );
                  },
                  child: Container(
                    decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderColor)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(children: [
                      Expanded(child: _selectedSubserviceNames.isEmpty ? Text('Select services', style: TextStyle(color: textSecondary)) : SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: _selectedSubserviceNames.map((n) => Padding(padding: const EdgeInsets.only(right:8.0), child: Chip(label: Text(n, style: TextStyle(color: textPrimary)), backgroundColor: Theme.of(context).brightness==Brightness.dark?Colors.white12:Colors.grey[200], onDeleted: () { setState(() { final idx = _selectedSubserviceNames.indexOf(n); if (idx>=0) { _selectedSubserviceNames.removeAt(idx); if (_selectedSubserviceIds.length>idx) _selectedSubserviceIds.removeAt(idx); } }); }))).toList()))),
                      Icon(Icons.keyboard_arrow_down_rounded, color: textSecondary)
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
              ]);
            }),

            // Budget + Experience
            Row(children: [
              Expanded(child: TextFormField(controller: _budgetController, decoration: InputDecoration(prefixText: '₦ ', hintText: 'e.g. 50000', labelText: 'Budget', filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))), keyboardType: TextInputType.number, )),
              SizedBox(width: 12),
              Expanded(child: DropdownButtonFormField<String>(initialValue: _experienceValue, items: ['Entry','Mid','Senior'].map((o)=>DropdownMenuItem(value:o,child:Text(o))).toList(), onChanged: (v){ setState(()=>_experienceValue=v); }, decoration: InputDecoration(labelText: 'Experience', filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))))
            ]),
            SizedBox(height: 12),

            // Description
            TextFormField(controller: _descriptionController, maxLines: 5, decoration: InputDecoration(prefixIcon: Icon(Icons.article_outlined), hintText: 'Job description', filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            SizedBox(height: 12),


            // Deadline picker (simple inline version)
            InkWell(
              onTap: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _selectedDeadline ?? now,
                  firstDate: now,
                  lastDate: DateTime(now.year + 5),
                );
                if (picked != null && mounted) setState(() => _selectedDeadline = picked);
              },
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF374151) : const Color(0xFFE5E7EB)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(_selectedDeadline != null ? DateFormat('MMM dd, yyyy').format(_selectedDeadline!) : 'Select deadline', style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.white : _getTextPrimary(context))),
                  Icon(Icons.calendar_today_rounded)
                ]),
              ),
            ),
            SizedBox(height: 12),

            if (_formErrorMessage != null) Padding(padding: EdgeInsets.symmetric(vertical:8), child: Text(_formErrorMessage!, style: TextStyle(color: Colors.red))),

            if (!widget.embedded)
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(onPressed: _submitting ? null : () => Navigator.of(context).maybePop(false), child: Text('Cancel')),
                SizedBox(width:12),
                ElevatedButton(onPressed: _submitting ? null : submit, style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(horizontal:18, vertical:12), backgroundColor: _getPrimaryColor(context), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: Text(_submitting ? 'Updating...' : 'Update Job'))
              ]),
          ]),
        ),
      ),
    );
  }
}
