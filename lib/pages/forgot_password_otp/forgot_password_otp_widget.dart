import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  static const int _otpLength = 6;

  // Colors
  static const Color _roseColor = Color(0xFFF43F5E);
  static const Color _darkBg = Color(0xFF09090B);
  static const Color _darkInputBg = Color(0xFF18181B);
  static const Color _darkButtonBg = Color(0xFF27272A);
  static const Color _darkButtonText = Color(0xFF71717A);
  static const Color _grayText = Color(0xFFA1A1AA);
  static const Color _lightGrayText = Color(0xFFD4D4D8);

  bool _submitting = false;
  bool _otpExpired = false;
  String? _errorMessage;

  final List<TextEditingController> _otpControllers =
      List.generate(_otpLength, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
      List.generate(_otpLength, (_) => FocusNode());

  Timer? _countdownTimer;
  Duration _remaining = _otpExpiryDuration;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
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

  // -- OTP Input Helpers --

  String get _otpText => _otpControllers.map((c) => c.text).join();

  bool get _isOtpComplete => _otpControllers.every((c) => c.text.isNotEmpty);

  void _onOtpDigitChanged(int index, String value) {
    _setError(null);

    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
      for (int i = 0; i < _otpLength && i < digits.length; i++) {
        _otpControllers[i].text = digits[i];
      }
      final lastIndex = (digits.length - 1).clamp(0, _otpLength - 1);
      if (lastIndex < _otpLength - 1) {
        _focusNodes[lastIndex + 1].requestFocus();
      } else {
        _focusNodes[lastIndex].unfocus();
        if (_isOtpComplete) _submitOtp();
      }
      return;
    }

    if (value.isNotEmpty && index < _otpLength - 1) {
      _focusNodes[index + 1].requestFocus();
    }

    if (_isOtpComplete) {
      _focusNodes[index].unfocus();
      _submitOtp();
    }
  }

  void _onOtpKeyEvent(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _otpControllers[index].text.isEmpty &&
        index > 0) {
      _otpControllers[index - 1].clear();
      _focusNodes[index - 1].requestFocus();
    }
  }

  // -- Submit OTP --

  Future<void> _submitOtp() async {
    if (_otpExpired) {
      _setError('OTP expired. Please request a new code.');
      return;
    }

    final otp = _otpText.trim();
    if (otp.isEmpty || otp.length < _otpLength) {
      _setError('Please enter the complete OTP');
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
        AppNotification.showSuccess(
            context, 'A new OTP has been sent to your email.');
        _startCountdown();
        // Clear existing OTP inputs
        for (final c in _otpControllers) {
          c.clear();
        }
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

  bool get _isButtonDisabled => _submitting || _otpExpired || !_isOtpComplete;

  // -- Build --

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? _darkBg : Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            children: [
              const SizedBox(height: 12),

              // Back button
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () => context.go(ForgetPasswordWidget.routePath),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.black : Colors.grey[100],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.chevron_left,
                      color: isDark ? _grayText : Colors.grey[600],
                      size: 24,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Email icon circle
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: _roseColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE11D48).withOpacity(0.2),
                      blurRadius: 30,
                      spreadRadius: -5,
                    ),
                  ],
                  border: Border.all(
                    color: _roseColor.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.email_outlined,
                  color: _roseColor,
                  size: 32,
                ),
              ),

              const SizedBox(height: 24),

              // Title
              Text(
                'Verify OTP',
                style: TextStyle(
                  fontSize: 25.5,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black87,
                  height: 1.41,
                ),
              ),

              const SizedBox(height: 12),

              // Subtitle
              Text(
                'Enter the one-time code sent to your email to\nreset your password.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: isDark ? _grayText : Colors.grey[500],
                  height: 1.85,
                ),
              ),

              const SizedBox(height: 20),

              // Email info
              Text(
                'We sent a verification code to:',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: isDark ? _lightGrayText : Colors.grey[600],
                  height: 1.68,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.email,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15.3,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black87,
                  height: 1.83,
                ),
                overflow: TextOverflow.ellipsis,
              ),

              const SizedBox(height: 20),

              // Timer
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Expires in  ',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: isDark ? _grayText : Colors.grey[500],
                      height: 1.68,
                    ),
                  ),
                  Text(
                    _formatDuration(_remaining),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _roseColor,
                      height: 1.68,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 36),

              // OTP Input Boxes
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(_otpLength, (index) {
                  return SizedBox(
                    width: 48,
                    height: 56,
                    child: KeyboardListener(
                      focusNode: FocusNode(),
                      onKeyEvent: (event) => _onOtpKeyEvent(index, event),
                      child: TextField(
                        controller: _otpControllers[index],
                        focusNode: _focusNodes[index],
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        maxLength: 1,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          counterText: '',
                          filled: true,
                          fillColor: isDark ? _darkInputBg : Colors.grey[100],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: _roseColor,
                              width: 1.5,
                            ),
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (value) => _onOtpDigitChanged(index, value),
                      ),
                    ),
                  );
                }),
              ),

              // Error message
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: _roseColor,
                  ),
                ),
              ],

              const SizedBox(height: 40),

              // Verify Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isButtonDisabled
                        ? (isDark ? _darkButtonBg : Colors.grey[200])
                        : _roseColor,
                    foregroundColor: _isButtonDisabled
                        ? (isDark ? _darkButtonText : Colors.grey[400])
                        : Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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
                      : Text(
                          'Verify',
                          style: TextStyle(
                            fontSize: 13.6,
                            fontWeight: FontWeight.w700,
                            color: _isButtonDisabled
                                ? (isDark ? _darkButtonText : Colors.grey[400])
                                : Colors.white,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 20),

              // Resend Code
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
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _roseColor,
                      height: 1.68,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
