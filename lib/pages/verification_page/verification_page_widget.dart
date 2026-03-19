import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '/services/token_storage.dart';
import '/services/auth_service.dart';
import '../../utils/phone_utils.dart';
import '/index.dart';
import '../../utils/navigation_utils.dart';
import '../../state/auth_notifier.dart';

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
  static const Color _primaryColor = Color(0xFFA20025);

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

  // Controllers
  final TextEditingController _otpController = TextEditingController();

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
    _otpController.dispose();
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

  // MARK: - OTP Verification
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

    _setSubmitting(true);

    try {
      // 1. Verify OTP with Firebase
      if (_reference == null || _reference!.isEmpty) {
        _setError('Missing verification ID. Please try again.');
        return;
      }

      final idToken = await AuthService.verifyOtpWithFirebase(
        verificationId: _reference!,
        smsCode: otp,
      );

      if (idToken != null) {
        // 2. Send ID Token to backend to complete registration/verification
        final result = await AuthService.registerWithFirebaseToken(
          idToken: idToken,
          name: _userName ?? '',
          email: _email ?? '',
          password: widget.password ?? '',
          // phone: _phone ?? '',
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
    // Extract token & role from common response shapes
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

    // Update AuthNotifier state
    try {
      if (parsedRole != null && parsedRole.isNotEmpty) {
        await AuthNotifier.instance.login(parsedRole, token: token);
      } else if (token != null && token.isNotEmpty) {
        await AuthNotifier.instance.setToken(token);
      } else {
        await AuthNotifier.instance.refreshAuth();
      }
    } catch (_) {}

    // Wait for profile to populate
    final timeout = DateTime.now().add(const Duration(seconds: 3));
    while (DateTime.now().isBefore(timeout)) {
      if (AuthNotifier.instance.profile != null) break;
      await Future.delayed(const Duration(milliseconds: 150));
    }

    if (!mounted) return;

    // Determine final role for navigation
    String roleStr = parsedRole ?? AuthNotifier.instance.userRole ?? '';
    if (roleStr.isEmpty) {
      try {
        final stored = await TokenStorage.getRole();
        if (stored != null && stored.isNotEmpty) roleStr = stored.toLowerCase();
      } catch (_) {}
    }

    // Show welcome bottom sheet
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
    final isDark = theme.brightness == Brightness.dark;

    // Use MediaQuery bottom padding to push content above the system
    // navigation bar on devices with gesture nav / soft keys.
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
          // Ensure the button clears the system navigation bar
          bottom: 32 + bottomInset,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Success animation/icon
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

            // Welcome header
            Text(
              'Welcome to RIJHUB! 🎉',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: _primaryColor,
              ),
            ),
            const SizedBox(height: 12),

            // Personalized greeting
            Text(
              'Hello, $name',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),

            // Welcome message
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

            // Feature highlights
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _primaryColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _primaryColor.withOpacity(0.1),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildFeatureItem(
                    icon: isArtisan ? Icons.work_outline : Icons.search,
                    label: isArtisan ? 'Manage Jobs' : 'Find Artisans',
                  ),
                  Container(
                    height: 30,
                    width: 1,
                    color: _primaryColor.withOpacity(0.2),
                  ),
                  _buildFeatureItem(
                    icon: Icons.message_outlined,
                    label: 'Chat',
                  ),
                  Container(
                    height: 30,
                    width: 1,
                    color: _primaryColor.withOpacity(0.2),
                  ),
                  _buildFeatureItem(
                    icon: Icons.payment_outlined,
                    label: 'Secure Payments',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Get Started button
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

  Widget _buildFeatureItem({required IconData icon, required String label}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          color: _primaryColor,
          size: 24,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: _primaryColor,
          ),
        ),
      ],
    );
  }

  Future<void> _navigateToDashboard(String role) async {
    // Close the bottom sheet first
    Navigator.of(context).pop();

    // Small delay to ensure smooth transition
    await Future.delayed(const Duration(milliseconds: 100));

    if (!mounted) return;

    // Use GoRouter.go() so GoRouter's internal state is updated correctly.
    // The imperative Navigator.pushAndRemoveUntil conflicts with GoRouter when
    // the router has already redirected away from this page (making the widget
    // context unmounted), causing safeReplaceAllWith to bail out silently.
    try {
      final router = GoRouter.of(context);
      if (role.contains('artisan')) {
        router.go(ArtisanDashboardPageWidget.routePath);
      } else {
        router.go(HomePageWidget.routePath);
      }
    } catch (_) {
      // Fallback to imperative navigation if GoRouter is unavailable
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

  bool get _isButtonDisabled => _submitting || _otpExpired;

  // MARK: - Build Methods
  @override
  Widget build(BuildContext context) {
    if (_loading) return _buildLoading();

    return Scaffold(
      backgroundColor: _getBackgroundColor(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
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
                'Verify phone',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black87,
                ),
              ),

              const SizedBox(height: 12),

              // Subtitle
              Text(
                'Enter the one-time code sent to your phone to verify your account.',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey[600],
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 40),

              // Phone info and timer
              if (_displayPhone != null) ...[
                Text(
                  'We sent an SMS with a verification code to:',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      _displayPhone!,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
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
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatDuration(_remaining),
                            style: TextStyle(
                              fontSize: 13,
                              color: _primaryColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
              ],

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
                  fillColor: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey[900]
                      : Colors.grey[50],
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
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
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
                  onPressed: _handleResendCode,
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

              // Optional: Add some bottom padding
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }

  Color _getBackgroundColor() {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.black
        : Colors.white;
  }
}