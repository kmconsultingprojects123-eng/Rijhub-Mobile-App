import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../features/home/home_screen.dart';
import '../features/onboarding/splash_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/shell/tab_screens.dart';
import 'routes.dart';
import 'session.dart';

export 'routes.dart';

GoRouter buildRouter(SessionController session, {String? initialLocation}) {
  return GoRouter(
    initialLocation: initialLocation ?? Routes.home,
    // Not refreshed when the session changes: screens navigate after the
    // change they cause, so a sign-in sheet can finish its success moment
    // before the welcome screen gives way to home.
    debugLogDiagnostics: kDebugMode,
    // First launch opens on the guest home with the welcome sheet over it
    // (see AppShell), so nothing here sends people anywhere else. The old
    // welcome path still lands on home.
    redirect: (context, state) =>
        state.matchedLocation == Routes.welcome ? Routes.home : null,
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (context, state) => SplashScreen(
          hold: kDebugMode && state.uri.queryParameters['hold'] == '1',
        ),
      ),
      GoRoute(
        path: Routes.welcome,
        redirect: (context, state) => Routes.home,
      ),
      StatefulShellRoute.indexedStack(
        pageBuilder: (context, state, shell) =>
            _fade(state, AppShell(navigationShell: shell)),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.home,
              builder: (context, state) => const HomeScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.explore,
              builder: (context, state) => const ExploreTab(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.bookings,
              builder: (context, state) => const BookingsTab(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.messages,
              builder: (context, state) => const MessagesTab(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.account,
              builder: (context, state) => const AccountTab(),
            ),
          ]),
        ],
      ),
    ],
  );
}

/// Arriving from the splash (or leaving welcome) cross-fades rather than
/// sliding sideways, because it isn't a step "forward".
Page<void> _fade(GoRouterState state, Widget child) => CustomTransitionPage(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 350),
      transitionsBuilder: (context, animation, secondary, child) =>
          FadeTransition(opacity: animation, child: child),
    );
