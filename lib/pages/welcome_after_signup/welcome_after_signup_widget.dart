import 'dart:async';
import '/flutter_flow/nav/nav.dart';
import '/index.dart';
import '../../utils/navigation_utils.dart';
import 'package:flutter/material.dart';

class WelcomeAfterSignupWidget extends StatefulWidget {
  const WelcomeAfterSignupWidget({super.key, this.role, this.name});

  final String? role;
  final String? name;

  static String routeName = 'WelcomeAfterSignup';
  static String routePath = '/welcomeAfterSignup';

  @override
  State<WelcomeAfterSignupWidget> createState() => _WelcomeAfterSignupWidgetState();
}

class _WelcomeAfterSignupWidgetState extends State<WelcomeAfterSignupWidget> {
  // Color scheme that works in both light and dark mode
  final Color _primaryColor = const Color(0xFFA20025);
  final Color _successColor = const Color(0xFF10B981);
  final Color _purpleColor = const Color(0xFF6366F1);

  // State variables
  Timer? _autoNavTimer;
  bool _navigated = false;
  String _role = 'customer';
  String? _name;
  double _progressValue = 0.0;

  @override
  void initState() {
    super.initState();

    // Initialize role and name
    if (widget.role != null && widget.role!.isNotEmpty) {
      _role = widget.role!.toLowerCase();
    } else {
      _role = 'customer';
    }
    _name = widget.name;

    // Extract data from route arguments
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map) {
        if (args['name'] != null && args['name'].toString().isNotEmpty) {
          setState(() => _name = args['name']?.toString());
        }
        if (args['role'] != null && args['role'].toString().isNotEmpty) {
          final r = args['role']?.toString();
          if (r != null && r.isNotEmpty) setState(() => _role = r.toLowerCase());
        }
      }
    });

    // Start progress animation
    _startProgressAnimation();

    // Auto-navigation after delay
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoNavTimer = Timer(const Duration(seconds: 5), () {
        if (!mounted || _navigated) return;
        _navigateToDashboard();
      });
    });
  }

  void _startProgressAnimation() {
    Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (_progressValue >= 1.0) {
        timer.cancel();
        return;
      }
      if (mounted) {
        setState(() {
          _progressValue += 0.01; // 5 seconds to complete
        });
      }
    });
  }

  @override
  void dispose() {
    _autoNavTimer?.cancel();
    super.dispose();
  }

  void _navigateToDashboard() {
    if (_navigated) return;
    _navigated = true;
    _autoNavTimer?.cancel();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        // Debug trace
        try { debugPrint('WelcomeAfterSignup: navigating to dashboard for role=$_role'); } catch (_) {}

        // Use replace-all so the onboarding/auth pages are removed from the
        // stack and the app lands at the proper home/dashboard route. The
        // NavigationUtils.safeReplaceAllWith helper maps NavBarPage to the
        // appropriate GoRouter path when the app uses the declarative router.
        final target = _role == 'artisan'
            ? NavBarPage(initialPage: 'homePage', showDiscover: false)
            : NavBarPage(initialPage: 'homePage');

        await NavigationUtils.safeReplaceAllWith(context, target);
      } catch (e) {
        // Fallback: try a simple replace so the user isn't blocked.
        try {
          NavigationUtils.safePushReplacement(
            context,
            _role == 'artisan' ? ArtisanDashboardPageWidget() : HomePageWidget(),
          );
        } catch (_) {}
      }
    });
  }

  Color _getTextPrimary(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : const Color(0xFF111827);
  }

  Color _getTextSecondary(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF9CA3AF)
        : const Color(0xFF6B7280);
  }

  Color _getBorderColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF374151)
        : const Color(0xFFE5E7EB);
  }

  Color _getSurfaceColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF1F2937)
        : const Color(0xFFF9FAFB);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallScreen = screenHeight < 700;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _navigateToDashboard,
      child: Scaffold(
        backgroundColor: isDark ? Colors.black : Colors.white,
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 24,
              vertical: isSmallScreen ? 16 : 32,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top section - Welcome content
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Welcome icon
                      Container(
                        width: isSmallScreen ? 80 : 100,
                        height: isSmallScreen ? 80 : 100,
                        decoration: BoxDecoration(
                          color: isDark
                              ? _primaryColor.withOpacity(0.2)
                              : _primaryColor.withOpacity(0.1),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark
                                ? _primaryColor.withOpacity(0.4)
                                : _primaryColor.withOpacity(0.3),
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          Icons.check_circle_rounded,
                          size: isSmallScreen ? 40 : 48,
                          color: _primaryColor,
                        ),
                      ),

                      SizedBox(height: isSmallScreen ? 24 : 32),

                      // Welcome message
                      Text(
                        _name != null && _name!.isNotEmpty
                            ? 'Welcome, ${_name!}!'
                            : 'Welcome!',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 24 : 28,
                          fontWeight: FontWeight.w700,
                          color: _getTextPrimary(context),
                          letterSpacing: -0.5,
                          height: 1.3,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      SizedBox(height: isSmallScreen ? 8 : 12),

                      // Subtitle
                      Text(
                        'Your account has been created successfully',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 14 : 16,
                          fontWeight: FontWeight.w400,
                          color: _getTextSecondary(context),
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      SizedBox(height: isSmallScreen ? 24 : 32),

                      // Role badge
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: isSmallScreen ? 16 : 20,
                          vertical: isSmallScreen ? 8 : 10,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? _primaryColor.withOpacity(0.15)
                              : _primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(isSmallScreen ? 20 : 24),
                          border: Border.all(
                            color: isDark
                                ? _primaryColor.withOpacity(0.3)
                                : _primaryColor.withOpacity(0.25),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _role == 'artisan'
                                  ? Icons.person_outline
                                  : Icons.business_center_outlined,
                              size: isSmallScreen ? 16 : 18,
                              color: _role == 'artisan' ? _successColor : _primaryColor,
                            ),
                            SizedBox(width: isSmallScreen ? 6 : 8),
                            Text(
                              _role == 'artisan' ? 'Artisan Account' : 'Client Account',
                              style: TextStyle(
                                fontSize: isSmallScreen ? 13 : 15,
                                fontWeight: FontWeight.w600,
                                color: _role == 'artisan' ? _successColor : _primaryColor,
                              ),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: isSmallScreen ? 32 : 40),

                      // Compact features list (horizontal)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildCompactFeatureItem(
                              icon: Icons.verified_rounded,
                              label: 'Verified',
                              color: _successColor,
                              isSmallScreen: isSmallScreen,
                            ),
                            SizedBox(width: isSmallScreen ? 12 : 16),
                            _buildCompactFeatureItem(
                              icon: _role == 'artisan'
                                  ? Icons.work_outline
                                  : Icons.search_rounded,
                              label: _role == 'artisan' ? 'Jobs' : 'Search',
                              color: _primaryColor,
                              isSmallScreen: isSmallScreen,
                            ),
                            SizedBox(width: isSmallScreen ? 12 : 16),
                            _buildCompactFeatureItem(
                              icon: Icons.security_rounded,
                              label: 'Secure',
                              color: _purpleColor,
                              isSmallScreen: isSmallScreen,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Bottom section - Timer indicator
                Padding(
                  padding: EdgeInsets.only(bottom: isSmallScreen ? 16 : 32),
                  child: Column(
                    children: [
                      // Progress indicator
                      Column(
                        children: [
                          LinearProgressIndicator(
                            value: _progressValue,
                            minHeight: 4,
                            backgroundColor: _getBorderColor(context),
                            valueColor: AlwaysStoppedAnimation<Color>(_primaryColor),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          SizedBox(height: isSmallScreen ? 8 : 12),
                          Text(
                            'Redirecting in ${(5 * (1 - _progressValue)).ceil()} seconds',
                            style: TextStyle(
                              fontSize: isSmallScreen ? 13 : 14,
                              fontWeight: FontWeight.w500,
                              color: _getTextSecondary(context),
                            ),
                          ),
                          SizedBox(height: isSmallScreen ? 8 : 12),
                          Text(
                            'Tap anywhere to skip',
                            style: TextStyle(
                              fontSize: isSmallScreen ? 12 : 13,
                              color: _getTextSecondary(context),
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildCompactFeatureItem({
    required IconData icon,
    required String label,
    required Color color,
    required bool isSmallScreen,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
      decoration: BoxDecoration(
        color: isDark ? color.withOpacity(0.15) : color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(isSmallScreen ? 16 : 20),
        border: Border.all(
          color: isDark ? color.withOpacity(0.3) : color.withOpacity(0.25),
          width: 1.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: isSmallScreen ? 36 : 44,
            height: isSmallScreen ? 36 : 44,
            decoration: BoxDecoration(
              color: isDark ? color.withOpacity(0.25) : color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(isSmallScreen ? 10 : 12),
            ),
            child: Icon(
              icon,
              size: isSmallScreen ? 18 : 22,
              color: color,
            ),
          ),
          SizedBox(height: isSmallScreen ? 6 : 8),
          Text(
            label,
            style: TextStyle(
              fontSize: isSmallScreen ? 12 : 13,
              fontWeight: FontWeight.w600,
              color: _getTextPrimary(context),
            ),
          ),
        ],
      ),
    );
  }
}