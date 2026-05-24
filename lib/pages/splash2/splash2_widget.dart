import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'splash2_model.dart';
export 'splash2_model.dart';

class Splash2Widget extends StatefulWidget {
  const Splash2Widget({super.key});

  static String routeName = 'Splash2';
  static String routePath = '/splash2';

  @override
  State<Splash2Widget> createState() => _Splash2WidgetState();
}

class _Splash2WidgetState extends State<Splash2Widget> {
  late Splash2Model _model;
  final scaffoldKey = GlobalKey<ScaffoldState>();
  final Color primaryColor = const Color(0xFFA20025);

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => Splash2Model());

    // Do NOT auto-redirect here. User must explicitly press Get Started / Login.
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  Future<void> _navigateToRoleSelection() async {
    if (!mounted) return;
    await Future.delayed(const Duration(milliseconds: 80));
    try {
      GoRouter.of(context).go(SplashScreenPage2Widget.routePath);
      return;
    } catch (_) {}

    try {
      if (appNavigatorKey.currentState != null &&
          appNavigatorKey.currentState!.mounted) {
        final route = MaterialPageRoute(
          builder: (_) => const SplashScreenPage2Widget(),
          settings: RouteSettings(name: SplashScreenPage2Widget.routeName),
        );
        await appNavigatorKey.currentState!.push(route);
        return;
      }
    } catch (_) {}

    if (mounted) {
      final route = MaterialPageRoute(
        builder: (_) => const SplashScreenPage2Widget(),
        settings: RouteSettings(name: SplashScreenPage2Widget.routeName),
      );
      await Navigator.of(context, rootNavigator: true).push(route);
    }
  }

  Future<void> _navigateToLogin() async {
    if (!mounted) return;
    await Future.delayed(const Duration(milliseconds: 80));
    try {
      GoRouter.of(context).go(LoginAccountWidget.routePath);
      return;
    } catch (_) {}

    try {
      if (appNavigatorKey.currentState != null &&
          appNavigatorKey.currentState!.mounted) {
        final route = MaterialPageRoute(
          builder: (_) => const LoginAccountWidget(),
          settings: RouteSettings(name: LoginAccountWidget.routeName),
        );
        await appNavigatorKey.currentState!.push<void>(route);
        return;
      }
    } catch (_) {}

    if (mounted) {
      final route = MaterialPageRoute(
        builder: (_) => const LoginAccountWidget(),
        settings: RouteSettings(name: LoginAccountWidget.routeName),
      );
      await Navigator.of(context, rootNavigator: true).push<void>(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 375;
    final isLargeScreen = screenSize.width > 600;

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: theme.scaffoldBackgroundColor,
        body: SafeArea(
          child: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: isDark
                  ? LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        theme.scaffoldBackgroundColor,
                        theme.scaffoldBackgroundColor
                            .withAlpha((0.98 * 255).round()),
                      ],
                    )
                  : null,
            ),
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: screenSize.height -
                      MediaQuery.of(context).padding.top -
                      MediaQuery.of(context).padding.bottom,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Top spacing
                    SizedBox(height: isSmallScreen ? 40 : 80),

                    // Main content
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: isSmallScreen
                              ? 140
                              : isLargeScreen
                                  ? 220
                                  : 200,
                          height: isSmallScreen
                              ? 140
                              : isLargeScreen
                                  ? 220
                                  : 200,
                          child: ClipRRect(
                            borderRadius:
                                BorderRadius.circular(isSmallScreen ? 12 : 16),
                            child: Image.asset(
                              isDark
                                  ? 'assets/images/logo_white.png'
                                  : 'assets/images/logo_black.png',
                              fit: BoxFit.contain,
                              errorBuilder: (c, e, s) {
                                return Center(
                                  child: Text(
                                    'R',
                                    style: TextStyle(
                                      color: primaryColor,
                                      fontSize: isSmallScreen ? 36 : 46,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        SizedBox(height: isSmallScreen ? 2 : 4),
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: isSmallScreen
                                ? 24
                                : isLargeScreen
                                    ? 80
                                    : 40,
                          ),
                          child: Text(
                            'Find skilled artisans and get work done...',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: isSmallScreen ? 13 : 14,
                              color: theme.colorScheme.onSurface
                                  .withAlpha((0.7 * 255).round()),
                              height: 1.25,
                            ),
                          ),
                        ),
                        SizedBox(height: isSmallScreen ? 40 : 60),
                      ],
                    ),

                    // Bottom buttons
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: isSmallScreen
                            ? 20
                            : isLargeScreen
                                ? 40
                                : 24,
                        vertical: 24,
                      ),
                      child: Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryColor,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(
                                  vertical: isSmallScreen ? 14 : 16,
                                  horizontal: 24,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                                shadowColor: Colors.transparent,
                              ),
                              onPressed: _navigateToRoleSelection,
                              child: Text(
                                'GET STARTED',
                                style: TextStyle(
                                  fontSize: isSmallScreen ? 15 : 16,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: theme.dividerColor
                                      .withAlpha((0.4 * 255).round()),
                                  width: 1.5,
                                ),
                                padding: EdgeInsets.symmetric(
                                  vertical: isSmallScreen ? 14 : 16,
                                  horizontal: 24,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                foregroundColor: theme.colorScheme.onSurface,
                              ),
                              onPressed: _navigateToLogin,
                              child: Text(
                                'SIGN IN',
                                style: TextStyle(
                                  fontSize: isSmallScreen ? 15 : 16,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                          // Continue as guest is not needed for now.
                          /*
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: theme.dividerColor
                                      .withAlpha((0.4 * 255).round()),
                                  width: 1.5,
                                ),
                                padding: EdgeInsets.symmetric(
                                  vertical: isSmallScreen ? 14 : 16,
                                  horizontal: 24,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                foregroundColor: theme.colorScheme.onSurface,
                              ),
                              onPressed: _continueAsGuest,
                              child: Text(
                                'CONTINUE AS GUEST',
                                style: TextStyle(
                                  fontSize: isSmallScreen ? 15 : 16,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                          */
                          Padding(
                            padding: const EdgeInsets.only(top: 24),
                            child: Text(
                              'By continuing you agree to our Terms & Privacy',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurface
                                    .withAlpha((0.5 * 255).round()),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
