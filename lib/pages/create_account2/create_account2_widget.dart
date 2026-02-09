import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'create_account2_model.dart';
import '/services/auth_service.dart';
import '/services/token_storage.dart';
import '../../state/auth_notifier.dart';
import '../../utils/awesome_dialogs.dart';
import 'package:flutter/foundation.dart'; // Import foundation library for kDebugMode
import '../../utils/navigation_utils.dart';
import '../../utils/account_creation_navigator.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';

export 'create_account2_model.dart';

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
  String? _effectiveRole;
  bool _navigateScheduled = false;
  bool _isCreatingAccount = false;
  bool _passwordVisible = false;
  bool _acceptedTos = false; // must accept T&C and Privacy to create account
  // Holds Google profile info (if user signed in with Google during this flow)
  Map<String, dynamic>? _googleProfile;

  // Tap recognizers for T&C and Privacy links
  late TapGestureRecognizer _tncRecognizer;
  late TapGestureRecognizer _privacyRecognizer;

  final scaffoldKey = GlobalKey<ScaffoldState>();
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _phoneController;
  late FocusNode _phoneFocusNode;
  late TextEditingController _passwordController;
  late FocusNode _passwordFocusNode;

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => CreateAccount2Model());

    // Initialize link recognizers
    _tncRecognizer = TapGestureRecognizer()
      ..onTap = () {
        _openUrl('https://rijhub.com/terms-and-conditions.html');
      };
    _privacyRecognizer = TapGestureRecognizer()
      ..onTap = () {
        _openUrl('https://rijhub.com/privacy-policy.html');
      };

    _model.fullNameTextController ??= TextEditingController();
    _model.fullNameFocusNode ??= FocusNode();

    _model.emailAddressTextController ??= TextEditingController();
    _model.emailAddressFocusNode ??= FocusNode();

    _phoneController = TextEditingController();
    _phoneFocusNode = FocusNode();
    _passwordController = TextEditingController();
    _passwordFocusNode = FocusNode();

    // Restore any previously cached Google profile so the button can reflect it
    TokenStorage.getGoogleProfile().then((p) {
      if (p != null && mounted) {
        setState(() {
          _googleProfile = p;
          _model.fullNameTextController?.text = (p['name'] ?? '').toString();
          _model.emailAddressTextController?.text =
              (p['email'] ?? '').toString();
        });
      }
    });

    // Set initial effective role from constructor so UI can display it immediately.
    _effectiveRole = widget.initialRole;
    if (kDebugMode)
      debugPrint('CreateAccount2 initState initialRole=${widget.initialRole}');

    // Determine the effective role for this flow. The role can come from the
    // widget constructor (when using generated routes), or from previous
    // navigation via Navigator/RouteSettings.arguments. We use a post frame
    // callback to safely access ModalRoute and avoid issues when called in
    // initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      String? role = widget.initialRole;
      try {
        final args = ModalRoute.of(context)?.settings.arguments;
        if (args is Map) {
          if (args['initialRole'] != null) {
            role = args['initialRole']?.toString();
          } else if (args['role'] != null) {
            role = args['role']?.toString();
          }
        }
      } catch (_) {}

      // Normalize some common synonyms (client -> customer)
      if (role != null) {
        final v = role.trim().toLowerCase();
        if (v == 'client') role = 'customer';
      }

      // Debug log to help trace navigation role propagation during testing
      if (kDebugMode)
        debugPrint(
            'CreateAccount2 resolved role: $role (widget.initialRole=${widget.initialRole})');

      if (mounted) setState(() => _effectiveRole = role);
    });
  }

  @override
  void dispose() {
    // dispose recognizers
    try {
      _tncRecognizer.dispose();
    } catch (_) {}
    try {
      _privacyRecognizer.dispose();
    } catch (_) {}

    _model.dispose();
    _phoneController.dispose();
    _phoneFocusNode.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  // Helper to open external URLs safely
  Future<void> _openUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        // Fallback: show an error dialog if opening fails
        if (!mounted) return;
        await showAppErrorDialog(context,
            title: 'Unable to open link',
            desc: 'Could not open the link. Please try again.');
      }
    } catch (e) {
      if (!mounted) return;
      await showAppErrorDialog(context,
          title: 'Unable to open link',
          desc: 'Could not open the link. Please try again.');
    }
  }

  String? _validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your full name';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your email';
    }
    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
    if (!emailRegex.hasMatch(value.trim())) {
      return 'Please enter a valid email';
    }
    return null;
  }

  String? _validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your phone number';
    }
    // Basic phone validation - adjust as needed
    final phoneRegex = RegExp(r'^[0-9+\-\s()]{10,}$');
    if (!phoneRegex.hasMatch(value.trim())) {
      return 'Please enter a valid phone number';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  Future<void> _handleGoogleSignIn() async {
    // If we already have a cached token, treat this as already authenticated and continue.
    try {
      final token = await TokenStorage.getToken();
      if (token != null && token.isNotEmpty) {
        // Quick UX: if token exists, navigate straight away using direct route
        // to avoid reliance on named routes/onGenerateRoute.
        if (!mounted) return;
        await NavigationUtils.safePushReplacement(context, HomePageWidget());
        return;
      }
    } catch (_) {}

    // Otherwise proceed with the interactive Google sign-in flow.
    showAppLoadingDialog(context);

    final res = await AuthService.signInWithGoogle(
      role: _effectiveRole ?? widget.initialRole,
    );

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (res['success'] == true) {
      final profile = res['profile'] as Map<String, dynamic>?;
      // Save profile to state so we can show it in the button
      if (profile != null) {
        setState(() {
          _googleProfile = profile;
        });
        // persist to TokenStorage so it survives app restarts
        try {
          await TokenStorage.saveGoogleProfile(profile);
        } catch (_) {}
      }
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
        // Extract token if present and set it on AppState so subsequent pages can
        // fetch profile data. Then navigate to the welcome-after-signup flow so
        // the user sees the onboarding screen before the dashboard.
        Future.microtask(() async {
          if (!mounted) return;
          try {
            String? token;
            if (res['token'] != null) token = res['token']?.toString();
            if (token == null)
              token = (data['token'] ?? data['data']?['token'])?.toString();
            // NOTE: previously we set the token here which could trigger app-wide
            // router redirects (to home/dashboard) before the WelcomeAfterSignup
            // page had a chance to show. Move token persistence until after we
            // successfully navigate to the welcome page below.

            final name =
                profile != null ? (profile['name']?.toString() ?? '') : '';
            final role = _effectiveRole ?? widget.initialRole ?? 'customer';
            final welcome = WelcomeAfterSignupWidget(role: role, name: name);
            await AccountCreationNavigator.navigateAfterSignup(
              context,
              welcome,
              goRoute: WelcomeAfterSignupWidget.routePath,
              preferImperative: true,
            );

            // Only after the welcome page was pushed should we apply the token
            // to the app state so that automatic router redirects will happen
            // when the user proceeds from the welcome screen. This preserves
            // the UX of showing onboarding first.
            if (token != null && token.isNotEmpty) {
              await AuthNotifier.instance.setToken(token);
            }
          } catch (_) {
            // Fallback to safer replacement to home if something goes wrong
            try {
              NavigationUtils.safePushReplacement(context, HomePageWidget());
            } catch (_) {}
          }
          return;
        });
        return;
      }

      await showAppSuccessDialog(
        context,
        title: 'Google signed in',
        desc:
            'We prefilled your name and email. Complete the form to finish creating your account.',
      );
    } else {
      final err = res['error'];
      final message = (err is Map && err['message'] != null)
          ? err['message'].toString()
          : (err != null ? err.toString() : 'Google sign-in failed');

      if (!mounted) return;
      await showAppErrorDialog(
        context,
        title: 'Sign-in error',
        desc: message,
      );
    }
  }

  Future<void> _handleAppleSignIn() async {
    // Only available on iOS
    if (!Platform.isIOS) return;

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
        // Navigate to welcome screen
        Future.microtask(() async {
          if (!mounted) return;
          try {
            String? token;
            if (res['token'] != null) token = res['token']?.toString();
            if (token == null)
              token = (data['token'] ?? data['data']?['token'])?.toString();

            final name =
                profile != null ? (profile['name']?.toString() ?? '') : '';
            final role = _effectiveRole ?? widget.initialRole ?? 'customer';
            final welcome = WelcomeAfterSignupWidget(role: role, name: name);
            await AccountCreationNavigator.navigateAfterSignup(
              context,
              welcome,
              goRoute: WelcomeAfterSignupWidget.routePath,
              preferImperative: true,
            );

            if (token != null && token.isNotEmpty) {
              await AuthNotifier.instance.setToken(token);
            }
          } catch (_) {
            try {
              NavigationUtils.safePushReplacement(context, HomePageWidget());
            } catch (_) {}
          }
          return;
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

  Future<void> _handleCreateAccount() async {
    if (_isCreatingAccount) return;

    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Enforce acceptance of T&C and Privacy Policy
    if (!_acceptedTos) {
      await showAppErrorDialog(context,
          title: 'Terms required',
          desc:
              'You must accept the Terms & Conditions and Privacy Policy to create an account.');
      return;
    }

    setState(() => _isCreatingAccount = true);

    try {
      String normalizeRole(String? r) {
        if (r == null) return 'customer';
        final val = r.trim().toLowerCase();
        if (val == 'client' || val == 'customer') return 'customer';
        return val;
      }

      // Use the effective role (from constructor/route args) if available,
      // otherwise fallback to the widget.initialRole and finally 'customer'.
      final normalizedRole =
          normalizeRole(_effectiveRole ?? widget.initialRole);

      final res = await AuthService.register(
        name: _model.fullNameTextController?.text.trim() ?? '',
        email: _model.emailAddressTextController?.text.trim() ?? '',
        // Send the raw password (DO NOT trim/modify). Trimming here could
        // change the user's chosen password and cause later login failures.
        password: _passwordController.text,
        role: normalizedRole,
        phone: _phoneController.text.trim(),
      ).timeout(const Duration(seconds: 30));

      if (res['success'] == true) {
        await _processSuccessfulRegistration(res, normalizedRole);
      } else {
        _handleRegistrationError(res);
      }
    } catch (e) {
      _handleGenericError(e);
    } finally {
      if (mounted) {
        setState(() => _isCreatingAccount = false);
      }
    }
  }

  Future<void> _processSuccessfulRegistration(
    Map<String, dynamic> res,
    String normalizedRole,
  ) async {
    try {
      await TokenStorage.saveRecentRegistration(
        name: _model.fullNameTextController?.text.trim(),
        email: _model.emailAddressTextController?.text.trim(),
        phone: _phoneController.text.trim(),
      );
    } catch (_) {}

    if (!_navigateScheduled) {
      _navigateScheduled = true;

      // Show a short, non-blocking success toast then navigate to the welcome page
      // Use a green, floating SnackBar with a check icon to indicate success
      final successMsg = 'Account created successfully';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(successMsg)),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
      // Wait briefly (match previous overlay duration) so the welcome page shows after the toast
      await Future.delayed(const Duration(seconds: 3));

      // Navigate to the WelcomeAfterSignup page and pass the role and the user's name
      final name = _model.fullNameTextController?.text.trim();
      // Schedule navigation after a short delay to avoid calling Navigator while
      // it's locked (this can happen when previous dialogs/snackbars are still
      // animating). Using a small delay is a robust cross-device solution.
      Future.delayed(const Duration(milliseconds: 300), () async {
        if (!mounted) return;

        // Ensure the app in-memory state knows about the token immediately so
        // subsequent pages (dashboard/home) can fetch the user's profile.
        try {
          String? token;
          final body = res['data'];
          if (res['token'] != null) token = res['token']?.toString();
          if (token == null && body is Map) {
            token = (body['token'] ?? body['data']?['token'])?.toString();
          }
          // NOTE: move setting token until after navigation to the welcome page
          // so the router does not auto-redirect before the welcome screen is shown.

          // Navigate to the welcome page passing role and name.
          final welcome =
              WelcomeAfterSignupWidget(role: normalizedRole, name: name);
          try {
            // Use the AccountCreationNavigator helper which detects GoRouter/pages API
            await AccountCreationNavigator.navigateAfterSignup(
              context,
              welcome,
              goRoute: WelcomeAfterSignupWidget.routePath,
              preferImperative: true,
            );

            // Now apply token so router redirects (when appropriate) happen only
            // after the welcome screen is presented.
            if (token != null && token.isNotEmpty) {
              await AuthNotifier.instance.setToken(token);
            }
          } catch (e) {
            // Fallback to existing navigation util if helper fails
            try {
              await NavigationUtils.safeReplaceAllWith(context, welcome);
              if (token != null && token.isNotEmpty) {
                await AuthNotifier.instance.setToken(token);
              }
            } catch (_) {}
          }
        } catch (_) {}
      });
    }
  }

  void _handleRegistrationError(Map<String, dynamic> res) {
    final err = res['error'];
    String message = 'Failed to create account';

    if (err is Map && err['message'] != null) {
      message = err['message'].toString();
    } else if (err != null) {
      message = err.toString();
    }

    showAppErrorDialog(
      context,
      title: 'Error',
      desc: message,
    );
  }

  void _handleGenericError(dynamic e) {
    final errorMessage = 'An error occurred. Please try again.';
    showAppErrorDialog(
      context,
      title: 'Error',
      desc: errorMessage,
    );
  }

  void _navigateBack() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    // Use app primary color (not default blue)
    final Color primaryColor = const Color(0xFFA20025);

    return Scaffold(
      key: scaffoldKey,
      backgroundColor: isDark ? Colors.black : Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Top spacing and back button
                const SizedBox(height: 40.0),
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.chevron_left_rounded),
                    color: colorScheme.onSurface.withAlpha((0.6 * 255).toInt()),
                    onPressed: _navigateBack,
                    iconSize: 32,
                  ),
                ),

                // Brand/Logo Area
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: primaryColor.withAlpha((0.1 * 255).toInt()),
                  ),
                  child: Icon(
                    Icons.person_add,
                    size: 40,
                    color: primaryColor,
                  ),
                ),

                // Title
                const SizedBox(height: 32.0),
                Text(
                  'Create an account',
                  style: theme.textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w300,
                    letterSpacing: -0.5,
                  ),
                ),

                const SizedBox(height: 8.0),
                Text(
                  'Let\'s get started by filling out the form below.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface
                        .withAlpha((0.5 * 255).toInt()),
                    fontWeight: FontWeight.w300,
                  ),
                ),

                // Role Indicator (if present). Use the resolved _effectiveRole so
                // role is shown regardless of whether it arrived via the
                // constructor or route arguments.
                if (_effectiveRole != null) ...[
                  const SizedBox(height: 16.0),
                  Container(
                    decoration: BoxDecoration(
                      color: _effectiveRole!.toLowerCase() == 'artisan'
                          ? primaryColor.withAlpha((0.1 * 255).toInt())
                          : colorScheme.secondary
                              .withAlpha((0.1 * 255).toInt()),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 8.0,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _effectiveRole!.toLowerCase() == 'artisan'
                              ? Icons.handyman_outlined
                              : Icons.person_outline,
                          color: _effectiveRole!.toLowerCase() == 'artisan'
                              ? primaryColor
                              : colorScheme.secondary,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _effectiveRole!.toLowerCase() == 'artisan'
                              ? 'Artisan Account'
                              : 'Client Account',
                          style: TextStyle(
                            color: _effectiveRole!.toLowerCase() == 'artisan'
                                ? primaryColor
                                : colorScheme.secondary,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Form
                const SizedBox(height: 40.0),
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Full Name Field
                      Text(
                        'FULL NAME',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurface
                              .withAlpha((0.6 * 255).toInt()),
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      TextFormField(
                        controller: _model.fullNameTextController,
                        focusNode: _model.fullNameFocusNode,
                        autofillHints: const [AutofillHints.name],
                        decoration: InputDecoration(
                          hintText: 'John Doe',
                          hintStyle: TextStyle(
                            color: theme.colorScheme.onSurface
                                .withAlpha((0.3 * 255).toInt()),
                          ),
                          filled: true,
                          fillColor:
                              isDark ? Colors.grey[900] : Colors.grey[50],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0),
                            borderSide: BorderSide(
                              color: primaryColor,
                              width: 1.5,
                            ),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0),
                            borderSide: BorderSide(
                              color: theme.colorScheme.error,
                              width: 1.0,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 16.0,
                          ),
                        ),
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 16,
                        ),
                        textInputAction: TextInputAction.next,
                        validator: _validateName,
                        onFieldSubmitted: (_) => FocusScope.of(context)
                            .requestFocus(_model.emailAddressFocusNode),
                      ),

                      const SizedBox(height: 20.0),

                      // Email Field
                      Text(
                        'EMAIL',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurface
                              .withAlpha((0.6 * 255).toInt()),
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      TextFormField(
                        controller: _model.emailAddressTextController,
                        focusNode: _model.emailAddressFocusNode,
                        autofillHints: const [AutofillHints.email],
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          hintText: 'your@email.com',
                          hintStyle: TextStyle(
                            color: theme.colorScheme.onSurface
                                .withAlpha((0.3 * 255).toInt()),
                          ),
                          filled: true,
                          fillColor:
                              isDark ? Colors.grey[900] : Colors.grey[50],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0),
                            borderSide: BorderSide(
                              color: primaryColor,
                              width: 1.5,
                            ),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0),
                            borderSide: BorderSide(
                              color: theme.colorScheme.error,
                              width: 1.0,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 16.0,
                          ),
                        ),
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 16,
                        ),
                        textInputAction: TextInputAction.next,
                        validator: _validateEmail,
                        onFieldSubmitted: (_) => FocusScope.of(context)
                            .requestFocus(_phoneFocusNode),
                      ),

                      const SizedBox(height: 20.0),

                      // Phone Number Field
                      Text(
                        'PHONE NUMBER',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurface
                              .withAlpha((0.6 * 255).toInt()),
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      TextFormField(
                        controller: _phoneController,
                        focusNode: _phoneFocusNode,
                        autofillHints: const [AutofillHints.telephoneNumber],
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          hintText: '+1234567890',
                          hintStyle: TextStyle(
                            color: theme.colorScheme.onSurface
                                .withAlpha((0.3 * 255).toInt()),
                          ),
                          filled: true,
                          fillColor:
                              isDark ? Colors.grey[900] : Colors.grey[50],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0),
                            borderSide: BorderSide(
                              color: primaryColor,
                              width: 1.5,
                            ),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0),
                            borderSide: BorderSide(
                              color: theme.colorScheme.error,
                              width: 1.0,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 16.0,
                          ),
                        ),
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 16,
                        ),
                        textInputAction: TextInputAction.next,
                        validator: _validatePhone,
                        onFieldSubmitted: (_) => FocusScope.of(context)
                            .requestFocus(_passwordFocusNode),
                      ),

                      const SizedBox(height: 20.0),

                      // Password Field
                      Text(
                        'PASSWORD',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurface
                              .withAlpha((0.6 * 255).toInt()),
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      TextFormField(
                        controller: _passwordController,
                        focusNode: _passwordFocusNode,
                        obscureText: !_passwordVisible,
                        decoration: InputDecoration(
                          hintText: '••••••••',
                          hintStyle: TextStyle(
                            color: theme.colorScheme.onSurface
                                .withAlpha((0.3 * 255).toInt()),
                          ),
                          filled: true,
                          fillColor:
                              isDark ? Colors.grey[900] : Colors.grey[50],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0),
                            borderSide: BorderSide(
                              color: primaryColor,
                              width: 1.5,
                            ),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0),
                            borderSide: BorderSide(
                              color: theme.colorScheme.error,
                              width: 1.0,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 16.0,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _passwordVisible
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: theme.colorScheme.onSurface
                                  .withAlpha((0.4 * 255).toInt()),
                              size: 20,
                            ),
                            onPressed: () {
                              setState(() {
                                _passwordVisible = !_passwordVisible;
                              });
                            },
                          ),
                        ),
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 16,
                        ),
                        textInputAction: TextInputAction.done,
                        validator: _validatePassword,
                        onFieldSubmitted: (_) => _handleCreateAccount(),
                      ),

                      // Create Account Button
                      const SizedBox(height: 32.0),

                      // Accept T&C and Privacy Policy (required)
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Checkbox(
                              value: _acceptedTos,
                              onChanged: (v) {
                                if (!mounted) return;
                                setState(() => _acceptedTos = v ?? false);
                              },
                              // Unchecked: white outline & transparent fill. Checked: primaryColor fill, white tick.
                              fillColor:
                                  MaterialStateProperty.resolveWith<Color?>(
                                      (states) {
                                if (states.contains(MaterialState.selected))
                                  return primaryColor;
                                return Colors.transparent;
                              }),
                              checkColor: Colors.white,
                              side: BorderSide(
                                  color: isDark ? Colors.white : Colors.black,
                                  width: 1.5),
                            ),
                            const SizedBox(width: 5),
                            // Tap non-link text to toggle the checkbox; link spans still open URLs.
                            GestureDetector(
                              onTap: () {
                                if (!mounted) return;
                                setState(() => _acceptedTos = !_acceptedTos);
                              },
                              child: Text.rich(
                                TextSpan(
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.color,
                                    fontSize:
                                        11, // slightly smaller to keep whole text on one line
                                  ),
                                  children: [
                                    const TextSpan(text: 'I accept the '),
                                    TextSpan(
                                      text: 'T&C',
                                      recognizer: _tncRecognizer,
                                      style: TextStyle(
                                        color: primaryColor,
                                        fontWeight: FontWeight.w600,
                                        decoration: TextDecoration.underline,
                                        fontSize: 10,
                                      ),
                                    ),
                                    const TextSpan(text: ' and the '),
                                    TextSpan(
                                      text: 'Privacy Policy',
                                      recognizer: _privacyRecognizer,
                                      style: TextStyle(
                                        color: primaryColor,
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
                      ),

                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 18.0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.0),
                          ),
                          elevation: 0,
                        ),
                        onPressed:
                            _isCreatingAccount ? null : _handleCreateAccount,
                        child: _isCreatingAccount
                            ? SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(
                                    colorScheme.onPrimary,
                                  ),
                                ),
                              )
                            : Text(
                                'CREATE ACCOUNT',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                      ),

                      // Divider
                      const SizedBox(height: 48.0),
                      Row(
                        children: [
                          Expanded(
                            child: Divider(
                              color: theme.colorScheme.onSurface
                                  .withAlpha((0.1 * 255).toInt()),
                              thickness: 1,
                            ),
                          ),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Text(
                              'OR',
                              style: TextStyle(
                                color: theme.colorScheme.onSurface
                                    .withAlpha((0.3 * 255).toInt()),
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Divider(
                              color: theme.colorScheme.onSurface
                                  .withAlpha((0.1 * 255).toInt()),
                              thickness: 1,
                            ),
                          ),
                        ],
                      ),

                      // Google Sign In Button
                      const SizedBox(height: 24.0),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: primaryColor,
                          ),
                          padding: const EdgeInsets.symmetric(
                              vertical: 12.0, horizontal: 12.0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.0),
                          ),
                        ),
                        // Google Sign-In enabled
                        onPressed: _handleGoogleSignIn,
                        child: LayoutBuilder(builder: (context, constraints) {
                          // Keep content constrained to avoid overflow on narrow screens
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Match login page: 24x24 asset icon and centered label
                              SizedBox(
                                height: 24,
                                width: 24,
                                child: Builder(builder: (ctx) {
                                  try {
                                    return Image.asset(
                                      'assets/images/google.webp',
                                      fit: BoxFit.contain,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                        return Icon(
                                          Icons.g_mobiledata,
                                          color: primaryColor,
                                          size: 20,
                                        );
                                      },
                                    );
                                  } catch (_) {
                                    return Icon(
                                      Icons.g_mobiledata,
                                      color: primaryColor,
                                      size: 20,
                                    );
                                  }
                                }),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Continue with Google',
                                style: TextStyle(
                                  color: primaryColor,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          );
                        }),
                      ),

                      // Apple Sign In Button (iOS only)
                      if (Platform.isIOS) ...[
                        const SizedBox(height: 12.0),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                                color: isDark ? Colors.white : Colors.black),
                            backgroundColor:
                                isDark ? Colors.white : Colors.black,
                            padding: const EdgeInsets.symmetric(
                                vertical: 12.0, horizontal: 12.0),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12.0),
                            ),
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
                        ),
                      ],

                      // Already have an account? Log in
                      const SizedBox(height: 24.0),
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Already have an account? ',
                              style: TextStyle(
                                color: theme.colorScheme.onSurface
                                    .withAlpha((0.7 * 255).toInt()),
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                // Direct navigation to Login page so tap immediately routes there.
                                if (!mounted) return;
                                try {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const LoginAccountWidget(),
                                    ),
                                  );
                                } catch (e) {
                                  // Fallback to safe helpers if direct push fails for any reason
                                  try {
                                    NavigationUtils.safePushNoAuth(
                                        context, const LoginAccountWidget());
                                  } catch (_) {
                                    try {
                                      NavigationUtils.safePush(
                                          context, const LoginAccountWidget());
                                    } catch (_) {}
                                  }
                                }
                              },
                              style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 4.0)),
                              child: Text(
                                'Log in',
                                style: TextStyle(
                                  color: primaryColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Bottom spacing
                      const SizedBox(height: 60.0),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
