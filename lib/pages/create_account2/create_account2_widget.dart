import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'create_account2_model.dart';
import '/services/auth_service.dart';
import '/services/token_storage.dart';
// import 'package:firebase_auth/firebase_auth.dart'; // Firebase phone auth disabled
import '../../state/auth_notifier.dart';
import '../../utils/awesome_dialogs.dart';
import 'package:flutter/foundation.dart';
import '../../utils/navigation_utils.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../pages/verify_otp/verify_otp_widget.dart';
import '../../utils/phone_utils.dart';

export 'create_account2_model.dart';

// ========== Constants ==========
class AuthConstants {
  static const int passwordMinLength = 6;
  static const Duration apiTimeout = Duration(seconds: 30);
  static const Duration toastDuration = Duration(seconds: 2);
  static const Duration dialogDelay = Duration(milliseconds: 300);

  static const String defaultRole = 'customer';
  static const String clientRole = 'client';
  static const String artisanRole = 'artisan';

  static const String termsUrl = 'https://www.rijhub.com/terms-and-conditions';
  static const String privacyUrl = 'https://www.rijhub.com/privacy-policy';
}

// ========== Role Utilities ==========
class RoleUtils {
  static String normalize(String? role) {
    if (role == null) return AuthConstants.defaultRole;
    final normalized = role.trim().toLowerCase();
    if (normalized == AuthConstants.clientRole)
      return AuthConstants.defaultRole;
    return normalized;
  }

  static bool isArtisan(String? role) =>
      normalize(role) == AuthConstants.artisanRole;
  static String getDisplayName(String? role) =>
      isArtisan(role) ? 'Artisan Account' : 'Client Account';
  static IconData getIcon(String? role) =>
      isArtisan(role) ? Icons.handyman_outlined : Icons.person_outline;
}

// ========== Validators ==========
class Validators {
  static String? validateName(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty)
      return 'Please enter your full name';
    if (trimmed.length < 2) return 'Name must be at least 2 characters';
    return null;
  }

  static String? validateEmail(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return 'Please enter your email';

    final emailRegex = RegExp(r'^[a-zA-Z0-9.]+@[a-zA-Z0-9]+\.[a-zA-Z]+$');
    if (!emailRegex.hasMatch(trimmed)) return 'Please enter a valid email';
    return null;
  }

  static String? validatePhone(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty)
      return 'Please enter your phone number';

    final digitsOnly = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length < 10 || digitsOnly.length > 15) {
      return 'Please enter a valid phone number (10-15 digits)';
    }
    return null;
  }

  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < AuthConstants.passwordMinLength) {
      return 'Password must be at least ${AuthConstants.passwordMinLength} characters';
    }
    if (!value.contains(RegExp(r'[A-Z]'))) {
      return 'Password must contain at least one uppercase letter';
    }
    if (!value.contains(RegExp(r'[0-9]'))) {
      return 'Password must contain at least one number';
    }
    return null;
  }
}

// ========== Navigation Service ==========
class AuthNavigationService {
  static Future<void> goToVerification({
    required BuildContext context,
    required String phone,
    String? reference,
    String? email,
    String? password,
    String? role,
  }) async {
    try {
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => VerifyOtpWidget(
            phone: phone,
            reference: reference,
            email: email,
            password: password,
            role: role,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Navigation error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                const Text('Account created. Please verify your phone number.'),
            duration: AuthConstants.toastDuration,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  static Future<void> goToLogin(BuildContext context) async {
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const LoginAccountWidget()),
      );
    } catch (e) {
      debugPrint('Login navigation error: $e');
      if (context.mounted) {
        NavigationUtils.safePushNoAuth(context, const LoginAccountWidget());
      }
    }
  }
}

// ========== Error Handler ==========
class AuthErrorHandler {
  static String getFriendlyMessage(dynamic error) {
    if (error is Map<String, dynamic>) {
      final code = error['code']?.toString().toLowerCase();
      final message = error['message']?.toString();

      switch (code) {
        case 'email-already-in-use':
          return 'This email is already registered. Try logging in instead.';
        case 'invalid-email':
          return 'Please enter a valid email address.';
        case 'weak-password':
          return 'Please choose a stronger password.';
        case 'phone-already-exists':
          return 'This phone number is already registered.';
        default:
          return message ?? 'An error occurred. Please try again.';
      }
    }
    if (error is String) return error;
    return 'Something went wrong. Please try again later.';
  }

  static void showErrorDialog(BuildContext context, dynamic error) {
    showAppErrorDialog(
      context,
      title: 'Error',
      desc: getFriendlyMessage(error),
    );
  }
}

// ========== Main Widget ==========
class CreateAccount2Widget extends StatefulWidget {
  const CreateAccount2Widget({super.key, this.initialRole});

  final String? initialRole;

  static String routeName = 'CreateAccount2';
  static String routePath = '/createAccount2';

  @override
  State<CreateAccount2Widget> createState() => _CreateAccount2WidgetState();
}

class _CreateAccount2WidgetState extends State<CreateAccount2Widget> {
  late CreateAccount2Model _model;
  late TextEditingController _phoneController;
  late FocusNode _phoneFocusNode;
  late TextEditingController _passwordController;
  late FocusNode _passwordFocusNode;
  late TapGestureRecognizer _tncRecognizer;
  late TapGestureRecognizer _privacyRecognizer;

  final scaffoldKey = GlobalKey<ScaffoldState>();
  final _formKey = GlobalKey<FormState>();

  String? _effectiveRole;
  bool _isCreatingAccount = false;
  bool _passwordVisible = false;
  bool _acceptedTos = false;

  bool get _isAppleSignInAvailable {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _initializeRecognizers();
    _loadGoogleProfile();
    _resolveEffectiveRole();
  }

  void _initializeControllers() {
    _model = createModel(context, () => CreateAccount2Model());
    _model.fullNameTextController ??= TextEditingController();
    _model.fullNameFocusNode ??= FocusNode();
    _model.emailAddressTextController ??= TextEditingController();
    _model.emailAddressFocusNode ??= FocusNode();
    _phoneController = TextEditingController();
    _phoneFocusNode = FocusNode();
    _passwordController = TextEditingController();
    _passwordFocusNode = FocusNode();
  }

  void _initializeRecognizers() {
    _tncRecognizer = TapGestureRecognizer()
      ..onTap = () => _openUrl(AuthConstants.termsUrl);
    _privacyRecognizer = TapGestureRecognizer()
      ..onTap = () => _openUrl(AuthConstants.privacyUrl);
  }

  Future<void> _loadGoogleProfile() async {
    final profile = await TokenStorage.getGoogleProfile();
    if (profile != null && mounted) {
      setState(() {
        _model.fullNameTextController?.text =
            (profile['name'] ?? '').toString();
        _model.emailAddressTextController?.text =
            (profile['email'] ?? '').toString();
      });
    }
  }

  void _resolveEffectiveRole() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      String? role = widget.initialRole;
      try {
        final args = ModalRoute.of(context)?.settings.arguments;
        if (args is Map) {
          role = args['initialRole']?.toString() ??
              args['role']?.toString() ??
              role;
        }
      } catch (_) {}

      role = RoleUtils.normalize(role);
      if (kDebugMode) debugPrint('CreateAccount2 resolved role: $role');
      // Normalize some common synonyms (client -> customer)
      final v = role.trim().toLowerCase();
      if (v == 'client') role = 'customer';

      // Debug log to help trace navigation role propagation during testing
      if (kDebugMode)
        debugPrint(
            'CreateAccount2 resolved role: $role (widget.initialRole=${widget.initialRole})');

      if (mounted) setState(() => _effectiveRole = role);
    });
  }

  @override
  void dispose() {
    _tncRecognizer.dispose();
    _privacyRecognizer.dispose();
    _model.dispose();
    _phoneController.dispose();
    _phoneFocusNode.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _openUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
          mounted) {
        await showAppErrorDialog(
          context,
          title: 'Unable to open link',
          desc: 'Could not open the link. Please try again.',
        );
      }
    } catch (e) {
      if (mounted) {
        await showAppErrorDialog(
          context,
          title: 'Unable to open link',
          desc: 'Could not open the link. Please try again.',
        );
      }
    }
  }

  // ========== Google Sign-In ==========
  Future<void> _handleGoogleSignIn() async {
    try {
      final token = await TokenStorage.getToken();
      if (token?.isNotEmpty ?? false) {
        if (mounted)
          await NavigationUtils.safePushReplacement(context, HomePageWidget());
        return;
      }
    } catch (_) {}

    showAppLoadingDialog(context);
    final res = await AuthService.signInWithGoogle(
        role: _effectiveRole ?? widget.initialRole);

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (res['success'] == true) {
      await _processGoogleSignInSuccess(res);
    } else {
      _handleGoogleSignInError(res);
    }
  }

  Future<void> _processGoogleSignInSuccess(Map<String, dynamic> res) async {
    final profile = res['profile'] as Map<String, dynamic>?;
    final data = res['data'];
    if (data != null &&
        data is Map &&
        (data['token'] != null || (data['user'] != null))) {
      // Extract token if present. Navigate to welcome-after-signup before
      // setting token so onboarding shows first.
      String? token;
      if (res['token'] != null) token = res['token']?.toString();
      if (token == null)
        token = (data['token'] ?? data['data']?['token'])?.toString();

      final name = profile != null ? (profile['name']?.toString() ?? '') : '';

      // Use the backend-returned role (from the user object) so that
      // existing users see the correct welcome message. Fall back to
      // the locally-selected role only for genuinely new accounts.
      String role = _effectiveRole ?? widget.initialRole ?? 'customer';
      try {
        final userData = data['user'] ?? data['data'];
        if (userData is Map && userData['role'] != null) {
          final backendRole = userData['role'].toString().toLowerCase();
          if (backendRole == 'artisan' || backendRole == 'customer') {
            role = backendRole;
          }
        }
      } catch (_) {}

      // Use post-frame callback so navigation runs after loading dialog is
      // fully dismissed and the tree has settled. Future.microtask can run
      // while the navigator is still processing the pop, or the widget can
      // be unmounted when returning from external OAuth (e.g. Google).
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        try {
          if (token != null && token.isNotEmpty) {
            await AuthNotifier.instance.setToken(token);
          }

          // Prefer GoRouter for navigation — more reliable when returning
          // from background (Google OAuth) and avoids imperative navigator races.
          final router = GoRouter.maybeOf(context);
          if (router != null) {
            final path = WelcomeAfterSignupWidget.routePath;
            final q = <String, String>{
              if (role.isNotEmpty) 'role': role,
              if (name.isNotEmpty) 'name': name,
            };
            final uri = Uri(path: path, queryParameters: q);
            router.go(uri.toString());
          } else {
            await NavigationUtils.safePushReplacement(
              context,
              WelcomeAfterSignupWidget(role: role, name: name),
            );
          }
        } catch (_) {
          try {
            if (mounted) {
              await NavigationUtils.safePushReplacement(
                  context, HomePageWidget());
            }
          } catch (_) {}
        }
      });
      return;
    }

    if (profile != null) {
      setState(() {
        _model.fullNameTextController?.text =
            (profile['name'] ?? '').toString();
        _model.emailAddressTextController?.text =
            (profile['email'] ?? '').toString();
      });
      await TokenStorage.saveGoogleProfile(profile);
    }

    // After Google sign in, if profile is new, we still need to collect phone.
    // In this app's current flow, it seems to just show success dialog.
    if (!mounted) return;

    await showAppSuccessDialog(
      context,
      title: 'Google signed in',
      desc:
          'We prefilled your name and email. Complete the form to finish creating your account.',
    );
  }

  void _handleGoogleSignInError(Map<String, dynamic> res) {
    final err = res['error'];
    String message = (err is Map && err['message'] != null)
        ? err['message'].toString()
        : (err != null ? err.toString() : 'Google sign-in failed');
    // Append code/details when available so users see the real error
    // (e.g. signInFailed, developerError) instead of generic messages
    if (err is Map) {
      final code = err['code']?.toString();
      final details = err['details']?.toString();
      if (code != null && code.isNotEmpty) {
        message = message.contains(code) ? message : '$message [code: $code]';
      }
      if (details != null && details.isNotEmpty && details.length < 200) {
        message = '$message\n$details';
      }
    }
    if (!mounted) return;
    AuthErrorHandler.showErrorDialog(context, message);
  }

  Future<void> _handleAppleSignIn() async {
    // Only available on Apple platforms
    if (!_isAppleSignInAvailable) return;

    showAppLoadingDialog(context);

    final res = await AuthService.signInWithApple(
      role: _effectiveRole ?? widget.initialRole,
    );

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (res['success'] == true) {
      final profile = res['profile'] as Map<String, dynamic>?;
      // Save profile to state so we can show it in the button
      if (profile != null) {
        _model.fullNameTextController?.text =
            (profile['name'] ?? '').toString();
        _model.emailAddressTextController?.text =
            (profile['email'] ?? '').toString();
      }

      final data = res['data'];
      if (data != null &&
          data is Map &&
          (data['token'] != null || (data['user'] != null))) {
        String? token;
        if (res['token'] != null) token = res['token']?.toString();
        if (token == null)
          token = (data['token'] ?? data['data']?['token'])?.toString();

        final name = profile != null ? (profile['name']?.toString() ?? '') : '';

        String role = _effectiveRole ?? widget.initialRole ?? 'customer';
        try {
          final userData = data['user'] ?? data['data'];
          if (userData is Map && userData['role'] != null) {
            final backendRole = userData['role'].toString().toLowerCase();
            if (backendRole == 'artisan' || backendRole == 'customer') {
              role = backendRole;
            }
          }
        } catch (_) {}

        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          try {
            if (token != null && token.isNotEmpty) {
              await AuthNotifier.instance.setToken(token);
            }

            final router = GoRouter.maybeOf(context);
            if (router != null) {
              final path = WelcomeAfterSignupWidget.routePath;
              final q = <String, String>{
                if (role.isNotEmpty) 'role': role,
                if (name.isNotEmpty) 'name': name,
              };
              final uri = Uri(path: path, queryParameters: q);
              router.go(uri.toString());
            } else {
              await NavigationUtils.safePushReplacement(
                context,
                WelcomeAfterSignupWidget(role: role, name: name),
              );
            }
          } catch (_) {
            try {
              if (mounted) {
                await NavigationUtils.safePushReplacement(
                    context, HomePageWidget());
              }
            } catch (_) {}
          }
        });
        return;
      }

      await showAppSuccessDialog(
        context,
        title: 'Apple signed in',
        desc:
            'We prefilled your name and email. Complete the form to finish creating your account.',
      );
    } else {
      final err = res['error'];
      final message = (err is Map && err['message'] != null)
          ? err['message'].toString()
          : (err != null ? err.toString() : 'Apple sign-in failed');

      // Don't show error dialog for user cancellation
      if (message != 'Apple sign-in cancelled') {
        if (!mounted) return;
        await showAppErrorDialog(
          context,
          title: 'Sign-in error',
          desc: message,
        );
      }
    }
  }

  // ========== Account Creation ==========
  Future<void> _handleCreateAccount() async {
    if (_isCreatingAccount || !_formKey.currentState!.validate()) return;

    if (!_acceptedTos) {
      await showAppErrorDialog(
        context,
        title: 'Terms required',
        desc:
            'You must accept the Terms & Conditions and Privacy Policy to create an account.',
      );
      return;
    }

    setState(() => _isCreatingAccount = true);

    try {
      final normalizedRole =
          RoleUtils.normalize(_effectiveRole ?? widget.initialRole);
      final phone = normalizePhoneForApi(_phoneController.text.trim());

      final router = GoRouter.of(context);
      final savedName = _model.fullNameTextController?.text.trim();
      final savedEmail = _model.emailAddressTextController?.text.trim() ?? '';
      final savedPassword = _passwordController.text;

      // Register via backend — user is stored in a temporary collection
      // and an OTP is sent via the configured provider (phone/email).
      final result = await AuthService.register(
        name: savedName ?? '',
        email: savedEmail,
        password: savedPassword,
        phone: phone,
        role: normalizedRole,
        persist: false, // Don't persist token yet — user must verify OTP first
      );

      if (result['success'] == true) {
        // Save details for later use after OTP verification.
        await TokenStorage.saveRecentRegistration(
          name: savedName,
          email: savedEmail,
          phone: phone,
        );

        if (mounted) {
          setState(() => _isCreatingAccount = false);
        }

        final uri = Uri(
          path: VerifyOtpWidget.routePath,
          queryParameters: {
            'phone': phone,
            'email': savedEmail,
            'password': savedPassword,
            'role': normalizedRole,
          },
        );
        router.push(uri.toString());
      } else {
        if (mounted) setState(() => _isCreatingAccount = false);
        final error = result['error'];
        String errorMsg = 'Registration failed. Please try again.';
        if (error is Map && error['message'] != null) {
          errorMsg = error['message'].toString();
        } else if (error != null) {
          errorMsg = error.toString();
        }
        if (mounted) {
          AuthErrorHandler.showErrorDialog(context, errorMsg);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isCreatingAccount = false);
      AuthErrorHandler.showErrorDialog(context, e);
    }
  }

  void _navigateBack() => Navigator.of(context).maybePop();

  // ========== UI Helpers ==========
  Color get _primaryColor => Theme.of(context).colorScheme.primary;
  Color _getSurfaceAlpha(double opacity) =>
      Theme.of(context).colorScheme.onSurface.withOpacity(opacity);
  bool get _isButtonDisabled => _isCreatingAccount;

  // ========== Build Methods ==========
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      key: scaffoldKey,
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildHeader(),
              if (_effectiveRole != null) _buildRoleIndicator(),
              const SizedBox(height: 40.0),
              _buildForm(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        const SizedBox(height: 40.0),
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            color: _getSurfaceAlpha(0.6),
            onPressed: _navigateBack,
            iconSize: 32,
          ),
        ),
        _buildIcon(),
        const SizedBox(height: 32.0),
        _buildTitle(),
        const SizedBox(height: 8.0),
        _buildSubtitle(),
      ],
    );
  }

  Widget _buildIcon() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _primaryColor.withOpacity(0.1),
      ),
      child: Icon(Icons.person_add, size: 40, color: _primaryColor),
    );
  }

  Widget _buildTitle() {
    return Text(
      'Create an account',
      style: Theme.of(context).textTheme.headlineLarge?.copyWith(
            fontWeight: FontWeight.w300,
            letterSpacing: -0.5,
          ),
    );
  }

  Widget _buildSubtitle() {
    return Text(
      'Let\'s get started by filling out the form below.',
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: _getSurfaceAlpha(0.5),
            fontWeight: FontWeight.w300,
          ),
    );
  }

  Widget _buildRoleIndicator() {
    final isArtisan = RoleUtils.isArtisan(_effectiveRole);
    final color =
        isArtisan ? _primaryColor : Theme.of(context).colorScheme.secondary;

    return Padding(
      padding: const EdgeInsets.only(top: 16.0),
      child: Container(
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(RoleUtils.getIcon(_effectiveRole), color: color, size: 18),
            const SizedBox(width: 8),
            Text(
              RoleUtils.getDisplayName(_effectiveRole),
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(ThemeData theme) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildNameField(theme),
          const SizedBox(height: 20.0),
          _buildEmailField(theme),
          const SizedBox(height: 20.0),
          _buildPhoneField(theme),
          const SizedBox(height: 20.0),
          _buildPasswordField(theme),
          const SizedBox(height: 32.0),
          _buildTermsCheckbox(),
          _buildCreateAccountButton(),
          const SizedBox(height: 48.0),
          _buildDivider(theme),
          const SizedBox(height: 24.0),
          _buildGoogleSignInButton(),
          if (_isAppleSignInAvailable) ...[
            const SizedBox(height: 12.0),
            _buildAppleSignInButton(),
          ],
          const SizedBox(height: 24.0),
          _buildLoginLink(),
          const SizedBox(height: 60.0),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: _getSurfaceAlpha(0.6),
        letterSpacing: 1.0,
      ),
    );
  }

  Widget _buildNameField(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('FULL NAME'),
        const SizedBox(height: 8.0),
        TextFormField(
          controller: _model.fullNameTextController,
          focusNode: _model.fullNameFocusNode,
          autofillHints: const [AutofillHints.name],
          decoration: _buildInputDecoration(theme, 'John Doe'),
          style: const TextStyle(fontSize: 16),
          textInputAction: TextInputAction.next,
          validator: Validators.validateName,
          onFieldSubmitted: (_) =>
              FocusScope.of(context).requestFocus(_model.emailAddressFocusNode),
        ),
      ],
    );
  }

  Widget _buildEmailField(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('EMAIL'),
        const SizedBox(height: 8.0),
        TextFormField(
          controller: _model.emailAddressTextController,
          focusNode: _model.emailAddressFocusNode,
          autofillHints: const [AutofillHints.email],
          keyboardType: TextInputType.emailAddress,
          decoration: _buildInputDecoration(theme, 'your@email.com'),
          style: const TextStyle(fontSize: 16),
          textInputAction: TextInputAction.next,
          validator: Validators.validateEmail,
          onFieldSubmitted: (_) =>
              FocusScope.of(context).requestFocus(_phoneFocusNode),
        ),
      ],
    );
  }

  Widget _buildPhoneField(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('PHONE NUMBER'),
        const SizedBox(height: 8.0),
        TextFormField(
          controller: _phoneController,
          focusNode: _phoneFocusNode,
          autofillHints: const [AutofillHints.telephoneNumber],
          keyboardType: TextInputType.phone,
          decoration: _buildInputDecoration(theme, '8012345678')
              .copyWith(
            prefixIcon: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🇳🇬', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 6),
                  Text(
                    '+234',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    height: 20,
                    width: 1,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.25),
                  ),
                ],
              ),
            ),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 0, minHeight: 48),
          ),
          style: const TextStyle(fontSize: 16),
          textInputAction: TextInputAction.next,
          validator: Validators.validatePhone,
          onFieldSubmitted: (_) =>
              FocusScope.of(context).requestFocus(_passwordFocusNode),
        ),
      ],
    );
  }

  Widget _buildPasswordField(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('PASSWORD'),
        const SizedBox(height: 8.0),
        TextFormField(
          controller: _passwordController,
          focusNode: _passwordFocusNode,
          obscureText: !_passwordVisible,
          decoration: _buildInputDecoration(
            theme,
            '••••••••',
            suffixIcon: IconButton(
              icon: Icon(
                _passwordVisible
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: _getSurfaceAlpha(0.4),
                size: 20,
              ),
              onPressed: () =>
                  setState(() => _passwordVisible = !_passwordVisible),
            ),
          ),
          style: const TextStyle(fontSize: 16),
          textInputAction: TextInputAction.done,
          validator: Validators.validatePassword,
          onFieldSubmitted: (_) => _handleCreateAccount(),
        ),
      ],
    );
  }

  InputDecoration _buildInputDecoration(
    ThemeData theme,
    String hintText, {
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(color: _getSurfaceAlpha(0.3)),
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: BorderSide(color: _primaryColor, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: BorderSide(color: theme.colorScheme.error, width: 1.0),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
      suffixIcon: suffixIcon,
    );
  }

  Widget _buildTermsCheckbox() {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Checkbox(
            value: _acceptedTos,
            onChanged: (v) => setState(() => _acceptedTos = v ?? false),
            fillColor: WidgetStateProperty.resolveWith<Color?>((states) {
              if (states.contains(WidgetState.selected)) return _primaryColor;
              // Use a visible fill when unchecked so the checkbox is always visible
              final isDark = Theme.of(context).brightness == Brightness.dark;
              return isDark
                  ? Colors.white.withOpacity(0.25)
                  : _getSurfaceAlpha(0.2);
            }),
            checkColor: Colors.white,
            side: BorderSide(
              color: _getSurfaceAlpha(0.7),
              width: 2,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => setState(() => _acceptedTos = !_acceptedTos),
            child: Text.rich(
              TextSpan(
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontSize: 11),
                children: [
                  const TextSpan(text: 'I accept the '),
                  TextSpan(
                    text: 'T&C',
                    recognizer: _tncRecognizer,
                    style: TextStyle(
                      color: _primaryColor,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                      fontSize: 11,
                    ),
                  ),
                  const TextSpan(text: ' and the '),
                  TextSpan(
                    text: 'Privacy Policy',
                    recognizer: _privacyRecognizer,
                    style: TextStyle(
                      color: _primaryColor,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                      fontSize: 11,
                    ),
                  ),
                  const TextSpan(text: ' of Rijhub'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateAccountButton() {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: _primaryColor,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        padding: const EdgeInsets.symmetric(vertical: 18.0),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
        elevation: 0,
      ),
      onPressed: _isButtonDisabled ? null : _handleCreateAccount,
      child: _isCreatingAccount
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text(
              'CREATE ACCOUNT',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5),
            ),
    );
  }

  Widget _buildDivider(ThemeData theme) {
    return Row(
      children: [
        Expanded(child: Divider(color: _getSurfaceAlpha(0.1), thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text('OR',
              style: TextStyle(color: _getSurfaceAlpha(0.3), fontSize: 12)),
        ),
        Expanded(child: Divider(color: _getSurfaceAlpha(0.1), thickness: 1)),
      ],
    );
  }

  Widget _buildGoogleSignInButton() {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: _primaryColor),
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 12.0),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      ),
      onPressed: _handleGoogleSignIn,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            height: 24,
            width: 24,
            child: _buildGoogleIcon(),
          ),
          const SizedBox(width: 12),
          Text(
            'Continue with Google',
            style: TextStyle(
                color: _primaryColor,
                fontSize: 15,
                fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildAppleSignInButton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: isDark ? Colors.white : Colors.black),
        backgroundColor: isDark ? Colors.white : Colors.black,
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 12.0),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      ),
      onPressed: _handleAppleSignIn,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.apple,
            color: isDark ? Colors.black : Colors.white,
            size: 24,
          ),
          const SizedBox(width: 12),
          Text(
            'Continue with Apple',
            style: TextStyle(
              color: isDark ? Colors.black : Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoogleIcon() {
    try {
      return Image.asset(
        'assets/images/google.webp',
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) =>
            Icon(Icons.g_mobiledata, color: _primaryColor, size: 20),
      );
    } catch (_) {
      return Icon(Icons.g_mobiledata, color: _primaryColor, size: 20);
    }
  }

  Widget _buildLoginLink() {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Already have an account? ',
            style: TextStyle(color: _getSurfaceAlpha(0.7), fontSize: 14),
          ),
          TextButton(
            onPressed: () => AuthNavigationService.goToLogin(context),
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 4.0)),
            child: Text(
              'Log in',
              style: TextStyle(
                  color: _primaryColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
