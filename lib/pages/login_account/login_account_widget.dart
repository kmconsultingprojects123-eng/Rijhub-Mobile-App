import 'dart:ui';
import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import '/services/auth_service.dart';
import '../forget_password/forget_password_widget.dart';
import 'login_account_model.dart';
import '../../utils/app_notification.dart';
import '../../utils/error_messages.dart';
import '../../state/app_state_notifier.dart';
import '../../state/auth_notifier.dart';
import '../artisan_dashboard_page/artisan_dashboard_page_widget.dart';
import '../home_page/home_page_widget.dart';
import '/flutter_flow/flutter_flow_model.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/nav/nav.dart';
import '../../services/token_storage.dart';
import '../create_account2/create_account2_widget.dart';
import '/main.dart';
import '../../utils/navigation_utils.dart';
import '../../utils/notification_permission_dialog.dart';
export 'login_account_model.dart';

class LoginAccountWidget extends StatefulWidget {
  const LoginAccountWidget({super.key});

  static String routeName = 'LoginAccount';
  static String routePath = '/loginAccount';

  @override
  State<LoginAccountWidget> createState() => _LoginAccountWidgetState();
}

class _LoginAccountWidgetState extends State<LoginAccountWidget> {
  late LoginAccountModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();
  final _formKey = GlobalKey<FormState>();
  bool _isLoggingIn = false;
  bool _passwordVisible = false;

  // Add a navigation lock
  bool _isNavigating = false;
  // Google sign-in in progress
  bool _isGoogleSigningIn = false;
  // Apple sign-in in progress
  bool _isAppleSigningIn = false;
  // Remember-me flag (persisted)
  bool _rememberMe = false;

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => LoginAccountModel());

    _model.emailAddressTextController ??= TextEditingController();
    _model.emailAddressFocusNode ??= FocusNode();

    _model.passWordTextController ??= TextEditingController();
    _model.passWordFocusNode ??= FocusNode();

    // Load saved remember-me state and prefilling email
    TokenStorage.getRememberMe().then((v) {
      if (!mounted) return;
      setState(() => _rememberMe = v);
    });
    TokenStorage.getRememberedEmail().then((email) {
      if (!mounted) return;
      if (email != null && email.isNotEmpty) {
        _model.emailAddressTextController?.text = email;
      }
    });
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your email';
    }
    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
    if (!emailRegex.hasMatch(value)) {
      return 'Please enter a valid email';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your password';
    }
    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  Future<void> _handleLogin() async {
    if (_isLoggingIn) return;

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoggingIn = true);

    try {
      final email = _model.emailAddressTextController?.text.trim() ?? '';
      final password = _model.passWordTextController?.text ?? '';

      final res = await AuthService.login(
        email: email,
        password: password,
      ).timeout(const Duration(seconds: 30), onTimeout: () {
        throw TimeoutException('Login timeout. Please try again.');
      });

      if (res['success'] == true) {
        // Persist remember-me preference/email
        try {
          await TokenStorage.saveRememberMe(_rememberMe);
          if (_rememberMe)
            await TokenStorage.saveRememberedEmail(email);
          else
            await TokenStorage.saveRememberedEmail(null);
        } catch (_) {}

        await _processSuccessfulLogin(res);
      } else {
        // Best-effort: if login failed with ambiguous error (invalid credentials),
        // try to verify whether the email exists on the server. If the email
        // does not exist (or was deleted), show a clearer 'Account not found'
        // message. This avoids telling users "invalid credentials" when their
        // account was removed.
        try {
          // If server already indicated 404/not found, let _handleLoginError handle it
          final err = res['error'];
          bool handled = false;
          if (err is Map && err.containsKey('status')) {
            final s = int.tryParse(err['status'].toString());
            if (s == 404) {
              _handleLoginError(res);
              handled = true;
            }
          } else if (err is String && err.toLowerCase().contains('not found')) {
            _handleLoginError(res);
            handled = true;
          }

          if (!handled) {
            // Try check-email endpoint (best-effort). The server may not expose
            // this endpoint; in that case we fall back to the generic error.
            try {
              final check = await AuthService.checkEmailExists(email: email).timeout(const Duration(seconds: 8));
              if (check['success'] == true) {
                final body = check['data'];
                bool? exists;
                try {
                  if (body is Map) {
                    if (body.containsKey('exists')) exists = body['exists'] as bool?;
                    else if (body.containsKey('data') && body['data'] is Map && body['data'].containsKey('exists')) exists = body['data']['exists'] as bool?;
                  }
                } catch (_) {}

                if (exists == false) {
                  AppNotification.showError(context, 'Account not found. Please register or check the email used.');
                  handled = true;
                }
              }
            } catch (_) {
              // ignore any check-email errors and fallback to generic handler
            }
          }

          if (!handled) _handleLoginError(res);
        } catch (_) {
          _handleLoginError(res);
        }
      }
    } on TimeoutException catch (e) {
      AppNotification.showError(context, ErrorMessages.humanize(e));
    } catch (e) {
      AppNotification.showError(context, ErrorMessages.humanize(e));
    } finally {
      if (mounted) {
        setState(() => _isLoggingIn = false);
      }
    }
  }

  Future<void> _processSuccessfulLogin(Map<String, dynamic> res) async {
    final token = _extractToken(res['data']);

    // Attempt to parse role from common locations in the response so we can
    // set AuthNotifier status immediately instead of waiting for profile fetch.
    String? parsedRole;
    try {
      final body = res['data'] ?? res;
      if (body is Map) {
        parsedRole =
            (body['role'] ?? body['user']?['role'] ?? body['data']?['role'])
                ?.toString();
        // Some APIs include user object at top-level
        if (parsedRole == null && body['user'] is Map) {
          parsedRole =
              (body['user']?['type'] ?? body['user']?['role'])?.toString();
        }
      }
      if (parsedRole != null && parsedRole.isNotEmpty)
        parsedRole = parsedRole.toLowerCase();
    } catch (_) {
      parsedRole = null;
    }

    if (parsedRole != null && parsedRole.isNotEmpty) {
      // If we have an explicit role, use login(role, token) to set status fast.
      await AuthNotifier.instance.login(parsedRole, token: token);
    } else if (token != null) {
      // No role found; persist token and refresh profile (compatibility path).
      await AuthNotifier.instance.setToken(token);
    } else {
      await AuthNotifier.instance.refreshAuth();
    }

    // Wait briefly for profile to populate
    final timeout = DateTime.now().add(Duration(seconds: 3));
    while (DateTime.now().isBefore(timeout)) {
      final prof = AuthNotifier.instance.profile;
      if (prof != null) break;
      await Future.delayed(Duration(milliseconds: 150));
    }

    if (!mounted) return;

    // Notify user of successful login
    AppNotification.showSuccess(context, 'Logged in successfully');
    await Future.delayed(const Duration(milliseconds: 200));

    // Show friendly notification permission dialog before navigating (Apple Guideline 4.5.4)
    if (!mounted) return;
    var roleForDialog = parsedRole ?? '';
    if (roleForDialog.isEmpty) {
      final prof = AuthNotifier.instance.profile;
      roleForDialog = (prof?['role'] ?? prof?['type'] ?? 'customer').toString();
    }
    await showNotificationPermissionDialog(context, role: roleForDialog.isNotEmpty ? roleForDialog : 'customer');

    // Do NOT pop the route stack here. When login is reached via Navigator.push
    // (e.g. from create_account2 or splash_screen_page2), popping would pop back
    // through create_account2 to splash, leaving the user on the splash screen
    // instead of home. The GoRouter redirect also does not apply when login was
    // pushed (GoRouter's location stays at the underlying route). Always use
    // imperative role-based navigation to ensure the user reaches home/dashboard.
    if (!mounted) return;
    await _navigateBasedOnRole();
  }

  String? _extractToken(dynamic data) {
    if (data is Map) {
      return (data['token'] ?? data['data']?['token'])?.toString();
    }
    return null;
  }

  // Update navigation logic to use the lock
  Future<void> _navigateBasedOnRole() async {
    if (_isNavigating) return;
    _isNavigating = true;

    try {
      final profile = AppStateNotifier.instance.profile;
      final role = _getUserRole(profile);

      // If profile did not include a role yet, fall back to persisted role from TokenStorage
      var roleStr = role;
      if (roleStr.isEmpty) {
        try {
          final storedRole = await TokenStorage.getRole();
          if (storedRole != null && storedRole.isNotEmpty)
            roleStr = storedRole.toLowerCase();
        } catch (_) {}
      }

      final routeName = roleStr.contains('artisan')
          ? ArtisanDashboardPageWidget.routeName
          : HomePageWidget.routeName;
      final routePath = roleStr.contains('artisan')
          ? ArtisanDashboardPageWidget.routePath
          : HomePageWidget.routePath;

      // Helper to log navigation attempts for debugging
      void _log(String m) {
        try {
          if (kDebugMode) debugPrint('LoginNav: $m');
        } catch (_) {}
      }

      var navigated = false;

      // 1) Try GoRouter goNamed (preferred)
      try {
        _log('Attempting goNamed($routeName)');
        GoRouter.of(context).goNamed(routeName);
        navigated = true;
        _log('goNamed succeeded');
      } catch (e) {
        _log('goNamed failed: $e');
      }

      // 2) Try GoRouter.go with path
      if (!navigated) {
        try {
          _log('Attempting go($routePath)');
          GoRouter.of(context).go(routePath);
          navigated = true;
          _log('go(path) succeeded');
        } catch (e) {
          _log('go(path) failed: $e');
        }
      }

      // 3) Try context.pushNamed (push onto stack)
      if (!navigated) {
        try {
          _log('Attempting context.pushNamed($routeName)');
          await context.pushNamed(routeName);
          navigated = true;
          _log('context.pushNamed succeeded');
        } catch (e) {
          _log('context.pushNamed failed: $e');
        }
      }

      // 4) Fallback to direct pushReplacement with Widget
      if (!navigated) {
        try {
          _log(
              'Attempting NavigationUtils.safePushReplacement with direct widget');
          final widget = role.contains('artisan')
              ? NavBarPage(initialPage: 'homePage')
              : HomePageWidget();
          await NavigationUtils.safePushReplacement(context, widget);
          navigated = true;
          _log('NavigationUtils.safePushReplacement scheduled');
        } catch (e) {
          _log('Navigator fallback failed: $e');
        }
      }

      // 5) App-level navigator fallback: replace entire stack via appNavigatorKey
      if (!navigated) {
        try {
          _log('Attempting appNavigatorKey.pushAndRemoveUntil');
          final page = roleStr.contains('artisan')
              ? NavBarPage(initialPage: 'homePage')
              : HomePageWidget();
          NavigationUtils.safeReplaceAllWith(context, page);
          navigated = true;
          _log('NavigationUtils.safeReplaceAllWith scheduled');
        } catch (e) {
          _log('appNavigatorKey fallback failed: $e');
        }
      }
    } catch (e) {
      _fallbackNavigation();
    } finally {
      _isNavigating = false;
    }
  }

  String _getUserRole(Map<String, dynamic>? profile) {
    final role = (profile?['role'] ?? profile?['type'] ?? '')?.toString();
    final roleLowerCase = role?.toLowerCase() ?? '';
    return roleLowerCase;
  }

  void _fallbackNavigation() {
    if (_isNavigating) return;
    _isNavigating = true;

    try {
      final profile = AppStateNotifier.instance.profile;
      final role = _getUserRole(profile);

      final widget = role.contains('artisan')
          ? NavBarPage(initialPage: 'homePage')
          : HomePageWidget();
      NavigationUtils.safeReplaceAllWith(context, widget);
    } finally {
      _isNavigating = false;
    }
  }

  void _handleLoginError(Map<String, dynamic> res) {
    // Default generic message
    String errorMessage = 'Login failed. Please check your credentials.';

    final dynamic err = res['error'];
    String? serverMsg;
    int? statusCode;

    try {
      if (err is Map) {
        // Common shapes: { message: '...', status: 404 } or { error: '...' }
        if (err.containsKey('status')) statusCode = int.tryParse(err['status'].toString());
        serverMsg = (err['message'] ?? err['error'] ?? err['msg'] ?? err['detail'])?.toString();
      } else if (err != null) {
        serverMsg = err.toString();
      }
    } catch (_) {
      serverMsg = err?.toString();
    }

    final low = serverMsg?.toLowerCase() ?? '';

    // If server indicates resource not found -> show 'Account not found'
    if (statusCode == 404 || low.contains('not found') || low.contains('user not found') || low.contains('account not found') || low.contains('no account')) {
      errorMessage = 'Account not found. Please register or check the email used.';
    }
    // If server was explicit about invalid credentials keep a clearer message
    else if (low.contains('invalid') && (low.contains('credential') || low.contains('password') || low.contains('email'))) {
      errorMessage = 'Invalid email or password.';
    }
    // Fallback to server message when it's informative
    else if (serverMsg != null && serverMsg.isNotEmpty) {
      errorMessage = serverMsg;
    }

    AppNotification.showError(context, errorMessage);
  }

  Future<void> _handleGoogleSignIn() async {
    if (_isGoogleSigningIn || _isNavigating) return;
    setState(() => _isGoogleSigningIn = true);

    try {
      final res = await AuthService.signInWithGoogle();

      if (!mounted) return;

      if (res['success'] == true) {
        // Notify user
        AppNotification.showSuccess(context, 'Logged in with Google');
        await Future.delayed(const Duration(milliseconds: 200));

        // Extract token and role from response
        final data = res['data'];
        String? token;
        String? parsedRole;

        if (data is Map) {
          token = (data['token'] ?? data['data']?['token'])?.toString();
          parsedRole =
              (data['role'] ?? data['user']?['role'] ?? data['data']?['role'])
                  ?.toString();
        }

        // Set auth state
        if (parsedRole != null && parsedRole.isNotEmpty) {
          await AuthNotifier.instance
              .login(parsedRole.toLowerCase(), token: token);
        } else if (token != null) {
          await AuthNotifier.instance.setToken(token);
        } else {
          await AuthNotifier.instance.refreshAuth();
        }

        // Wait briefly for profile
        final timeout = DateTime.now().add(Duration(seconds: 2));
        while (DateTime.now().isBefore(timeout)) {
          if (AuthNotifier.instance.profile != null) break;
          await Future.delayed(Duration(milliseconds: 100));
        }

        if (!mounted) return;
        await _navigateBasedOnRole();
      } else {
        final err = res['error'];
        final message = (err is Map && err['message'] != null)
            ? err['message'].toString()
            : (err != null ? err.toString() : 'Google sign-in failed');
        AppNotification.showError(context, message);
      }
    } catch (e) {
      AppNotification.showError(context, ErrorMessages.humanize(e));
    } finally {
      if (mounted) setState(() => _isGoogleSigningIn = false);
    }
  }

  Future<void> _handleAppleSignIn() async {
    // Only available on iOS
    if (!Platform.isIOS) {
      AppNotification.showError(
          context, 'Apple Sign-In is only available on iOS');
      return;
    }

    if (_isAppleSigningIn || _isNavigating) return;
    setState(() => _isAppleSigningIn = true);

    try {
      final res = await AuthService.signInWithApple();

      if (!mounted) return;

      if (res['success'] == true) {
        // Notify user
        AppNotification.showSuccess(context, 'Logged in with Apple');
        await Future.delayed(const Duration(milliseconds: 200));

        // Extract token and role from response
        final data = res['data'];
        String? token;
        String? parsedRole;

        if (data is Map) {
          token = (data['token'] ?? data['data']?['token'])?.toString();
          parsedRole =
              (data['role'] ?? data['user']?['role'] ?? data['data']?['role'])
                  ?.toString();
        }

        // Set auth state
        if (parsedRole != null && parsedRole.isNotEmpty) {
          await AuthNotifier.instance
              .login(parsedRole.toLowerCase(), token: token);
        } else if (token != null) {
          await AuthNotifier.instance.setToken(token);
        } else {
          await AuthNotifier.instance.refreshAuth();
        }

        // Wait briefly for profile
        final timeout = DateTime.now().add(Duration(seconds: 2));
        while (DateTime.now().isBefore(timeout)) {
          if (AuthNotifier.instance.profile != null) break;
          await Future.delayed(Duration(milliseconds: 100));
        }

        if (!mounted) return;
        await _navigateBasedOnRole();
      } else {
        final err = res['error'];
        final message = (err is Map && err['message'] != null)
            ? err['message'].toString()
            : (err != null ? err.toString() : 'Apple sign-in failed');
        if (message != 'Apple sign-in cancelled') {
          AppNotification.showError(context, message);
        }
      }
    } catch (e) {
      AppNotification.showError(context, ErrorMessages.humanize(e));
    } finally {
      if (mounted) setState(() => _isAppleSigningIn = false);
    }
  }

  Future<void> _navigateToSignUp() async {
    if (_isNavigating) return;
    if (!mounted) return;
    setState(() => _isNavigating = true);

    try {
      final navigator = Navigator.of(context);
      var navigated = false;

      // Prefer direct MaterialPageRoute navigation to avoid reliance on
      // Navigator.onGenerateRoute / named routes that may not be configured.
      try {
        await NavigationUtils.safePushNoAuth(context, CreateAccount2Widget());
        navigated = true;
      } catch (_) {}

      // If the direct push failed for any reason, try named routes as a fallback
      if (!navigated) {
        try {
          await NavigationUtils.safePushNoAuth(context, CreateAccount2Widget());
          navigated = true;
        } catch (_) {}
      }

      if (!navigated) {
        try {
          await NavigationUtils.safePushNoAuth(context, CreateAccount2Widget());
          navigated = true;
        } catch (_) {}
      }
    } catch (e, st) {
      // Show a friendly error and log stacktrace if navigation fails
      AppNotification.showError(
          context, 'Could not open Sign up: ${ErrorMessages.humanize(e)}');
      // Optionally: print to console for debugging
      if (kDebugMode)
        debugPrint('Navigation error in _navigateToSignUp: $e\n$st');
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  // Show a bottom sheet prompting user to choose a role (artisan or client)
  Future<void> _showRoleSelectionSheet() async {
    if (_isNavigating) return;

    final selected = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final isDark = theme.brightness == Brightness.dark;
        final primaryColor = const Color(0xFFA20025);

        return SafeArea(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            decoration: BoxDecoration(
              color: isDark ? Color(0xFF0B0B0B) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.dividerColor.withOpacity(0.08)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Drag handle and close button
                Row(
                  children: [
                    Expanded(
                      child: Center(
                        child: Container(
                          width: 48,
                          height: 4,
                          decoration: BoxDecoration(
                            color: theme.dividerColor.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(null),
                      icon: Icon(Icons.close,
                          size: 20, color: theme.iconTheme.color),
                      tooltip: 'Close',
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // Title
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: Text(
                    'Create account',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: Text(
                    'Choose how you want to use the platform',
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color:
                            theme.textTheme.bodySmall?.color?.withOpacity(0.8)),
                  ),
                ),

                const SizedBox(height: 14),

                // Options
                Column(
                  children: [
                    Material(
                      color: isDark ? Color(0xFF111212) : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.of(ctx).pop('artisan'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 14.0, horizontal: 12.0),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: primaryColor.withOpacity(0.12),
                                child: Icon(Icons.handyman_rounded,
                                    color: primaryColor, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Artisan',
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                                fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 4),
                                    Text(
                                        'Sign up to offer services and get booked by clients',
                                        style: theme.textTheme.bodySmall),
                                  ],
                                ),
                              ),
                              Icon(Icons.arrow_forward_ios,
                                  size: 14,
                                  color:
                                      theme.iconTheme.color?.withOpacity(0.6)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Material(
                      color: isDark ? Color(0xFF111212) : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.of(ctx).pop('customer'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 14.0, horizontal: 12.0),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: primaryColor.withOpacity(0.12),
                                child: Icon(Icons.person_rounded,
                                    color: primaryColor, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Client',
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                                fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 4),
                                    Text(
                                        'Sign up to post jobs and hire artisans in your area',
                                        style: theme.textTheme.bodySmall),
                                  ],
                                ),
                              ),
                              Icon(Icons.arrow_forward_ios,
                                  size: 14,
                                  color:
                                      theme.iconTheme.color?.withOpacity(0.6)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Cancel secondary action
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: Text('Cancel',
                      style: TextStyle(
                          color: theme.textTheme.bodySmall?.color
                              ?.withOpacity(0.9))),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected != null) {
      await _navigateToSignUpWithRole(selected);
    }
  }

  Future<void> _navigateToSignUpWithRole(String role) async {
    if (_isNavigating) return;
    if (!mounted) return;
    setState(() => _isNavigating = true);

    try {
      final navigator = Navigator.of(context);
      var navigated = false;

      // Try named route with arguments if configured (best-effort)
      try {
        await navigator.push(MaterialPageRoute(
            builder: (_) => CreateAccount2Widget(initialRole: role)));
        navigated = true;
      } catch (_) {}

      // Fallbacks: attempt other navigation styles
      if (!navigated) {
        try {
          await navigator.pushNamed(CreateAccount2Widget.routeName,
              arguments: {'initialRole': role});
          navigated = true;
        } catch (_) {}
      }

      if (!navigated) {
        try {
          await navigator.pushNamed(CreateAccount2Widget.routePath,
              arguments: {'initialRole': role});
          navigated = true;
        } catch (_) {}
      }

      if (!navigated) {
        // direct push (already attempted above, but keep final fallback)
        await navigator.push(MaterialPageRoute(
            builder: (_) => CreateAccount2Widget(initialRole: role)));
      }
    } catch (e, st) {
      AppNotification.showError(
          context, 'Could not open Sign up: ${ErrorMessages.humanize(e)}');
      if (kDebugMode)
        debugPrint('Navigation error in _navigateToSignUpWithRole: $e\n$st');
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  // Navigation to forget-password uses direct `context.go(...)` from the UI now.

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // Update the primary color to #a20025
    final Color primaryColor = const Color(0xFFA20025);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: isDark ? Colors.black : Colors.white,
        body: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Top Spacing
                  const SizedBox(height: 80.0),

                  // Brand/Logo Area - Minimal
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: primaryColor.withAlpha((0.1 * 255).toInt()),
                    ),
                    child: Icon(
                      Icons.person,
                      size: 40,
                      color: primaryColor,
                    ),
                  ),

                  // Title - Minimal Typography
                  const SizedBox(height: 40.0),
                  Text(
                    'Welcome Back',
                    style: theme.textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w300,
                      letterSpacing: -0.5,
                    ),
                  ),

                  const SizedBox(height: 8.0),
                  Text(
                    'Sign in to your account',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withAlpha((0.5 * 255).toInt()),
                      fontWeight: FontWeight.w300,
                    ),
                  ),

                  // Form
                  const SizedBox(height: 48.0),
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
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
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          validator: _validateEmail,
                          onFieldSubmitted: (_) => FocusScope.of(context)
                              .requestFocus(_model.passWordFocusNode),
                        ),

                        const SizedBox(height: 24.0),

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
                          controller: _model.passWordTextController,
                          focusNode: _model.passWordFocusNode,
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
                          onFieldSubmitted: (_) => _handleLogin(),
                        ),

                        // Forgot Password - Minimal Link
                        const SizedBox(height: 16.0),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () =>
                                context.go(ForgetPasswordWidget.routePath),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'Forgot password?',
                              style: TextStyle(
                                color: primaryColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                        ),

                        // Remember me checkbox
                        const SizedBox(height: 8.0),
                        Row(
                          children: [
                            Checkbox(
                              value: _rememberMe,
                              onChanged: (v) {
                                if (!mounted) return;
                                setState(() => _rememberMe = v ?? false);
                              },
                              fillColor:
                                  MaterialStateProperty.resolveWith<Color?>(
                                      (states) {
                                if (states.contains(MaterialState.selected))
                                  return primaryColor;
                                return isDark
                                    ? Colors.grey[800]
                                    : Colors.grey[100];
                              }),
                              checkColor: Colors.white,
                              side: BorderSide(
                                color: _rememberMe
                                    ? primaryColor
                                    : theme.colorScheme.outline,
                                width: 1.5,
                              ),
                            ),
                            Expanded(
                                child: Text('Remember me',
                                    style: theme.textTheme.bodyMedium)),
                          ],
                        ),

                        // Login Button - Minimal
                        const SizedBox(height: 32.0),
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
                          onPressed: _isLoggingIn ? null : _handleLogin,
                          child: _isLoggingIn
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
                                  'SIGN IN',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),

                  // Divider - Minimal
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
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
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
                      side: BorderSide(color: primaryColor),
                      padding: const EdgeInsets.symmetric(
                          vertical: 14.0, horizontal: 12.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                    ),
                    onPressed: _isGoogleSigningIn ? null : _handleGoogleSignIn,
                    child: _isGoogleSigningIn
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(primaryColor),
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
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
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                  ),

                  // Apple Sign In Button (iOS only)
                  if (Platform.isIOS) ...[
                    const SizedBox(height: 12.0),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color: isDark ? Colors.white : Colors.black),
                        backgroundColor: isDark ? Colors.white : Colors.black,
                        padding: const EdgeInsets.symmetric(
                            vertical: 14.0, horizontal: 12.0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                      ),
                      onPressed: _isAppleSigningIn ? null : _handleAppleSignIn,
                      child: _isAppleSigningIn
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(
                                    isDark ? Colors.black : Colors.white),
                              ),
                            )
                          : Row(
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

                  // Sign Up - Minimal
                  const SizedBox(height: 32.0),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Don't have an account? ",
                        style: TextStyle(
                          color: theme.colorScheme.onSurface
                              .withAlpha((0.5 * 255).toInt()),
                          fontSize: 14,
                        ),
                      ),
                      TextButton(
                        onPressed: _showRoleSelectionSheet,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          'Sign up',
                          style: TextStyle(
                            color: primaryColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Bottom Spacing
                  const SizedBox(height: 60.0),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
