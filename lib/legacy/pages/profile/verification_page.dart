import 'dart:math';
import 'package:flutter/material.dart';

enum VerificationType { email, phone }

class VerificationPage extends StatefulWidget {
  const VerificationPage({super.key});

  static const String routeName = 'verification';
  static const String routePath = '/profile/verification';

  @override
  State<VerificationPage> createState() => _VerificationPageState();
}

class _VerificationPageState extends State<VerificationPage> {
  bool _emailVerified = false;
  bool _phoneVerified = false;

  void _markVerified(VerificationType type) {
    setState(() {
      if (type == VerificationType.email) _emailVerified = true;
      if (type == VerificationType.phone) _phoneVerified = true;
    });
  }

  void _showVerificationSheet(BuildContext context, VerificationType type) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return VerificationBottomSheet(
          type: type,
          onVerified: () {
            Navigator.of(ctx).pop();
            _markVerified(type);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(type == VerificationType.email
                    ? 'Email verified successfully'
                    : 'Phone number verified successfully'),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final onSurfaceAlpha10 = colorScheme.onSurface.withAlpha((0.1 * 255).toInt());

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      appBar: AppBar(
        title: Text(
          'Verification',
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w500, fontSize: 18),
        ),
        backgroundColor: isDark ? Colors.black : Colors.white,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24.0, 0.0, 24.0, MediaQuery.of(context).padding.bottom + 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withAlpha((0.1 * 255).toInt()),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 20, color: colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Please complete the following verifications to secure your account',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Verification items
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: onSurfaceAlpha10, width: 1),
                ),
                child: Column(
                  children: [
                    // Email verification
                    _buildVerificationTile(
                      icon: Icons.email_outlined,
                      title: 'Verify email',
                      subtitle: 'Confirm your email address to secure your account',
                      isVerified: _emailVerified,
                      onTap: _emailVerified ? null : () => _showVerificationSheet(context, VerificationType.email),
                      colorScheme: colorScheme,
                      theme: theme,
                    ),

                    Container(height: 1, color: onSurfaceAlpha10),

                    // Phone verification
                    _buildVerificationTile(
                      icon: Icons.phone_android_outlined,
                      title: 'Verify phone number',
                      subtitle: 'Confirm your phone number to enable SMS notifications',
                      isVerified: _phoneVerified,
                      onTap: _phoneVerified ? null : () => _showVerificationSheet(context, VerificationType.phone),
                      colorScheme: colorScheme,
                      theme: theme,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Status summary
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: onSurfaceAlpha10, width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Verification Status',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _buildStatusChip(
                          label: 'Email',
                          isVerified: _emailVerified,
                          colorScheme: colorScheme,
                        ),
                        const SizedBox(width: 12),
                        _buildStatusChip(
                          label: 'Phone',
                          isVerified: _phoneVerified,
                          colorScheme: colorScheme,
                        ),
                      ],
                    ),
                    if (_emailVerified && _phoneVerified) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.withAlpha((0.1 * 255).toInt()),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.verified_rounded, color: Colors.green, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'All verifications complete! Your account is fully secured.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: Colors.green[700],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVerificationTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isVerified,
    required VoidCallback? onTap,
    required ColorScheme colorScheme,
    required ThemeData theme,
  }) {
    final onSurfaceAlpha30 = colorScheme.onSurface.withAlpha((0.3 * 255).toInt());
    final onSurfaceAlpha60 = colorScheme.onSurface.withAlpha((0.6 * 255).toInt());

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Icon container
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: (isVerified ? Colors.green : colorScheme.primary).withAlpha((0.1 * 255).toInt()),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 24,
                  color: isVerified ? Colors.green : colorScheme.primary,
                ),
              ),
              const SizedBox(width: 16),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: onSurfaceAlpha60,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Status indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isVerified
                      ? Colors.green.withAlpha((0.1 * 255).toInt())
                      : onSurfaceAlpha30.withAlpha((0.1 * 255).toInt()),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isVerified ? Icons.check_circle : Icons.circle_outlined,
                      size: 16,
                      color: isVerified ? Colors.green : onSurfaceAlpha60,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isVerified ? 'Verified' : 'Pending',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isVerified ? Colors.green : onSurfaceAlpha60,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip({
    required String label,
    required bool isVerified,
    required ColorScheme colorScheme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isVerified
            ? Colors.green.withAlpha((0.1 * 255).toInt())
            : colorScheme.error.withAlpha((0.1 * 255).toInt()),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isVerified ? Icons.check_circle : Icons.pending_outlined,
            size: 14,
            color: isVerified ? Colors.green : colorScheme.error,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isVerified ? Colors.green : colorScheme.error,
            ),
          ),
        ],
      ),
    );
  }
}

class VerificationBottomSheet extends StatefulWidget {
  final VerificationType type;
  final VoidCallback onVerified;

  const VerificationBottomSheet({super.key, required this.type, required this.onVerified});

  @override
  State<VerificationBottomSheet> createState() => _VerificationBottomSheetState();
}

class _VerificationBottomSheetState extends State<VerificationBottomSheet> {
  int _step = 0; // 0: input, 1: enter OTP
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  String? _generatedOtp;
  bool _loading = false;

  @override
  void dispose() {
    _inputController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  String get _label => widget.type == VerificationType.email ? 'Email' : 'Phone number';

  bool _validateInput() {
    final v = _inputController.text.trim();
    if (v.isEmpty) return false;
    if (widget.type == VerificationType.email) {
      final emailRegex = RegExp(r"^[\w\-\.]+@([\w-]+\.)+[\w-]{2,}$");
      return emailRegex.hasMatch(v);
    } else {
      final phoneRegex = RegExp(r"^[0-9]{10,15}$");
      return phoneRegex.hasMatch(v);
    }
  }

  void _sendOtp() async {
    if (!_validateInput()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please enter a valid ${widget.type == VerificationType.email ? 'email address' : 'phone number'}'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    setState(() => _loading = true);

    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 800));

    final rnd = Random();
    _generatedOtp = (rnd.nextInt(900000) + 100000).toString();

    if (!mounted) return;
    setState(() {
      _loading = false;
      _step = 1;
    });

    // For testing/dev show OTP in a snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('OTP sent: $_generatedOtp'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _verifyOtp() async {
    final entered = _otpController.text.trim();
    if (entered.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please enter the OTP'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }
    if (entered != _generatedOtp) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Incorrect OTP. Please try again.'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    widget.onVerified();
  }

  void _resendOtp() async {
    setState(() => _loading = true);
    await Future.delayed(const Duration(milliseconds: 600));

    final rnd = Random();
    _generatedOtp = (rnd.nextInt(900000) + 100000).toString();

    if (!mounted) return;
    setState(() => _loading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('New OTP sent: $_generatedOtp'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final media = MediaQuery.of(context);
    final onSurfaceAlpha10 = colorScheme.onSurface.withAlpha((0.1 * 255).toInt());
    final onSurfaceAlpha30 = colorScheme.onSurface.withAlpha((0.3 * 255).toInt());
    final onSurfaceAlpha60 = colorScheme.onSurface.withAlpha((0.6 * 255).toInt());

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[900] : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: onSurfaceAlpha30,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Title
            Text(
              widget.type == VerificationType.email ? 'Verify email' : 'Verify phone',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, fontSize: 20),
            ),
            const SizedBox(height: 4),
            Text(
              widget.type == VerificationType.email
                  ? 'We\'ll send a verification code to your email'
                  : 'We\'ll send a verification code to your phone',
              style: theme.textTheme.bodyMedium?.copyWith(color: onSurfaceAlpha60),
            ),
            const SizedBox(height: 24),

            // Step indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.primary.withAlpha((0.1 * 255).toInt()),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _step == 0 ? colorScheme.primary : Colors.green,
                    ),
                    child: Center(
                      child: Text(
                        '1',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  Container(width: 20, height: 1, color: onSurfaceAlpha30),
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _step == 1 ? colorScheme.primary : onSurfaceAlpha30,
                    ),
                    child: Center(
                      child: Text(
                        '2',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _step == 1 ? Colors.white : onSurfaceAlpha60,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            if (_step == 0) ...[
              // Step 1: Input field
              Text(
                'Step 1 — Enter your $_label',
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _inputController,
                keyboardType: widget.type == VerificationType.email ? TextInputType.emailAddress : TextInputType.phone,
                style: theme.textTheme.bodyLarge,
                decoration: InputDecoration(
                  labelText: _label,
                  hintText: widget.type == VerificationType.email ? 'you@example.com' : '+234 801 234 5678',
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(color: onSurfaceAlpha30),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: onSurfaceAlpha30),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: onSurfaceAlpha10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colorScheme.primary, width: 2),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colorScheme.error),
                  ),
                  filled: true,
                  fillColor: isDark ? Colors.grey[850] : Colors.grey[50],
                ),
              ),
              const SizedBox(height: 20),

              // Send button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _sendOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _loading
                      ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(colorScheme.onPrimary),
                    ),
                  )
                      : Text(
                    'Send verification code',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colorScheme.onPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ] else ...[
              // Step 2: OTP input
              Text(
                'Step 2 — Enter verification code',
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'We\'ve sent a 6-digit code to ${_inputController.text}',
                style: theme.textTheme.bodySmall?.copyWith(color: onSurfaceAlpha60),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 8,
                ),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  labelText: 'OTP',
                  hintText: '000000',
                  hintStyle: theme.textTheme.headlineMedium?.copyWith(
                    color: onSurfaceAlpha30,
                    letterSpacing: 8,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: onSurfaceAlpha30),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: onSurfaceAlpha10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colorScheme.primary, width: 2),
                  ),
                  counterText: '',
                  filled: true,
                  fillColor: isDark ? Colors.grey[850] : Colors.grey[50],
                ),
              ),
              const SizedBox(height: 20),

              // Verify button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _verifyOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: Text(
                    'Verify',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colorScheme.onPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Action row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Back button
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _step = 0;
                        _otpController.clear();
                        _generatedOtp = null;
                      });
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: onSurfaceAlpha60,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_back_ios_new_rounded, size: 14),
                        const SizedBox(width: 4),
                        const Text('Edit'),
                      ],
                    ),
                  ),

                  // Resend button
                  TextButton(
                    onPressed: _loading ? null : _resendOtp,
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.primary,
                    ),
                    child: _loading
                        ? SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.primary,
                      ),
                    )
                        : const Text('Resend code'),
                  ),
                ],
              ),
            ],

            // Testing helper text
            if (_step == 1)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withAlpha((0.1 * 255).toInt()),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Testing: OTP is shown in the snackbar",
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

