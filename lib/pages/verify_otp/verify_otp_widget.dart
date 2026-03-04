// Adapter page for navigating to the existing verification UI while
// ensuring the recent registration email is cached so `VerificationPageWidget`
// can read it from `TokenStorage.getRecentRegistration()`.

import 'package:flutter/material.dart';
import '/services/token_storage.dart';
import '/index.dart';
import '../../utils/navigation_utils.dart';
import '../../utils/phone_utils.dart';

class VerifyOtpWidget extends StatefulWidget {
  const VerifyOtpWidget({super.key, this.phone, this.reference, this.email, Object? $creationLocation});

  final String? phone;
  // Provider reference returned by server (SendChamp reference). Optional.
  final String? reference;
  // Email passed via query string from registration page. Optional.
  final String? email;

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
        // Replace current route with the core VerificationPageWidget to avoid
        // stacking duplicate pages when users go back.
        try {
          // Use pushReplacement to avoid triggering router-level replace-all
          // logic which can be intercepted by global redirects. This keeps
          // navigation imperative and avoids accidental redirection to splash.
          await NavigationUtils.safePushReplacement(context, VerificationPageWidget());
        } catch (_) {
          // Fallback: simple push replacement
          try {
            NavigationUtils.safePushReplacement(context, VerificationPageWidget());
          } catch (_) {
            // As a last resort, just push the page normally
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => VerificationPageWidget()));
          }
        }
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
