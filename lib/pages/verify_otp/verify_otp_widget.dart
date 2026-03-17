// Adapter page for navigating to the existing verification UI while
// ensuring the recent registration email is cached so `VerificationPageWidget`
// can read it from `TokenStorage.getRecentRegistration()`.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '/services/token_storage.dart';
import '/index.dart';
import '../../utils/phone_utils.dart';

class VerifyOtpWidget extends StatefulWidget {
  const VerifyOtpWidget({
    super.key,
    this.phone,
    this.reference,
    this.email,
    this.password,
    this.role,
    Object? $creationLocation,
  });

  final String? phone;
  // Provider reference returned by server (SendChamp reference or Firebase verificationId).
  final String? reference;
  final String? email;
  final String? password;
  final String? role;

  static String routeName = 'VerifyOtp';
  static String routePath = '/verificationPage';

  @override
  State<VerifyOtpWidget> createState() => _VerifyOtpWidgetState();
}

class _VerifyOtpWidgetState extends State<VerifyOtpWidget> {
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    // Cache the recent registration email so the verification page can read it
    // when opened via router with a query param.
    // Cache phone when provided (phone-only verification)
    if (widget.phone != null && widget.phone!.isNotEmpty) {
      // Normalize phone to API shape before saving so verification reads canonical value
      final normalized = normalizePhoneForApi(widget.phone!.trim());
      TokenStorage.saveRecentRegistration(phone: normalized);
    }
    // Cache the email if passed via query so verification page receives it
    // even if TokenStorage wasn't populated previously.
    if (widget.email != null && widget.email!.isNotEmpty) {
      TokenStorage.saveRecentRegistration(email: widget.email!.trim());
    }
    // Cache provider reference if present so verification handler can use it
    if (widget.reference != null && widget.reference!.isNotEmpty) {
      TokenStorage.saveRecentRegistration(reference: widget.reference);
    }
    // Small delay to allow route transition to complete before pushing the
    // real verification UI. This keeps the navigation smooth.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (!_initialized) {
        _initialized = true;
        // Replace current route with the core VerificationPageWidget.
        // Use GoRouter directly — safePushRoute checks isGuestSession() which
        // returns true for unauthenticated users and would block navigation
        // during the registration/verification flow.
        if (!mounted) return;
        final uri = Uri(
          path: VerificationPageWidget.routePath,
          queryParameters: {
            'password': widget.password ?? '',
            'role': widget.role ?? '',
          },
        );
        GoRouter.of(context).pushReplacement(uri.toString());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Render a placeholder while the adapter performs its work.
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}
