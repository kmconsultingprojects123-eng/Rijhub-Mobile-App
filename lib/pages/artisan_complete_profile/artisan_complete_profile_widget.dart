import 'dart:math' as math;

import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../services/artist_service.dart';
import '../../services/user_service.dart';
import '../../services/token_storage.dart';
import 'package:file_picker/file_picker.dart';
import '../../google_maps_config.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';

class ArtisanCompleteProfileWidget extends StatefulWidget {
  // Route identifiers used by the app router
  static const String routeName = 'ArtisanCompleteProfileWidget';
  static const String routePath = '/artisanCompleteProfile';
  const ArtisanCompleteProfileWidget({Key? key}) : super(key: key);

  @override
  _ArtisanCompleteProfileWidgetState createState() => _ArtisanCompleteProfileWidgetState();
}

class _ArtisanCompleteProfileWidgetState extends State<ArtisanCompleteProfileWidget> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _step1Key = GlobalKey<FormState>();
  final _step2Key = GlobalKey<FormState>();
  final _step3Key = GlobalKey<FormState>();
  bool _loading = true;
  bool _saving = false;
  bool _hasArtisanProfile = false;
  int _currentStep = 0;

  // draft to collect step data as user moves through steps
  final Map<String, dynamic> _draftProfile = {};
  final PageController _pageController = PageController();
  late AnimationController _animationController;
  Animation<double>? _fadeAnimation;

  // form fields
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _locationCtrl = TextEditingController();
  final TextEditingController _bioCtrl = TextEditingController();
  final TextEditingController _tradeCtrl = TextEditingController();
  final TextEditingController _perJobCtrl = TextEditingController();
  final TextEditingController _expCtrl = TextEditingController();
  final TextEditingController _certCtrl = TextEditingController();
  final TextEditingController _portfolioCtrl = TextEditingController();
  final TextEditingController _coordsCtrl = TextEditingController();
  final TextEditingController _radiusCtrl = TextEditingController();
  final TextEditingController _perHourCtrl = TextEditingController();

  // Portfolio items: each item {title: string, imagePath: local path or null, imageUrl: remote url or null}
  final List<Map<String, dynamic>> _portfolioItems = [];

  // Certifications: list of {name, filePath, fileUrl}
  final List<Map<String, dynamic>> _certItems = [];

  // Availability: list of {day: String, start: String, end: String}
  final List<Map<String, String>> _availabilityItems = [];

  // Input helper for services (user-facing label 'Service')
  final TextEditingController _serviceInputCtrl = TextEditingController();
  final List<String> _serviceItems = []; // services list shown as chips

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );
    _animationController.forward();
    _load();

    // Ensure any stale dashboard/profile cache is cleared when opening the
    // complete-profile flow so unrelated cached data doesn't prefill fields.
    // This prevents cross-user cached data from appearing if the device was
    // previously used for another artisan account.
    try {
      TokenStorage.deleteDashboardCache();
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to clear dashboard cache on open: $e');
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _locationCtrl.dispose();
    _bioCtrl.dispose();
    _tradeCtrl.dispose();
    _perJobCtrl.dispose();
    _expCtrl.dispose();
    _certCtrl.dispose();
    _portfolioCtrl.dispose();
    _coordsCtrl.dispose();
    _radiusCtrl.dispose();
    _perHourCtrl.dispose();
    _pageController.dispose();
    _serviceInputCtrl.dispose();
    super.dispose();
  }

  // Modern, theme-aware input decoration with improved styling
  InputDecoration _inputDecoration(BuildContext ctx, String label,
      {IconData? prefixIcon, Widget? suffixIcon}) {
    final theme = FlutterFlowTheme.of(ctx);
    final brightness = Theme
        .of(ctx)
        .brightness;

    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        color: theme.secondaryText,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      floatingLabelStyle: TextStyle(
        color: theme.primary,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      prefixIcon: prefixIcon != null ? Icon(
        prefixIcon,
        color: theme.secondaryText,
        size: 20,
      ) : null,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: brightness == Brightness.light
          ? Colors.white.withOpacity(0.95)
          : const Color(0xFF1E1E1E),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: theme.alternate.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: theme.primary,
          width: 2,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: theme.error,
          width: 1.5,
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: theme.error,
          width: 2,
        ),
      ),
      hintStyle: TextStyle(
        color: theme.secondaryText.withOpacity(0.6),
        fontSize: 14,
      ),
    );
  }

  // Styled page title with progress indicator
  Widget _pageTitle(String title, String subtitle, int stepNumber) {
    final theme = FlutterFlowTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: theme.primary,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  stepNumber.toString(),
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.titleLarge.copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 24,
                      color: theme.primaryText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.bodyMedium.copyWith(
                      color: theme.secondaryText,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        // Progress bar
        Container(
          height: 4,
          decoration: BoxDecoration(
            color: theme.alternate.withOpacity(0.2),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Row(
            children: List.generate(3, (index) {
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(
                    right: index < 2 ? 2 : 0,
                  ),
                  decoration: BoxDecoration(
                    color: _currentStep >= index
                        ? theme.primary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  // Styled card for form sections
  Widget _formCard({required Widget child, EdgeInsetsGeometry? padding}) {
    final theme = FlutterFlowTheme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: Theme
            .of(context)
            .brightness == Brightness.light
            ? Colors.white
            : const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
        boxShadow: Theme
            .of(context)
            .brightness == Brightness.light
            ? [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ]
            : null,
        border: Border.all(
          color: theme.alternate.withOpacity(0.1),
          width: 1,
        ),
      ),
      padding: padding ?? const EdgeInsets.all(24),
      child: child,
    );
  }

  // Styled button
  Widget _styledButton({
    required String text,
    required VoidCallback onPressed,
    Color? backgroundColor,
    Color? textColor,
    bool fullWidth = true,
    IconData? icon,
  }) {
    final theme = FlutterFlowTheme.of(context);

    Widget buttonChild = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: textColor ?? Colors.white),
          const SizedBox(width: 8),
        ],
        Text(
          text,
          style: TextStyle(
            color: textColor ?? Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ],
    );

    return Container(
      width: fullWidth ? double.infinity : null,
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor ?? theme.primary,
          foregroundColor: textColor ?? Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shadowColor: theme.primary.withOpacity(0.3),
        ),
        child: buttonChild,
      ),
    );
  }

  // Service chip with modern design
  Widget _serviceChip(String service, int index) {
    final theme = FlutterFlowTheme.of(context);

    return Container(
      margin: const EdgeInsets.only(right: 8, bottom: 8),
      child: Chip(
        label: Text(
          service,
          style: TextStyle(
            color: theme.primaryText,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: theme.primary.withOpacity(0.1),
        deleteIcon: Icon(
          Icons.close,
          size: 18,
          color: theme.secondaryText,
        ),
        onDeleted: () => _removeService(index),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: theme.primary.withOpacity(0.2),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        labelPadding: const EdgeInsets.only(right: 4),
      ),
    );
  }

  // Portfolio item card
  Widget _portfolioItemCard(Map<String, dynamic> item, int index) {
    final theme = FlutterFlowTheme.of(context);
    final title = item['title']?.toString() ?? 'Untitled';
    final imagePath = item['imagePath'];
    final imageUrl = item['imageUrl'];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme
            .of(context)
            .brightness == Brightness.light
            ? Colors.white
            : const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.alternate.withOpacity(0.1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Image preview
              Container(
                height: 140,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16)),
                  color: theme.alternate.withOpacity(0.1),
                ),
                child: imagePath != null
                    ? ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16)),
                  child: Image.file(
                    File(imagePath),
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        _buildImagePlaceholder(theme),
                  ),
                )
                    : imageUrl != null
                    ? ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16)),
                  child: Image.network(
                    imageUrl,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        _buildImagePlaceholder(theme),
                  ),
                )
                    : _buildImagePlaceholder(theme),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: theme.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () => _editPortfolioItem(index),
                          icon: Icon(
                            Icons.edit_outlined,
                            size: 20,
                            color: theme.secondaryText,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: () => _removePortfolioItem(index),
                          icon: Icon(
                            Icons.delete_outline,
                            size: 20,
                            color: theme.error,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildImagePlaceholder(FlutterFlowTheme theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image_outlined,
            size: 48,
            color: theme.secondaryText.withOpacity(0.3),
          ),
          const SizedBox(height: 8),
          Text(
            'No image',
            style: TextStyle(
              color: theme.secondaryText.withOpacity(0.5),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // Certification card
  Widget _certificationCard(Map<String, dynamic> item, int index) {
    final theme = FlutterFlowTheme.of(context);
    final name = item['name']?.toString() ?? 'Untitled';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme
            .of(context)
            .brightness == Brightness.light
            ? Colors.white
            : const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.alternate.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: theme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.verified_outlined,
              color: theme.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item['fileUrl'] != null || item['filePath'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'File attached',
                      style: theme.bodySmall.copyWith(
                        color: theme.secondaryText,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: () => _editCertification(index),
                icon: Icon(
                  Icons.edit_outlined,
                  size: 20,
                  color: theme.secondaryText,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _removeCertification(index),
                icon: Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: theme.error,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Availability card
  Widget _availabilityCard(Map<String, String> item, int index) {
    final theme = FlutterFlowTheme.of(context);
    final day = item['day'] ?? '';
    final start = item['start'] ?? '';
    final end = item['end'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme
            .of(context)
            .brightness == Brightness.light
            ? Colors.white
            : const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.alternate.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.access_time_outlined,
              color: Colors.green,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  day,
                  style: theme.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '$start - $end',
                    style: theme.bodySmall.copyWith(
                      color: theme.secondaryText,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: () => _editAvailability(index),
                icon: Icon(
                  Icons.edit_outlined,
                  size: 20,
                  color: theme.secondaryText,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _removeAvailability(index),
                icon: Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: theme.error,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Empty state widget
  Widget _emptyState(String message, IconData icon, {VoidCallback? onAdd}) {
    final theme = FlutterFlowTheme.of(context);

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: theme.alternate.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.alternate.withOpacity(0.1),
          width: 1,
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 48,
            color: theme.secondaryText.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: theme.bodyMedium.copyWith(
              color: theme.secondaryText,
            ),
            textAlign: TextAlign.center,
          ),
          if (onAdd != null) ...[
            const SizedBox(height: 16),
            _styledButton(
              text: 'Add Item',
              onPressed: onAdd,
              backgroundColor: theme.primary.withOpacity(0.1),
              textColor: theme.primary,
              fullWidth: false,
            ),
          ],
        ],
      ),
    );
  }

  // Load profile data
  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final user = await UserService.getProfile();
      if (kDebugMode) {
        try {
          debugPrint('ArtisanCompleteProfile._load -> user payload keys: ${user?.keys.toList() ?? user}');
        } catch (_) {}
      }
      // Prefer fetching the artisan profile with the explicit userId first
      // to avoid issues with the backend `/me` endpoint and to ensure we
      // always load the correct artisan record for the currently signed-in
      // user. Fall back to the `/me` endpoint if no user-scoped result exists.
      Map<String, dynamic>? artisan;
      final userId = (user?['id'] ?? user?['_id'] ?? user?['userId'])
          ?.toString();
      if (userId != null && userId.isNotEmpty) {
        try {
          artisan = await ArtistService.getByUserId(userId);
          debugPrint('my artisan $artisan');
          if (kDebugMode) {
            try { debugPrint('ArtisanCompleteProfile._load -> getByUserId returned keys: ${artisan?.keys.toList() ?? artisan}'); } catch (_) {}
          }
          if (kDebugMode) debugPrint(
              'ArtisanCompleteProfile._load -> got artisan via getByUserId for userId=$userId');
        } catch (e) {
          if (kDebugMode) debugPrint(
              'ArtisanCompleteProfile._load -> getByUserId failed for $userId: $e');
        }
      }
      // debugPrint('nothing');
      // If getByUserId didn't return a profile, try the /me endpoint as a
      // fallback (some deployments still rely on it).
      if (artisan == null) {
        try {
          artisan = await ArtistService.getMyProfile();
          if (kDebugMode) {
            try { debugPrint('ArtisanCompleteProfile._load -> getMyProfile returned keys: ${artisan?.keys.toList() ?? artisan}'); } catch (_) {}
          }
          if (kDebugMode) debugPrint(
              'ArtisanCompleteProfile._load -> got artisan via getMyProfile fallback');
        } catch (e) {
          if (kDebugMode) debugPrint(
              'ArtisanCompleteProfile._load -> getMyProfile fallback failed: $e');
        }
      }

      // Decide whether the fetched `artisan` is a true artisan document or
      // just a user-like object returned by some servers. Only consider it an
      // artisan when it contains artisan-specific markers to avoid prefill
      // from plain user payloads.
      bool _isArtisanDocument(Map<String, dynamic>? doc) {
        if (doc == null) return false;
        try {
          // Common artisan-specific fields
          final markers = [
            'trade',
            'portfolio',
            'pricing',
            'serviceArea',
            'availability',
            'experience',
            'bio'
          ];
          for (final m in markers) {
            if (doc.containsKey(m) && doc[m] != null) return true;
          }
          // Sometimes backend nests user details under `user` and includes role
          if (doc['user'] is Map) {
            final u = Map<String, dynamic>.from(doc['user']);
            final role = (u['role'] ?? u['type'] ?? '')
                .toString()
                .toLowerCase();
            if (role.contains('artisan')) return true;
          }
          // Some APIs return an explicit `role` or `type` on the artisan object
          final r = (doc['role'] ?? doc['type'] ?? doc['accountType'] ?? '')
              .toString()
              .toLowerCase();
          if (r.contains('artisan')) return true;
          // If it has an _id and at least one contact field, it's still likely a user not an artisan
        } catch (_) {}
        return false;
      }

      _hasArtisanProfile = _isArtisanDocument(artisan);
      if (kDebugMode) {
        try {
          debugPrint('ArtisanCompleteProfile._load -> isArtisanDocument=$_hasArtisanProfile; artisan keys=${artisan?.keys.toList() ?? artisan}');
        } catch (_) {}
      }

      // Helper to read nested strings safely
      String? pickFirstString(List<dynamic> candidates) {
        for (final c in candidates) {
          if (c == null) continue;
          try {
            final s = c.toString();
            if (s.isNotEmpty) return s;
          } catch (_) {}
        }
        return null;
      }

      // If we found an existing artisan profile, prefill the form from it.
      // Otherwise (create-flow) keep the form blank to force explicit input.
      if (_hasArtisanProfile) {
        // Name
        final name = pickFirstString([
          artisan?['user']?['name'],
          artisan?['artisanAuthDetails']?['name'],
          user?['name'],
          user?['fullName']
        ]);
        if (name != null) _nameCtrl.text = name;

        // Email
        final email = pickFirstString(
            [user?['email'], artisan?['user']?['email'], artisan?['email']]);
        if (email != null) _emailCtrl.text = email;

        // Phone
        final phone = pickFirstString(
            [artisan?['user']?['phone'], user?['phone'], user?['mobile']]);
        if (phone != null) _phoneCtrl.text = phone;

        // Location
        final location = pickFirstString([
          artisan?['serviceArea']?['address'],
          user?['location'],
          user?['address']
        ]);
        if (location != null) _locationCtrl.text = location;

        // Services
        final t = artisan?['trade'] ?? user?['trade'];
        _serviceItems.clear();
        if (t is List) {
          for (final s in t) {
            try {
              final v = s?.toString() ?? '';
              if (v.isNotEmpty) _serviceItems.add(v);
            } catch (_) {}
          }
        } else if (t is String && t.isNotEmpty) {
          _serviceItems.addAll(
              t.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty));
        }

        // Pricing perJob
        final perJob = artisan?['pricing']?['perJob'] ?? artisan?['price'] ??
            null;
        if (perJob != null) _perJobCtrl.text = perJob.toString();

        // Bio
        final bio = pickFirstString(
            [artisan?['bio'], user?['bio'], user?['description']]);
        if (bio != null) _bioCtrl.text = bio;

        // Certifications
        final certs = artisan?['certifications'];
        _certItems.clear();
        if (certs is List) {
          for (final c in certs) {
            try {
              if (c is String) {
                _certItems.add({'name': c, 'filePath': null, 'fileUrl': c});
              } else if (c is Map) {
                final name = c['name']?.toString() ?? '';
                final url = c['url']?.toString() ?? c['file']?.toString();
                _certItems.add(
                    {'name': name, 'filePath': null, 'fileUrl': url});
              }
            } catch (_) {}
          }
        }

        // Experience
        final expVal = artisan?['experience'] ?? user?['experience'];
        if (expVal != null) _expCtrl.text = expVal.toString();

        // Availability
        _availabilityItems.clear();
        final avail = artisan?['availability'];
        if (avail is List) {
          for (final a in avail) {
            try {
              if (a is String) {
                final parts = a.split(':');
                if (parts.length >= 2) {
                  final day = parts[0].trim();
                  final times = parts.sublist(1).join(':').trim();
                  final tparts = times.split('-').map((s) => s.trim()).toList();
                  final start = tparts.isNotEmpty ? tparts[0] : '';
                  final end = tparts.length > 1 ? tparts[1] : '';
                  _availabilityItems.add(
                      {'day': day, 'start': start, 'end': end});
                }
              } else if (a is Map) {
                final day = a['day']?.toString() ?? '';
                final start = a['start']?.toString() ?? '';
                final end = a['end']?.toString() ?? '';
                _availabilityItems.add(
                    {'day': day, 'start': start, 'end': end});
              }
            } catch (_) {}
          }
        }

        // Pricing perHour
        final perHour = artisan?['pricing']?['perHour'];
        if (perHour != null) _perHourCtrl.text = perHour.toString();

        // Portfolio items
        final portfolio = artisan?['portfolio'];
        if (portfolio is List) {
          _portfolioItems.clear();
          for (final p in portfolio) {
            try {
              final title = p['title']?.toString() ?? '';
              String? url;
              if (p['images'] is List && (p['images'] as List).isNotEmpty)
                url = (p['images'] as List).first.toString();
              _portfolioItems.add(
                  {'title': title, 'imagePath': null, 'imageUrl': url});
            } catch (_) {}
          }
        }
      } else {
        // Create-flow: ensure all fields are empty so the user fills artisan details explicitly
        _nameCtrl.text = '';
        _emailCtrl.text = '';
        _phoneCtrl.text = '';
        _locationCtrl.text = '';
        _serviceItems.clear();
        _perJobCtrl.text = '';
        _bioCtrl.text = '';
        _certItems.clear();
        _portfolioItems.clear();
        _availabilityItems.clear();
        _coordsCtrl.text = '';
        _radiusCtrl.text = '';
        _perHourCtrl.text = '';
      }
    } catch (e) {
      if (kDebugMode) debugPrint('ArtisanCompleteProfile._load -> error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Save profile
  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      // Build payload using collected draft data where available
      final payload = <String, dynamic>{};

      // trade / services
      payload['trade'] = (_draftProfile['services'] as List?) ?? _serviceItems;

      // experience
      payload['experience'] =
          _draftProfile['experience'] ?? (int.tryParse(_expCtrl.text) ?? 0);

      // certifications
      payload['certifications'] = (_draftProfile['certifications'] as List?) ??
          _certItems.map((c) => c['fileUrl'] ?? c['name'] ?? '').toList();

      // bio
      payload['bio'] = _draftProfile['bio'] ?? _bioCtrl.text.trim();

      // service area
      if (_draftProfile['serviceArea'] != null) {
        payload['serviceArea'] = _draftProfile['serviceArea'];
      } else {
        final addr = _locationCtrl.text.trim();
        if (_coordsCtrl.text.isNotEmpty) {
          final parts = _coordsCtrl.text.split(',').map((s) => s.trim()).where((
              s) => s.isNotEmpty).toList();
          if (parts.length >= 2) {
            final p0 = double.tryParse(parts[0]);
            final p1 = double.tryParse(parts[1]);
            if (p0 != null && p1 != null) {
              payload['serviceArea'] = {
                'address': addr,
                'coordinates': [p1, p0],
                'radius': int.tryParse(_radiusCtrl.text) ?? 0
              };
            } else {
              payload['serviceArea'] =
              {'address': addr, 'radius': int.tryParse(_radiusCtrl.text) ?? 0};
            }
          } else {
            payload['serviceArea'] =
            {'address': addr, 'radius': int.tryParse(_radiusCtrl.text) ?? 0};
          }
        } else {
          payload['serviceArea'] =
          {'address': addr, 'radius': int.tryParse(_radiusCtrl.text) ?? 0};
        }
      }

      // pricing
      payload['pricing'] = {
        'perHour': _draftProfile['perHour'] ?? (int.tryParse(
            _perHourCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0),
        'perJob': _draftProfile['perJob'] ??
            (int.tryParse(_perJobCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ??
                0),
      };

      // availability
      List<String> availabilityList = [];
      final rawAvail = _draftProfile['availability'];
      if (rawAvail != null && rawAvail is List) {
        for (final a in rawAvail) {
          if (a == null) continue;
          if (a is String) {
            availabilityList.add(a);
            continue;
          }
          if (a is Map) {
            final day = (a['day'] ?? a['d'] ?? '').toString();
            final start = (a['start'] ?? a['from'] ?? '').toString();
            final end = (a['end'] ?? a['to'] ?? '').toString();
            if (day.isNotEmpty && (start.isNotEmpty || end.isNotEmpty)) {
              availabilityList.add(
                  '$day: ${start.isNotEmpty ? start : ''}${(start.isNotEmpty &&
                      end.isNotEmpty) ? '-' : ''}${end.isNotEmpty ? end : ''}');
            } else {
              availabilityList.add(a.toString());
            }
            continue;
          }
          availabilityList.add(a.toString());
        }
      } else {
        availabilityList = _availabilityItems.map((a) {
          final day = a['day'] ?? '';
          final start = a['start'] ?? '';
          final end = a['end'] ?? '';
          return '$day: ${start}${(start.isNotEmpty && end.isNotEmpty)
              ? '-'
              : ''}${end}';
        }).where((s) =>
        s
            .trim()
            .isNotEmpty).toList();
      }
      payload['availability'] = availabilityList;

      // Normalize serviceArea coords if draft contains 'coords' string like 'lat,lon'
      if (payload['serviceArea'] is Map) {
        final sa = payload['serviceArea'] as Map;
        if (sa.containsKey('coords') && (sa['coords'] is String)) {
          final coordsRaw = (sa['coords'] as String).split(',').map((s) =>
              s.trim()).where((s) => s.isNotEmpty).toList();
          if (coordsRaw.length >= 2) {
            final lat = double.tryParse(coordsRaw[0]);
            final lon = double.tryParse(coordsRaw[1]);
            if (lat != null && lon != null) {
              sa['coordinates'] = [lon, lat];
            }
          }
          sa.remove('coords');
        }
      }

      // Update user fields
      try {
        final userFields = <String, String>{};
        final nameVal = (_draftProfile['name'] as String?) ??
            _nameCtrl.text.trim();
        final emailVal = (_draftProfile['email'] as String?) ??
            _emailCtrl.text.trim();
        final phoneVal = (_draftProfile['phone'] as String?) ??
            _phoneCtrl.text.trim();
        if (nameVal.isNotEmpty) userFields['name'] = nameVal;
        if (emailVal.isNotEmpty) userFields['email'] = emailVal;
        if (phoneVal.isNotEmpty) userFields['phone'] = phoneVal;
        if (userFields.isNotEmpty) {
          await UserService.updateProfile(userFields);
        }
      } catch (e) {
        if (kDebugMode) debugPrint('UserService.updateProfile failed: $e');
      }

      // Always upload local files via attachments/direct Cloudinary (no multipart to backend)
      final localPaths = <String>[];
      for (final p in _portfolioItems) {
        final path = (p['imagePath'] as String?)?.trim();
        if (path != null && path.isNotEmpty) localPaths.add(path);
      }

      Map<String, dynamic>? res;
      if (localPaths.isNotEmpty) {
        // Always upload local files via attachments/direct Cloudinary (no multipart to backend)
        try {
          if (kDebugMode) debugPrint('Uploading ${localPaths
              .length} portfolio files via attachments/direct upload...');
          final uploaded = await ArtistService.uploadFilesToAttachments(
              localPaths);
          if (kDebugMode) debugPrint('Uploaded results: $uploaded');

          // Map uploaded URLs back into the portfolio items in the same order where possible
          for (int i = 0; i < localPaths.length && i < uploaded.length; i++) {
            final url = (uploaded[i]['url'] ?? '').toString();
            if (url.isNotEmpty) {
              for (final item in _portfolioItems) {
                if ((item['imagePath'] as String?)?.trim() == localPaths[i]) {
                  item['imageUrl'] = url;
                  item['imagePath'] = null;
                  break;
                }
              }
            }
          }

          payload['portfolio'] = _portfolioItems.map((p) =>
          {
            'title': (p['title'] ?? '').toString(),
            'images': p['imageUrl'] != null ? [p['imageUrl']] : [],
          }).toList();

          if (_hasArtisanProfile) {
            res = await ArtistService.updateMyProfile(payload);
          } else {
            res = await ArtistService.createMyProfile(payload);
          }
        } catch (e) {
          if (kDebugMode) debugPrint('Portfolio upload failed: $e');
          // Try sending JSON without portfolio images (best-effort)
          payload['portfolio'] = _portfolioItems.map((p) =>
          {
            'title': (p['title'] ?? '').toString(),
            'images': p['imageUrl'] != null ? [p['imageUrl']] : [],
          }).toList();
          if (_hasArtisanProfile) {
            res = await ArtistService.updateMyProfile(payload);
          } else {
            res = await ArtistService.createMyProfile(payload);
          }
        }
      } else {
        // No local files: send JSON create request
        payload['portfolio'] = _portfolioItems.map((p) =>
        {
          'title': (p['title'] ?? '').toString(),
          'images': p['imageUrl'] != null ? [p['imageUrl']] : [],
        }).toList();
        res = await ArtistService.createMyProfile(payload);
      }

      if (res != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Profile updated successfully',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: FlutterFlowTheme
                .of(context)
                .success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        try {
          await TokenStorage.deleteDashboardCache();
        } catch (e) {
          if (kDebugMode) debugPrint(
              'Failed to clear dashboard cache after save: $e');
        }
        Navigator.of(context).pop(true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Update failed',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: FlutterFlowTheme
                .of(context)
                .error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('ArtisanCompleteProfile._save -> error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Update failed: $e',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: FlutterFlowTheme
              .of(context)
              .error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // Forward geocode
  Future<void> _forwardGeocode(String query) async {
    if (query
        .trim()
        .isEmpty) return;
    try {
      final key = GOOGLE_MAPS_API_KEY;
      if (key.isEmpty) return;
      final encoded = Uri.encodeComponent(query + ' Nigeria');
      final url = Uri.parse('https://maps.googleapis.com/maps/api/geocode/json?address=$encoded&key=$key');
      final resp = await http.get(url).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200 && resp.body.isNotEmpty) {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map && decoded['results'] is List && (decoded['results'] as List).isNotEmpty) {
          final first = (decoded['results'] as List).first;
          final placeName = first['formatted_address']?.toString() ?? '';
          final geometry = first['geometry'];
          if (geometry is Map && geometry['location'] is Map) {
            final loc = geometry['location'];
            final lat = loc['lat'];
            final lon = loc['lng'];
            if (lat is num && lon is num) {
              _coordsCtrl.text = '${lat.toString()},${lon.toString()}';
              _locationCtrl.text = placeName;
              setState(() {});
              return;
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('forwardGeocode error: $e');
    }
  }

  Future<void> _collectStepData(int step) async {
    // Collect fields per step into the draft map
    if (step == 0) {
      _draftProfile['name'] = _nameCtrl.text.trim();
      _draftProfile['email'] = _emailCtrl.text.trim();
      _draftProfile['phone'] = _phoneCtrl.text.trim();
      _draftProfile['bio'] = _bioCtrl.text.trim();
    } else if (step == 1) {
      _draftProfile['services'] = List<String>.from(_serviceItems);
      _draftProfile['experience'] = int.tryParse(_expCtrl.text) ?? 0;
      _draftProfile['certifications'] =
          List.from(_certItems.map((c) => c['fileUrl'] ?? c['name'] ?? ''));
      _draftProfile['availability'] = List.from(_availabilityItems);
    } else if (step == 2) {
      _draftProfile['perHour'] =
          int.tryParse(_perHourCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ??
              0;
      _draftProfile['perJob'] =
          int.tryParse(_perJobCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      _draftProfile['portfolio'] = List.from(_portfolioItems);
      _draftProfile['serviceArea'] = {
        'address': _locationCtrl.text.trim(),
        'coords': _coordsCtrl.text.trim(),
        'radius': int.tryParse(_radiusCtrl.text) ?? 0,
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Scaffold(
      backgroundColor: theme.primaryBackground,
      body: SafeArea(
        child: _loading
            ? Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(theme.primary),
                strokeWidth: 3,
              ),
              const SizedBox(height: 20),
              Text(
                'Loading your profile...',
                style: theme.bodyMedium.copyWith(
                  color: theme.secondaryText,
                ),
              ),
            ],
          ),
        )
            : FadeTransition(
          opacity: _fadeAnimation ?? const AlwaysStoppedAnimation<double>(1.0),
          child: Padding(
            padding: const EdgeInsets.all(0),
            child: Column(
              children: [
                // App Bar
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: theme.secondaryBackground,
                    border: Border(
                      bottom: BorderSide(
                        color: theme.alternate.withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: Icon(
                          Icons.arrow_back_rounded,
                          color: theme.primaryText,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Complete Your Profile',
                          style: theme.titleLarge.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                            color: theme.primaryText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: constraints.maxHeight,
                              maxWidth: math.min(600, constraints.maxWidth),
                            ),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                children: [
                                  SizedBox(
                                    height: constraints.maxHeight,
                                    child: Column(
                                      children: [
                                        Expanded(
                                          child: PageView(
                                            controller: _pageController,
                                            physics: const NeverScrollableScrollPhysics(),
                                            onPageChanged: (i) {
                                              setState(() => _currentStep = i);
                                              _animationController.reset();
                                              _animationController.forward();
                                            },
                                            children: [
                                              // Step 1: Basic Information
                                              SingleChildScrollView(
                                                child: FadeTransition(
                                                  opacity: _fadeAnimation ??
                                                      const AlwaysStoppedAnimation<
                                                          double>(1.0),
                                                  child: Form(
                                                    key: _step1Key,
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment
                                                          .stretch,
                                                      children: [
                                                        _pageTitle(
                                                          'Basic Information',
                                                          'Tell us about yourself',
                                                          1,
                                                        ),
                                                        _formCard(
                                                          child: Column(
                                                            crossAxisAlignment: CrossAxisAlignment
                                                                .stretch,
                                                            children: [
                                                              TextFormField(
                                                                controller: _nameCtrl,
                                                                decoration: _inputDecoration(
                                                                  context,
                                                                  'Full Name',
                                                                  prefixIcon: Icons
                                                                      .person_outline,
                                                                ),
                                                                validator: (
                                                                    v) =>
                                                                (v == null || v
                                                                    .trim()
                                                                    .isEmpty)
                                                                    ? 'Required'
                                                                    : null,
                                                              ),
                                                              const SizedBox(
                                                                  height: 20),
                                                              TextFormField(
                                                                controller: _emailCtrl,
                                                                decoration: _inputDecoration(
                                                                  context,
                                                                  'Email Address',
                                                                  prefixIcon: Icons
                                                                      .email_outlined,
                                                                ),
                                                                keyboardType: TextInputType
                                                                    .emailAddress,
                                                                validator: (
                                                                    v) =>
                                                                (v == null || v
                                                                    .trim()
                                                                    .isEmpty)
                                                                    ? 'Required'
                                                                    : null,
                                                              ),
                                                              const SizedBox(
                                                                  height: 20),
                                                              TextFormField(
                                                                controller: _phoneCtrl,
                                                                decoration: _inputDecoration(
                                                                  context,
                                                                  'Phone Number',
                                                                  prefixIcon: Icons
                                                                      .phone_outlined,
                                                                ),
                                                                keyboardType: TextInputType
                                                                    .phone,
                                                              ),
                                                              const SizedBox(
                                                                  height: 20),
                                                              TextFormField(
                                                                controller: _bioCtrl,
                                                                decoration: _inputDecoration(
                                                                  context,
                                                                  'Bio / About You',
                                                                  prefixIcon: Icons
                                                                      .description_outlined,
                                                                ),
                                                                maxLines: 4,
                                                                minLines: 3,
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              // Step 2: Professional Details
                                              SingleChildScrollView(
                                                child: FadeTransition(
                                                  opacity: _fadeAnimation ??
                                                      const AlwaysStoppedAnimation<
                                                          double>(1.0),
                                                  child: Form(
                                                    key: _step2Key,
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment
                                                          .stretch,
                                                      children: [
                                                        _pageTitle(
                                                          'Professional Details',
                                                          'Tell us about your expertise',
                                                          2,
                                                        ),
                                                        _formCard(
                                                          child: Column(
                                                            crossAxisAlignment: CrossAxisAlignment
                                                                .stretch,
                                                            children: [
                                                              // Services
                                                              Text(
                                                                'Services',
                                                                style: theme
                                                                    .titleMedium
                                                                    .copyWith(
                                                                  fontWeight: FontWeight
                                                                      .w600,
                                                                  fontSize: 18,
                                                                  color: theme
                                                                      .primaryText,
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                  height: 8),
                                                              Text(
                                                                'Add the services you offer',
                                                                style: theme
                                                                    .bodySmall
                                                                    .copyWith(
                                                                  color: theme
                                                                      .secondaryText,
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                  height: 20),
                                                              Row(
                                                                children: [
                                                                  Expanded(
                                                                    child: TextField(
                                                                      controller: _serviceInputCtrl,
                                                                      decoration: _inputDecoration(
                                                                        context,
                                                                        'Type a service and press Add',
                                                                        prefixIcon: Icons
                                                                            .add_circle_outline,
                                                                      ),
                                                                      onSubmitted: (
                                                                          _) =>
                                                                          _addService(),
                                                                    ),
                                                                  ),
                                                                  const SizedBox(
                                                                      width: 12),
                                                                  _styledButton(
                                                                    text: 'Add',
                                                                    onPressed: _addService,
                                                                    fullWidth: false,
                                                                    backgroundColor: theme
                                                                        .primary,
                                                                  ),
                                                                ],
                                                              ),
                                                              const SizedBox(
                                                                  height: 16),
                                                              if (_serviceItems
                                                                  .isNotEmpty)
                                                                Wrap(
                                                                  children: _serviceItems
                                                                      .asMap()
                                                                      .entries
                                                                      .map((
                                                                      entry) =>
                                                                      _serviceChip(
                                                                          entry
                                                                              .value,
                                                                          entry
                                                                              .key))
                                                                      .toList(),
                                                                ),
                                                              const SizedBox(
                                                                  height: 30),
                                                              // Experience
                                                              Text(
                                                                'Experience',
                                                                style: theme
                                                                    .titleMedium
                                                                    .copyWith(
                                                                  fontWeight: FontWeight
                                                                      .w600,
                                                                  fontSize: 18,
                                                                  color: theme
                                                                      .primaryText,
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                  height: 8),
                                                              TextFormField(
                                                                controller: _expCtrl,
                                                                decoration: _inputDecoration(
                                                                  context,
                                                                  'Years of Experience',
                                                                  prefixIcon: Icons
                                                                      .work_history_outlined,
                                                                ),
                                                                keyboardType: TextInputType
                                                                    .number,
                                                              ),
                                                              const SizedBox(
                                                                  height: 30),
                                                              // Certifications
                                                              Row(
                                                                mainAxisAlignment: MainAxisAlignment
                                                                    .spaceBetween,
                                                                children: [
                                                                  Column(
                                                                    crossAxisAlignment: CrossAxisAlignment
                                                                        .start,
                                                                    children: [
                                                                      Text(
                                                                        'Certifications',
                                                                        style: theme
                                                                            .titleMedium
                                                                            .copyWith(
                                                                          fontWeight: FontWeight
                                                                              .w600,
                                                                          fontSize: 18,
                                                                          color: theme
                                                                              .primaryText,
                                                                        ),
                                                                      ),
                                                                      const SizedBox(
                                                                          height: 4),
                                                                      Text(
                                                                        'Add your professional certifications',
                                                                        style: theme
                                                                            .bodySmall
                                                                            .copyWith(
                                                                          color: theme
                                                                              .secondaryText,
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                  IconButton(
                                                                    onPressed: _pickCertification,
                                                                    icon: Icon(
                                                                      Icons
                                                                          .add_circle_outline,
                                                                      color: theme
                                                                          .primary,
                                                                      size: 28,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                              const SizedBox(
                                                                  height: 16),
                                                              if (_certItems
                                                                  .isEmpty)
                                                                _emptyState(
                                                                  'No certifications added yet',
                                                                  Icons
                                                                      .verified_outlined,
                                                                  onAdd: _pickCertification,
                                                                ),
                                                              if (_certItems
                                                                  .isNotEmpty)
                                                                Column(
                                                                  children: List
                                                                      .generate(
                                                                    _certItems
                                                                        .length,
                                                                        (i) =>
                                                                        _certificationCard(
                                                                            _certItems[i],
                                                                            i),
                                                                  ),
                                                                ),
                                                              const SizedBox(
                                                                  height: 30),
                                                              // Availability
                                                              Row(
                                                                mainAxisAlignment: MainAxisAlignment
                                                                    .spaceBetween,
                                                                children: [
                                                                  Column(
                                                                    crossAxisAlignment: CrossAxisAlignment
                                                                        .start,
                                                                    children: [
                                                                      Text(
                                                                        'Availability',
                                                                        style: theme
                                                                            .titleMedium
                                                                            .copyWith(
                                                                          fontWeight: FontWeight
                                                                              .w600,
                                                                          fontSize: 18,
                                                                          color: theme
                                                                              .primaryText,
                                                                        ),
                                                                      ),
                                                                      const SizedBox(
                                                                          height: 4),
                                                                      Text(
                                                                        'Set your working hours',
                                                                        style: theme
                                                                            .bodySmall
                                                                            .copyWith(
                                                                          color: theme
                                                                              .secondaryText,
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                  IconButton(
                                                                    onPressed: _addAvailability,
                                                                    icon: Icon(
                                                                      Icons
                                                                          .add_circle_outline,
                                                                      color: theme
                                                                          .primary,
                                                                      size: 28,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                              const SizedBox(
                                                                  height: 16),
                                                              if (_availabilityItems
                                                                  .isEmpty)
                                                                _emptyState(
                                                                  'No availability slots added yet',
                                                                  Icons
                                                                      .access_time_outlined,
                                                                  onAdd: _addAvailability,
                                                                ),
                                                              if (_availabilityItems
                                                                  .isNotEmpty)
                                                                Column(
                                                                  children: List
                                                                      .generate(
                                                                    _availabilityItems
                                                                        .length,
                                                                        (i) =>
                                                                        _availabilityCard(
                                                                            _availabilityItems[i],
                                                                            i),
                                                                  ),
                                                                ),
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              // Step 3: Pricing and Portfolio
                                              SingleChildScrollView(
                                                child: FadeTransition(
                                                  opacity: _fadeAnimation ??
                                                      const AlwaysStoppedAnimation<
                                                          double>(1.0),
                                                  child: Form(
                                                    key: _step3Key,
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment
                                                          .stretch,
                                                      children: [
                                                        _pageTitle(
                                                          'Pricing & Portfolio',
                                                          'Set your rates and showcase your work',
                                                          3,
                                                        ),
                                                        _formCard(
                                                          child: Column(
                                                            crossAxisAlignment: CrossAxisAlignment
                                                                .stretch,
                                                            children: [
                                                              // Pricing
                                                              Text(
                                                                'Pricing',
                                                                style: theme
                                                                    .titleMedium
                                                                    .copyWith(
                                                                  fontWeight: FontWeight
                                                                      .w600,
                                                                  fontSize: 18,
                                                                  color: theme
                                                                      .primaryText,
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                  height: 8),
                                                              Text(
                                                                'Set your rates for clients',
                                                                style: theme
                                                                    .bodySmall
                                                                    .copyWith(
                                                                  color: theme
                                                                      .secondaryText,
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                  height: 20),
                                                              TextFormField(
                                                                controller: _perHourCtrl,
                                                                decoration: _inputDecoration(
                                                                  context,
                                                                  'Hourly Rate (₦)',
                                                                  // use prefixText so we can show the Naira symbol without changing the decoration helper
                                                                  prefixIcon: null,
                                                                ).copyWith(
                                                                    prefixText: '₦'),
                                                                keyboardType: TextInputType
                                                                    .number,
                                                              ),
                                                              const SizedBox(
                                                                  height: 16),
                                                              TextFormField(
                                                                controller: _perJobCtrl,
                                                                decoration: _inputDecoration(
                                                                  context,
                                                                  'Project Rate (₦)',
                                                                  prefixIcon: Icons
                                                                      .assignment_outlined,
                                                                ).copyWith(
                                                                    prefixText: '₦'),
                                                                keyboardType: TextInputType
                                                                    .number,
                                                              ),
                                                              const SizedBox(
                                                                  height: 30),
                                                              // Portfolio
                                                              Row(
                                                                mainAxisAlignment: MainAxisAlignment
                                                                    .spaceBetween,
                                                                children: [
                                                                  Column(
                                                                    crossAxisAlignment: CrossAxisAlignment
                                                                        .start,
                                                                    children: [
                                                                      Text(
                                                                        'Portfolio',
                                                                        style: theme
                                                                            .titleMedium
                                                                            .copyWith(
                                                                          fontWeight: FontWeight
                                                                              .w600,
                                                                          fontSize: 18,
                                                                          color: theme
                                                                              .primaryText,
                                                                        ),
                                                                      ),
                                                                      const SizedBox(
                                                                          height: 4),
                                                                      Text(
                                                                        'Showcase your best work',
                                                                        style: theme
                                                                            .bodySmall
                                                                            .copyWith(
                                                                          color: theme
                                                                              .secondaryText,
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                  IconButton(
                                                                    onPressed: _pickPortfolioItem,
                                                                    icon: Icon(
                                                                      Icons
                                                                          .add_circle_outline,
                                                                      color: theme
                                                                          .primary,
                                                                      size: 28,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                              const SizedBox(
                                                                  height: 16),
                                                              if (_portfolioItems
                                                                  .isEmpty)
                                                              // show a single action to add portfolio images instead of a textual placeholder
                                                                Center(
                                                                  child: Column(
                                                                    mainAxisSize: MainAxisSize
                                                                        .min,
                                                                    children: [
                                                                      const SizedBox(
                                                                          height: 8),
                                                                      _styledButton(
                                                                        text: 'Add portfolio images',
                                                                        onPressed: _pickPortfolioItem,
                                                                        backgroundColor: theme
                                                                            .primary,
                                                                        fullWidth: false,
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ),
                                                              if (_portfolioItems
                                                                  .isNotEmpty)
                                                                Column(
                                                                  children: List
                                                                      .generate(
                                                                    _portfolioItems
                                                                        .length,
                                                                        (i) =>
                                                                        _portfolioItemCard(
                                                                            _portfolioItems[i],
                                                                            i),
                                                                  ),
                                                                ),
                                                              const SizedBox(
                                                                  height: 30),
                                                              // Location
                                                              Text(
                                                                'Service Area',
                                                                style: theme
                                                                    .titleMedium
                                                                    .copyWith(
                                                                  fontWeight: FontWeight
                                                                      .w600,
                                                                  fontSize: 18,
                                                                  color: theme
                                                                      .primaryText,
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                  height: 8),
                                                              Text(
                                                                'Set your service location and radius',
                                                                style: theme
                                                                    .bodySmall
                                                                    .copyWith(
                                                                  color: theme
                                                                      .secondaryText,
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                  height: 20),
                                                              Row(
                                                                children: [
                                                                  Expanded(
                                                                    child: TextFormField(
                                                                      controller: _locationCtrl,
                                                                      decoration: _inputDecoration(
                                                                        context,
                                                                        'Service Location',
                                                                        prefixIcon: Icons
                                                                            .location_on_outlined,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  const SizedBox(
                                                                      width: 12),
                                                                  _styledButton(
                                                                    text: 'Locate',
                                                                    onPressed: () =>
                                                                        _forwardGeocode(
                                                                            _locationCtrl
                                                                                .text),
                                                                    fullWidth: false,
                                                                    backgroundColor: theme
                                                                        .secondary,
                                                                  ),
                                                                ],
                                                              ),
                                                              const SizedBox(
                                                                  height: 16),
                                                              TextFormField(
                                                                controller: _coordsCtrl,
                                                                decoration: _inputDecoration(
                                                                  context,
                                                                  'Coordinates (lat,long)',
                                                                  prefixIcon: Icons
                                                                      .map_outlined,
                                                                  suffixIcon: IconButton(
                                                                    onPressed: _openMapPicker,
                                                                    icon: Icon(
                                                                      Icons
                                                                          .explore_outlined,
                                                                      color: theme
                                                                          .primary,
                                                                    ),
                                                                  ),
                                                                ),
                                                                keyboardType: TextInputType
                                                                    .numberWithOptions(
                                                                    decimal: true),
                                                              ),
                                                              const SizedBox(
                                                                  height: 16),
                                                              TextFormField(
                                                                controller: _radiusCtrl,
                                                                decoration: _inputDecoration(
                                                                  context,
                                                                  'Service Radius (meters)',
                                                                  prefixIcon: Icons
                                                                      .radio_button_checked_outlined,
                                                                ),
                                                                keyboardType: TextInputType
                                                                    .number,
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 24),
                                        // Navigation Buttons
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment
                                              .center,
                                          children: [
                                            if (_currentStep > 0)
                                              _styledButton(
                                                text: 'Back',
                                                onPressed: () {
                                                  _pageController.previousPage(
                                                    duration: const Duration(
                                                        milliseconds: 400),
                                                    curve: Curves.easeInOut,
                                                  );
                                                },
                                                backgroundColor: theme
                                                    .secondaryBackground,
                                                textColor: theme.primaryText,
                                                fullWidth: false,
                                                icon: Icons.arrow_back_rounded,
                                              ),
                                            if (_currentStep >
                                                0) const SizedBox(width: 12),
                                            Expanded(
                                              child: _styledButton(
                                                text: _currentStep == 2
                                                    ? 'Save Profile'
                                                    : 'Continue',
                                                onPressed: () async {
                                                  // collect data for current step before navigation
                                                  await _collectStepData(
                                                      _currentStep);
                                                  if (_currentStep == 0) {
                                                    if (_step1Key.currentState
                                                        ?.validate() ?? false) {
                                                      await _pageController
                                                          .nextPage(
                                                        duration: const Duration(
                                                            milliseconds: 400),
                                                        curve: Curves.easeInOut,
                                                      );
                                                    }
                                                  } else
                                                  if (_currentStep == 1) {
                                                    // ensure at least one service
                                                    if ((_draftProfile['services'] as List?)
                                                        ?.isNotEmpty ??
                                                        _serviceItems
                                                            .isNotEmpty) {
                                                      await _pageController
                                                          .nextPage(
                                                        duration: const Duration(
                                                            milliseconds: 400),
                                                        curve: Curves.easeInOut,
                                                      );
                                                    } else {
                                                      ScaffoldMessenger.of(
                                                          context).showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                              'Please add at least one service'),
                                                          backgroundColor: theme
                                                              .warning,
                                                        ),
                                                      );
                                                    }
                                                  } else {
                                                    // final collect and save
                                                    await _collectStepData(2);
                                                    await _save();
                                                  }
                                                },
                                                backgroundColor: theme.primary,
                                                icon: _currentStep == 2
                                                    ? Icons.check_circle_outline
                                                    : Icons
                                                    .arrow_forward_rounded,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 32),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Helper methods (addService, removeService, etc.) from original code
  void _addService() {
    final text = _serviceInputCtrl.text.trim();
    if (text.isNotEmpty && !_serviceItems.contains(text)) {
      _serviceItems.add(text);
      _serviceInputCtrl.clear();
      setState(() {});
    }
  }

  void _removeService(int idx) {
    if (idx >= 0 && idx < _serviceItems.length) {
      _serviceItems.removeAt(idx);
      setState(() {});
    }
  }

  Future<void> _pickPortfolioItem() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
      );
      if (result == null) return;
      for (final f in result.files) {
        if (f.path == null) continue;
        final filename = f.name;
        _portfolioItems.add({
          'title': filename,
          'imagePath': f.path,
          'imageUrl': null,
        });
      }
      setState(() {});
    } catch (e) {
      if (kDebugMode) debugPrint('pickPortfolioItem error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not pick images'),
          backgroundColor: FlutterFlowTheme
              .of(context)
              .error,
        ),
      );
    }
  }

  Future<void> _pickCertification() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final f = result.files.first;
      if (f.path == null) return;
      _certItems.add({
        'name': f.name,
        'filePath': f.path,
        'fileUrl': null,
      });
      setState(() {});
    } catch (e) {
      if (kDebugMode) debugPrint('pickCertification error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not pick file'),
          backgroundColor: FlutterFlowTheme
              .of(context)
              .error,
        ),
      );
    }
  }

  // Remove certification
  void _removeCertification(int idx) {
    if (idx >= 0 && idx < _certItems.length) {
      _certItems.removeAt(idx);
      setState(() {});
    }
  }

  // Edit certification: change name or replace file
  Future<void> _editCertification(int idx) async {
    if (idx < 0 || idx >= _certItems.length) return;
    final item = Map<String, dynamic>.from(_certItems[idx]);
    final TextEditingController nameCtrl = TextEditingController(
        text: item['name']?.toString() ?? '');
    String? pickedPath = item['filePath'] as String?;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Edit Certification'),
          content: StatefulBuilder(builder: (ctx2, setStateModal) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Name')),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.attach_file),
                      label: const Text('Replace File'),
                      onPressed: () async {
                        try {
                          final res = await FilePicker.platform.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
                              allowMultiple: false);
                          if (res != null && res.files.isNotEmpty) {
                            final f = res.files.first;
                            if (f.path != null) setStateModal(() =>
                            pickedPath = f.path);
                          }
                        } catch (e) {
                          if (kDebugMode) debugPrint(
                              'replace certification file error: $e');
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(pickedPath != null ? pickedPath!.split(
                        '/').last : (item['fileUrl'] != null
                        ? 'Using remote file'
                        : 'No file'))),
                  ],
                ),
              ],
            );
          }),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final newName = nameCtrl.text.trim();
                _certItems[idx] = {
                  'name': newName.isEmpty ? (item['name'] ?? '') : newName,
                  'filePath': pickedPath,
                  'fileUrl': (pickedPath == null) ? item['fileUrl'] : null,
                };
                setState(() {});
                Navigator.of(ctx).pop();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _removePortfolioItem(int idx) {
    if (idx >= 0 && idx < _portfolioItems.length) {
      _portfolioItems.removeAt(idx);
      setState(() {});
    }
  }

  // Add a new availability slot via dialog
  void _addAvailability() {
    final TextEditingController dayCtrl = TextEditingController();
    final TextEditingController startCtrl = TextEditingController();
    final TextEditingController endCtrl = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = FlutterFlowTheme.of(ctx);
        return AlertDialog(
          title: const Text('Add Availability'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: dayCtrl,
                decoration: InputDecoration(labelText: 'Day (e.g. Mon)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: startCtrl,
                decoration: InputDecoration(
                    labelText: 'Start time (e.g. 08:00)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: endCtrl,
                decoration: InputDecoration(labelText: 'End time (e.g. 17:00)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final day = dayCtrl.text.trim();
                final start = startCtrl.text.trim();
                final end = startCtrl.text.trim();
                if (day.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: const Text('Please enter a day')));
                  return;
                }
                _availabilityItems.add(
                    {'day': day, 'start': start, 'end': end});
                setState(() {});
                Navigator.of(ctx).pop();
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  // Edit an existing availability entry
  void _editAvailability(int idx) {
    if (idx < 0 || idx >= _availabilityItems.length) return;
    final current = Map<String, String>.from(_availabilityItems[idx]);
    final TextEditingController dayCtrl = TextEditingController(
        text: current['day'] ?? '');
    final TextEditingController startCtrl = TextEditingController(
        text: current['start'] ?? '');
    final TextEditingController endCtrl = TextEditingController(
        text: current['end'] ?? '');

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Edit Availability'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: dayCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Day (e.g. Mon)')),
              const SizedBox(height: 8),
              TextField(controller: startCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Start time (e.g. 08:00)')),
              const SizedBox(height: 8),
              TextField(controller: endCtrl,
                  decoration: const InputDecoration(
                      labelText: 'End time (e.g. 17:00)')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final day = dayCtrl.text.trim();
                final start = startCtrl.text.trim();
                final end = endCtrl.text.trim();
                if (day.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: const Text('Please enter a day')));
                  return;
                }
                _availabilityItems[idx] =
                {'day': day, 'start': start, 'end': end};
                setState(() {});
                Navigator.of(ctx).pop();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  // Remove availability
  void _removeAvailability(int idx) {
    if (idx >= 0 && idx < _availabilityItems.length) {
      _availabilityItems.removeAt(idx);
      setState(() {});
    }
  }

  // Simple map picker replacement: allow manual coordinate entry
  Future<void> _openMapPicker() async {
    final TextEditingController coords = TextEditingController(
        text: _coordsCtrl.text);
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Set Coordinates'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter coordinates in the form: latitude,longitude'),
              const SizedBox(height: 8),
              TextField(
                controller: coords,
                decoration: const InputDecoration(
                    labelText: 'Coordinates (lat,lon)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                _coordsCtrl.text = coords.text.trim();
                setState(() {});
                Navigator.of(ctx).pop();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _editPortfolioItem(int idx) async {
    if (idx < 0 || idx >= _portfolioItems.length) return;
    final item = Map<String, dynamic>.from(_portfolioItems[idx]);
    final TextEditingController _titleCtrl = TextEditingController(
        text: item['title']?.toString()
    );
    String? pickedPath = item['imagePath'] as String?;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Edit Portfolio Item'),
          content: StatefulBuilder(builder: (ctx2, setStateModal) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: _titleCtrl,
                    decoration: const InputDecoration(labelText: 'Title')),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.attach_file),
                      label: const Text('Replace Image'),
                      onPressed: () async {
                        try {
                          final res = await FilePicker.platform.pickFiles(
                              type: FileType.image,
                              allowMultiple: false);
                          if (res != null && res.files.isNotEmpty) {
                            final f = res.files.first;
                            if (f.path != null) setStateModal(() =>
                            pickedPath = f.path);
                          }
                        } catch (e) {
                          if (kDebugMode) debugPrint(
                              'replace portfolio image error: $e');
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(pickedPath != null ? pickedPath!.split(
                        '/').last : 'No image selected')),
                  ],
                ),
              ],
            );
          }),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                _portfolioItems[idx] = {
                  'title': _titleCtrl.text.trim(),
                  'imagePath': pickedPath,
                  'imageUrl': (pickedPath == null) ? item['imageUrl'] : null,
                };
                setState(() {});
                Navigator.of(ctx).pop();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }
}

