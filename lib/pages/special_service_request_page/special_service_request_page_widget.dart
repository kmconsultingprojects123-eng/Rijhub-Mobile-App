import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../api_config.dart';
import '../../services/token_storage.dart';
import '../../utils/app_notification.dart';
import '../../utils/location_permission.dart';
import 'package:geolocator/geolocator.dart';
import '../../google_maps_config.dart';
import '../../services/special_service_request_service.dart';
import '../../services/notification_service.dart';
import '../../services/my_service_service.dart';

class SpecialServiceRequestPageWidget extends StatefulWidget {
  const SpecialServiceRequestPageWidget({
    super.key,
    required this.artisanId,
    required this.artisanName,
    this.artisanEmail,
    this.artisanData,
  });

  final String artisanId;
  final String artisanName;
  final String? artisanEmail;
  final Map<String, dynamic>? artisanData;

  static String routeName = 'SpecialServiceRequestPage';
  static String routePath = '/specialServiceRequest';

  @override
  State<SpecialServiceRequestPageWidget> createState() =>
      _SpecialServiceRequestPageWidgetState();
}

class _SpecialServiceRequestPageWidgetState
    extends State<SpecialServiceRequestPageWidget> {
  // Controllers
  late TextEditingController _descriptionController;
  late TextEditingController _locationController;

  // State Variables
  bool _submitting = false;
  String? _errorMessage;
  String? _authToken;
  Map<String, dynamic>? _fetchedArtisan;

  // Form Data
  Map<String, dynamic>? _selectedCategory;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  String _urgency = 'Normal';
  List<XFile> _selectedImages = [];
  bool _isLoadingCategories = false;
  List<Map<String, dynamic>> _artisanServices = [];

  // Location
  bool _isGettingLocation = false;

  // Constants
  static const Color _defaultPrimaryColor = Color(0xFFA20025);
  static const Duration _timeout = Duration(seconds: 15);

  Color get primaryColor =>
      FlutterFlowTheme.of(context).primary ?? _defaultPrimaryColor;

  @override
  void initState() {
    super.initState();
    _descriptionController = TextEditingController();
    _locationController = TextEditingController();

    _loadCategories();
    _loadCachedLocation();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeToken();
      _maybeFetchArtisan();
    });
  }

  Map<String, dynamic>? _effectiveArtisan() {
    // Prefer freshly fetched artisan data when available
    return _fetchedArtisan ?? widget.artisanData;
  }

  Future<void> _maybeFetchArtisan() async {
    try {
      // If widget payload exists and looks rich, skip fetch; otherwise fetch full artisan
      final payload = widget.artisanData;
      if (payload != null && _isWidgetPayloadRich(payload)) return;
      final id = widget.artisanId;
      if (id.isEmpty) return;
      String? token = _authToken;
      if (token == null || token.isEmpty) {
        token = await TokenStorage.getToken();
        _authToken = token;
      }
      final base = _normalizeBaseUrl(API_BASE_URL);
      final uri = Uri.parse('$base/api/artisans/$id');
      final headers = <String, String>{'Accept': 'application/json'};
      if (token?.isNotEmpty ?? false)
        headers['Authorization'] = 'Bearer $token';

      final resp = await http.get(uri, headers: headers).timeout(_timeout);
      if (resp.statusCode == 200 && resp.body.isNotEmpty) {
        final body = _safeParseJson(resp.body);
        Map<String, dynamic>? data;
        if (body is Map && body['data'] is Map)
          data = Map<String, dynamic>.from(body['data']);
        else if (body is Map) data = Map<String, dynamic>.from(body);
        if (data != null) {
          if (mounted) setState(() => _fetchedArtisan = data);
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch artisan for special service page: $e');
    }
  }

  bool _isWidgetPayloadRich(dynamic wa) {
    try {
      if (wa == null) return false;
      if (wa is! Map) return false;
      final m = Map<String, dynamic>.from(wa.cast<String, dynamic>());
      for (final k in [
        'name',
        'bio',
        'pricing',
        'services',
        'artisanServices',
        'reviews'
      ]) {
        if (m.containsKey(k) && m[k] != null) return true;
      }
    } catch (_) {}
    return false;
  }

  // Safe JSON parse, returns decoded object or raw string on failure
  dynamic _safeParseJson(String input) {
    try {
      return jsonDecode(input);
    } catch (_) {
      return input;
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _initializeToken() async {
    try {
      _authToken = await TokenStorage.getToken();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error loading token: $e');
      _authToken = null;
    }
  }

  Future<void> _loadCategories() async {
    setState(() => _isLoadingCategories = true);
    try {
      final svc = MyServiceService();
      final resp = await svc.fetchArtisanServices(widget.artisanId);
      if (resp.ok) {
        _artisanServices = MyServiceService.flattenArtisanServices(resp.data);
      } else {
        _artisanServices = [];
      }
    } catch (e) {
      debugPrint('Error loading artisan services: $e');
      _artisanServices = [];
    } finally {
      if (mounted) setState(() => _isLoadingCategories = false);
    }
  }

  Future<void> _loadCachedLocation() async {
    try {
      final location = await TokenStorage.getLocation();
      if (location != null && mounted) {
        final address = location['address'] as String?;
        if (address != null && address.isNotEmpty) {
          setState(() {
            _locationController.text = address;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _selectCategory() async {
    if (_artisanServices.isEmpty) {
      await _loadCategories();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.grey.withOpacity(0.2),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Select Service',
                        style:
                        Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: primaryColor),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              // Search bar
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search services...',
                    prefixIcon: Icon(Icons.search, color: primaryColor),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.grey.withOpacity(0.1),
                  ),
                  onChanged: (query) {
                    // Filter categories
                  },
                ),
              ),
              // Categories list
              Expanded(
                child: _isLoadingCategories
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _artisanServices.length,
                  itemBuilder: (context, index) {
                    final category = _artisanServices[index];
                    final isSelected = _selectedCategory == category;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedCategory = category;
                        });
                        Navigator.pop(context);
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? primaryColor.withOpacity(0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? primaryColor
                                : Colors.grey.withOpacity(0.2),
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: primaryColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.category_outlined,
                                color: primaryColor,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${category['subCategoryName'] ?? 'Unknown'}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              Icon(Icons.check_circle,
                                  color: primaryColor, size: 20),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: primaryColor,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (date != null && mounted) {
      setState(() {
        _selectedDate = date;
      });
    }
  }

  Future<void> _selectTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: primaryColor,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (time != null && mounted) {
      setState(() {
        _selectedTime = time;
      });
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isGettingLocation = true);

    final hasPermission =
    await LocationPermissionService.ensureLocationPermissions(context);
    if (!hasPermission) {
      setState(() => _isGettingLocation = false);
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      );

      // Reverse geocode to get address
      String? address;
      try {
        final key = GOOGLE_MAPS_API_KEY;
        if (key.isNotEmpty) {
          final url = Uri.parse(
              'https://maps.googleapis.com/maps/api/geocode/json?latlng=${position.latitude},${position.longitude}&key=$key');
          final response =
          await http.get(url).timeout(const Duration(seconds: 10));

          if (response.statusCode == 200 && response.body.isNotEmpty) {
            final body = jsonDecode(response.body);
            if (body is Map &&
                body['results'] is List &&
                (body['results'] as List).isNotEmpty) {
              final result = (body['results'] as List).first;
              if (result is Map && result['formatted_address'] != null) {
                address = result['formatted_address'].toString();
              }
            }
          }
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _locationController.text = address ?? 'Location detected';
          _isGettingLocation = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGettingLocation = false);
        AppNotification.showError(context, 'Failed to get location');
      }
    }
  }

  Future<void> _showLocationOptions() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.my_location, color: primaryColor),
                ),
                title: const Text('Use Current Location'),
                onTap: () async {
                  Navigator.pop(context);
                  await _getCurrentLocation();
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.edit_location, color: primaryColor),
                ),
                title: const Text('Enter Manually'),
                onTap: () {
                  Navigator.pop(context);
                  _showManualLocationDialog();
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showManualLocationDialog() async {
    final controller = TextEditingController(text: _locationController.text);
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Enter Location'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'Enter your address',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _locationController.text = controller.text;
                });
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
              ),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage();

    if (images != null && mounted) {
      setState(() {
        _selectedImages = images;
      });
    }
  }

  Future<void> _removeImage(int index) async {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  bool get _isFormValid {
    return _selectedCategory != null &&
        _descriptionController.text.trim().isNotEmpty &&
        _locationController.text.trim().isNotEmpty &&
        _selectedDate != null &&
        _selectedTime != null;
  }

  Future<void> _submitRequest() async {
    if (!_isFormValid) {
      AppNotification.showError(context, 'Please fill all required fields');
      return;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      // ensure token available for any service calls
      if (_authToken == null || _authToken!.isEmpty) {
        _authToken = await TokenStorage.getToken();
      }

      // Build title from service category name
      final title = _selectedCategory?['subCategoryName'] ?? 'Service Request';

      // Combine date and time into a single datetime string
      String? scheduleDateTime;
      if (_selectedDate != null && _selectedTime != null) {
        final combined = DateTime(
          _selectedDate!.year,
          _selectedDate!.month,
          _selectedDate!.day,
          _selectedTime!.hour,
          _selectedTime!.minute,
        );
        scheduleDateTime = combined.toIso8601String();
      }

      // Build payload according to API spec
      final payload = <String, dynamic>{
        'artisanId': widget.artisanId, // API expects artisanId (camelCase)
        'title': title, // Required: service title
        'description': _descriptionController.text.trim(),
        'location': _locationController.text.trim(),
        'budget': 0, // Optional budget (can be 0)
        'urgency': _urgency, // 'Normal' or 'Urgent'
      };

      // Add date and time if selected
      if (_selectedDate != null) {
        payload['date'] = _selectedDate!.toIso8601String();
      }
      if (_selectedTime != null) {
        payload['time'] =
        '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}';
      }

      // Log the complete payload with images for debugging
      debugPrint(
          '┌────────────────── SPECIAL SERVICE REQUEST PAYLOAD ──────────────────');
      debugPrint('│ Artisan ID: ${payload['artisanId']}');
      debugPrint('│ Title: ${payload['title']}');
      debugPrint('│ Description: ${payload['description']}');
      debugPrint('│ Location: ${payload['location']}');
      debugPrint('│ Schedule: $scheduleDateTime');
      debugPrint('│ Urgency: ${payload['urgency']}');
      debugPrint('│ Budget: ${payload['budget']}');
      debugPrint('│ Number of Images: ${_selectedImages.length}');
      debugPrint(
          '│ Token Available: ${_authToken?.isNotEmpty == true ? 'Yes' : 'No'}');
      debugPrint(
          '└────────────────────────────────────────────────────────────────────');

      // Add full payload logging
      debugPrint('Full payload JSON: ${payload.toString()}');

      // Use multipart when images are present so the backend stores them as attachments.
      final created = await (_selectedImages.isNotEmpty
          ? SpecialServiceRequestService.createWithFiles(
          payload, _selectedImages)
          : SpecialServiceRequestService.create(payload))
          .timeout(
        const Duration(seconds: 30),
        onTimeout: () =>
        throw TimeoutException('Request took too long to complete'),
      );

      // Best-effort: create a server-side notification record for the artisan.
      try {
        final clientName = await TokenStorage.getUserName();
        final createdMap =
        created != null ? Map<String, dynamic>.from(created) : null;
        final requestId = createdMap?['_id']?.toString() ??
            createdMap?['id']?.toString() ??
            '';
        if (requestId.isNotEmpty) {
          NotificationService.sendSpecialRequestNotification(
            toUserId: widget.artisanId,
            requestId: requestId,
            eventType: 'created',
            requestTitle: createdMap?['title']?.toString() ??
                payload['title']?.toString(),
            actorName: clientName,
          );
        }
      } catch (_) {}

      if (created != null) {
        debugPrint('✓ Service request created successfully!');
        debugPrint('Response: $created');

        if (mounted) {
          AppNotification.showSuccess(context, 'Request sent successfully!');
        }

        await Future.delayed(const Duration(milliseconds: 500));

        if (mounted) {
          // Return to caller (artisan detail page) so it can refresh its history list.
          Navigator.of(context).pop(true);
        }
      } else {
        final errMsg = 'Failed to send request';
        debugPrint('✗ $errMsg - Server returned null');
        if (mounted) {
          AppNotification.showError(context, errMsg);
          setState(() => _errorMessage = errMsg);
        }
      }
    } on TimeoutException catch (e) {
      final errMsg =
          'Request timeout. Network may be slow or server unreachable.';
      debugPrint('✗ TimeoutException: ${e.toString()}');
      if (mounted) {
        AppNotification.showError(context, errMsg);
        setState(() => _errorMessage = errMsg);
      }
    } catch (e, st) {
      String errMsg = 'An error occurred. Please try again later.';

      // Provide more specific error messages
      if (e.toString().contains('Connection refused') ||
          e.toString().contains('Connection reset') ||
          e.toString().contains('No address associated')) {
        errMsg = 'Network error. Please check your internet connection.';
      } else if (e.toString().contains('Socket exception') ||
          e.toString().contains('SocketException')) {
        errMsg = 'Connection failed. Please check your internet.';
      } else if (e.toString().contains('FormatException')) {
        errMsg = 'Invalid response from server.';
      }

      debugPrint('✗ Error submitting request: $e');
      debugPrint('Stack trace: $st');

      if (mounted) {
        AppNotification.showError(context, errMsg);
        setState(() => _errorMessage = errMsg);
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  String _normalizeBaseUrl(String url) {
    try {
      if (url.endsWith('/')) return url.substring(0, url.length - 1);
      return url;
    } catch (_) {
      return url;
    }
  }

  // Helper: extract profile image URL from artisan data
  String? _extractProfileImageFromArtisan(Map<String, dynamic>? a) {
    try {
      if (a == null) return null;
      final directKeys = [
        'profilePicture',
        'profileImage',
        'avatar',
        'photo',
        'image'
      ];
      for (final k in directKeys) {
        final url = _toAbsoluteImageUrl(a[k]);
        if (url != null) return url;
      }

      if (a['user'] is Map) {
        final user = a['user'];
        for (final k in directKeys) {
          final url = _toAbsoluteImageUrl(user[k]);
          if (url != null) return url;
        }
      }

      if (a['profileImage'] is Map) {
        final profileImage = a['profileImage'];
        for (final k in ['url', 'src', 'path', 'imageUrl']) {
          final url = _toAbsoluteImageUrl(profileImage[k]);
          if (url != null) return url;
        }
      }

      if (a['portfolio'] is List && (a['portfolio'] as List).isNotEmpty) {
        final firstPortfolio = a['portfolio'][0];
        if (firstPortfolio is Map &&
            firstPortfolio['images'] is List &&
            (firstPortfolio['images'] as List).isNotEmpty) {
          final firstImage = (firstPortfolio['images'] as List)[0];
          return _toAbsoluteImageUrl(firstImage);
        }
      }
    } catch (e) {
      debugPrint('Error extracting profile image: $e');
    }
    return null;
  }

  String? _toAbsoluteImageUrl(dynamic candidate) {
    try {
      if (candidate == null) return null;
      if (candidate is String) {
        final s = candidate.trim();
        if (s.isEmpty) return null;
        if (s.startsWith('http://') || s.startsWith('https://')) return s;
        final base = _normalizeBaseUrl(API_BASE_URL);
        if (s.startsWith('/')) return '$base$s';
        return '$base/$s';
      }
      if (candidate is Map) {
        for (final k in ['url', 'src', 'path', 'imageUrl']) {
          final v = candidate[k];
          final res = _toAbsoluteImageUrl(v);
          if (res != null) return res;
        }
      }
    } catch (_) {}
    return null;
  }

  // Helper: extract display name from artisan data
  String _extractDisplayNameFromArtisan(Map<String, dynamic>? a) {
    try {
      if (a == null) return 'Artisan';
      final candidates = ['name', 'fullName', 'displayName', 'username'];
      for (final k in candidates) {
        final v = a[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      if (a['user'] is Map) {
        return _extractDisplayNameFromArtisan(
            Map<String, dynamic>.from(a['user']));
      }
    } catch (_) {}
    return 'Artisan';
  }

  // Helper: extract a primary service string from artisan data
  String? _extractPrimaryServiceFromArtisan(Map<String, dynamic>? a) {
    try {
      if (a == null) return null;
      if (a['services'] is List && (a['services'] as List).isNotEmpty) {
        final first = (a['services'] as List).first;
        if (first is Map && first['name'] != null)
          return first['name'].toString();
        if (first is String) return first;
      }
      // fallback to trade or category
      final trade = a['trade'] ?? a['category'] ?? a['service'];
      if (trade is String && trade.trim().isNotEmpty) return trade.trim();
      if (a['user'] is Map) {
        return _extractPrimaryServiceFromArtisan(
            Map<String, dynamic>.from(a['user']));
      }
    } catch (_) {}
    return null;
  }

  // Helper: extract rating and review count
  double? _extractAverageRating(Map<String, dynamic>? a) {
    try {
      if (a == null) return null;
      final candidates = [
        'averageRating',
        'avgRating',
        'rating',
        'ratingAverage',
        'score'
      ];
      for (final k in candidates) {
        final v = a[k];
        if (v != null) {
          final d = double.tryParse(v.toString());
          if (d != null) return d.clamp(0.0, 5.0);
        }
      }

      // If reviews list exists compute average
      if (a['reviews'] is List && (a['reviews'] as List).isNotEmpty) {
        double sum = 0;
        int cnt = 0;
        for (final r in a['reviews']) {
          try {
            final rv = r is Map ? (r['rating'] ?? r['stars'] ?? r['score']) : r;
            final val = double.tryParse(rv.toString());
            if (val != null) {
              sum += val;
              cnt++;
            }
          } catch (_) {}
        }
        if (cnt > 0) return (sum / cnt).clamp(0.0, 5.0);
      }
      if (a['user'] is Map)
        return _extractAverageRating(Map<String, dynamic>.from(a['user']));
    } catch (_) {}
    return null;
  }

  int _extractReviewCount(Map<String, dynamic>? a) {
    try {
      if (a == null) return 0;
      final candidates = [
        'reviewCount',
        'reviewsCount',
        'reviews_count',
        'ratingCount'
      ];
      for (final k in candidates) {
        final v = a[k];
        if (v != null) {
          final i = int.tryParse(v.toString());
          if (i != null) return i;
        }
      }
      if (a['reviews'] is List) return (a['reviews'] as List).length;
      if (a['user'] is Map)
        return _extractReviewCount(Map<String, dynamic>.from(a['user']));
    } catch (_) {}
    return 0;
  }

  // Helper: extract list of service names from artisan data
  List<String> _extractServices(Map<String, dynamic>? a) {
    final out = <String>[];
    try {
      if (a == null) return out;
      final possibleLists = [
        'services',
        'artisanServices',
        'myServices',
        'service_list',
        'offerings',
        'serviceItems',
        'serviceList'
      ];
      for (final k in possibleLists) {
        final v = a[k];
        if (v is List && v.isNotEmpty) {
          for (final s in v) {
            if (s == null) continue;
            if (s is String)
              out.add(s);
            else if (s is Map) {
              final name = s['name'] ??
                  s['title'] ??
                  s['serviceName'] ??
                  s['subCategoryName'];
              if (name != null) out.add(name.toString());
            }
          }
          if (out.isNotEmpty) return out;
        }
      }

      // Fallback: check trade or category
      final trade = a['trade'] ?? a['category'] ?? a['service'];
      if (trade is String && trade.trim().isNotEmpty) out.add(trade.trim());

      if (a['user'] is Map) {
        final nested = _extractServices(Map<String, dynamic>.from(a['user']));
        for (final s in nested) out.add(s);
      }
    } catch (_) {}
    return out;
  }

  bool _isVerifiedArtisan(Map<String, dynamic>? a) {
    try {
      if (a == null) return false;
      final v = a['isVerified'] ??
          a['verified'] ??
          a['kycStatus'] ??
          a['kyc_verified'];
      if (v is bool) return v;
      if (v is String)
        return v.toString().toLowerCase() == 'true' ||
            v.toString().toLowerCase() == 'verified' ||
            v.toString().toLowerCase() == 'completed';
      if (a['user'] is Map)
        return _isVerifiedArtisan(Map<String, dynamic>.from(a['user']));
    } catch (_) {}
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 375;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final horizontalPadding = isSmallScreen ? 16.0 : 20.0;
    final bodyFontSize = isSmallScreen ? 14.0 : 15.0;
    final smallFontSize = isSmallScreen ? 12.0 : 13.0;

    Color _surfaceColor() => Theme.of(context).colorScheme.surface;
    Color _borderColor() => Theme.of(context).dividerColor;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: _borderColor(), width: 1),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(Icons.arrow_back_outlined,
                          color: Theme.of(context).colorScheme.onSurface,
                          size: isSmallScreen ? 22 : 24),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Service Request',
                      style: theme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: isSmallScreen ? 20 : 22,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding, vertical: 20),
                child: Column(
                  children: [
                    // Artisan summary card (recipient)
                    Builder(builder: (c) {
                      final eff = _effectiveArtisan();
                      final imageUrl = _extractProfileImageFromArtisan(eff);
                      var displayName = _extractDisplayNameFromArtisan(eff);
                      if ((displayName == null || displayName.trim().isEmpty) &&
                          widget.artisanName.isNotEmpty)
                        displayName = widget.artisanName;
                      final avg = _extractAverageRating(eff);
                      final reviewCount = _extractReviewCount(eff);
                      final services = _extractServices(eff);

                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            // Profile image
                            Container(
                              width: 64,
                              height: 64,
                              child: Stack(
                                children: [
                                  Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      color: primaryColor.withOpacity(0.08),
                                      shape: BoxShape.circle,
                                    ),
                                    child: ClipOval(
                                      child: imageUrl != null
                                          ? Image.network(imageUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder: (c, e, s) => Icon(
                                              Icons.person_outline,
                                              color: primaryColor,
                                              size: 36))
                                          : Icon(Icons.person_outline,
                                          color: primaryColor, size: 36),
                                    ),
                                  ),
                                  if (_isVerifiedArtisan(eff))
                                    Positioned(
                                      bottom: 0,
                                      right: 0,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.green,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .surface,
                                              width: 2),
                                        ),
                                        child: Icon(Icons.verified,
                                            color: Colors.white, size: 12),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Name, verification, rating and services
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          displayName ?? '',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                              fontWeight: FontWeight.w700),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(children: [
                                    // Stars
                                    for (var i = 0; i < 5; i++)
                                      if (avg != null && avg >= i + 1)
                                        const Icon(Icons.star_rounded,
                                            size: 14, color: Colors.amber)
                                      else if (avg != null &&
                                          avg > i &&
                                          avg < i + 1)
                                        const Icon(Icons.star_half,
                                            size: 14, color: Colors.amber)
                                      else
                                        const Icon(Icons.star_border,
                                            size: 14, color: Colors.amber),
                                    const SizedBox(width: 8),
                                    Text(
                                      avg != null
                                          ? '${avg.toStringAsFixed(1)} ($reviewCount)'
                                          : 'No reviews',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: Colors.grey[600]),
                                    ),
                                  ]),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      for (final s in services.take(3))
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                              color: primaryColor
                                                  .withOpacity(0.12),
                                              borderRadius:
                                              BorderRadius.circular(12)),
                                          child: Text(s,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                  color: primaryColor,
                                                  fontWeight:
                                                  FontWeight.w600)),
                                        ),
                                      if (services.length > 3)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                              color:
                                              primaryColor.withOpacity(0.2),
                                              borderRadius:
                                              BorderRadius.circular(12),
                                              border: Border.all(
                                                  color: primaryColor
                                                      .withOpacity(0.3),
                                                  width: 0.8)),
                                          child: Text(
                                              '+${services.length - 3} more',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                  color: primaryColor,
                                                  fontWeight:
                                                  FontWeight.w600)),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),

                    if (_errorMessage != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: theme.error.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: theme.error, width: 1),
                        ),
                        child: Text(_errorMessage!,
                            style: TextStyle(color: theme.error)),
                      ),

                    // Service Category
                    _buildSelectionCard(
                      context: context,
                      icon: Icons.category_outlined,
                      label: 'Service',
                      value: _selectedCategory?['subCategoryName']?.toString(),
                      placeholder: 'Select a service',
                      onTap: _selectCategory,
                      isRequired: true,
                      isDark: isDark,
                      primaryColor: primaryColor,
                    ),

                    const SizedBox(height: 16),

                    // Service Description (improved helper text)
                    _buildTextAreaCard(
                      context: context,
                      icon: Icons.description_outlined,
                      label: 'Service Description',
                      controller: _descriptionController,
                      hintText:
                      'Brief description (what, where, any constraints)',
                      maxLines: 5,
                      isRequired: true,
                      isDark: isDark,
                      primaryColor: primaryColor,
                    ),

                    const SizedBox(height: 8),
                    // Short helper bullets
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Tip: include details like:',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: Colors.grey[600])),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.check, size: 14, color: primaryColor),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text('What needs to be done',
                                      style: TextStyle(
                                          color: Colors.grey[700],
                                          fontSize: smallFontSize))),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.check, size: 14, color: primaryColor),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text('Any measurements or constraints',
                                      style: TextStyle(
                                          color: Colors.grey[700],
                                          fontSize: smallFontSize))),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.check, size: 14, color: primaryColor),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text('Preferred timeline',
                                      style: TextStyle(
                                          color: Colors.grey[700],
                                          fontSize: smallFontSize))),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Location
                    _buildSelectionCard(
                      context: context,
                      icon: Icons.location_on_outlined,
                      label: 'Location',
                      value: _locationController.text.isEmpty
                          ? null
                          : _locationController.text,
                      placeholder: _isGettingLocation
                          ? 'Getting location...'
                          : 'Tap to set location',
                      onTap: _showLocationOptions,
                      isRequired: true,
                      isDark: isDark,
                      primaryColor: primaryColor,
                      showLoading: _isGettingLocation,
                    ),

                    const SizedBox(height: 16),

                    // Date & Time Row
                    Row(
                      children: [
                        Expanded(
                          child: _buildSelectionCard(
                            context: context,
                            icon: Icons.calendar_today_outlined,
                            label: 'Date',
                            value: _selectedDate != null
                                ? '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}'
                                : null,
                            placeholder: 'Select date',
                            onTap: _selectDate,
                            isRequired: true,
                            isDark: isDark,
                            primaryColor: primaryColor,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildSelectionCard(
                            context: context,
                            icon: Icons.access_time_outlined,
                            label: 'Time',
                            value: _selectedTime != null
                                ? _selectedTime!.format(context)
                                : null,
                            placeholder: 'Select time',
                            onTap: _selectTime,
                            isRequired: true,
                            isDark: isDark,
                            primaryColor: primaryColor,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Urgency
                    _buildUrgencySelector(
                      context: context,
                      primaryColor: primaryColor,
                      urgency: _urgency,
                      onChanged: (value) => setState(() => _urgency = value),
                      isDark: isDark,
                    ),

                    const SizedBox(height: 16),

                    // Attach Photos
                    _buildPhotoSection(
                      context: context,
                      selectedImages: _selectedImages,
                      onPickImages: _pickImages,
                      onRemoveImage: _removeImage,
                      primaryColor: primaryColor,
                      isDark: isDark,
                      smallFontSize: smallFontSize,
                    ),

                    const SizedBox(height: 24),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      child: _isFormValid
                          ? ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFFA20025),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          disabledBackgroundColor: Colors.grey.withOpacity(0.1),
                          disabledForegroundColor: Colors.grey[600],
                        ),
                        onPressed: _submitting ? null : _submitRequest,
                        child: _submitting
                            ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white),
                          ),
                        )
                            : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.send_rounded, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Send Request',
                              style: TextStyle(
                                fontSize: bodyFontSize + 1,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      )
                          : OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.grey.withOpacity(0.2),
                          foregroundColor: Colors.black,
                          side: BorderSide(color: Colors.black, width: 1),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          disabledBackgroundColor: Colors.grey.withOpacity(0.1),
                          disabledForegroundColor: Colors.grey[600],
                        ),
                        onPressed: null,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.send_rounded, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Send Request',
                              style: TextStyle(
                                fontSize: bodyFontSize + 1,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionCard({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    String? value,
    String? placeholder,
    bool isRequired = false,
    bool showLoading = false,
    required bool isDark,
    required Color primaryColor,
  }) {
    final theme = Theme.of(context);
    final isSmall = MediaQuery.of(context).size.width < 375;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: primaryColor, size: isSmall ? 18 : 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontSize: isSmall ? 14 : 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (isRequired)
                        Text(' *',
                            style:
                            TextStyle(color: primaryColor, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (showLoading)
                    SizedBox(
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Text(
                      value ?? placeholder ?? 'Not set',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight:
                        value != null ? FontWeight.w600 : FontWeight.normal,
                        color: value != null
                            ? theme.colorScheme.onSurface
                            : Colors.grey[500],
                        fontSize: isSmall ? 13 : 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildTextAreaCard({
    required BuildContext context,
    required IconData icon,
    required String label,
    required TextEditingController controller,
    required String hintText,
    int maxLines = 4,
    bool isRequired = false,
    required bool isDark,
    required Color primaryColor,
  }) {
    final theme = Theme.of(context);
    final isSmall = MediaQuery.of(context).size.width < 375;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: primaryColor, size: isSmall ? 18 : 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontSize: isSmall ? 14 : 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (isRequired)
                      Text(' *',
                          style: TextStyle(color: primaryColor, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  maxLines: 5,
                  decoration: InputDecoration(
                    hintText: hintText,
                    hintStyle: TextStyle(
                        color: Colors.grey[400], fontSize: isSmall ? 12 : 13),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: isSmall ? 13 : 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUrgencySelector({
    required BuildContext context,
    required Color primaryColor,
    required String urgency,
    required Function(String) onChanged,
    required bool isDark,
  }) {
    final theme = Theme.of(context);
    final isSmall = MediaQuery.of(context).size.width < 375;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.speed_outlined,
                color: primaryColor, size: isSmall ? 18 : 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Urgency',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
                fontSize: isSmall ? 12 : 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Row(
            children: [
              _buildUrgencyChip(
                label: 'Normal',
                isSelected: urgency == 'Normal',
                onTap: () => onChanged('Normal'),
                primaryColor: primaryColor,
              ),
              const SizedBox(width: 8),
              _buildUrgencyChip(
                label: 'Urgent',
                isSelected: urgency == 'Urgent',
                onTap: () => onChanged('Urgent'),
                primaryColor: primaryColor,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUrgencyChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required Color primaryColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? primaryColor : Colors.grey[300]!,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[600],
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoSection({
    required BuildContext context,
    required List<XFile> selectedImages,
    required VoidCallback onPickImages,
    required Function(int) onRemoveImage,
    required Color primaryColor,
    required bool isDark,
    required double smallFontSize,
  }) {
    final theme = Theme.of(context);
    final isSmall = MediaQuery.of(context).size.width < 375;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.photo_camera_outlined,
                    color: primaryColor, size: isSmall ? 18 : 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Attach Photos (Optional)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                    fontSize: isSmall ? 12 : 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onPickImages,
                icon: Icon(Icons.add_photo_alternate_outlined,
                    color: primaryColor, size: 16),
                label: Text(
                  'Add',
                  style: TextStyle(
                      color: primaryColor, fontWeight: FontWeight.w600),
                ),
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
              ),
            ],
          ),
          if (selectedImages.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 80,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: selectedImages.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(selectedImages[index].path),
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () => onRemoveImage(index),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.close,
                                size: 12, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
