import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/kyc_service.dart';
import '../../services/token_storage.dart';

/// **LEGACY — kept for rollback.**
///
/// Original camera-based liveness selfie capture. Posts the selfie + NIN to
/// `POST /api/kyc/dojah/nin-selfie` and pops with a result map:
///   { status: 'approved' | 'rejected' | 'pending_review', failureReason?, ... }
///
/// Replaced by the official `dojah_kyc_sdk_flutter` SDK which is launched
/// directly from `_startVerification` in `artisan_onboarding_widget.dart`.
/// The SDK runs Dojah's full active-liveness flow (smile/blink) inside a
/// native widget and returns a reference ID, which the client then sends to
/// `POST /api/kyc/dojah/verify-reference` (see KYC_DOJAH_SDK_BACKEND_SPEC.md).
///
/// This file is intentionally retained — the `/nin-selfie` endpoint is still
/// supported by the backend as a fallback, so this widget can be re-wired
/// quickly if the SDK path is unavailable on a given device.
class LivenessCheckWidget extends StatefulWidget {
  final String nin;
  final String? firstName;
  final String? lastName;

  const LivenessCheckWidget({
    super.key,
    required this.nin,
    this.firstName,
    this.lastName,
  });

  @override
  State<LivenessCheckWidget> createState() => _LivenessCheckWidgetState();
}

class _LivenessCheckWidgetState extends State<LivenessCheckWidget> {
  final Color primaryColor = const Color(0xFFA20025);
  bool _submitting = false;

  Future<void> _verify() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 80,
        maxWidth: 1200,
      );
      if (picked == null) {
        setState(() => _submitting = false);
        return;
      }
      final selfie = File(picked.path);
      final token = await TokenStorage.getToken();
      if (token == null || token.isEmpty) {
        _toast('You\'re not signed in. Please log in and try again.');
        if (mounted) setState(() => _submitting = false);
        return;
      }

      final body = await KycService.submitDojahNinSelfie(
        nin: widget.nin,
        selfie: selfie,
        firstName: widget.firstName,
        lastName: widget.lastName,
        token: token,
      );

      Map<String, dynamic> data = {};
      if (body['data'] is Map) {
        data = Map<String, dynamic>.from(body['data'] as Map);
      } else if (body.isNotEmpty) {
        data = Map<String, dynamic>.from(body);
      }
      // Common response shapes:
      //   approved   → { status: 'approved', match, confidenceValue, ... }
      //   rejected   → { status: 'rejected', match, confidenceValue, ... }
      //   manual     → { status: 'pending_review', failureReason, ... }
      if (!mounted) return;
      Navigator.of(context).pop(data);
    } on UserFriendlyException catch (e) {
      if (kDebugMode) debugPrint('Liveness: ${e.developerMessage ?? e.userMessage}');
      _toast(e.userMessage);
      if (mounted) setState(() => _submitting = false);
    } catch (e) {
      if (kDebugMode) debugPrint('Liveness unexpected: $e');
      _toast('Verification failed. Please try again.');
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F8),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'Get Set Up',
          style: TextStyle(fontWeight: FontWeight.w700, color: Colors.black),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Profile Completion',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: const LinearProgressIndicator(
                value: 0,
                minHeight: 6,
                backgroundColor: Color(0xFFFCE4EC),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Complete these 3 steps to start receiving booking requests from customers in your area.',
              style:
                  TextStyle(fontSize: 13, color: Colors.black54, height: 1.4),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFEFEFEF)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFCE4EC),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.person_outline,
                            color: primaryColor, size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Liveness Check',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Verification to confirm Personality',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.expand_less, color: Colors.black54),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Center(
                    child: SizedBox(
                      height: 200,
                      width: 220,
                      child: CustomPaint(
                        painter: _FaceFramePainter(color: primaryColor),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  color: primaryColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                width: 110,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFCE4EC),
                                  borderRadius: BorderRadius.circular(60),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      onPressed: _submitting ? null : _verify,
                      child: _submitting
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Text(
                              'Verify Now',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FaceFramePainter extends CustomPainter {
  final Color color;
  _FaceFramePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const corner = 26.0;
    // Top-left
    canvas.drawLine(const Offset(0, corner), Offset.zero, paint);
    canvas.drawLine(Offset.zero, const Offset(corner, 0), paint);
    // Top-right
    canvas.drawLine(Offset(size.width - corner, 0), Offset(size.width, 0), paint);
    canvas.drawLine(
        Offset(size.width, 0), Offset(size.width, corner), paint);
    // Bottom-left
    canvas.drawLine(
        Offset(0, size.height - corner), Offset(0, size.height), paint);
    canvas.drawLine(
        Offset(0, size.height), Offset(corner, size.height), paint);
    // Bottom-right
    canvas.drawLine(Offset(size.width - corner, size.height),
        Offset(size.width, size.height), paint);
    canvas.drawLine(Offset(size.width, size.height - corner),
        Offset(size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
