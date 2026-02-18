import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import '/services/notification_controller.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import 'flutter_flow/flutter_flow_util.dart';
import 'package:floating_bottom_navigation_bar/floating_bottom_navigation_bar.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'index.dart';
import '/utils/auth_guard.dart';
import 'utils/location_permission.dart';
import 'utils/navigation_utils.dart';
import 'services/health_service.dart';
import 'widgets/health_snackbar.dart';
import 'state/auth_notifier.dart';

import 'dart:io';
import 'package:flutter/services.dart' show PlatformAssetBundle;
import 'dart:convert';

void main() async {
  // Ensure Flutter binding is initialized before calling any platform
  // channels (including SharedPreferences) or running async startup logic.
  WidgetsFlutterBinding.ensureInitialized();

  print('');
  print('═══════════════════════════════════════════════════════════');
  print('🚀 APP STARTING');
  print('═══════════════════════════════════════════════════════════');
  print('');

  // Initialize Firebase
  print('🔥 Initializing Firebase...');
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  print('🔥 Firebase initialized');

  // Register background message handler (required for background/terminated data messages).
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Initialize Awesome Notifications (no permission request here — deferred until after login per Apple Guideline 4.5.4)
  await NotificationController.initializeNotifications();
  await NotificationController.startListeningNotificationEvents();

  print('');
  print('═══════════════════════════════════════════════════════════');
  print('✅ NOTIFICATION SETUP COMPLETE - PERMISSION DEFERRED TO LOGIN');
  print('═══════════════════════════════════════════════════════════');
  print('');

  // Disable debugPrint globally to prevent logging sensitive data to terminal
  // try {
  //   debugPrint = (String? messagege, {int? wrapWidth}) {};
  // } catch (_) {}

  // Global error handlers to capture runtime assertion stack traces (helps diagnose '!semantics.parentDataDirty' issues)
  FlutterError.onError = (FlutterErrorDetails details) {
    // Always dump error details; avoid printing extra debug info to terminal
    FlutterError.dumpErrorToConsole(details);
    // Removed debugPrint calls for security: do not log exception or stacktrace to terminal
  };

  ui.PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    // Removed debugPrint calls for security: do not log platform errors to terminal
    return false; // prevent the engine from exiting
  };

  // ✅ FIX: Remove edgeToEdge to prevent Android from showing app name ("RijHub")
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: [
      SystemUiOverlay.top,
      SystemUiOverlay.bottom,
    ],
  );

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  // Eagerly initialize SharedPreferences on the UI thread so plugins using
  // method channels (e.g. shared_preferences) don't race with engine setup on iOS.
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  // Use the pre-created prefs instance when initializing the theme so that
  // FlutterFlowTheme.themeMode and other consumers read a ready-backed value.
  GoRouter.optionURLReflectsImperativeAPIs = true;
  usePathUrlStrategy();

  await FlutterFlowTheme.initialize(prefs: prefs);

  try {
    await AppStateNotifier.instance.refreshAuth();
  } catch (_) {}

  // Initialize realtime notifications (socket + local notifications)
  try {
    // Realtime notifications temporarily disabled to avoid navigation build-time races
    // await RealtimeNotifications.instance.init();
  } catch (_) {}

  // Ensure location permission on startup where possible. We don't have a BuildContext here,
  // so the consent dialog will be triggered on first resume / when UI builds (see MyApp lifecycle).

  // Trust Let's Encrypt roots
  final bundle = PlatformAssetBundle();

  try {
    // Removed debugPrint: do not log certificate loading to terminal

    // Load ISRG Root X1 certificate
    final rootData = await bundle.load('assets/ca/isrgrootx1.pem');
    SecurityContext.defaultContext
        .setTrustedCertificatesBytes(rootData.buffer.asUint8List());
    // Removed debugPrint: do not log certificate load success

    // Load Let's Encrypt R3 Intermediate certificate
    final r3Data = await bundle.load('assets/ca/lets-encrypt-r3.pem');
    SecurityContext.defaultContext
        .setTrustedCertificatesBytes(r3Data.buffer.asUint8List());
    // Removed debugPrint: do not log certificate load success

    // Removed debugPrint: do not log certificate list or context to terminal
  } catch (e, stackTrace) {
    // Removed debugPrint: do not print errors or stack traces to terminal
  }

  // Use a zone to intercept print() calls and silence them for security
  runZonedGuarded(() {
    runApp(MyApp());
  }, (error, stack) {
    // Forward to Flutter error handlers without printing stacktrace to terminal
    try {
      FlutterError.reportError(
          FlutterErrorDetails(exception: error, stack: stack));
    } catch (_) {}
  }, zoneSpecification: ZoneSpecification(
    print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
      // Intentionally ignore prints to avoid leaking data to terminal
    },
  ));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();

  static _MyAppState of(BuildContext context) =>
      context.findAncestorStateOfType<_MyAppState>()!;
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  // Observe app lifecycle to re-check location permissions on resume
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // When app resumes, try to ensure location permissions using current context
      try {
        LocationPermissionService.ensureLocationPermissions(context);
      } catch (_) {}
      // Also refresh auth state non-blocking so token expiry is revalidated on resume
      try {
        AppStateNotifier.instance.refreshAuth();
      } catch (_) {}
    }
  }

  ThemeMode _themeMode = FlutterFlowTheme.themeMode;

  late AppStateNotifier _appStateNotifier;
  late GoRouter _router;

  String getRoute([RouteMatchBase? routeMatch]) {
    final RouteMatchBase lastMatch =
        routeMatch ?? _router.routerDelegate.currentConfiguration.last;
    final RouteMatchList matchList = lastMatch is ImperativeRouteMatch
        ? lastMatch.matches
        : _router.routerDelegate.currentConfiguration;
    return matchList.uri.toString();
  }

  List<String> getRouteStack() =>
      _router.routerDelegate.currentConfiguration.matches
          .map((e) => getRoute(e))
          .toList();

  bool displaySplashImage = true;

  @override
  void initState() {
    super.initState();

    // Register this state as a lifecycle observer so we can check permissions on resume
    WidgetsBinding.instance.addObserver(this);

    // After first frame, prompt for location permissions if needed (we need a BuildContext)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Run a lightweight health-check after first frame and show a user-friendly
      // snackbar if there's a problem. We intentionally don't block app init.
      try {
        final hs = HealthService();
        final token = AppStateNotifier.instance.token;
        final res = await hs.check(token: token);
        if (!res.healthy && mounted) {
          showHealthSnackBar(context, res.message, isError: true);
        }
      } catch (_) {}
      try {
        await LocationPermissionService.ensureLocationPermissions(context);
      } catch (_) {}
    });

    _appStateNotifier = AppStateNotifier.instance;

    // Instantiate AuthNotifier and refresh auth state before creating router
    final auth = AuthNotifier.instance;
    // Refresh asynchronously; we don't await here because initState can't be async
    auth.refreshAuth().catchError((_) {});

    _router = createRouter(auth);

    Future.delayed(const Duration(milliseconds: 1800), () {
      _appStateNotifier.stopShowingSplashImage();
      try {
        _router.go(Splash2Widget.routePath);
      } catch (e) {
        // navigation failed - ignore in release logs
      }
    });
  }

  void setThemeMode(ThemeMode mode) => safeSetState(() {
        _themeMode = mode;
        FlutterFlowTheme.saveThemeMode(mode);
      });

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: '',
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en', '')],
      theme: ThemeData(
        brightness: Brightness.light,
        useMaterial3: false,
        // Ensure the app-wide ColorScheme uses the brand primary color
        colorScheme: ColorScheme.light(
          primary: const Color(0xFFA20025),
          onPrimary: Colors.white,
        ),
        // Use pure white scaffold background for light mode per design request
        scaffoldBackgroundColor: Colors.white,
        // Keep canvas consistent for widgets that inherit colors from the Material theme
        canvasColor: Colors.white,
        // Default card color (used by Cards, Containers that use Theme.cardColor)
        cardColor: const Color(0xFFFFFFFF),
        // Unified AppBar theme across the app: no elevation, consistent typography and colors
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: const TextStyle(
              fontFamily: 'Inter Tight',
              fontSize: 18.0,
              fontWeight: FontWeight.w600,
              color: Colors.black),
          iconTheme: const IconThemeData(color: Colors.black),
          actionsIconTheme: const IconThemeData(color: Colors.black),
        ),
        // Input highlight and cursor theme — use app primary color and stronger highlight
        inputDecorationTheme: InputDecorationTheme(
          focusedBorder: OutlineInputBorder(
              borderSide:
                  BorderSide(color: const Color(0xFFA20025), width: 2.0),
              borderRadius: BorderRadius.circular(12)),
        ),
        textSelectionTheme: TextSelectionThemeData(
            cursorColor: const Color(0xFFA20025),
            selectionColor: const Color(0x33A20025),
            selectionHandleColor: const Color(0xFFA20025)),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: false,
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFFA20025),
          onPrimary: Colors.white,
        ),
        // Match dark mode scaffold background to the theme's dark primaryBackground (keeps consistency).
        scaffoldBackgroundColor: const Color(0xFF1D2428),
        canvasColor: const Color(0xFF1D2428),
        cardColor: const Color(0xFF14181B),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF000000),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
              fontFamily: 'Inter Tight',
              fontSize: 18.0,
              fontWeight: FontWeight.w600,
              color: Colors.white),
          iconTheme: IconThemeData(color: Colors.white),
          actionsIconTheme: IconThemeData(color: Colors.white),
        ),
        inputDecorationTheme: InputDecorationTheme(
          focusedBorder: OutlineInputBorder(
              borderSide:
                  BorderSide(color: const Color(0xFFA20025), width: 2.0),
              borderRadius: BorderRadius.circular(12)),
        ),
        textSelectionTheme: TextSelectionThemeData(
            cursorColor: const Color(0xFFA20025),
            selectionColor: const Color(0x33A20025),
            selectionHandleColor: const Color(0xFFA20025)),
      ),
      themeMode: _themeMode,
      routerConfig: _router,
    );
  }
}

class NavBarPage extends StatefulWidget {
  // Route identifiers used across the app
  static String routeName = 'navBar';
  static String routePath = '/';
  const NavBarPage({
    super.key,
    this.initialPage,
    this.page,
    this.disableResizeToAvoidBottomInset = false,
    this.showDiscover = true,
  });

  final String? initialPage;
  final Widget? page;
  final bool disableResizeToAvoidBottomInset;
  // When false the Discover tab is hidden (used for artisan flows)
  final bool showDiscover;

  @override
  _NavBarPageState createState() => _NavBarPageState();
}

class _NavBarPageState extends State<NavBarPage> {
  String _currentPageName = 'homePage';
  late Widget? _currentPage;
  String? _lastKnownRole;

  // Helper to show the guest sign-in prompt; returns true if the user chose Sign in, false for Continue as guest or null if dismissed.
  Future<bool?> _showGuestPrompt() async {
    if (!mounted) return false;
    final res = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (c) {
        final theme = FlutterFlowTheme.of(context);
        final maxWidth =
            MediaQuery.of(context).size.width < 640 ? double.infinity : 640.0;
        return Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Container(
                margin: const EdgeInsets.symmetric(
                    horizontal: 16.0, vertical: 12.0),
                padding: const EdgeInsets.all(20.0),
                decoration: BoxDecoration(
                  color: Colors
                      .white, // user requested white background for the sheet
                  borderRadius: BorderRadius.circular(16.0),
                  boxShadow: [],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Illustration / icon (themed tint)
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                          color:
                              Color.lerp(theme.primary, Colors.white, 0.88) ??
                                  theme.primary,
                          shape: BoxShape.circle),
                      child: Center(
                          child: Icon(Icons.login_rounded,
                              size: 36, color: theme.primary)),
                    ),
                    const SizedBox(height: 12.0),
                    Text('Continue with RijHub',
                        style:
                            theme.titleMedium.copyWith(color: theme.primary)),
                    const SizedBox(height: 8.0),
                    Text(
                        'Sign in to unlock all features or continue as a guest with limited access.',
                        textAlign: TextAlign.center,
                        style: theme.bodyMedium
                            .copyWith(color: theme.secondaryText)),
                    const SizedBox(height: 18.0),
                    // Continue as guest (top) — show as a simple text link in primary color
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14.0),
                          foregroundColor: theme.primary,
                          alignment: Alignment.center,
                        ),
                        onPressed: () => Navigator.of(c).pop(false),
                        child: Text('Continue as guest',
                            style:
                                theme.bodyLarge.copyWith(color: theme.primary)),
                      ),
                    ),
                    const SizedBox(height: 12.0),
                    // Sign in (primary as well) — remove elevation/shadow so it's flat
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.primary,
                          elevation: 0,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 14.0),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8.0)),
                        ),
                        onPressed: () => Navigator.of(c).pop(true),
                        child: Text('Sign in',
                            style: theme.bodyLarge
                                .copyWith(color: theme.onPrimary)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    return res;
  }

  @override
  void initState() {
    super.initState();
    _currentPageName = widget.initialPage ?? _currentPageName;
    _currentPage = widget.page;
    // Listen for app state changes (login/logout/role changes) so we can
    // rebuild the nav bar and tabs accordingly and prevent role leakage.
    try {
      _lastKnownRole = AppStateNotifier.instance.profile?['role']?.toString();
      AppStateNotifier.instance.addListener(_onAppStateChanged);
    } catch (_) {}
  }

  void _onAppStateChanged() {
    // Only rebuild when the user's role or auth state changes to avoid
    // unnecessary rebuilds.
    final currentRole = AppStateNotifier.instance.profile?['role']?.toString();
    if (currentRole != _lastKnownRole) {
      _lastKnownRole = currentRole;
      // Reset current page to ensure tabs are recomputed for new role.
      setState(() {
        _currentPage = null;
        // If the current page name is no longer available for the new role,
        // default to homePage.
        _currentPageName = widget.initialPage ?? 'homePage';
      });
    }
  }

  @override
  void dispose() {
    // Clean up the listener on dispose to prevent memory leaks.
    try {
      AppStateNotifier.instance.removeListener(_onAppStateChanged);
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Choose nav items and order depending on role.
    // Client & Guest: Home, Job, Discover, Booking, Profile
    // Artisan: Home, Job, Booking, Profile (Discover hidden)
    final bool isArtisan = (AppStateNotifier.instance.profile?['role']
            ?.toString()
            .toLowerCase()
            .contains('artisan') ??
        false);
    // Discover is shown only when both the widget allows it and the user is not an artisan.
    final bool shouldShowDiscover = widget.showDiscover && !isArtisan;

    // Build ordered tabs map according to role
    final tabs = <String, Widget>{};
    // Home
    tabs['homePage'] =
        isArtisan ? ArtisanDashboardPageWidget() : HomePageWidget();
    // Job
    tabs['JobPostPage'] = JobPostPageWidget();
    // Discover (only for client/guest when allowed)
    if (shouldShowDiscover) tabs['DiscoverPage'] = DiscoverPageWidget();
    // Booking
    tabs['BookingPage'] = BookingPageWidget();
    // Profile (artisan uses artisan profile)
    tabs['profile'] = isArtisan ? ArtisanProfilepageWidget() : ProfileWidget();

    var currentIndex = tabs.keys.toList().indexOf(_currentPageName);
    // If the current page name isn't found, default to the first tab.
    if (currentIndex < 0) {
      currentIndex = 0;
      _currentPageName = tabs.keys.first;
    }
    final MediaQueryData queryData = MediaQuery.of(context);

    // Icon mapping for the bottom nav. Keep keys in sync with `tabs` above.
    final iconMap = <String, IconData>{
      'homePage': FontAwesomeIcons.house,
      'JobPostPage': FontAwesomeIcons.briefcase,
      'BookingPage': Icons.book,
      'profile': FontAwesomeIcons.solidCircleUser,
    };
    if (shouldShowDiscover) iconMap['DiscoverPage'] = Icons.pin_drop_rounded;

    // Determine whether current cached profile represents a guest so we can dim restricted tabs visually
    final bool isGuestNow = (() {
      final p = AppStateNotifier.instance.profile;
      if (p == null) return true;
      if (p['isGuest'] == true) return true;
      final role = p['role'];
      final email = p['email'];
      if ((role == null || role.toString().isEmpty) &&
          (email == null || email.toString().isEmpty)) return true;
      return false;
    })();

    final restrictedForGuests = <String>{
      'JobPostPage',
      'BookingPage',
      'profile'
    };

    // Build FloatingNavbar items from the tabs keys so they always stay in sync.
    final navItems = tabs.keys.toList().asMap().entries.map((entry) {
      final idx = entry.key;
      final key = entry.value;
      final iconData = iconMap[key];
      final label = switch (key) {
        'homePage' => 'Home',
        'DiscoverPage' => 'Discover',
        'JobPostPage' => 'Job',
        'BookingPage' => 'Booking',
        'profile' => 'Profile',
        _ => key,
      };

      // Determine if this tab should appear disabled for guests
      final disabledForGuest = isGuestNow && restrictedForGuests.contains(key);
      final fadedSecondary = disabledForGuest
          ? Color.lerp(FlutterFlowTheme.of(context).secondaryText,
                  Colors.transparent, 0.55) ??
              FlutterFlowTheme.of(context).secondaryText
          : FlutterFlowTheme.of(context).secondaryText;
      final iconColor = currentIndex == idx
          ? FlutterFlowTheme.of(context).primary
          : fadedSecondary;
      final labelColor = currentIndex == idx
          ? FlutterFlowTheme.of(context).primary
          : fadedSecondary;

      return FloatingNavbarItem(
        customWidget: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              iconData ?? Icons.circle,
              color: iconColor,
              size: 20.0,
            ),
            Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: labelColor,
                fontSize: 11.0,
              ),
            ),
          ],
        ),
      );
    }).toList();

    final bool _isNestedNavBar =
        context.findAncestorWidgetOfExactType<NavBarPage>() != null;

    return Scaffold(
      resizeToAvoidBottomInset: !widget.disableResizeToAvoidBottomInset,
      body: MediaQuery(
        data: queryData
            .removeViewInsets(removeBottom: true)
            .removeViewPadding(removeBottom: true),
        child: _currentPage ?? tabs[_currentPageName] ?? tabs.values.first,
      ),
      extendBody: true,
      bottomNavigationBar: Visibility(
        // Hide nav on desktop or when we have fewer than 2 tabs (avoids assertion),
        // and also hide if this NavBarPage is nested inside another NavBarPage to
        // avoid duplicate bottom bars.
        visible: responsiveVisibility(
              context: context,
              desktop: false,
            ) &&
            tabs.length > 1 &&
            !_isNestedNavBar,
        child: FloatingNavbar(
          currentIndex: currentIndex,
          onTap: (i) async {
            // Handle taps asynchronously because we may need to check guest session and prompt sign-in
            final key = tabs.keys.toList()[i];
            final restrictedKeysForGuests = [
              'JobPostPage',
              'BookingPage',
              'profile'
            ];
            final guest = await isGuestSession();

            if (guest && restrictedKeysForGuests.contains(key)) {
              // For guests: show the themed guest prompt (immediately on tap) and respect choice
              final res = await _showGuestPrompt();
              if (res == true) {
                try {
                  NavigationUtils.safePush(context, const LoginAccountWidget());
                } catch (_) {}
              }
              return;
            }

            // Not a guest or allowed: proceed to change tab
            safeSetState(() {
              _currentPage = null;
              // If user taps Home and is an artisan, ensure we show the artisan dashboard
              if (key == 'homePage' && isArtisan) {
                _currentPageName = 'homePage';
                _currentPage = ArtisanDashboardPageWidget();
              } else {
                // Final guard: ensure the tapped key exists in the computed tabs.
                if (tabs.containsKey(key)) {
                  _currentPageName = key;
                } else {
                  // Fallback to first allowed tab.
                  _currentPageName = tabs.keys.first;
                }
              }
            });
          },
          backgroundColor: FlutterFlowTheme.of(context).secondaryBackground,
          selectedItemColor: FlutterFlowTheme.of(context).primary,
          unselectedItemColor: FlutterFlowTheme.of(context).secondaryText,
          selectedBackgroundColor: const Color(0x00000000),
          borderRadius: 0.0,
          itemBorderRadius: 0.0,
          margin: const EdgeInsets.all(0.0),
          padding: const EdgeInsetsDirectional.fromSTEB(0.0, 15.0, 0.0, 15.0),
          width: double.infinity,
          elevation: 0.0,
          items: navItems,
        ),
      ),
    );
  }
}

// Global route observer used by pages that need to know when they're re-shown
final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

// Return a configured HttpClient. We don't extend `HttpClient` (it's an
// interface class) — instead we create and configure an instance. For
// additional logging or custom behavior, call the helper functions below.
HttpClient createCustomHttpClient() {
  final client = HttpClient();
  client.badCertificateCallback =
      (X509Certificate cert, String host, int port) {
    // Removed debugPrint to prevent logging host info to terminal.
    // Keep default behavior: don't accept bad certificates unless you have a
    // specific reason to allow them. Returning false rejects the certificate.
    return false;
  };
  return client;
}

void testCustomHttpClient() async {
  final client = createCustomHttpClient();
  try {
    final request = await client.getUrl(Uri.parse('https://rijhub.com'));
    final response = await request.close();
    // Removed debugPrint: do not log HTTP response code or body to terminal.
    final responseBody = await response.transform(utf8.decoder).join();
    // Intentionally not printing response body for security.
  } catch (e, stackTrace) {
    // Intentionally not printing errors or stack traces to terminal for security.
  }
}
