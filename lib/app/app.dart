import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/theme/theme.dart';
import '../data/repositories/repositories.dart';
import 'auth_gate.dart';
import 'dependencies.dart';
import 'location.dart';
import 'media.dart';
import 'payments.dart';
import 'push.dart';
import 'router.dart';
import 'session.dart';

/// Screens are designed at this size (an iPhone 14-class phone).
const designSize = Size(390, 844);

class RijHubApp extends StatefulWidget {
  const RijHubApp({
    super.key,
    required this.dependencies,
    required this.session,
    required this.authFlow,
    required this.authGate,
    this.initialLocation,
    this.navigatorKey,
    this.debugSignInPrompt,
    this.debugOnLaunch,
  });

  final AppDependencies dependencies;
  final SessionController session;
  final AuthFlowController authFlow;
  final AuthGate authGate;
  final String? initialLocation;

  /// The app navigator's key, for what opens pages from outside a screen
  /// (Paystack's checkout during a booking).
  final GlobalKey<NavigatorState>? navigatorKey;

  /// Debug only: opens the sign-in sheet after launch (for screenshots).
  final AuthPrompt? debugSignInPrompt;

  /// Debug only: runs after launch with the navigator's context, for
  /// screenshots of other sheets.
  final Future<void> Function(BuildContext context)? debugOnLaunch;

  @override
  State<RijHubApp> createState() => _RijHubAppState();
}

class _RijHubAppState extends State<RijHubApp> {
  late final GoRouter _router = buildRouter(
    widget.session,
    initialLocation: widget.initialLocation,
    navigatorKey: widget.navigatorKey,
  );

  @override
  void initState() {
    super.initState();
    final prompt = widget.debugSignInPrompt;
    final onLaunch = widget.debugOnLaunch;
    if (prompt == null && onLaunch == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      final context = _router.routerDelegate.navigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      if (prompt != null) {
        await widget.authGate.ensureSignedIn(context, prompt);
      } else {
        await onLaunch!(context);
      }
    });
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.dependencies;
    return MultiProvider(
      providers: [
        Provider<AuthRepository>.value(value: d.auth),
        Provider<CatalogRepository>.value(value: d.catalog),
        Provider<ArtisanRepository>.value(value: d.artisans),
        Provider<JobRepository>.value(value: d.jobs),
        Provider<BookingRepository>.value(value: d.bookings),
        Provider<ArtisanDashboardRepository>.value(value: d.artisanDashboard),
        Provider<AskRepository>.value(value: d.ask),
        Provider<DirectoryRepository>.value(value: d.directory),
        Provider<BookingFlowRepository>.value(value: d.bookingFlow),
        Provider<ClientJobRepository>.value(value: d.clientJobs),
        Provider<QuoteRepository>.value(value: d.quotes),
        Provider<ChatRepository>.value(value: d.chat),
        Provider<NoticeRepository>.value(value: d.notices),
        Provider<WalletRepository>.value(value: d.wallet),
        Provider<AccountRepository>.value(value: d.account),
        Provider<ArtisanSetupRepository>.value(value: d.artisanSetup),
        Provider<SupportRepository>.value(value: d.support),
        Provider<MediaService>.value(value: d.media),
        Provider<LocationService>.value(value: d.location),
        Provider<PushPermission>.value(value: d.push),
        Provider<PaymentGateway>.value(value: d.payments),
        Provider<AuthGate>.value(value: widget.authGate),
        ChangeNotifierProvider.value(value: widget.session),
        ChangeNotifierProvider.value(value: widget.authFlow),
      ],
      // Rebuilds when the window changes size, so the scale stays right
      // after rotation or in split screen.
      child: MediaQuery.fromView(
        view: View.of(context),
        child: Builder(
          builder: (context) {
            final width = MediaQuery.sizeOf(context).width;
            // Phones scale with their width; wider screens stop at 125% so
            // the layout doesn't balloon on tablets.
            final designWidth = math.max(designSize.width, width / 1.25);
            return ScreenUtilInit(
              designSize: Size(designWidth, designSize.height),
              builder: (context, _) => MaterialApp.router(
                title: 'RijHub',
                debugShowCheckedModeBanner: false,
                theme: AppTheme.light(),
                darkTheme: AppTheme.dark(),
                themeMode: context
                    .select<SessionController, ThemeMode>((s) => s.themeMode),
                routerConfig: _router,
                supportedLocales: const [Locale('en', 'NG'), Locale('en')],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                builder: (context, child) => _ReduceMotion(
                  child: _SystemBars(
                    // Respect the user's text size, within limits the
                    // layouts can hold.
                    child: MediaQuery.withClampedTextScaling(
                      maxScaleFactor: 1.3,
                      child: child!,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Turns on `MediaQuery.disableAnimations` when iOS asks for reduced motion.
///
/// Flutter sets it only from Android's "Remove animations"; iOS reports
/// Reduce Motion as a separate flag that nothing reads. Folding it in here
/// lets every `context.motion` call, and Flutter's own widgets, respect both.
class _ReduceMotion extends StatefulWidget {
  const _ReduceMotion({required this.child});

  final Widget child;

  @override
  State<_ReduceMotion> createState() => _ReduceMotionState();
}

class _ReduceMotionState extends State<_ReduceMotion>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAccessibilityFeatures() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final features = View.of(context).platformDispatcher.accessibilityFeatures;
    final media = MediaQuery.of(context);
    // Always the same tree, so turning the setting on or off while the app
    // runs keeps every screen's state.
    return MediaQuery(
      data: media.copyWith(
        disableAnimations: media.disableAnimations || features.reduceMotion,
      ),
      child: widget.child,
    );
  }
}

/// Dark status-bar icons on light pages and light icons in dark mode.
/// Screens over photos or crimson set their own style, which wins.
class _SystemBars extends StatelessWidget {
  const _SystemBars({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDarkMode;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      ),
      child: child,
    );
  }
}
