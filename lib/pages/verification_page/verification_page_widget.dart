import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '/services/token_storage.dart';
import '/services/auth_service.dart';
import '../../utils/phone_utils.dart';
import '/index.dart';
import '../../utils/navigation_utils.dart';
import '../../state/auth_notifier.dart';
import '../../flutter_flow/flutter_flow_theme.dart';

class VerificationPageWidget extends StatefulWidget {
  const VerificationPageWidget({
    super.key,
    this.password,
    this.role,
  });

  final String? password;
  final String? role;

  static String routeName = 'VerificationPage';
  static String routePath = '/verificationPageCore';

  @override
  State<VerificationPageWidget> createState() => _VerificationPageWidgetState();
}

class _VerificationPageWidgetState extends State<VerificationPageWidget> {
  // Constants
  static const Duration _otpExpiryDuration = Duration(minutes: 15);
  static const int _otpLength = 6;

  // Colors
  static const Color _darkBg = Color(0xFF09090B);
  static const Color _darkInputBg = Color(0xFF18181B);
  static const Color _darkButtonBg = Color(0xFF27272A);
  static const Color _darkButtonText = Color(0xFF71717A);
  static const Color _grayText = Color(0xFFA1A1AA);
  static const Color _lightGrayText = Color(0xFFD4D4D8);

  // State
  bool _loading = true;
  bool _submitting = false;
  bool _otpExpired = false;
  String? _errorMessage;

  // Data
  String? _phone;
  String? _reference;
  String? _email;
  String? _displayPhone;
  String? _userName;

  // Controllers - one per OTP digit
  final List<TextEditingController> _otpControllers =
      List.generate(_otpLength, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
      List.generate(_otpLength, (_) => FocusNode());

  // Timer
  Timer? _countdownTimer;
  Duration _remaining = _otpExpiryDuration;

  @override
  void initState() {
    super.initState();
    _startCountdown();
    _loadRecent();
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

  // MARK: - Timer Management
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

  // MARK: - Data Loading
  Future<void> _loadRecent() async {
    final recent = await TokenStorage.getRecentRegistration();
    if (!mounted) return;

    setState(() {
      _phone = recent['phone']?.toString();
      _reference = recent['reference']?.toString();
      _email = recent['email']?.toString();
      _userName = recent['name']?.toString();

      if (_phone?.isNotEmpty ?? false) {
        final normalized = _phone!.startsWith('+') ? _phone! : '+$_phone!';
        _displayPhone = formatPhoneForDisplay(normalized);
      }

      _loading = false;
    });
  }

  // MARK: - OTP Input Helpers
  String get _otpText => _otpControllers.map((c) => c.text).join();

  bool get _isOtpComplete => _otpControllers.every((c) => c.text.isNotEmpty);

  void _onOtpDigitChanged(int index, String value) {
    _setError(null);

    if (value.length > 1) {
      // Handle paste: distribute digits across fields
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

  // MARK: - OTP Verification
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

    _setSubmitting(true);

    try {
      if (_reference == null || _reference!.isEmpty) {
        _setError('Missing verification ID. Please try again.');
        return;
      }

      final idToken = await AuthService.verifyOtpWithFirebase(
        verificationId: _reference!,
        smsCode: otp,
      );

      if (idToken != null) {
        final result = await AuthService.registerWithFirebaseToken(
          idToken: idToken,
          name: _userName ?? '',
          email: _email ?? '',
          password: widget.password ?? '',
          role: widget.role ?? 'customer',
        );

        if (result['success'] == true) {
          await _handleVerificationSuccess(result);
        } else {
          _handleVerificationError(result);
        }
      } else {
        _setError('Firebase verification failed. Please try again.');
      }
    } catch (e) {
      _setError('Invalid OTP. Please check the code and try again.');
    } finally {
      if (mounted) _setSubmitting(false);
    }
  }

  Future<void> _handleVerificationSuccess(Map<String, dynamic> result) async {
    String? token;
    String? parsedRole;
    try {
      final body = result['data'] ?? result;
      if (body is Map) {
        token = (body['token'] ?? body['data']?['token'])?.toString();
        parsedRole =
            (body['role'] ?? body['user']?['role'] ?? body['data']?['role'])
                ?.toString();
      }
      if (parsedRole != null && parsedRole.isNotEmpty)
        parsedRole = parsedRole.toLowerCase();
    } catch (_) {
      token = null;
      parsedRole = null;
    }

    try {
      if (parsedRole != null && parsedRole.isNotEmpty) {
        await AuthNotifier.instance.login(parsedRole, token: token);
      } else if (token != null && token.isNotEmpty) {
        await AuthNotifier.instance.setToken(token);
      } else {
        await AuthNotifier.instance.refreshAuth();
      }
    } catch (_) {}

    final timeout = DateTime.now().add(const Duration(seconds: 3));
    while (DateTime.now().isBefore(timeout)) {
      if (AuthNotifier.instance.profile != null) break;
      await Future.delayed(const Duration(milliseconds: 150));
    }

    if (!mounted) return;

    String roleStr = parsedRole ?? AuthNotifier.instance.userRole ?? '';
    if (roleStr.isEmpty) {
      try {
        final stored = await TokenStorage.getRole();
        if (stored != null && stored.isNotEmpty) roleStr = stored.toLowerCase();
      } catch (_) {}
    }

    await _showWelcomeBottomSheet(roleStr);
  }

  Future<void> _showWelcomeBottomSheet(String role) async {
    final displayName = _userName?.isNotEmpty == true ? _userName! : 'there';

    await showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildWelcomeSheet(displayName, role),
    );
  }

  Widget _buildWelcomeSheet(String name, String role) {
    final isArtisan = role.toLowerCase().contains('artisan');
    final theme = Theme.of(context);
    final ffTheme = FlutterFlowTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
      ),
      constraints: BoxConstraints(
        minHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 32,
          bottom: 32 + bottomInset,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                color: Colors.green,
                size: 60,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Welcome to RIJHUB!',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: ffTheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Hello, $name',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isArtisan
                  ? 'Your artisan account has been successfully verified. You can now start receiving job requests and growing your business.'
                  : 'Your account has been successfully verified. You can now explore and hire skilled artisans in your area.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.7),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: ffTheme.primary.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: ffTheme.primary.withOpacity(0.1),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildFeatureItem(
                    icon: isArtisan ? Icons.work_outline : Icons.search,
                    label: isArtisan ? 'Manage Jobs' : 'Find Artisans',
                    primaryColor: ffTheme.primary,
                  ),
                  Container(
                    height: 30,
                    width: 1,
                    color: ffTheme.primary.withOpacity(0.2),
                  ),
                  _buildFeatureItem(
                    icon: Icons.message_outlined,
                    label: 'Chat',
                    primaryColor: ffTheme.primary,
                  ),
                  Container(
                    height: 30,
                    width: 1,
                    color: ffTheme.primary.withOpacity(0.2),
                  ),
                  _buildFeatureItem(
                    icon: Icons.payment_outlined,
                    label: 'Secure Payments',
                    primaryColor: ffTheme.primary,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: ffTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                onPressed: () => _navigateToDashboard(role),
                child: const Text(
                  'Get Started',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureItem({required IconData icon, required String label, required Color primaryColor}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: primaryColor, size: 24),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: primaryColor,
          ),
        ),
      ],
    );
  }

  Future<void> _navigateToDashboard(String role) async {
    Navigator.of(context).pop();
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    try {
      final router = GoRouter.of(context);
      if (role.contains('artisan')) {
        router.go(ArtisanDashboardPageWidget.routePath);
      } else {
        router.go(HomePageWidget.routePath);
      }
    } catch (_) {
      try {
        if (role.contains('artisan')) {
          await NavigationUtils.safeReplaceAllWith(
              context, ArtisanDashboardPageWidget());
        } else {
          await NavigationUtils.safeReplaceAllWith(context, HomePageWidget());
        }
      } catch (_) {}
    }
  }

  void _handleVerificationError(Map<String, dynamic> result) {
    final error = result['error'];
    String message = 'Verification failed';

    if (error is Map && error['message'] != null) {
      message = error['message'].toString();
    } else if (error != null) {
      message = error.toString();
    }

    _setError(message);
  }

  // MARK: - Resend Code
  Future<void> _handleResendCode() async {
    if (!mounted) return;

    if (_otpExpired) {
      _startCountdown();
      for (final c in _otpControllers) {
        c.clear();
      }
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A new code will be requested.')));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'To resend, go back to the registration screen and try again.')));
  }

  // MARK: - State Helpers
  void _setError(String? message) {
    if (mounted) setState(() => _errorMessage = message);
  }

  void _setSubmitting(bool value) {
    if (mounted) setState(() => _submitting = value);
  }

  bool get _isButtonDisabled => _submitting || _otpExpired || !_isOtpComplete;

  // MARK: - Build Methods
  @override
  Widget build(BuildContext context) {
    if (_loading) return _buildLoading();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ffTheme = FlutterFlowTheme.of(context);

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
                  onTap: () => Navigator.of(context).maybePop(),
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

              // Rose icon circle
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: ffTheme.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: ffTheme.primary.withOpacity(0.2),
                      blurRadius: 30,
                      spreadRadius: -5,
                    ),
                  ],
                  border: Border.all(
                    color: ffTheme.primary.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: ffTheme.primary,
                  size: 32,
                ),
              ),

              const SizedBox(height: 24),

              // Title
              Text(
                'Verify phone',
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
                'Enter the one-time code sent to your phone to\nverify your account.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: isDark ? _grayText : Colors.grey[500],
                  height: 1.85,
                ),
              ),

              const SizedBox(height: 20),

              // Phone info
              if (_displayPhone != null) ...[
                Text(
                  'We sent an SMS with a verification code to:',
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
                  _displayPhone!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15.3,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87,
                    height: 1.83,
                  ),
                ),
              ],

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
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: ffTheme.primary,
                      height: 1.68,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

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
                            borderSide: BorderSide(
                              color: ffTheme.primary,
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
                  style: TextStyle(
                    fontSize: 12,
                    color: ffTheme.primary,
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
                        : ffTheme.primary,
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
                  onPressed: _handleResendCode,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(50, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    _otpExpired ? 'Request new code' : 'Resend code',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: ffTheme.primary,
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

  Widget _buildLoading() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ffTheme = FlutterFlowTheme.of(context);
    return Scaffold(
      backgroundColor: isDark ? _darkBg : Colors.white,
      body: Center(
        child: CircularProgressIndicator(color: ffTheme.primary),
      ),
    );
  }
}
