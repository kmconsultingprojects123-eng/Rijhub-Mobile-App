import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '/services/auth_service.dart';
import '../../utils/app_notification.dart';
import '../../utils/error_messages.dart';
import '../reset_password/reset_password_widget.dart';
import '../forget_password/forget_password_widget.dart';
import 'forgot_password_otp_model.dart';
export 'forgot_password_otp_model.dart';

/// OTP verification screen for the forgot-password flow.
/// The user enters the OTP they received via email, then proceeds
/// to the reset-password screen with the token.
class ForgotPasswordOtpWidget extends StatefulWidget {
  const ForgotPasswordOtpWidget({
    super.key,
    required this.email,
  });

  final String email;

  static String routeName = 'forgotPasswordOtp';
  static String routePath = '/forgotPasswordOtp';

  @override
  State<ForgotPasswordOtpWidget> createState() =>
      _ForgotPasswordOtpWidgetState();
}

class _ForgotPasswordOtpWidgetState extends State<ForgotPasswordOtpWidget> {
  static const Duration _otpExpiryDuration = Duration(minutes: 15);
  static const Color _primaryColor = Color(0xFFA20025);

  bool _submitting = false;
  bool _otpExpired = false;
  String? _errorMessage;

  final TextEditingController _otpController = TextEditingController();

  Timer? _countdownTimer;
  Duration _remaining = _otpExpiryDuration;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _otpController.dispose();
    _stopCountdown();
    super.dispose();
  }

  // -- Timer --

  void _startCountdown() {
    _stopCountdown();
    setState(() {
      _remaining = _otpExpiryDuration;
      _otpExpired = false;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_remaining > const Duration(seconds: 1)) {
          _remaining = _remaining - const Duration(seconds: 1);
        } else {
          _remaining = Duration.zero;
          _otpExpired = true;
          _stopCountdown();
        }
      });
    });
  }

  void _stopCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  // -- Submit OTP --

  Future<void> _submitOtp() async {
    if (_otpExpired) {
      _setError('OTP expired. Please request a new code.');
      return;
    }

    final otp = _otpController.text.trim();
    if (otp.isEmpty) {
      _setError('Please enter the OTP');
      return;
    }

    // The OTP itself is the reset token. Navigate to the reset-password page.
    if (!mounted) return;
    final uri = Uri(
      path: ResetPasswordWidget.routePath,
      queryParameters: {
        'token': otp,
        'email': widget.email,
      },
    );
    context.go(uri.toString());
  }

  // -- Resend Code --

  Future<void> _handleResendCode() async {
    if (!mounted) return;

    setState(() {
      _errorMessage = null;
      _submitting = true;
    });

    try {
      final resp = await AuthService.forgotPasswordImmediate(
        email: widget.email,
        timeoutSeconds: 12,
      );

      if (!mounted) return;
      if (resp['success'] == true) {
        AppNotification.showSuccess(context, 'A new OTP has been sent to your email.');
        _startCountdown();
      } else {
        String msg = 'Could not resend OTP.';
        if (resp['error'] is Map && resp['error']['message'] != null) {
          msg = resp['error']['message'].toString();
        }
        AppNotification.showError(context, msg);
      }
    } catch (e) {
      AppNotification.showError(context, ErrorMessages.humanize(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // -- State helpers --

  void _setError(String? message) {
    if (mounted) setState(() => _errorMessage = message);
  }

  bool get _isButtonDisabled => _submitting || _otpExpired;

  // -- Build --

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.go(ForgetPasswordWidget.routePath),
          color: Colors.grey[600],
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),

              // Title
              Text(
                'Verify OTP',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),

              const SizedBox(height: 12),

              // Subtitle
              Text(
                'Enter the one-time code sent to your email to reset your password.',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey[600],
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 40),

              // Email info and timer
              Text(
                'We sent a verification code to:',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      widget.email,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _formatDuration(_remaining),
                      style: TextStyle(
                        fontSize: 13,
                        color: _primaryColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 40),

              // OTP Field
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                style: const TextStyle(
                  fontSize: 18,
                  letterSpacing: 2,
                ),
                decoration: InputDecoration(
                  hintText: 'Enter verification code',
                  hintStyle: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[400],
                    letterSpacing: 0,
                  ),
                  filled: true,
                  fillColor: isDark ? Colors.grey[900] : Colors.grey[50],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: _primaryColor,
                      width: 1.5,
                    ),
                  ),
                  errorText: _errorMessage,
                  contentPadding: const EdgeInsets.all(18),
                ),
                onSubmitted: (_) => _submitOtp(),
              ),

              const SizedBox(height: 24),

              // Verify Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  onPressed: _isButtonDisabled ? null : _submitOtp,
                  child: _submitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Verify',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 16),

              // Resend Code Button
              Center(
                child: TextButton(
                  onPressed: _submitting ? null : _handleResendCode,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(50, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    _otpExpired ? 'Request new code' : 'Resend code',
                    style: TextStyle(
                      color: _primaryColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),

              const Spacer(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
