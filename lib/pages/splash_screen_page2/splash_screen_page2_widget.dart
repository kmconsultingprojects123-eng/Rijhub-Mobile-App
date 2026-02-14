import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '/index.dart';
import 'dart:async';
import 'splash_screen_page2_model.dart';
import '/services/auth_service.dart';
import '../../services/token_storage.dart';
import '../../utils/navigation_utils.dart';
import '../../utils/awesome_dialogs.dart';
import '../../state/auth_notifier.dart';
export 'splash_screen_page2_model.dart';

class SplashScreenPage2Widget extends StatefulWidget {
  const SplashScreenPage2Widget({super.key, this.skipAutoRedirect = false});

  final bool skipAutoRedirect;

  static String routeName = 'SplashScreenPage2';
  static String routePath = '/splashScreenPage2';

  @override
  State<SplashScreenPage2Widget> createState() =>
      _SplashScreenPage2WidgetState();
}

class _SplashScreenPage2WidgetState extends State<SplashScreenPage2Widget>
    with TickerProviderStateMixin {
  late SplashScreenPage2Model _model;
  final scaffoldKey = GlobalKey<ScaffoldState>();
  final PageController _pageController = PageController();
  // Absolute page index used for PageController animations when the PageView
  // is treated as infinite. _currentPage remains the indicator index (0..n-1).
  int _pageIndex = 0;
  Timer? _carouselTimer;

  // Background slideshow fields
  final List<String> _bgImages = [
    // use the WebP variants declared in pubspec.yaml to avoid missing
    // variant/extension issues and ensure the asset list matches the
    // bundled files.
    'assets/images/fade-1.webp',
    'assets/images/fade-2.webp',
    'assets/images/fade-3.webp',
    'assets/images/fade-4.webp',
    'assets/images/fade-5.webp',
  ];
  int _bgIndex = 0;
  int _prevBgIndex = 0;
  AnimationController? _bgFadeController;
  Animation<double>? _bgFade;
  Timer? _bgTimer;

  // Carousel messages with different value propositions
  final List<Map<String, dynamic>> _carouselMessages = [
    {
      'title': 'Find Trusted Artisans',
      'subtitle': 'Connect with verified professionals for any job',
      'icon': Icons.verified_user_rounded,
    },
    {
      'title': 'Secure Work Opportunities',
      'subtitle': 'Get paid safely and on time for your skills',
      'icon': Icons.payment_rounded,
    },
    {
      'title': 'Manage Your Schedule',
      'subtitle': 'Flexible work hours that fit your lifestyle',
      'icon': Icons.schedule_rounded,
    },
    {
      'title': 'Grow Your Business',
      'subtitle': 'Build your reputation and expand your client base',
      'icon': Icons.trending_up_rounded,
    },
  ];

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => SplashScreenPage2Model());

    // Start carousel auto-play
    _startCarouselTimer();

    // Background fade controller
    _bgFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _bgFade =
        CurvedAnimation(parent: _bgFadeController!, curve: Curves.easeInOut);
    // show first image fully
    _bgFadeController?.value = 1.0;

    // start background slideshow timer
    _bgTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) return;
      setState(() {
        _prevBgIndex = _bgIndex;
        _bgIndex = (_bgIndex + 1) % _bgImages.length;
      });
      // animate the fade for the new image
      try {
        _bgFadeController?.forward(from: 0.0);
      } catch (_) {}
    });

    // keep UI updating while the animation runs
    _bgFadeController?.addListener(() {
      if (mounted) setState(() {});
    });
  }

  void _startCarouselTimer() {
    _carouselTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (_pageController.hasClients) {
        // advance absolute page index and animate to it — the PageView.builder
        // is infinite (no itemCount) so indices can keep growing.
        _pageIndex = _pageIndex + 1;
        try {
          _pageController.animateToPage(
            _pageIndex,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        } catch (_) {}
      }
    });
  }

  @override
  void dispose() {
    _carouselTimer?.cancel();
    _pageController.dispose();
    _bgTimer?.cancel();
    _bgFadeController?.dispose();
    _model.dispose();
    super.dispose();
  }

  Widget _buildCarouselContent(BuildContext context) {
    return SizedBox(
      height: 140,
      child: PageView.builder(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            // Keep an absolute page index for animation.
            _pageIndex = index;
          });
        },
        // No itemCount -> builder can produce an effectively infinite page list.
        itemBuilder: (context, index) {
          final message = _carouselMessages[index % _carouselMessages.length];
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  message['icon'] as IconData,
                  size: 32,
                  color: Colors.white,
                ),
                const SizedBox(height: 16),
                Text(
                  message['title'] as String,
                  textAlign: TextAlign.center,
                  style: FlutterFlowTheme.of(context).displayMedium.override(
                        font: GoogleFonts.interTight(
                          fontWeight: FontWeight.w700,
                        ),
                        color: Colors.white,
                        fontSize: 24.0,
                        letterSpacing: 0.0,
                        fontWeight: FontWeight.bold,
                        lineHeight: 1.2,
                      ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    message['subtitle'] as String,
                    textAlign: TextAlign.center,
                    style: FlutterFlowTheme.of(context).bodyLarge.override(
                          font: GoogleFonts.inter(
                            fontWeight: FontWeight.w400,
                          ),
                          color: Colors.white.withAlpha((0.9 * 255).round()),
                          letterSpacing: 0.0,
                          lineHeight: 1.4,
                        ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRoleButton({
    required BuildContext context,
    required String label,
    required String role,
    required IconData icon,
    bool isPrimary = false,
  }) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 320),
      child: ElevatedButton(
        onPressed: () async {
          // Deterministic navigation: always construct the CreateAccount2Widget
          // with the selected role so the page receives it via the
          // `initialRole` constructor parameter. This avoids mismatches where
          // router extras are not forwarded to the page builder.
          // (We intentionally avoid context.pushNamed here to prevent the
          // framework-specific extra handling differences.)
          // ignore: avoid_print
          if (kDebugMode)
            debugPrint('Navigating to CreateAccount2 with role: $role');
          // Use safe navigation utility to schedule navigation after the current
          // frame and avoid Navigator lock assertions. Pass the constructed
          // CreateAccount2Widget so it receives the role via constructor.
          // Use the no-auth version to avoid prompting the user with the guest
          // authentication bottom sheet while they are still onboarding.
          NavigationUtils.safePushNoAuth(
              context, CreateAccount2Widget(initialRole: role));
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary
              ? FlutterFlowTheme.of(context).primary
              : Colors.transparent,
          foregroundColor: isPrimary ? Colors.white : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isPrimary
                  ? FlutterFlowTheme.of(context).primary
                  : Colors.white.withAlpha((0.3 * 255).round()),
              width: isPrimary ? 0 : 1.5,
            ),
          ),
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
        body: SafeArea(
          top: false,
          bottom: false,
          child: SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: Stack(
              children: [
                // Background Image
                // Subtle fading slideshow background: we draw the previous image
                // and the current image on top, and animate the top image's
                // opacity for a gentle cross-fade.
                AnimatedBuilder(
                  animation: (_bgFade ?? const AlwaysStoppedAnimation(1.0)),
                  builder: (context, child) {
                    final fadeVal = (_bgFade?.value ?? 1.0).clamp(0.0, 1.0);
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.asset(
                          _bgImages[_prevBgIndex % _bgImages.length],
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                        ),
                        Opacity(
                          opacity: fadeVal,
                          child: Image.asset(
                            _bgImages[_bgIndex % _bgImages.length],
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ],
                    );
                  },
                ),

                // Dark Overlay
                Container(
                  width: double.infinity,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.transparent, const Color(0xCC000000)],
                      stops: const [0.0, 0.6],
                      begin: AlignmentDirectional(0.0, -1.0),
                      end: AlignmentDirectional(0, 1.0),
                    ),
                  ),
                ),

                // Content
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20.0,
                    vertical: 40.0,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Carousel Content
                      Expanded(
                        child: Column(
                          // place carousel near the bottom of this area
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            _buildCarouselContent(context),
                            // add spacing so there's a comfortable gap between the
                            // carousel and the action buttons below (indicator removed).
                            const SizedBox(height: 32),
                          ],
                        ),
                      ),

                      // Buttons Section
                      Column(
                        children: [
                          // Client Button
                          _buildRoleButton(
                            context: context,
                            label: 'I\'m a Client',
                            role: 'customer',
                            icon: Icons.person_outline_rounded,
                            isPrimary: false,
                          ),
                          const SizedBox(height: 12),

                          // Artisan Button
                          _buildRoleButton(
                            context: context,
                            label: 'I\'m an Artisan',
                            role: 'artisan',
                            icon: Icons.handyman_outlined,
                            isPrimary: true,
                          ),
                          const SizedBox(height: 16),

                          // Continue as Guest button (restored)
                          Container(
                            width: double.infinity,
                            constraints: const BoxConstraints(maxWidth: 320),
                            child: ElevatedButton(
                              onPressed: () async {
                                // Guest flow: call server, persist token + role, set profile, mark guest, and go to /homePage
                                showAppLoadingDialog(context);
                                try {
                                  final res = await AuthService.guest();
                                  if (!mounted) return;

                                  // Dismiss loading dialog
                                  try {
                                    Navigator.of(context, rootNavigator: true)
                                        .pop();
                                  } catch (_) {
                                    try {
                                      NavigationUtils.safeMaybePop(context);
                                    } catch (_) {}
                                  }

                                  if (res['success'] == true) {
                                    final body = res['data'] ?? res;

                                    // Extract token (support common response shapes)
                                    String? token;
                                    Map<String, dynamic>? userProfile;
                                    if (body is Map) {
                                      token = (body['token'] ??
                                              body['accessToken'] ??
                                              body['data']?['token'] ??
                                              body['data']?['accessToken'] ??
                                              body['user']?['token'])
                                          ?.toString();
                                      // Try to find a user object in common locations
                                      if (body['user'] is Map)
                                        userProfile = Map<String, dynamic>.from(
                                            body['user']);
                                      else if (body['data'] is Map &&
                                          body['data']['user'] is Map)
                                        userProfile = Map<String, dynamic>.from(
                                            body['data']['user']);
                                      else if (body['data'] is Map &&
                                          (body['data']['profile'] is Map))
                                        userProfile = Map<String, dynamic>.from(
                                            body['data']['profile']);
                                      else {
                                        // If body itself contains common profile fields (id/name/email), use it as profile
                                        final hasId = body.containsKey('_id') ||
                                            body.containsKey('id') ||
                                            body.containsKey('userId');
                                        if (hasId)
                                          userProfile =
                                              Map<String, dynamic>.from(body);
                                      }
                                    }

                                    if (token != null && token.isNotEmpty) {
                                      // Persist token and role explicitly
                                      try {
                                        await TokenStorage.saveToken(token);
                                      } catch (_) {}
                                      try {
                                        await TokenStorage.saveRole('guest');
                                      } catch (_) {}

                                      // Update in-memory auth state: AuthNotifier and AppStateNotifier
                                      try {
                                        await AuthNotifier.instance
                                            .setGuest(token: token);
                                      } catch (_) {}

                                      // Normalize and ensure profile includes guest markers
                                      if (userProfile == null)
                                        userProfile = <String, dynamic>{};
                                      userProfile['role'] = 'guest';
                                      userProfile['isGuest'] = true;

                                      // Update both notifiers so other parts of the app reflect guest state
                                      try {
                                        await AuthNotifier.instance
                                            .setProfile(userProfile);
                                      } catch (_) {}
                                      try {
                                        AppStateNotifier.instance.token = token;
                                      } catch (_) {}
                                      try {
                                        AppStateNotifier.instance
                                            .setProfile(userProfile);
                                      } catch (_) {}

                                      // Navigate to /homePage using go_router as requested.
                                      // Do NOT use pushReplacement, do NOT rebuild router.
                                      try {
                                        context.go('/homePage');
                                      } catch (_) {
                                        // If go() throws, log and don't attempt additional navigation
                                      }

                                      // Show a snackbar prompting sign-in with action linking to login page
                                      try {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: const Text(
                                                'You are now browsing as a guest.'),
                                            action: SnackBarAction(
                                              label: 'Sign in',
                                              onPressed: () {
                                                // Must link directly to the login page using GoRouter
                                                context.go(LoginAccountWidget
                                                    .routePath);
                                              },
                                            ),
                                            duration:
                                                const Duration(seconds: 6),
                                          ),
                                        );
                                      } catch (_) {}
                                    } else {
                                      final msg =
                                          'Guest login failed: server did not return a token.';
                                      if (!mounted) return;
                                      await showAppErrorDialog(context,
                                          title: 'Error', desc: msg);
                                    }
                                  } else {
                                    final err = res['error'];
                                    final message =
                                        (err is Map && err['message'] != null)
                                            ? err['message'].toString()
                                            : (err?.toString() ??
                                                'Failed to enter as guest');
                                    if (!mounted) return;
                                    await showAppErrorDialog(context,
                                        title: 'Error', desc: message);
                                  }
                                } catch (e) {
                                  if (!mounted) return;
                                  try {
                                    Navigator.of(context, rootNavigator: true)
                                        .pop();
                                  } catch (_) {
                                    try {
                                      NavigationUtils.safeMaybePop(context);
                                    } catch (_) {}
                                  }
                                  await showAppErrorDialog(context,
                                      title: 'Error', desc: e.toString());
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 24, vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: Colors.white
                                        .withAlpha((0.3 * 255).round()),
                                    width: 1.5,
                                  ),
                                ),
                                elevation: 0,
                                shadowColor: Colors.transparent,
                              ),
                              child: const Text(
                                'Continue as Guest',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Small login link for users who already have an account
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "I already have an account",
                                style: TextStyle(
                                    color: Colors.white
                                        .withAlpha((0.85 * 255).round())),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: () {
                                  try {
                                    NavigationUtils.safePushNoAuth(
                                        context, const LoginAccountWidget());
                                  } catch (_) {
                                    try {
                                      Navigator.of(context).push(
                                          MaterialPageRoute(
                                              builder: (_) =>
                                                  const LoginAccountWidget()));
                                    } catch (_) {}
                                  }
                                },
                                child: const Text(
                                  'Login',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(0, 0),
                                ),
                              ),
                            ],
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
}
